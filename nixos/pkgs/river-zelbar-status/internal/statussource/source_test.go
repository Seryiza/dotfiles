package statussource

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
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
	case model.FieldClock:
		return snapshot.Clock
	default:
		return ""
	}
}

func TestOrgFirstLineAndFailures(t *testing.T) {
	for _, test := range []struct {
		name string
		out  string
		err  error
		want string
		warn bool
	}{
		{"valid", "Plan today\nignored\n", nil, "Plan today", false},
		{"empty", "\nignored\n", nil, "", false},
		{"malformed", string([]byte{0xff, '\n'}), nil, "", true},
		{"timeout", "", context.DeadlineExceeded, "", true},
		{"nonzero exit", "", errors.New("exit status 7"), "", true},
	} {
		t.Run(test.name, func(t *testing.T) {
			runner := runnerFunc(func(context.Context, Command) ([]byte, error) { return []byte(test.out), test.err })
			event := runFirst(t, NewOrg(Command{Path: "/store/org"}, model.FieldOrgTimeblock, runner))
			if got := eventValue(event, model.FieldOrgTimeblock); got != test.want || (event.Warning != nil) != test.warn {
				t.Fatalf("value/warning = %q/%v, want %q/%v", got, event.Warning, test.want, test.warn)
			}
		})
	}
}

func TestWireGuardJSONContract(t *testing.T) {
	for _, test := range []struct {
		name string
		out  string
		err  error
		want string
		warn bool
	}{
		{"valid", `{"text":"wg-work","tooltip":"secret"}`, nil, "wg-work", false},
		{"empty", `{"text":"","tooltip":""}`, nil, "", false},
		{"malformed", `{nope}`, nil, "", true},
		{"timeout", "", context.DeadlineExceeded, "", true},
		{"nonzero exit", "", errors.New("exit status 7"), "", true},
	} {
		t.Run(test.name, func(t *testing.T) {
			runner := runnerFunc(func(_ context.Context, command Command) ([]byte, error) {
				if !reflect.DeepEqual(command.Args, []string{"short"}) {
					t.Fatalf("args = %#v", command.Args)
				}
				return []byte(test.out), test.err
			})
			event := runFirst(t, NewWireGuard(Command{Path: "/store/wg"}, runner))
			if got := eventValue(event, model.FieldWireGuard); got != test.want || (event.Warning != nil) != test.warn {
				t.Fatalf("value/warning = %q/%v, want %q/%v", got, event.Warning, test.want, test.warn)
			}
		})
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

func TestNetworkVisibleSemantics(t *testing.T) {
	for _, test := range []struct {
		name    string
		outputs [][]byte
		err     error
		want    string
	}{
		{"healthy wifi", [][]byte{[]byte("enabled\n"), []byte("wlp1s0:wifi:connected\n"), []byte("10.0.0.2/24\n"), []byte("*:75\n")}, nil, ""},
		{"healthy ethernet", [][]byte{[]byte("enabled\n"), []byte("enp1s0:ethernet:connected\n"), []byte("10.0.0.2/24\n")}, nil, ""},
		{"low wifi", [][]byte{[]byte("enabled\n"), []byte("wlp1s0:wifi:connected\n"), []byte("10.0.0.2/24\n"), []byte("*:19\n")}, nil, "<20% wlan"},
		{"disconnected", [][]byte{[]byte("enabled\n"), []byte("wlp1s0:wifi:disconnected\n")}, nil, "Disconnected"},
		{"linked without IP", [][]byte{[]byte("enabled\n"), []byte("enp1s0:ethernet:connected\n"), []byte("\n")}, nil, "enp1s0 (No IP)"},
		{"disabled", [][]byte{[]byte("disabled\n"), []byte("wlp1s0:wifi:disconnected\n")}, nil, "Wi-Fi disabled"},
		{"empty", [][]byte{[]byte("enabled\n"), []byte("")}, nil, "network?"},
		{"malformed", [][]byte{[]byte("enabled\n"), []byte("bad row\n")}, nil, "network?"},
		{"invalid UTF-8", [][]byte{[]byte("enabled\n"), {0xff, '\n'}}, nil, "network?"},
		{"timeout", nil, context.DeadlineExceeded, "network?"},
		{"nonzero exit", nil, errors.New("exit status 7"), "network?"},
	} {
		t.Run(test.name, func(t *testing.T) {
			index := 0
			runner := runnerFunc(func(_ context.Context, command Command) ([]byte, error) {
				if index == 0 && test.err == nil && !reflect.DeepEqual(command.Args, []string{"-g", "WIFI", "general"}) {
					t.Fatalf("first nmcli args = %#v", command.Args)
				}
				if test.err != nil {
					return nil, test.err
				}
				out := test.outputs[index]
				index++
				return out, nil
			})
			event := runFirst(t, NewNetwork(Command{Path: "/store/nmcli"}, runner))
			if got := eventValue(event, model.FieldNetwork); got != test.want {
				t.Fatalf("network = %q, want %q", got, test.want)
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
	mu    sync.Mutex
	now   time.Time
	waits []time.Duration
	wake  chan time.Time
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
