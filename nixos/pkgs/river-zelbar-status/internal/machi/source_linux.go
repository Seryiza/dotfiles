//go:build linux

// Package machi adapts machictl's complete NDJSON snapshots to typed status updates.
package machi

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os/exec"

	"seryiza.local/river-zelbar-status/internal/engine"
	"seryiza.local/river-zelbar-status/internal/model"
)

type Command struct {
	Path string
	Args []string
	Env  []string
}

type Source struct {
	command Command
	output  string
}

func New(command Command, output string) *Source {
	return &Source{command: command, output: output}
}

type wireSnapshot struct {
	Name                  *string        `json:"name"`
	CurrentWorkspaceIndex *uint32        `json:"current_workspace_index"`
	TotalWorkspaces       *uint32        `json:"total_workspaces"`
	TotalSeats            *uint32        `json:"total_seats"`
	Workspace             *wireWorkspace `json:"workspace_info"`
	Panel                 *wirePanel     `json:"panel_info"`
	Window                *wireWindow    `json:"window_info"`
}

type wireWorkspace struct {
	CurrentPanelIndex *uint32 `json:"current_panel_index"`
	TotalPanels       *uint32 `json:"total_panels"`
}

type wirePanel struct {
	TotalWindows *uint32 `json:"total_windows"`
	Mode         *string `json:"mode"`
}

type wireWindow struct {
	Title json.RawMessage `json:"title"`
}

func (source *Source) Run(ctx context.Context, sink engine.Sink) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	args := append(append([]string{}, source.command.Args...), "-watch", source.output)
	cmd := exec.CommandContext(ctx, source.command.Path, args...)
	cmd.Env = source.command.Env
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("machictl stdout: %w", err)
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start machictl: %w", err)
	}

	stop := func() {
		if cmd.Process != nil {
			_ = cmd.Process.Kill()
		}
		_ = cmd.Wait()
	}
	scanner := bufio.NewScanner(stdout)
	for scanner.Scan() {
		state, decodeErr := decodeSnapshot(scanner.Bytes(), source.output)
		if decodeErr != nil {
			stop()
			return decodeErr
		}
		update := model.MachiUpdate(state)
		if publishErr := sink.Publish(ctx, engine.Event{Update: &update}); publishErr != nil {
			stop()
			return publishErr
		}
	}
	if scanErr := scanner.Err(); scanErr != nil {
		stop()
		if ctx.Err() != nil {
			return ctx.Err()
		}
		return fmt.Errorf("read machictl stream: %w", scanErr)
	}
	killed := cmd.Process.Kill() == nil
	waitErr := cmd.Wait()
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if waitErr != nil && (!killed || cmd.ProcessState.ExitCode() >= 0) {
		return fmt.Errorf("machictl exited: %w", waitErr)
	}
	return io.ErrUnexpectedEOF
}

func decodeSnapshot(line []byte, output string) (model.MachiState, error) {
	decoder := json.NewDecoder(bytes.NewReader(line))
	decoder.DisallowUnknownFields()
	var snapshot wireSnapshot
	if err := decoder.Decode(&snapshot); err != nil {
		return model.MachiState{}, fmt.Errorf("decode snapshot: %w", err)
	}
	if err := ensureJSONEnd(decoder); err != nil {
		return model.MachiState{}, fmt.Errorf("decode snapshot: %w", err)
	}
	if err := validateSchema(snapshot, output); err != nil {
		return model.MachiState{}, err
	}
	title := ""
	if !bytes.Equal(snapshot.Window.Title, []byte("null")) {
		if err := json.Unmarshal(snapshot.Window.Title, &title); err != nil {
			return model.MachiState{}, fmt.Errorf("Machi snapshot schema: title: %w", err)
		}
	}
	return model.MachiState{
		Valid:          true,
		WorkspaceIndex: int(*snapshot.CurrentWorkspaceIndex),
		WorkspaceCount: int(*snapshot.TotalWorkspaces),
		PanelIndex:     int(*snapshot.Workspace.CurrentPanelIndex),
		PanelCount:     int(*snapshot.Workspace.TotalPanels),
		Mode:           *snapshot.Panel.Mode,
		WindowCount:    int(*snapshot.Panel.TotalWindows),
		Title:          title,
	}, nil
}

func ensureJSONEnd(decoder *json.Decoder) error {
	var extra any
	if err := decoder.Decode(&extra); errors.Is(err, io.EOF) {
		return nil
	} else if err != nil {
		return err
	}
	return errors.New("multiple JSON values on one line")
}

func validateSchema(snapshot wireSnapshot, output string) error {
	if snapshot.Name == nil || snapshot.CurrentWorkspaceIndex == nil || snapshot.TotalWorkspaces == nil || snapshot.TotalSeats == nil || snapshot.Workspace == nil || snapshot.Panel == nil || snapshot.Window == nil || snapshot.Workspace.CurrentPanelIndex == nil || snapshot.Workspace.TotalPanels == nil || snapshot.Panel.TotalWindows == nil || snapshot.Panel.Mode == nil || snapshot.Window.Title == nil {
		return errors.New("Machi snapshot schema: missing required field")
	}
	if *snapshot.Name != output {
		return fmt.Errorf("unexpected output %q, want %q", *snapshot.Name, output)
	}
	if *snapshot.Panel.Mode != "single" && *snapshot.Panel.Mode != "split" {
		return fmt.Errorf("Machi snapshot schema: unknown panel mode %q", *snapshot.Panel.Mode)
	}
	if (*snapshot.TotalWorkspaces == 0 && *snapshot.CurrentWorkspaceIndex != 0) || (*snapshot.TotalWorkspaces > 0 && *snapshot.CurrentWorkspaceIndex >= *snapshot.TotalWorkspaces) {
		return fmt.Errorf("workspace index %d is invalid for count %d", *snapshot.CurrentWorkspaceIndex, *snapshot.TotalWorkspaces)
	}
	if (*snapshot.Workspace.TotalPanels == 0 && *snapshot.Workspace.CurrentPanelIndex != 0) || (*snapshot.Workspace.TotalPanels > 0 && *snapshot.Workspace.CurrentPanelIndex >= *snapshot.Workspace.TotalPanels) {
		return fmt.Errorf("panel index %d is invalid for count %d", *snapshot.Workspace.CurrentPanelIndex, *snapshot.Workspace.TotalPanels)
	}
	return nil
}
