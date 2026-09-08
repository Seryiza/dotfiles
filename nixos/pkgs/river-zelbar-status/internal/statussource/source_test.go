package statussource

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"seryiza.local/river-zelbar-status/internal/engine"
	"seryiza.local/river-zelbar-status/internal/model"
)

type runnerFunc func(context.Context, Command) ([]byte, error)

func (run runnerFunc) Run(ctx context.Context, command Command) ([]byte, error) {
	return run(ctx, command)
}

type cancelSink struct {
	mu     sync.Mutex
	cancel context.CancelFunc
	events []engine.Event
}

func (sink *cancelSink) Publish(_ context.Context, event engine.Event) error {
	sink.mu.Lock()
	sink.events = append(sink.events, event)
	sink.mu.Unlock()
	if sink.cancel != nil {
		sink.cancel()
	}
	return nil
}

func (sink *cancelSink) count() int {
	sink.mu.Lock()
	defer sink.mu.Unlock()
	return len(sink.events)
}

func (sink *cancelSink) event(index int) engine.Event {
	sink.mu.Lock()
	defer sink.mu.Unlock()
	return sink.events[index]
}

type eventSink struct{ events chan engine.Event }

func (sink *eventSink) Publish(_ context.Context, event engine.Event) error {
	sink.events <- event
	return nil
}

func nextEvent(t *testing.T, sink *eventSink) engine.Event {
	t.Helper()
	select {
	case event := <-sink.events:
		return event
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for source event")
		return engine.Event{}
	}
}

type gateSink struct {
	events  chan engine.Event
	release chan struct{}
}

func (sink *gateSink) Publish(_ context.Context, event engine.Event) error {
	sink.events <- event
	<-sink.release
	return nil
}

func runFirst(t *testing.T, source engine.Source) engine.Event {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	sink := &cancelSink{cancel: cancel}
	if err := source.Run(ctx, sink); !errors.Is(err, context.Canceled) {
		t.Fatalf("Run() = %v, want cancellation", err)
	}
	if sink.count() != 1 {
		t.Fatalf("events = %d, want 1", sink.count())
	}
	return sink.event(0)
}

func eventValue(event engine.Event, field model.Field) string {
	if event.Update == nil {
		return "<nil>"
	}
	return fieldValue(model.Reduce(model.Snapshot{}, *event.Update), field)
}

func fieldValue(snapshot model.Snapshot, field model.Field) string {
	switch field {
	case model.FieldOrgTimeblock:
		return snapshot.OrgTimeblock
	case model.FieldOrgClock:
		return snapshot.OrgClock
	case model.FieldWireGuard:
		return snapshot.WireGuard
	case model.FieldAudio:
		return snapshot.Audio
	case model.FieldNetwork:
		return snapshot.Network
	case model.FieldBattery:
		return snapshot.Battery
	case model.FieldPowerSaver:
		return snapshot.PowerSaver
	case model.FieldClock:
		return snapshot.Clock
	default:
		return ""
	}
}

func timeblockPayload(t *testing.T, text string, transition time.Time) []byte {
	t.Helper()
	body, err := json.Marshal(struct {
		Text           string `json:"text"`
		NextTransition int64  `json:"next_transition"`
	}{text, transition.Unix()})
	if err != nil {
		t.Fatal(err)
	}
	return append([]byte(base64.StdEncoding.EncodeToString(body)), '\n')
}

func timeblockRaw(raw []byte) []byte {
	return append([]byte(base64.StdEncoding.EncodeToString(raw)), '\n')
}

func waitForSourceWait(t *testing.T, clock *fakeClock) time.Duration {
	t.Helper()
	select {
	case <-clock.waited:
		clock.mu.Lock()
		defer clock.mu.Unlock()
		return clock.waits[len(clock.waits)-1]
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for source timer")
		return 0
	}
}

