// Package statussource contains the optional, read-only text status adapters.
package statussource

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"golang.org/x/sys/unix"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"

	"seryiza.local/river-zelbar-status/internal/engine"
	"seryiza.local/river-zelbar-status/internal/model"
)

const maxCommandOutput = 64 << 10

type Command struct {
	Path string
	Args []string
	Env  []string
}

type Runner interface {
	Run(context.Context, Command) ([]byte, error)
}

type ExecRunner struct{}

func (ExecRunner) Run(ctx context.Context, command Command) ([]byte, error) {
	cmd := exec.CommandContext(ctx, command.Path, command.Args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return os.ErrProcessDone
		}
		err := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		if errors.Is(err, syscall.ESRCH) {
			return os.ErrProcessDone
		}
		return err
	}
	cmd.WaitDelay = time.Second
	if command.Env != nil {
		cmd.Env = command.Env
	}
	var stdout limitedBuffer
	var stderr limitedBuffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return nil, fmt.Errorf("command timeout: %w", ctx.Err())
	}
	if stdout.overflow || stderr.overflow {
		return nil, fmt.Errorf("command output exceeds %d bytes", maxCommandOutput)
	}
	if err != nil {
		detail := strings.TrimSpace(stderr.String())
		if detail != "" {
			return nil, fmt.Errorf("%w: %s", err, detail)
		}
		return nil, err
	}
	return stdout.Bytes(), nil
}

type limitedBuffer struct {
	bytes.Buffer
	overflow bool
}

func (buffer *limitedBuffer) Write(value []byte) (int, error) {
	original := len(value)
	remaining := maxCommandOutput - buffer.Len()
	if remaining <= 0 {
		buffer.overflow = true
		return original, nil
	}
	if len(value) > remaining {
		buffer.overflow = true
		value = value[:remaining]
	}
	_, _ = buffer.Buffer.Write(value)
	return original, nil
}

type sampleFunc func(context.Context) (string, error)

type pollingSource struct {
	name         string
	field        model.Field
	interval     time.Duration
	timeout      time.Duration
	failureValue string
	sample       sampleFunc
	now          func() time.Time
}

