package renderer

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"syscall"
	"time"

	"seryiza.local/river-zelbar-status/internal/engine"
)

type Command struct {
	Path string
	Args []string
	Env  []string
}

type Zelbar struct {
	command     Command
	stopTimeout time.Duration
}

func NewZelbar(command Command, stopTimeout time.Duration) *Zelbar {
	return &Zelbar{command: command, stopTimeout: stopTimeout}
}

// Run starts Zelbar with a packet socket as stdin and owns it until it is
// reaped. On shutdown the socket is closed only after SIGTERM/timeout/reap.
func (zelbar *Zelbar) Run(ctx context.Context, frames *engine.Latest[[]byte]) error {
	fds, err := socketPair()
	if err != nil {
		return fmt.Errorf("create renderer socketpair: %w", err)
	}
	parent := os.NewFile(uintptr(fds[0]), "zelbar-packet-parent")
	child := os.NewFile(uintptr(fds[1]), "zelbar-packet-child")
	started := false
	defer func() {
		if !started {
			_ = parent.Close()
			_ = child.Close()
		}
	}()

	devNull, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	if err != nil {
		return fmt.Errorf("open /dev/null: %w", err)
	}
	defer func() {
		if !started {
			_ = devNull.Close()
		}
	}()

	cmd := exec.Command(zelbar.command.Path, zelbar.command.Args...)
	cmd.Stdin = child
	cmd.Stdout = devNull
	cmd.Stderr = os.Stderr
	if zelbar.command.Env != nil {
		cmd.Env = zelbar.command.Env
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGTERM}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start renderer: %w", err)
	}
	started = true
	_ = child.Close()
	_ = devNull.Close()

	waited := make(chan error, 1)
	go func() { waited <- cmd.Wait() }()

	for {
		select {
		case waitErr := <-waited:
			_ = parent.Close()
			if waitErr == nil {
				return errors.New("renderer exited successfully while supervisor was running")
			}
			return fmt.Errorf("renderer exited: %w", waitErr)
		case <-ctx.Done():
			stopped := terminateAndReap(cmd, waited, zelbar.stopTimeout)
			if stopped.reaped {
				_ = parent.Close()
			}
			if stopped.err != nil && !isSignalExit(stopped.err) {
				return fmt.Errorf("stop renderer: %w", stopped.err)
			}
			return ctx.Err()
		case <-frames.Notify():
			frame, ok := frames.Load()
			if !ok {
				continue
			}
			if err := SendFrame(int(parent.Fd()), frame); err != nil {
				stopped := terminateAndReap(cmd, waited, zelbar.stopTimeout)
				if stopped.reaped {
					_ = parent.Close()
				}
				return errors.Join(err, stopped.err)
			}
		}
	}
}

type reapResult struct {
	err    error
	reaped bool
}

func terminateAndReap(cmd *exec.Cmd, waited <-chan error, timeout time.Duration) reapResult {
	termErr := cmd.Process.Signal(syscall.SIGTERM)
	if termErr != nil && !errors.Is(termErr, os.ErrProcessDone) {
		killErr := cmd.Process.Kill()
		if killErr != nil && !errors.Is(killErr, os.ErrProcessDone) {
			return reapResult{err: errors.Join(termErr, killErr)}
		}
		return reapResult{err: errors.Join(termErr, <-waited), reaped: true}
	}

	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case err := <-waited:
		return reapResult{err: err, reaped: true}
	case <-timer.C:
		killErr := cmd.Process.Kill()
		if killErr != nil && !errors.Is(killErr, os.ErrProcessDone) {
			return reapResult{err: killErr}
		}
		return reapResult{err: <-waited, reaped: true}
	}
}

func isSignalExit(err error) bool {
	var exitErr *exec.ExitError
	if !errors.As(err, &exitErr) || exitErr.ProcessState == nil {
		return false
	}
	status, ok := exitErr.ProcessState.Sys().(syscall.WaitStatus)
	return ok && status.Signaled()
}