func TestOrgClockWatchesAtomicSnapshots(t *testing.T) {
	runtimeDir := t.TempDir()
	snapshot := filepath.Join(runtimeDir, "river-zelbar-status-org-clock")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	sink := &eventSink{events: make(chan engine.Event, 4)}
	result := make(chan error, 1)
	go func() { result <- NewOrgClock(snapshot).Run(ctx, sink) }()

	if got := eventValue(nextEvent(t, sink), model.FieldOrgClock); got != "" {
		t.Fatalf("initial clock = %q, want empty", got)
	}
	temporary, err := os.CreateTemp(runtimeDir, ".clock-")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := temporary.WriteString("Meeting\n"); err != nil {
		t.Fatal(err)
	}
	if err := temporary.Close(); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(temporary.Name(), snapshot); err != nil {
		t.Fatal(err)
	}
	select {
	case event := <-sink.events:
		if got := eventValue(event, model.FieldOrgClock); got != "Meeting" {
			t.Fatalf("renamed clock = %q, want Meeting", got)
		}
	case err := <-result:
		t.Fatalf("source stopped after rename: %v", err)
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for renamed clock")
	}
	if err := os.Remove(snapshot); err != nil {
		t.Fatal(err)
	}
	if got := eventValue(nextEvent(t, sink), model.FieldOrgClock); got != "" {
		t.Fatalf("deleted clock = %q, want empty", got)
	}

	cancel()
	select {
	case err := <-result:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("Run() = %v, want cancellation", err)
		}
	case <-time.After(time.Second):
		t.Fatal("source did not leave idle poll after cancellation")
	}
}

func TestOrgClockStopsWhenRuntimeDirectoryMoves(t *testing.T) {
	runtimeDir := t.TempDir()
	movedRuntimeDir := runtimeDir + "-moved"
	defer os.RemoveAll(movedRuntimeDir)
	snapshot := filepath.Join(runtimeDir, "river-zelbar-status-org-clock")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	sink := &eventSink{events: make(chan engine.Event, 1)}
	result := make(chan error, 1)
	go func() { result <- NewOrgClock(snapshot).Run(ctx, sink) }()
	_ = nextEvent(t, sink)
	if err := os.Rename(runtimeDir, movedRuntimeDir); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-result:
		if err == nil || errors.Is(err, context.Canceled) {
			t.Fatalf("Run() = %v, want watch-loss error", err)
		}
	case <-time.After(time.Second):
		t.Fatal("source did not stop when its runtime directory moved")
	}
}