func (source *pollingSource) Run(ctx context.Context, sink engine.Sink) error {
	ticker := time.NewTicker(source.interval)
	defer ticker.Stop()
	lastWarning := time.Time{}
	for {
		sampleCtx, cancel := context.WithTimeout(ctx, source.timeout)
		value, err := source.sample(sampleCtx)
		cancel()
		event := engine.Event{}
		update := model.FieldUpdate(source.field, value)
		if err != nil {
			update = model.FieldUpdate(source.field, source.failureValue)
			event.Warning = throttledNonfatal(source.name, err, source.now(), &lastWarning)
		}
		event.Update = &update
		if publishErr := sink.Publish(ctx, event); publishErr != nil {
			return publishErr
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}

func throttledNonfatal(source string, err error, now time.Time, lastWarning *time.Time) *engine.Fault {
	if !(*lastWarning).IsZero() && now.Sub(*lastWarning) < 5*time.Minute {
		return nil
	}
	*lastWarning = now
	return &engine.Fault{Class: engine.Nonfatal, Source: source, Err: err}
}

func newPolling(name string, field model.Field, interval, timeout time.Duration, failure string, sample sampleFunc) engine.Source {
	return &pollingSource{name: name, field: field, interval: interval, timeout: timeout, failureValue: failure, sample: sample, now: time.Now}
}

func runnerOrDefault(runner Runner) Runner {
	if runner == nil {
		return ExecRunner{}
	}
	return runner
}

type orgClockSource struct{ snapshotPath string }

func NewOrgClock(snapshotPath string) engine.Source {
	return &orgClockSource{snapshotPath: snapshotPath}
}

func (source *orgClockSource) Run(ctx context.Context, sink engine.Sink) error {
	fd, err := unix.InotifyInit1(unix.IN_CLOEXEC | unix.IN_NONBLOCK)
	if err != nil {
		return fmt.Errorf("org clock inotify: %w", err)
	}
	pipe := [2]int{}
	if err := unix.Pipe2(pipe[:], unix.O_CLOEXEC|unix.O_NONBLOCK); err != nil {
		_ = unix.Close(fd)
		return fmt.Errorf("org clock cancellation pipe: %w", err)
	}
	done := make(chan struct{})
	stopWake := context.AfterFunc(ctx, func() {
		defer close(done)
		_, _ = unix.Write(pipe[1], []byte{1})
	})
	defer func() {
		if !stopWake() {
			<-done
		}
		_ = unix.Close(pipe[0])
		_ = unix.Close(pipe[1])
		_ = unix.Close(fd)
	}()

	parent := filepath.Dir(source.snapshotPath)
	name := filepath.Base(source.snapshotPath)
	nameBytes := []byte(name)
	wd, err := unix.InotifyAddWatch(fd, parent, unix.IN_MOVED_TO|unix.IN_CLOSE_WRITE|unix.IN_DELETE|unix.IN_DELETE_SELF|unix.IN_MOVE_SELF)
	if err != nil {
		return fmt.Errorf("org clock watch %q: %w", parent, err)
	}
	lastWarning := time.Time{}
	if err := source.publish(ctx, sink, &lastWarning); err != nil {
		return err
	}

	buffer := make([]byte, 4096)
	for {
		ready := []unix.PollFd{{Fd: int32(fd), Events: unix.POLLIN}, {Fd: int32(pipe[0]), Events: unix.POLLIN}}
		if _, err := unix.Poll(ready, -1); err != nil {
			if err == unix.EINTR {
				continue
			}
			return fmt.Errorf("org clock poll: %w", err)
		}
		if ready[1].Revents != 0 {
			return ctx.Err()
		}
		if ready[0].Revents&(unix.POLLERR|unix.POLLHUP|unix.POLLNVAL) != 0 {
			return errors.New("org clock inotify descriptor failure")
		}

		length, err := unix.Read(fd, buffer)
		if err != nil {
			if err == unix.EAGAIN {
				continue
			}
			return fmt.Errorf("org clock inotify read: %w", err)
		}
		changed := false
		for offset := 0; offset < length; {
			if length-offset < unix.SizeofInotifyEvent {
				return errors.New("org clock malformed inotify event")
			}
			event := buffer[offset:]
			mask := binary.NativeEndian.Uint32(event[4:8])
			eventWD := int32(binary.NativeEndian.Uint32(event[:4]))
			nameLength := int(binary.NativeEndian.Uint32(event[12:16]))
			offset += unix.SizeofInotifyEvent
			if nameLength > length-offset {
				return errors.New("org clock malformed inotify event name")
			}
			eventName := bytes.TrimRight(event[unix.SizeofInotifyEvent:unix.SizeofInotifyEvent+nameLength], "\x00")
			offset += nameLength

			if mask&unix.IN_Q_OVERFLOW != 0 {
				changed = true
				continue
			}
			if eventWD != int32(wd) {
				return errors.New("org clock unexpected inotify watch descriptor")
			}
			if mask&(unix.IN_IGNORED|unix.IN_UNMOUNT|unix.IN_DELETE_SELF|unix.IN_MOVE_SELF) != 0 {
				return errors.New("org clock watch lost")
			}
			if bytes.Equal(eventName, nameBytes) && mask&(unix.IN_MOVED_TO|unix.IN_CLOSE_WRITE|unix.IN_DELETE) != 0 {
				changed = true
			}
		}
		if changed {
			if err := source.publish(ctx, sink, &lastWarning); err != nil {
				return err
			}
		}
	}
}

func (source *orgClockSource) publish(ctx context.Context, sink engine.Sink, lastWarning *time.Time) error {
	value, err := readOrgClockSnapshot(source.snapshotPath)
	event := engine.Event{}
	if err != nil {
		value = ""
		event.Warning = throttledNonfatal("org-clock", err, time.Now(), lastWarning)
	}
	update := model.FieldUpdate(model.FieldOrgClock, value)
	event.Update = &update
	return sink.Publish(ctx, event)
}

func readOrgClockSnapshot(path string) (string, error) {
	value, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	value = bytes.TrimSuffix(value, []byte{'\n'})
	if bytes.Contains(value, []byte{'\n'}) {
		return "", errors.New("clock snapshot contains an embedded newline")
	}
	if !utf8.Valid(value) {
		return "", errors.New("clock snapshot is not valid UTF-8")
	}
	return string(value), nil
}

type orgTimeblockState struct {
	text     string
	deadline time.Time
}

type orgTimeblockSource struct {
	command Command
	runner  Runner
	clock   Clock
}

func NewOrgTimeblock(command Command, runner Runner, clock Clock) engine.Source {
	if clock == nil {
		clock = WallClock{}
	}
	return &orgTimeblockSource{command: command, runner: runnerOrDefault(runner), clock: clock}
}

func (source *orgTimeblockSource) Run(ctx context.Context, sink engine.Sink) error {
	lastWarning := time.Time{}
	for {
		state, err := source.query(ctx)
		if err == nil && !state.deadline.IsZero() && !state.deadline.After(source.clock.Now()) {
			state, err = source.query(ctx)
			if err == nil && !state.deadline.After(source.clock.Now()) {
				state.deadline = time.Time{}
			}
		}

		event := engine.Event{}
		if err != nil {
			state = orgTimeblockState{}
			event.Warning = throttledNonfatal("org-timeblock", err, source.clock.Now(), &lastWarning)
		}
		update := model.FieldUpdate(model.FieldOrgTimeblock, state.text)
		event.Update = &update
		if err := sink.Publish(ctx, event); err != nil {
			return err
		}

		now := source.clock.Now()
		recovery := orgTimeblockRecovery(now)
		if !recovery.After(now) {
			return errors.New("org timeblock recovery is not in the future")
		}
		if !state.deadline.IsZero() && state.deadline.Before(recovery) {
			recovery = state.deadline
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-source.clock.After(recovery.Sub(now)):
		}
	}
}

func (source *orgTimeblockSource) query(ctx context.Context) (orgTimeblockState, error) {
	queryCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	output, err := source.runner.Run(queryCtx, source.command)
	if err != nil {
		return orgTimeblockState{}, err
	}
	return parseOrgTimeblockPayload(output)
}

func parseOrgTimeblockPayload(output []byte) (orgTimeblockState, error) {
	line, rest, found := bytes.Cut(output, []byte{'\n'})
	if !found || len(bytes.TrimSpace(rest)) != 0 {
		return orgTimeblockState{}, errors.New("timeblock command returned unexpected output")
	}
	if len(line) == 0 {
		return orgTimeblockState{}, nil
	}
	payload, err := base64.StdEncoding.DecodeString(string(line))
	if err != nil {
		return orgTimeblockState{}, fmt.Errorf("decode timeblock payload: %w", err)
	}
	if !utf8.Valid(payload) {
		return orgTimeblockState{}, errors.New("timeblock payload is not valid UTF-8")
	}
	var payloadState struct {
		Text           *string `json:"text"`
		NextTransition *int64  `json:"next_transition"`
	}
	decoder := json.NewDecoder(bytes.NewReader(payload))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payloadState); err != nil {
		return orgTimeblockState{}, fmt.Errorf("decode timeblock JSON: %w", err)
	}
	if payloadState.Text == nil || payloadState.NextTransition == nil || *payloadState.NextTransition <= 0 {
		return orgTimeblockState{}, errors.New("timeblock payload is missing required fields")
	}
	if err := rejectTrailingJSON(decoder); err != nil {
		return orgTimeblockState{}, err
	}
	return orgTimeblockState{text: *payloadState.Text, deadline: time.Unix(*payloadState.NextTransition, 0)}, nil
}

func orgTimeblockRecovery(now time.Time) time.Time {
	return now.Add(10*time.Minute - (time.Duration(now.Minute()%10)*time.Minute +
		time.Duration(now.Second())*time.Second + time.Duration(now.Nanosecond())))
}

func rejectTrailingJSON(decoder *json.Decoder) error {
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return errors.New("unexpected trailing JSON")
	}
	return nil
}

