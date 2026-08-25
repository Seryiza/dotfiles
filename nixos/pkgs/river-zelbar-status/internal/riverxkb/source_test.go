package riverxkb_test

import (
	"context"
	"testing"

	"seryiza.local/river-zelbar-status/internal/engine"
	"seryiza.local/river-zelbar-status/internal/model"
	"seryiza.local/river-zelbar-status/internal/riverxkb"
)

type xkbSink struct{ values []string }

func (sink *xkbSink) Publish(_ context.Context, event engine.Event) error {
	if event.Update != nil {
		snapshot := model.Reduce(model.Snapshot{}, *event.Update)
		sink.values = append(sink.values, snapshot.XKB)
	}
	return nil
}

func TestTrackerPublishesInitialAndSwitchedLayoutOnDone(t *testing.T) {
	sink := &xkbSink{}
	tracker := riverxkb.NewTracker(sink, []string{"us", "ru"})
	tracker.Add(10)
	mustLayout(t, tracker, 10, 0)
	mustDone(t, tracker, 10)
	mustLayout(t, tracker, 10, 1)
	mustDone(t, tracker, 10)
	assertLayouts(t, sink.values, []string{"us", "ru"})
}

func TestTrackerAggregatesMultipleKeyboards(t *testing.T) {
	t.Run("equal", func(t *testing.T) {
		sink := &xkbSink{}
		tracker := riverxkb.NewTracker(sink, []string{"us", "ru"})
		tracker.Add(1)
		mustLayout(t, tracker, 1, 0)
		mustDone(t, tracker, 1)
		tracker.Add(2)
		mustLayout(t, tracker, 2, 0)
		mustDone(t, tracker, 2)
		assertLayouts(t, sink.values, []string{"us", "us"})
	})

	t.Run("mixed then removal", func(t *testing.T) {
		sink := &xkbSink{}
		tracker := riverxkb.NewTracker(sink, []string{"us", "ru"})
		tracker.Add(1)
		mustLayout(t, tracker, 1, 0)
		mustDone(t, tracker, 1)
		tracker.Add(2)
		mustLayout(t, tracker, 2, 1)
		mustDone(t, tracker, 2)
		if err := tracker.Remove(context.Background(), 2); err != nil {
			t.Fatal(err)
		}
		assertLayouts(t, sink.values, []string{"us", "mixed", "us"})
	})
}

func TestTrackerDoesNotCommitLayoutUntilDone(t *testing.T) {
	sink := &xkbSink{}
	tracker := riverxkb.NewTracker(sink, []string{"us", "ru"})
	tracker.Add(1)
	mustLayout(t, tracker, 1, 0)
	if len(sink.values) != 0 {
		t.Fatalf("layout published before done: %v", sink.values)
	}
}

func mustLayout(t *testing.T, tracker *riverxkb.Tracker, id, index uint32) {
	t.Helper()
	if err := tracker.Layout(id, index); err != nil {
		t.Fatal(err)
	}
}

func mustDone(t *testing.T, tracker *riverxkb.Tracker, id uint32) {
	t.Helper()
	if err := tracker.Done(context.Background(), id); err != nil {
		t.Fatal(err)
	}
}

func assertLayouts(t *testing.T, got, want []string) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("layouts = %v, want %v", got, want)
	}
	for index := range want {
		if got[index] != want[index] {
			t.Fatalf("layouts = %v, want %v", got, want)
		}
	}
}
