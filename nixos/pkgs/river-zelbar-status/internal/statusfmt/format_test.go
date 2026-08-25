package statusfmt

import (
	"errors"
	"strings"
	"testing"
	"unicode/utf8"

	"seryiza.local/river-zelbar-status/internal/model"
)

func TestFormatPlacesOnlyTitleLeftAndWorkspacePanelRight(t *testing.T) {
	snapshot := model.Snapshot{
		Machi:        model.MachiState{Valid: true, WorkspaceIndex: 1, WorkspaceCount: 4, PanelIndex: 0, PanelCount: 3, Mode: "split", WindowCount: 3, Title: "Current title"},
		OrgTimeblock: "Focus", Audio: "52% audio +MIC", WireGuard: "wg-work", XKB: "ru", Battery: "87% battery", Clock: "23 Aug 21:35",
	}

	got, err := Format(snapshot)
	if err != nil {
		t.Fatal(err)
	}
	want := "%{l}%{X:4}Current title%{r}W 2/4 | P 1/3 | Focus | 52％ audio +MIC | wg-work | ru | 87％ battery | 23 Aug 21:35 \n"
	if string(got) != want {
		t.Fatalf("got %q\nwant %q", got, want)
	}
	if strings.Contains(string(got), "||") || strings.Contains(string(got), "split") || strings.Contains(string(got), "3w") {
		t.Fatalf("unexpected or duplicate status module: %q", got)
	}
}

func TestFormatPreservesCompleteTextSourceOrder(t *testing.T) {
	snapshot := model.Snapshot{
		OrgTimeblock: "timeblock",
		OrgClock:     "org-clock",
		Audio:        "audio",
		Network:      "network",
		WireGuard:    "wireguard",
		XKB:          "xkb",
		Battery:      "battery",
		Clock:        "clock",
	}
	got, err := Format(snapshot)
	if err != nil {
		t.Fatal(err)
	}
	want := "%{l}%{r}timeblock | org-clock | audio | network | wireguard | xkb | battery | clock \n"
	if string(got) != want {
		t.Fatalf("got %q\nwant %q", got, want)
	}
}

func TestFormatEmptySnapshotStillEndsInTextBlock(t *testing.T) {
	got, err := Format(model.Snapshot{})
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "%{l}%{r} \n" {
		t.Fatalf("unexpected empty frame %q", got)
	}
}

func TestSanitizeControlsMarkupAndWhitespace(t *testing.T) {
	got, err := Sanitize("  title\t%{A:rm -rf /:}\n{x}\x00 end  ", 100)
	if err != nil {
		t.Fatal(err)
	}
	want := "title ％｛A:rm -rf /:｝ ｛x｝ end"
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
	if strings.Contains(got, "%{") {
		t.Fatalf("markup survived: %q", got)
	}
}

func TestSanitizePreservesUnicodeDataAndGraphemeClusters(t *testing.T) {
	input := "Кириллица 👩‍💻 e\u0301 עברית"
	got, err := Sanitize(input, 100)
	if err != nil {
		t.Fatal(err)
	}
	if got != input {
		t.Fatalf("Unicode data changed: got %q, want %q", got, input)
	}

	truncated, err := Sanitize(input, 11)
	if err != nil {
		t.Fatal(err)
	}
	if truncated != "Кириллица 👩‍💻" {
		t.Fatalf("grapheme truncation split or miscounted Unicode: %q", truncated)
	}
}

func TestSanitizeNeutralizesTrailingPercentAndBidiControls(t *testing.T) {
	got, err := Sanitize("abc\u202edef\u2066 tail%", 100)
	if err != nil {
		t.Fatal(err)
	}
	if got != "abc def tail％" {
		t.Fatalf("unsafe format controls survived: %q", got)
	}
}

func TestSanitizeRejectsInvalidUTF8(t *testing.T) {
	_, err := Sanitize(string([]byte{0xff, 'x'}), 10)
	if !errors.Is(err, ErrInvalidUTF8) {
		t.Fatalf("got %v, want ErrInvalidUTF8", err)
	}
}

func TestFormatEnforcesUTF8ByteBudgetAtGraphemeBoundary(t *testing.T) {
	snapshot := model.Snapshot{Machi: model.MachiState{Valid: true, WindowCount: 1, Title: strings.Repeat("👩‍💻", 2048)}}
	frame, err := Format(snapshot)
	if err != nil {
		t.Fatal(err)
	}
	if len(frame) > MaxFrameBytes {
		t.Fatalf("frame has %d bytes", len(frame))
	}
	if !utf8.Valid(frame) || !strings.HasSuffix(string(frame), " \n") {
		t.Fatalf("invalid frame ending or UTF-8: %q", frame[len(frame)-16:])
	}
}

func FuzzSanitize(f *testing.F) {
	f.Add("Cyrillic Кириллица 👩‍💻 %{A:x:} {}\n")
	f.Fuzz(func(t *testing.T, input string) {
		got, err := Sanitize(input, 60)
		if !utf8.ValidString(input) {
			if !errors.Is(err, ErrInvalidUTF8) {
				t.Fatalf("invalid input returned %v", err)
			}
			return
		}
		if err != nil {
			t.Fatal(err)
		}
		if !utf8.ValidString(got) || strings.ContainsAny(got, "%{}\r\n\t\x00") {
			t.Fatalf("unsafe sanitized value %q", got)
		}
	})
}