func NewAudio(command Command, runner Runner) engine.Source {
	runner = runnerOrDefault(runner)
	return newPolling("audio", model.FieldAudio, 2*time.Second, 1500*time.Millisecond, "audio?", func(ctx context.Context) (string, error) {
		sinkCommand := command
		sinkCommand.Args = append(append([]string{}, command.Args...), "get-volume", "@DEFAULT_AUDIO_SINK@")
		sinkOutput, err := runner.Run(ctx, sinkCommand)
		if err != nil {
			return "", fmt.Errorf("default sink: %w", err)
		}
		sourceCommand := command
		sourceCommand.Args = append(append([]string{}, command.Args...), "get-volume", "@DEFAULT_AUDIO_SOURCE@")
		sourceOutput, err := runner.Run(ctx, sourceCommand)
		if err != nil {
			return "", fmt.Errorf("default source: %w", err)
		}
		volume, sinkMuted, err := parseWPCTL(sinkOutput)
		if err != nil {
			return "", fmt.Errorf("default sink: %w", err)
		}
		_, sourceMuted, err := parseWPCTL(sourceOutput)
		if err != nil {
			return "", fmt.Errorf("default source: %w", err)
		}
		value := fmt.Sprintf("%d%% audio", int(math.Round(volume*100)))
		if sinkMuted {
			value = "MUTED"
		}
		if !sourceMuted {
			value += " +MIC"
		}
		return value, nil
	})
}

