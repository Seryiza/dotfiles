package renderer

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"strconv"
	"syscall"
	"testing"
	"time"

	"seryiza.local/river-zelbar-status/internal/engine"
)

func TestHelperProcess(t *testing.T) {
	mode := os.Getenv("RIVER_ZELBAR_HELPER")
	if mode == "" {
		return
	}
	if mode == "exit" {
		os.Exit(0)
	}
	if mode == "supervisor" {
		frames := engine.NewLatest[[]byte]()
		frames.Store([]byte("ready\n"))
		command := helperCommand("child", os.Getenv("RIVER_ZELBAR_PID_FILE"))
		err := NewZelbar(command, time.Second).Run(context.Background(), frames)
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	if mode == "ignore-term" {
		signal.Ignore(syscall.SIGTERM)
	}
	if pidFile := os.Getenv("RIVER_ZELBAR_PID_FILE"); pidFile != "" {
		if err := os.WriteFile(pidFile, []byte(strconv.Itoa(os.Getpid())), 0o600); err != nil {
			os.Exit(3)
		}
	}
	_, _ = io.Copy(io.Discard, os.Stdin)
	os.Exit(0)
}

func TestRendererExitIsReported(t *testing.T) {
	frames := engine.NewLatest[[]byte]()
	frames.Store([]byte("frame\n"))
	err := NewZelbar(helperCommand("exit", ""), time.Second).Run(context.Background(), frames)
	if err == nil {
		t.Fatal("unexpected renderer exit was accepted")
	}
}

func TestSIGTERMTimeoutKillsAndReapsRenderer(t *testing.T) {
	pidFile := t.TempDir() + "/pid"
	frames := engine.NewLatest[[]byte]()
	frames.Store([]byte("frame\n"))
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	const timeout = 40 * time.Millisecond
	go func() { done <- NewZelbar(helperCommand("ignore-term", pidFile), timeout).Run(ctx, frames) }()
	pid := waitForPID(t, pidFile)
	started := time.Now()
	cancel()
	if err := <-done; !errors.Is(err, context.Canceled) {
		t.Fatalf("shutdown returned %v", err)
	}
	if time.Since(started) < timeout {
		t.Fatal("renderer was killed before SIGTERM timeout")
	}
	if err := syscall.Kill(pid, 0); !errors.Is(err, syscall.ESRCH) {
		t.Fatalf("renderer %d was not reaped: %v", pid, err)
	}
}

func TestParentDeathSignalPreventsRendererOrphan(t *testing.T) {
	pidFile := t.TempDir() + "/child-pid"
	command := exec.Command(os.Args[0], "-test.run=^TestHelperProcess$")
	command.Env = append(os.Environ(), "RIVER_ZELBAR_HELPER=supervisor", "RIVER_ZELBAR_PID_FILE="+pidFile)
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	childPID := waitForPID(t, pidFile)
	if err := command.Process.Kill(); err != nil {
		t.Fatal(err)
	}
	_ = command.Wait()

	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if err := syscall.Kill(childPID, 0); errors.Is(err, syscall.ESRCH) {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	_ = syscall.Kill(childPID, syscall.SIGKILL)
	t.Fatalf("renderer %d survived its supervisor", childPID)
}

func helperCommand(mode, pidFile string) Command {
	environment := append(os.Environ(), "RIVER_ZELBAR_HELPER="+mode)
	if pidFile != "" {
		environment = append(environment, "RIVER_ZELBAR_PID_FILE="+pidFile)
	}
	return Command{Path: os.Args[0], Args: []string{"-test.run=^TestHelperProcess$"}, Env: environment}
}

func waitForPID(t *testing.T, path string) int {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		data, err := os.ReadFile(path)
		if err == nil {
			pid, parseErr := strconv.Atoi(string(data))
			if parseErr != nil {
				t.Fatal(parseErr)
			}
			return pid
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("helper did not write %s", path)
	return 0
}
