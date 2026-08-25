package machi_test

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"seryiza.local/river-zelbar-status/internal/engine"
	"seryiza.local/river-zelbar-status/internal/machi"
	"seryiza.local/river-zelbar-status/internal/model"
)

type recordingSink struct {
	mu     sync.Mutex
	events []engine.Event
}

func (sink *recordingSink) Publish(_ context.Context, event engine.Event) error {
	sink.mu.Lock()
	defer sink.mu.Unlock()
	sink.events = append(sink.events, event)
	return nil
}

func (sink *recordingSink) machiStates() []model.MachiState {
	sink.mu.Lock()
	defer sink.mu.Unlock()
	state := model.Snapshot{}
	values := make([]model.MachiState, 0, len(sink.events))
	for _, event := range sink.events {
		if event.Update != nil {
			state = model.Reduce(state, *event.Update)
			values = append(values, state.Machi)
		}
	}
	return values
}

func TestSourcePublishesCompleteZeroBasedSnapshots(t *testing.T) {
	logPath := filepath.Join(t.TempDir(), "argv")
	source := machi.New(machi.Command{
		Path: os.Args[0],
		Args: []string{"-test.run=TestMachiHelperProcess", "--", logPath},
		Env:  append(os.Environ(), "GO_WANT_MACHI_HELPER=valid"),
	}, "eDP-1")
	sink := &recordingSink{}

	err := source.Run(context.Background(), sink)
	if err == nil || !strings.Contains(err.Error(), "EOF") {
		t.Fatalf("Run() error = %v, want fatal EOF", err)
	}
	want := []model.MachiState{
		{Valid: true, WorkspaceIndex: 0, WorkspaceCount: 1, PanelIndex: 0, PanelCount: 1, Mode: "single", WindowCount: 1, Title: "Terminal"},
		{Valid: true, WorkspaceIndex: 1, WorkspaceCount: 4, PanelIndex: 2, PanelCount: 3, Mode: "split", WindowCount: 5, Title: "README"},
		{Valid: true, WorkspaceIndex: 0, WorkspaceCount: 0, PanelIndex: 0, PanelCount: 0, Mode: "single", WindowCount: 0, Title: ""},
	}
	if got := sink.machiStates(); !reflect.DeepEqual(got, want) {
		t.Fatalf("states = %#v, want %#v", got, want)
	}
	argv, readErr := os.ReadFile(logPath)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if got := string(argv); got != "-watch\neDP-1\n" {
		t.Fatalf("machictl argv = %q", got)
	}
}

func TestSourceRejectsInvalidSnapshots(t *testing.T) {
	for _, test := range []struct {
		name string
		mode string
		want string
	}{
		{"malformed JSON", "malformed", "decode snapshot"},
		{"wrong output", "wrong-output", "unexpected output"},
		{"missing schema field", "missing-field", "schema"},
		{"out of range index", "bad-index", "workspace index"},
	} {
		t.Run(test.name, func(t *testing.T) {
			source := machi.New(machi.Command{
				Path: os.Args[0],
				Args: []string{"-test.run=TestMachiHelperProcess", "--", filepath.Join(t.TempDir(), "argv")},
				Env:  append(os.Environ(), "GO_WANT_MACHI_HELPER="+test.mode),
			}, "eDP-1")
			err := source.Run(context.Background(), &recordingSink{})
			if err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("Run() error = %v, want substring %q", err, test.want)
			}
		})
	}
}

func TestSourceTreatsEOFAsFatalWhileWatcherIsStillAlive(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	source := machi.New(machi.Command{
		Path: os.Args[0],
		Args: []string{"-test.run=TestMachiHelperProcess", "--", filepath.Join(t.TempDir(), "argv")},
		Env:  append(os.Environ(), "GO_WANT_MACHI_HELPER=eof-alive"),
	}, "eDP-1")
	if err := source.Run(ctx, &recordingSink{}); !errors.Is(err, io.ErrUnexpectedEOF) {
		t.Fatalf("Run() error = %v, want fatal EOF before timeout", err)
	}
}

