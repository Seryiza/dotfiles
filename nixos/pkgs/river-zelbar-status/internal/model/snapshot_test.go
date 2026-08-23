package model

import "testing"

func TestReduceReplacesFieldsAndSupportsClearing(t *testing.T) {
	initial := Snapshot{Audio: "51% audio", XKB: "us"}
	updated := Reduce(initial, FieldUpdate(FieldAudio, "MUTED"))
	cleared := Reduce(updated, FieldUpdate(FieldAudio, ""))

	if updated.Audio != "MUTED" || updated.XKB != "us" {
		t.Fatalf("unexpected update: %#v", updated)
	}
	if cleared.Audio != "" || cleared.XKB != "us" {
		t.Fatalf("unexpected clear: %#v", cleared)
	}
	if initial.Audio != "51% audio" {
		t.Fatalf("previous snapshot was mutated: %#v", initial)
	}
}

func TestReduceReplacesCompleteMachiSnapshotAtomically(t *testing.T) {
	initial := Snapshot{Machi: MachiState{Valid: true, Mode: "split", Title: "old", WindowCount: 2}}
	fresh := MachiState{Valid: true, WorkspaceIndex: 1, WorkspaceCount: 4, PanelIndex: 0, PanelCount: 3, Mode: "stack", WindowCount: 5, Title: "new"}

	got := Reduce(initial, MachiUpdate(fresh))
	if got.Machi != fresh {
		t.Fatalf("got %#v, want %#v", got.Machi, fresh)
	}
	if initial.Machi.Title != "old" {
		t.Fatal("previous Machi snapshot was mutated")
	}
}