func parseWPCTL(output []byte) (float64, bool, error) {
	fields := strings.Fields(string(output))
	if len(fields) < 2 || len(fields) > 3 || fields[0] != "Volume:" {
		return 0, false, errors.New("malformed wpctl output")
	}
	volume, err := strconv.ParseFloat(fields[1], 64)
	if err != nil || math.IsNaN(volume) || math.IsInf(volume, 0) || volume < 0 {
		return 0, false, errors.New("malformed wpctl volume")
	}
	muted := len(fields) == 3
	if muted && fields[2] != "[MUTED]" {
		return 0, false, errors.New("malformed wpctl mute state")
	}
	return volume, muted, nil
}

func NewBattery(root string) engine.Source {
	return newPolling("battery", model.FieldBattery, 60*time.Second, 5*time.Second, "", func(context.Context) (string, error) {
		entries, err := os.ReadDir(root)
		if errors.Is(err, os.ErrNotExist) {
			return "", nil
		}
		if err != nil {
			return "", err
		}
		sort.Slice(entries, func(i, j int) bool { return entries[i].Name() < entries[j].Name() })
		for _, entry := range entries {
			dir := filepath.Join(root, entry.Name())
			kind, err := readSysfs(filepath.Join(dir, "type"))
			if err != nil || kind != "Battery" {
				continue
			}
			present, err := readOptionalSysfs(filepath.Join(dir, "present"))
			if err != nil {
				return "", err
			}
			if present != "" && present != "0" && present != "1" {
				return "", errors.New("malformed battery present state")
			}
			if present == "0" {
				continue
			}
			status, err := readSysfs(filepath.Join(dir, "status"))
			if err != nil {
				return "", err
			}
			capacityText, err := readSysfs(filepath.Join(dir, "capacity"))
			if err != nil {
				return "", err
			}
			capacity, err := strconv.Atoi(capacityText)
			if err != nil || capacity < 0 || capacity > 100 {
				return "", errors.New("malformed battery capacity")
			}
			switch status {
			case "Full":
				return "", nil
			case "Charging", "Discharging", "Not charging", "Unknown":
				return fmt.Sprintf("%d%% battery", capacity), nil
			default:
				return "", errors.New("malformed battery status")
			}
		}
		return "", nil
	})
}

func readSysfs(path string) (string, error) {
	value, err := os.ReadFile(path)
	return strings.TrimSpace(string(value)), err
}
func readOptionalSysfs(path string) (string, error) {
	value, err := readSysfs(path)
	if errors.Is(err, os.ErrNotExist) {
		return "", nil
	}
	return value, err
}

type Clock interface {
	Now() time.Time
	After(time.Duration) <-chan time.Time
}
type WallClock struct{}

func (WallClock) Now() time.Time                                { return time.Now() }
func (WallClock) After(duration time.Duration) <-chan time.Time { return time.After(duration) }

type clockSource struct{ clock Clock }

func NewClock(clock Clock) engine.Source {
	if clock == nil {
		clock = WallClock{}
	}
	return &clockSource{clock: clock}
}
func (source *clockSource) Run(ctx context.Context, sink engine.Sink) error {
	for {
		now := source.clock.Now()
		update := model.FieldUpdate(model.FieldClock, now.Format("02 Jan 15:04"))
		if err := sink.Publish(ctx, engine.Event{Update: &update}); err != nil {
			return err
		}
		next := now.Truncate(time.Minute).Add(time.Minute)
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-source.clock.After(next.Sub(now)):
		}
	}
}
