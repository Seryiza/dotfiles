package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"seryiza.local/river-zelbar-status/internal/engine"
	"seryiza.local/river-zelbar-status/internal/machi"
	"seryiza.local/river-zelbar-status/internal/renderer"
	"seryiza.local/river-zelbar-status/internal/riverxkb"
	"seryiza.local/river-zelbar-status/internal/statusfmt"
	"seryiza.local/river-zelbar-status/internal/statussource"
)

var (
	zelbarDefault       string
	machictlDefault     string
	orgTimeblockDefault string
	wireGuardDefault    string
	wpctlDefault        string
	nmcliDefault        string
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "river-zelbar-status: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	const output = "eDP-1"

	flags := flag.NewFlagSet("river-zelbar-status", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	zelbarPath := flags.String("zelbar", zelbarDefault, "absolute path to the Zelbar executable")
	machictlPath := flags.String("machictl", machictlDefault, "absolute path to the machictl executable")
	if err := flags.Parse(os.Args[1:]); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return fmt.Errorf("unexpected arguments: %v", flags.Args())
	}
	paths := map[string]string{
		"--zelbar":               *zelbarPath,
		"--machictl":             *machictlPath,
		"packaged org-timeblock": orgTimeblockDefault,
		"packaged wireguard":     wireGuardDefault,
		"packaged wpctl":         wpctlDefault,
		"packaged nmcli":         nmcliDefault,
	}
	for name, path := range paths {
		if path == "" || !filepath.IsAbs(path) {
			return fmt.Errorf("configuration: %s must be an absolute executable path", name)
		}
	}

	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	if !filepath.IsAbs(runtimeDir) {
		return errors.New("configuration: XDG_RUNTIME_DIR must be an absolute path")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	zelbar := renderer.NewZelbar(renderer.Command{
		Path: *zelbarPath,
		Args: []string{
			"-o", output,
			"-L", "1",
			"-g", "0:20",
			"-fn", "Iosevka,Noto Color Emoji",
			"-B", "0xFFFFFFFF",
			"-F", "0x000000FF",
		},
	}, 3*time.Second)

	runner := statussource.ExecRunner{}
	sources := []engine.Source{
		machi.New(machi.Command{Path: *machictlPath}, output),
		riverxkb.NewSource(),
		statussource.NewOrgTimeblock(statussource.Command{Path: orgTimeblockDefault, Args: []string{"--state"}}, runner, nil),
		statussource.NewOrgClock(filepath.Join(runtimeDir, "river-zelbar-status-org-clock")),
		statussource.NewAudio(statussource.Command{Path: wpctlDefault}, runner),
		statussource.NewNetwork(statussource.Command{Path: nmcliDefault}, runner),
		statussource.NewWireGuard(statussource.Command{Path: wireGuardDefault}, runner),
		statussource.NewBattery("/sys/class/power_supply"),
		statussource.NewClock(nil),
	}
	return engine.Run(ctx, sources, zelbar, statusfmt.Format)
}