func TestOrgClockRereadsAfterInotifyQueueOverflow(t *testing.T) {
	limitText, err := os.ReadFile("/proc/sys/fs/inotify/max_queued_events")
	if err != nil {
		t.Fatal(err)
	}
	limit, err := strconv.Atoi(strings.TrimSpace(string(limitText)))
	if err != nil {
		t.Fatal(err)
	}
	runtimeDir := t.TempDir()
	snapshot := filepath.Join(runtimeDir, "river-zelbar-status-org-clock")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	sink := &gateSink{events: make(chan engine.Event, 2), release: make(chan struct{})}
	result := make(chan error, 1)
	go func() { result <- NewOrgClock(snapshot).Run(ctx, sink) }()
	if got := eventValue(<-sink.events, model.FieldOrgClock); got != "" {
		t.Fatalf("initial clock = %q, want empty", got)
	}
	for range limit/2 + 2 {
		file, err := os.CreateTemp(runtimeDir, ".flood-")
		if err != nil {
			t.Fatal(err)
		}
		if err := file.Close(); err != nil {
			t.Fatal(err)
		}
		if err := os.Remove(file.Name()); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(snapshot, []byte("Overflow\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	close(sink.release)
	select {
	case event := <-sink.events:
		if got := eventValue(event, model.FieldOrgClock); got != "Overflow" {
			t.Fatalf("overflow clock = %q, want Overflow", got)
		}
	case err := <-result:
		t.Fatalf("source stopped after overflow: %v", err)
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for overflow reread")
	}
	cancel()
	select {
	case err := <-result:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("Run() = %v, want cancellation", err)
		}
	case <-time.After(time.Second):
		t.Fatal("source did not leave idle poll after cancellation")
	}
}

func TestOrgTimeblockImmediateSampling(t *testing.T) {
	next := time.Unix(1_800_000_000, 0)
	for _, test := range []struct {
		name string
		out  []byte
		want string
	}{
		{"valid", timeblockPayload(t, "Plan today", next), "Plan today"},
		{"empty unavailable", []byte("\n"), ""},
	} {
		t.Run(test.name, func(t *testing.T) {
			runner := runnerFunc(func(context.Context, Command) ([]byte, error) { return test.out, nil })
			event := runFirst(t, NewOrgTimeblock(Command{Path: "/store/org"}, runner, nil))
			if got := eventValue(event, model.FieldOrgTimeblock); got != test.want || event.Warning != nil {
				t.Fatalf("value/warning = %q/%v, want %q/no warning", got, event.Warning, test.want)
			}
		})
	}
}

func TestOrgTimeblockFailuresRecover(t *testing.T) {
	location := time.FixedZone("local-test", 6*60*60)
	now := time.Date(2026, time.September, 4, 10, 3, 20, 0, location)
	for _, test := range []struct {
		name string
		out  []byte
		err  error
	}{
		{"missing wrapper line", nil, nil},
		{"invalid base64", []byte("not base64\n"), nil},
		{"invalid UTF-8", timeblockRaw([]byte{0xff}), nil},
		{"missing text", timeblockRaw([]byte(`{"next_transition":1}`)), nil},
		{"nonpositive transition", timeblockRaw([]byte(`{"text":"x","next_transition":0}`)), nil},
		{"unknown field", timeblockRaw([]byte(`{"text":"x","next_transition":1,"extra":true}`)), nil},
		{"trailing JSON", timeblockRaw([]byte(`{"text":"x","next_transition":1} {}`)), nil},
		{"extra command output", append(timeblockPayload(t, "x", now.Add(time.Minute)), []byte("noise\n")...), nil},
		{"timeout", nil, context.DeadlineExceeded},
		{"nonzero exit", nil, errors.New("exit status 7")},
	} {
		t.Run(test.name, func(t *testing.T) {
			clock := &fakeClock{now: now, wake: make(chan time.Time, 1), waited: make(chan struct{}, 2)}
			recovered := timeblockPayload(t, "Recovered", now.Add(20*time.Minute))
			calls := 0
			runner := runnerFunc(func(context.Context, Command) ([]byte, error) {
				calls++
				if calls == 1 {
					return test.out, test.err
				}
				return recovered, nil
			})
			ctx, cancel := context.WithCancel(context.Background())
			sink := &eventSink{events: make(chan engine.Event, 2)}
			done := make(chan error, 1)
			go func() { done <- NewOrgTimeblock(Command{Path: "/store/org"}, runner, clock).Run(ctx, sink) }()
			event := nextEvent(t, sink)
			if got := eventValue(event, model.FieldOrgTimeblock); got != "" || event.Warning == nil {
				t.Fatalf("failure value/warning = %q/%v, want empty/nonfatal warning", got, event.Warning)
			}
			recovery := now.Add(6*time.Minute + 40*time.Second)
			if got := waitForSourceWait(t, clock); got != recovery.Sub(now) {
				t.Fatalf("wait = %v, want %v", got, recovery.Sub(now))
			}
			clock.setNow(recovery)
			clock.wake <- recovery
			event = nextEvent(t, sink)
			if got := eventValue(event, model.FieldOrgTimeblock); got != "Recovered" || event.Warning != nil {
				t.Fatalf("recovered value/warning = %q/%v, want Recovered/no warning", got, event.Warning)
			}
			if calls != 2 {
				t.Fatalf("calls = %d, want 2", calls)
			}
			cancel()
			if err := <-done; !errors.Is(err, context.Canceled) {
				t.Fatalf("Run() = %v, want cancellation", err)
			}
		})
	}
}

func TestOrgTimeblockSchedulesTransitionsAndRecovery(t *testing.T) {
	location := time.FixedZone("local-test", 6*60*60)
	now := time.Date(2026, time.September, 4, 10, 3, 20, 0, location)
	for _, test := range []struct {
		name      string
		out       []byte
		wantWait  time.Duration
		wantValue string
		wantCalls int
	}{
		{"semantic transition wins", timeblockPayload(t, "Focus", now.Add(100*time.Second)), 100 * time.Second, "Focus", 1},
		{"recovery at ten past", []byte("\n"), 6*time.Minute + 40*time.Second, "", 1},
		{"recovery beats later transition", timeblockPayload(t, "Later", now.Add(12*time.Minute)), 6*time.Minute + 40*time.Second, "Later", 1},
	} {
		t.Run(test.name, func(t *testing.T) {
			clock := &fakeClock{now: now, wake: make(chan time.Time), waited: make(chan struct{}, 1)}
			calls := 0
			runner := runnerFunc(func(context.Context, Command) ([]byte, error) {
				calls++
				return test.out, nil
			})
			ctx, cancel := context.WithCancel(context.Background())
			sink := &eventSink{events: make(chan engine.Event, 1)}
			done := make(chan error, 1)
			go func() { done <- NewOrgTimeblock(Command{Path: "/store/org"}, runner, clock).Run(ctx, sink) }()
			if got := eventValue(nextEvent(t, sink), model.FieldOrgTimeblock); got != test.wantValue {
				t.Fatalf("value = %q, want %q", got, test.wantValue)
			}
			if got := waitForSourceWait(t, clock); got != test.wantWait {
				t.Fatalf("wait = %v, want %v", got, test.wantWait)
			}
			cancel()
			if err := <-done; !errors.Is(err, context.Canceled) {
				t.Fatalf("Run() = %v, want cancellation", err)
			}
			if calls != test.wantCalls {
				t.Fatalf("calls = %d, want %d", calls, test.wantCalls)
			}
		})
	}
}

func TestOrgTimeblockRetriesOneStaleResponse(t *testing.T) {
	now := time.Date(2026, time.September, 4, 10, 3, 20, 0, time.Local)
	clock := &fakeClock{now: now, wake: make(chan time.Time), waited: make(chan struct{}, 1)}
	outputs := [][]byte{timeblockPayload(t, "Stale", now), timeblockPayload(t, "Fresh", now.Add(time.Minute))}
	calls := 0
	runner := runnerFunc(func(context.Context, Command) ([]byte, error) {
		output := outputs[calls]
		calls++
		return output, nil
	})
	ctx, cancel := context.WithCancel(context.Background())
	sink := &eventSink{events: make(chan engine.Event, 1)}
	done := make(chan error, 1)
	go func() { done <- NewOrgTimeblock(Command{Path: "/store/org"}, runner, clock).Run(ctx, sink) }()
	if got := eventValue(nextEvent(t, sink), model.FieldOrgTimeblock); got != "Fresh" {
		t.Fatalf("value = %q, want Fresh", got)
	}
	if got := waitForSourceWait(t, clock); got != time.Minute {
		t.Fatalf("wait = %v, want 1m", got)
	}
	cancel()
	if err := <-done; !errors.Is(err, context.Canceled) {
		t.Fatalf("Run() = %v, want cancellation", err)
	}
	if calls != 2 {
		t.Fatalf("calls = %d, want 2", calls)
	}
}

func TestOrgTimeblockRecoveryDuringFallBack(t *testing.T) {
	location, err := time.LoadLocation("America/New_York")
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, time.November, 1, 1, 3, 20, 0, location).Add(time.Hour)
	clock := &fakeClock{now: now, wake: make(chan time.Time), waited: make(chan struct{}, 1)}
	ctx, cancel := context.WithCancel(context.Background())
	sink := &eventSink{events: make(chan engine.Event, 1)}
	done := make(chan error, 1)
	go func() {
		done <- NewOrgTimeblock(Command{Path: "/store/org"}, runnerFunc(func(context.Context, Command) ([]byte, error) {
			return timeblockPayload(t, "Later", now.Add(20*time.Minute)), nil
		}), clock).Run(ctx, sink)
	}()
	_ = nextEvent(t, sink)
	if got := waitForSourceWait(t, clock); got != 6*time.Minute+40*time.Second {
		t.Fatalf("fallback wait = %v, want 6m40s", got)
	}
	cancel()
	if err := <-done; !errors.Is(err, context.Canceled) {
		t.Fatalf("Run() = %v, want cancellation", err)
	}
}

func TestAudioSinkAndSourceStates(t *testing.T) {
	for _, test := range []struct {
		name   string
		output map[string]string
		err    error
		want   string
	}{
		{"unmuted with mic", map[string]string{"@DEFAULT_AUDIO_SINK@": "Volume: 0.52\n", "@DEFAULT_AUDIO_SOURCE@": "Volume: 0.80\n"}, nil, "52% audio +MIC"},
		{"muted sink and source", map[string]string{"@DEFAULT_AUDIO_SINK@": "Volume: 0.52 [MUTED]\n", "@DEFAULT_AUDIO_SOURCE@": "Volume: 0.80 [MUTED]\n"}, nil, "MUTED"},
		{"source muted", map[string]string{"@DEFAULT_AUDIO_SINK@": "Volume: 1.00\n", "@DEFAULT_AUDIO_SOURCE@": "Volume: 0.80 [MUTED]\n"}, nil, "100% audio"},
		{"empty", map[string]string{"@DEFAULT_AUDIO_SINK@": "", "@DEFAULT_AUDIO_SOURCE@": ""}, nil, "audio?"},
		{"malformed", map[string]string{"@DEFAULT_AUDIO_SINK@": "unknown\n", "@DEFAULT_AUDIO_SOURCE@": "Volume: 0.8\n"}, nil, "audio?"},
		{"timeout", nil, context.DeadlineExceeded, "audio?"},
		{"nonzero exit", nil, errors.New("exit status 7"), "audio?"},
	} {
		t.Run(test.name, func(t *testing.T) {
			runner := runnerFunc(func(_ context.Context, command Command) ([]byte, error) {
				if test.err != nil {
					return nil, test.err
				}
				return []byte(test.output[command.Args[1]]), nil
			})
			event := runFirst(t, NewAudio(Command{Path: "/store/wpctl"}, runner))
			if got := eventValue(event, model.FieldAudio); got != test.want {
				t.Fatalf("audio = %q, want %q", got, test.want)
			}
		})
	}
}

func TestExecRunnerHandlesOutputExitAndTimeout(t *testing.T) {
	for _, test := range []struct {
		name    string
		mode    string
		timeout time.Duration
		want    string
		wantErr bool
	}{
		{"valid", "valid", 10 * time.Second, "fixture output\n", false},
		{"empty", "empty", 10 * time.Second, "", false},
		{"nonzero", "nonzero", 10 * time.Second, "", true},
		{"timeout", "timeout", 100 * time.Millisecond, "", true},
	} {
		t.Run(test.name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), test.timeout)
			defer cancel()
			output, err := (ExecRunner{}).Run(ctx, Command{
				Path: os.Args[0],
				Args: []string{"-test.run=TestCommandFixtureProcess"},
				Env:  append(os.Environ(), "GO_WANT_STATUS_COMMAND="+test.mode),
			})
			if string(output) != test.want || (err != nil) != test.wantErr {
				t.Fatalf("output/error = %q/%v, want %q/error=%v", output, err, test.want, test.wantErr)
			}
		})
	}
}

