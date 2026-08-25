// Package statussource contains the optional, read-only text status adapters.
package statussource

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
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
			now := source.now()
			if lastWarning.IsZero() || now.Sub(lastWarning) >= 5*time.Minute {
				event.Warning = &engine.Fault{Class: engine.Nonfatal, Source: source.name, Err: err}
				lastWarning = now
			}
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

func newPolling(name string, field model.Field, interval, timeout time.Duration, failure string, sample sampleFunc) engine.Source {
	return &pollingSource{name: name, field: field, interval: interval, timeout: timeout, failureValue: failure, sample: sample, now: time.Now}
}

func runnerOrDefault(runner Runner) Runner {
	if runner == nil {
		return ExecRunner{}
	}
	return runner
}

func NewOrg(command Command, field model.Field, runner Runner) engine.Source {
	runner = runnerOrDefault(runner)
	name := "org-timeblock"
	if field == model.FieldOrgClock {
		name = "org-clock"
	}
	return newPolling(name, field, 15*time.Second, 5*time.Second, "", func(ctx context.Context) (string, error) {
		output, err := runner.Run(ctx, command)
		if err != nil {
			return "", err
		}
		line, _, _ := bytes.Cut(output, []byte{'\n'})
		if !utf8.Valid(line) {
			return "", errors.New("first line is not valid UTF-8")
		}
		return strings.TrimSuffix(string(line), "\r"), nil
	})
}

func NewWireGuard(command Command, runner Runner) engine.Source {
	runner = runnerOrDefault(runner)
	command.Args = append(append([]string{}, command.Args...), "short")
	return newPolling("wireguard", model.FieldWireGuard, 15*time.Second, 5*time.Second, "", func(ctx context.Context) (string, error) {
		output, err := runner.Run(ctx, command)
		if err != nil {
			return "", err
		}
		if !utf8.Valid(output) {
			return "", errors.New("JSON is not valid UTF-8")
		}
		var result struct {
			Text *string `json:"text"`
		}
		decoder := json.NewDecoder(bytes.NewReader(output))
		if err := decoder.Decode(&result); err != nil {
			return "", fmt.Errorf("decode JSON: %w", err)
		}
		if result.Text == nil {
			return "", errors.New("JSON .text is missing or not a string")
		}
		if err := rejectTrailingJSON(decoder); err != nil {
			return "", err
		}
		return *result.Text, nil
	})
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

type networkDevice struct{ name, kind, state string }

func NewNetwork(command Command, runner Runner) engine.Source {
	runner = runnerOrDefault(runner)
	return newPolling("network", model.FieldNetwork, 15*time.Second, 5*time.Second, "network?", func(ctx context.Context) (string, error) {
		run := func(args ...string) ([]byte, error) {
			request := command
			request.Args = append(append([]string{}, command.Args...), args...)
			return runner.Run(ctx, request)
		}
		networkingState, err := run("-g", "WIFI", "general")
		if err != nil {
			return "", err
		}
		wifiDisabled := false
		switch strings.TrimSpace(string(networkingState)) {
		case "disabled":
			wifiDisabled = true
		case "enabled":
		default:
			return "", errors.New("malformed Wi-Fi state")
		}
		status, err := run("-t", "-e", "no", "-f", "DEVICE,TYPE,STATE", "device", "status")
		if err != nil {
			return "", err
		}
		devices, err := parseDevices(status)
		if err != nil {
			return "", err
		}
		for _, device := range devices {
			if wifiDisabled && device.kind == "wifi" && (device.state == "connected" || device.state == "connecting") {
				return "", errors.New("Wi-Fi is connected while hardware is disabled")
			}
			if (device.state != "connected" && device.state != "connecting") || (device.kind != "wifi" && device.kind != "ethernet") {
				continue
			}
			addresses, err := run("-g", "IP4.ADDRESS", "device", "show", device.name)
			if err != nil {
				return "", err
			}
			if strings.TrimSpace(string(addresses)) == "" {
				return device.name + " (No IP)", nil
			}
			if device.kind == "ethernet" {
				return "", nil
			}
			signal, err := run("-t", "-e", "no", "-f", "IN-USE,SIGNAL", "device", "wifi", "list", "--rescan", "no")
			if err != nil {
				return "", err
			}
			strength, err := activeSignal(signal)
			if err != nil {
				return "", err
			}
			if strength < 20 {
				return "<20% wlan", nil
			}
			return "", nil
		}
		if wifiDisabled {
			return "Wi-Fi disabled", nil
		}
		return "Disconnected", nil
	})
}

func parseDevices(output []byte) ([]networkDevice, error) {
	if !utf8.Valid(output) {
		return nil, errors.New("device status is not valid UTF-8")
	}
	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	if len(lines) == 1 && lines[0] == "" {
		return nil, errors.New("empty device status")
	}
	devices := make([]networkDevice, 0, len(lines))
	for _, line := range lines {
		parts := strings.Split(line, ":")
		if len(parts) != 3 || parts[0] == "" || parts[1] == "" || parts[2] == "" {
			return nil, fmt.Errorf("malformed device row %q", line)
		}
		devices = append(devices, networkDevice{name: parts[0], kind: parts[1], state: parts[2]})
	}
	return devices, nil
}

func activeSignal(output []byte) (int, error) {
	if !utf8.Valid(output) {
		return 0, errors.New("Wi-Fi signal is not valid UTF-8")
	}
	for _, line := range strings.Split(strings.TrimSpace(string(output)), "\n") {
		parts := strings.Split(line, ":")
		if len(parts) == 2 && parts[0] == "*" {
			value, err := strconv.Atoi(parts[1])
			if err != nil || value < 0 || value > 100 {
				return 0, errors.New("malformed Wi-Fi signal")
			}
			return value, nil
		}
	}
	return 0, errors.New("active Wi-Fi signal is missing")
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
