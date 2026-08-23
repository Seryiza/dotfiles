package engine

import (
	"context"
	"errors"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"seryiza.local/river-zelbar-status/internal/model"
	"seryiza.local/river-zelbar-status/internal/statusfmt"
)

type sourceFunc func(context.Context, Sink) error

func (fn sourceFunc) Run(ctx context.Context, sink Sink) error { return fn(ctx, sink) }

type rendererFunc func(context.Context, *Latest[[]byte]) error

func (fn rendererFunc) Run(ctx context.Context, frames *Latest[[]byte]) error { return fn(ctx, frames) }

func TestEventMailboxCoalescesNewestUpdatePerField(t *testing.T) {
	mailbox := newEventMailbox()
	ctx := context.Background()
	firstAudio := model.FieldUpdate(model.FieldAudio, "10% audio")
	latestAudio := model.FieldUpdate(model.FieldAudio, "20% audio")
	xkb := model.FieldUpdate(model.FieldXKB, "ru")
	if err := mailbox.Publish(ctx, Event{Update: &firstAudio}); err != nil {
		t.Fatal(err)
	}
	if err := mailbox.Publish(ctx, Event{Update: &latestAudio}); err != nil {
		t.Fatal(err)
	}
	if err := mailbox.Publish(ctx, Event{Update: &xkb}); err != nil {
		t.Fatal(err)
	}

	state := model.Snapshot{}
	events := mailbox.take()
	if len(events) != 2 {
		t.Fatalf("got %d pending fields, want 2", len(events))
	}
	for _, event := range events {
		state = model.Reduce(state, *event.Update)
	}
	if state.Audio != "20% audio" || state.XKB != "ru" {
		t.Fatalf("coalesced state = %#v", state)
	}
}

func TestLatestCoalescesToNewestValue(t *testing.T) {
	latest := NewLatest[int]()
	latest.Store(1)
	latest.Store(2)
	latest.Store(3)
	got, ok := latest.Next(context.Background())
	if !ok || got != 3 {
		t.Fatalf("got %d, %v; want 3, true", got, ok)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
	defer cancel()
	if _, ok := latest.Next(ctx); ok {
		t.Fatal("mailbox queued more than one notification")
	}
}

func TestProducerExitStopsRenderer(t *testing.T) {
	rendererStopped := make(chan struct{})
	renderer := rendererFunc(func(ctx context.Context, _ *Latest[[]byte]) error {
		<-ctx.Done()
		close(rendererStopped)
		return ctx.Err()
	})
	producerErr := errors.New("producer died")
	source := sourceFunc(func(context.Context, Sink) error { return producerErr })

	err := Run(context.Background(), []Source{source}, renderer, statusfmt.Format)
	var fault *Fault
	if !errors.As(err, &fault) || fault.Class != Fatal || !errors.Is(err, producerErr) {
		t.Fatalf("unexpected error: %v", err)
	}
	select {
	case <-rendererStopped:
	default:
		t.Fatal("renderer was not stopped")
	}
}

func TestRendererExitStopsSources(t *testing.T) {
	sourceStopped := make(chan struct{})
	source := sourceFunc(func(ctx context.Context, _ Sink) error {
		<-ctx.Done()
		close(sourceStopped)
		return ctx.Err()
	})
	rendererErr := errors.New("renderer died")
	renderer := rendererFunc(func(context.Context, *Latest[[]byte]) error { return rendererErr })

	err := Run(context.Background(), []Source{source}, renderer, statusfmt.Format)
	if !errors.Is(err, rendererErr) {
		t.Fatalf("unexpected error: %v", err)
	}
	select {
	case <-sourceStopped:
	default:
		t.Fatal("source was not stopped")
	}
}

func TestSupervisorCancellationStopsWholeGraphNormally(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	var stopped atomic.Int32
	wait := func(ctx context.Context) error {
		<-ctx.Done()
		stopped.Add(1)
		return ctx.Err()
	}
	source := sourceFunc(func(ctx context.Context, _ Sink) error { return wait(ctx) })
	renderer := rendererFunc(func(ctx context.Context, _ *Latest[[]byte]) error { return wait(ctx) })
	cancel()

	if err := Run(ctx, []Source{source}, renderer, statusfmt.Format); err != nil {
		t.Fatalf("normal cancellation returned %v", err)
	}
	if stopped.Load() != 2 {
		t.Fatalf("stopped %d components, want 2", stopped.Load())
	}
}

func TestOptionalSourceFailureDegradesWithoutRestart(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	gotFrame := make(chan string, 1)
	update := model.FieldUpdate(model.FieldAudio, "audio?")
	source := sourceFunc(func(ctx context.Context, sink Sink) error {
		if err := sink.Publish(ctx, Event{Update: &update, Warning: &Fault{Class: Nonfatal, Source: "audio", Err: errors.New("wpctl failed")}}); err != nil {
			return err
		}
		<-ctx.Done()
		return ctx.Err()
	})
	renderer := rendererFunc(func(ctx context.Context, frames *Latest[[]byte]) error {
		for {
			frame, ok := frames.Next(ctx)
			if !ok {
				return ctx.Err()
			}
			if strings.Contains(string(frame), "audio?") {
				gotFrame <- string(frame)
				cancel()
				return ctx.Err()
			}
		}
	})

	if err := Run(ctx, []Source{source}, renderer, statusfmt.Format); err != nil {
		t.Fatalf("optional failure restarted graph: %v", err)
	}
	select {
	case <-gotFrame:
	default:
		t.Fatal("degraded field was not rendered")
	}
}