func TestCommandFixtureProcess(t *testing.T) {
	switch os.Getenv("GO_WANT_STATUS_COMMAND") {
	case "":
		return
	case "valid":
		_, _ = os.Stdout.WriteString("fixture output\n")
		os.Exit(0)
	case "empty":
		os.Exit(0)
	case "nonzero":
		os.Exit(7)
	case "timeout":
		time.Sleep(30 * time.Second)
	}
}

func TestBatterySysfsStates(t *testing.T) {
	for _, test := range []struct {
		name, status, capacity, present, want string
		create                                bool
	}{
		{"full", "Full", "100", "1", "", true},
		{"charging", "Charging", "87", "1", "87% battery", true},
		{"discharging", "Discharging", "42", "1", "42% battery", true},
		{"missing", "", "", "", "", false},
		{"malformed capacity", "Charging", "wat", "1", "", true},
		{"malformed status", "Broken", "50", "1", "", true},
		{"malformed present", "Charging", "50", "wat", "", true},
	} {
		t.Run(test.name, func(t *testing.T) {
			root := t.TempDir()
			if test.create {
				dir := filepath.Join(root, "BAT1")
				if err := os.Mkdir(dir, 0o700); err != nil {
					t.Fatal(err)
				}
				for name, value := range map[string]string{"type": "Battery", "status": test.status, "capacity": test.capacity, "present": test.present} {
					if err := os.WriteFile(filepath.Join(dir, name), []byte(value+"\n"), 0o600); err != nil {
						t.Fatal(err)
					}
				}
			}
			event := runFirst(t, NewBattery(root))
			if got := eventValue(event, model.FieldBattery); got != test.want {
				t.Fatalf("battery = %q, want %q", got, test.want)
			}
		})
	}
}

