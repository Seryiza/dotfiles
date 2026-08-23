package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"seryiza.local/river-zelbar-status/internal/engine"
	"seryiza.local/river-zelbar-status/internal/renderer"
	"seryiza.local/river-zelbar-status/internal/statusfmt"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "river-zelbar-status: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	flags := flag.NewFlagSet("river-zelbar-status", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	zelbarPath := flags.String("zelbar", "", "absolute path to the Zelbar executable")
	if err := flags.Parse(os.Args[1:]); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return fmt.Errorf("unexpected arguments: %v", flags.Args())
	}
	if *zelbarPath == "" || !filepath.IsAbs(*zelbarPath) {
		return fmt.Errorf("configuration: --zelbar must be an absolute executable path")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	zelbar := renderer.NewZelbar(renderer.Command{
		Path: *zelbarPath,
		Args: []string{
			"-o", "eDP-1",
			"-L", "1",
			"-g", "0:20",
			"-fn", "Iosevka,Noto Color Emoji",
			"-B", "0xFFFFFFFF",
			"-F", "0x000000FF",
		},
	}, 3*time.Second)

	// Source adapters are added by the Machi/XKB and text-source tickets. The
	// core already renders and supervises the initial typed snapshot.
	return engine.Run(ctx, nil, zelbar, statusfmt.Format)
}