func TestSourceTreatsProcessExitAsFatal(t *testing.T) {
	source := machi.New(machi.Command{
		Path: os.Args[0],
		Args: []string{"-test.run=TestMachiHelperProcess", "--", filepath.Join(t.TempDir(), "argv")},
		Env:  append(os.Environ(), "GO_WANT_MACHI_HELPER=exit-failure"),
	}, "eDP-1")
	if err := source.Run(context.Background(), &recordingSink{}); err == nil || !strings.Contains(err.Error(), "machictl exited") {
		t.Fatalf("Run() error = %v, want process exit failure", err)
	}
}

func TestSourceCancellationStopsWatcher(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	source := machi.New(machi.Command{Path: os.Args[0]}, "eDP-1")
	if err := source.Run(ctx, &recordingSink{}); !errors.Is(err, context.Canceled) {
		t.Fatalf("Run() error = %v, want context cancellation", err)
	}
}

func TestMachiHelperProcess(t *testing.T) {
	if os.Getenv("GO_WANT_MACHI_HELPER") == "" {
		return
	}
	separator := -1
	for index, arg := range os.Args {
		if arg == "--" {
			separator = index
			break
		}
	}
	if separator < 0 || separator+1 >= len(os.Args) {
		os.Exit(2)
	}
	logPath := os.Args[separator+1]
	args := os.Args[separator+2:]
	if err := os.WriteFile(logPath, []byte(strings.Join(args, "\n")+"\n"), 0o600); err != nil {
		os.Exit(2)
	}
	if os.Getenv("GO_WANT_MACHI_HELPER") == "exit-failure" {
		os.Exit(7)
	}
	if os.Getenv("GO_WANT_MACHI_HELPER") == "eof-alive" {
		_ = os.Stdout.Close()
		time.Sleep(30 * time.Second)
		os.Exit(0)
	}
	fixtures := map[string]string{
		"valid": strings.Join([]string{
			`{"name":"eDP-1","current_workspace_index":0,"total_workspaces":1,"total_seats":1,"workspace_info":{"current_panel_index":0,"total_panels":1},"panel_info":{"total_windows":1,"mode":"single"},"window_info":{"title":"Terminal"}}`,
			`{"name":"eDP-1","current_workspace_index":1,"total_workspaces":4,"total_seats":1,"workspace_info":{"current_panel_index":2,"total_panels":3},"panel_info":{"total_windows":5,"mode":"split"},"window_info":{"title":"README"}}`,
			`{"name":"eDP-1","current_workspace_index":0,"total_workspaces":0,"total_seats":1,"workspace_info":{"current_panel_index":0,"total_panels":0},"panel_info":{"total_windows":0,"mode":"single"},"window_info":{"title":null}}`,
		}, "\n") + "\n",
		"malformed":     "{not-json}\n",
		"wrong-output":  `{"name":"DP-1","current_workspace_index":0,"total_workspaces":1,"total_seats":1,"workspace_info":{"current_panel_index":0,"total_panels":1},"panel_info":{"total_windows":1,"mode":"single"},"window_info":{"title":"Terminal"}}` + "\n",
		"missing-field": `{"name":"eDP-1","current_workspace_index":0,"total_workspaces":1,"workspace_info":{"current_panel_index":0,"total_panels":1},"panel_info":{"total_windows":1,"mode":"single"},"window_info":{"title":"Terminal"}}` + "\n",
		"bad-index":     `{"name":"eDP-1","current_workspace_index":1,"total_workspaces":1,"total_seats":1,"workspace_info":{"current_panel_index":0,"total_panels":1},"panel_info":{"total_windows":1,"mode":"single"},"window_info":{"title":"Terminal"}}` + "\n",
	}
	_, _ = os.Stdout.WriteString(fixtures[os.Getenv("GO_WANT_MACHI_HELPER")])
	os.Exit(0)
}