type fakeClock struct {
	mu     sync.Mutex
	now    time.Time
	waits  []time.Duration
	waited chan struct{}
	wake   chan time.Time
}

func (clock *fakeClock) Now() time.Time {
	clock.mu.Lock()
	defer clock.mu.Unlock()
	return clock.now
}
func (clock *fakeClock) After(duration time.Duration) <-chan time.Time {
	clock.mu.Lock()
	clock.waits = append(clock.waits, duration)
	clock.mu.Unlock()
	if clock.waited != nil {
		select {
		case clock.waited <- struct{}{}:
		default:
		}
	}
	return clock.wake
}
func (clock *fakeClock) setNow(now time.Time) {
	clock.mu.Lock()
	clock.now = now
	clock.mu.Unlock()
}
func (clock *fakeClock) firstWait() time.Duration {
	clock.mu.Lock()
	defer clock.mu.Unlock()
	return clock.waits[0]
}

func TestBatteryFollowsSysfsClassSymlink(t *testing.T) {
	root := t.TempDir()
	target := t.TempDir()
	for name, value := range map[string]string{"type": "Battery", "status": "Discharging", "capacity": "63", "present": "1"} {
		if err := os.WriteFile(filepath.Join(target, name), []byte(value+"\n"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(target, filepath.Join(root, "BAT0")); err != nil {
		t.Fatal(err)
	}
	event := runFirst(t, NewBattery(root))
	if got := eventValue(event, model.FieldBattery); got != "63% battery" {
		t.Fatalf("battery = %q, want symlinked battery capacity", got)
	}
}

func TestClockPublishesAtStartupAndMinuteBoundaryInLocalTimezone(t *testing.T) {
	location := time.FixedZone("local-test", 6*60*60)
	clock := &fakeClock{now: time.Date(2025, time.August, 23, 21, 35, 40, 0, location), wake: make(chan time.Time, 1)}
	ctx, cancel := context.WithCancel(context.Background())
	sink := &cancelSink{}
	source := NewClock(clock)
	done := make(chan error, 1)
	go func() { done <- source.Run(ctx, sink) }()
	for sink.count() == 0 {
		time.Sleep(time.Millisecond)
	}
	if got := eventValue(sink.event(0), model.FieldClock); got != "23 Aug 21:35" {
		t.Fatalf("startup clock = %q", got)
	}
	next := time.Date(2025, time.August, 23, 21, 36, 0, 0, location)
	clock.setNow(next)
	clock.wake <- next
	for sink.count() < 2 {
		time.Sleep(time.Millisecond)
	}
	cancel()
	<-done
	if got := eventValue(sink.event(1), model.FieldClock); got != "23 Aug 21:36" {
		t.Fatalf("rollover clock = %q", got)
	}
	if clock.firstWait() != 20*time.Second {
		t.Fatalf("first wait = %v", clock.firstWait())
	}
}
