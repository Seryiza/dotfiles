// Package statusfmt is the only package allowed to emit Zelbar markup.
package statusfmt

import (
	"errors"
	"fmt"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/rivo/uniseg"

	"seryiza.local/river-zelbar-status/internal/model"
)

const MaxFrameBytes = 4096

var ErrInvalidUTF8 = errors.New("status text is not valid UTF-8")

// Sanitize converts untrusted source text to safe Zelbar data.
func Sanitize(value string, graphemeLimit int) (string, error) {
	if !utf8.ValidString(value) {
		return "", ErrInvalidUTF8
	}

	var safe strings.Builder
	spacePending := false
	for _, r := range value {
		if unicode.IsControl(r) || unicode.IsSpace(r) || (unicode.In(r, unicode.Cf) && r != '\u200d') {
			spacePending = safe.Len() > 0
			continue
		}
		if spacePending {
			safe.WriteByte(' ')
			spacePending = false
		}
		switch r {
		case '%':
			safe.WriteRune('％')
		case '{':
			safe.WriteRune('｛')
		case '}':
			safe.WriteRune('｝')
		default:
			safe.WriteRune(r)
		}
	}

	return truncateGraphemes(safe.String(), graphemeLimit), nil
}

// Format renders a bounded frame ending in a text block and newline.
func Format(snapshot model.Snapshot) ([]byte, error) {
	left, right, err := formattedParts(snapshot)
	if err != nil {
		return nil, err
	}

	frame := buildFrame(left, right)
	for len(frame) > MaxFrameBytes {
		trimmed := false
		for i := len(left) - 1; i >= 0 && !trimmed; i-- {
			left[i], trimmed = removeLastGrapheme(left[i])
		}
		for i := len(right) - 1; i >= 0 && !trimmed; i-- {
			right[i], trimmed = removeLastGrapheme(right[i])
		}
		if !trimmed {
			return nil, fmt.Errorf("fixed Zelbar frame exceeds %d bytes", MaxFrameBytes)
		}
		frame = buildFrame(left, right)
	}
	return []byte(frame), nil
}

func formattedParts(snapshot model.Snapshot) ([]string, []string, error) {
	left := make([]string, 0, 1)
	right := make([]string, 0, 10)
	if snapshot.Machi.Valid {
		title, err := Sanitize(snapshot.Machi.Title, 2048)
		if err != nil {
			return nil, nil, fmt.Errorf("Machi title: %w", err)
		}
		left = appendNonempty(left, title)
		if snapshot.Machi.WorkspaceCount > 0 {
			right = append(right, fmt.Sprintf("W %d/%d", snapshot.Machi.WorkspaceIndex+1, snapshot.Machi.WorkspaceCount))
		}
		if snapshot.Machi.PanelCount > 0 {
			right = append(right, fmt.Sprintf("P %d/%d", snapshot.Machi.PanelIndex+1, snapshot.Machi.PanelCount))
		}
	}

	rightValues := []struct {
		name  string
		value string
		limit int
	}{
		{"Org timeblock", snapshot.OrgTimeblock, 60},
		{"Org clock", snapshot.OrgClock, 60},
		{"audio", snapshot.Audio, 256},
		{"network", snapshot.Network, 256},
		{"WireGuard", snapshot.WireGuard, 256},
		{"XKB", snapshot.XKB, 64},
		{"battery", snapshot.Battery, 64},
		{"clock", snapshot.Clock, 64},
	}
	for _, field := range rightValues {
		value, err := Sanitize(field.value, field.limit)
		if err != nil {
			return nil, nil, fmt.Errorf("%s: %w", field.name, err)
		}
		right = appendNonempty(right, value)
	}
	return left, right, nil
}

func appendNonempty(parts []string, value string) []string {
	if value != "" {
		return append(parts, value)
	}
	return parts
}

func buildFrame(left, right []string) string {
	leftText := join(left, " · ")
	rightText := join(right, " | ")
	if leftText != "" {
		leftText = "%{X:4}" + leftText
		if rightText != "" {
			rightText = "%{G:50}" + rightText
		}
	}
	return "%{l}" + leftText + "%{r}" + rightText + " \n"
}

func join(parts []string, separator string) string {
	values := make([]string, 0, len(parts))
	for _, item := range parts {
		if item != "" {
			values = append(values, item)
		}
	}
	return strings.Join(values, separator)
}

func truncateGraphemes(value string, limit int) string {
	if limit < 0 {
		return value
	}
	graphemes := uniseg.NewGraphemes(value)
	count := 0
	end := 0
	for graphemes.Next() {
		if count == limit {
			break
		}
		_, end = graphemes.Positions()
		count++
	}
	if count < limit || end == len(value) {
		return value
	}
	return value[:end]
}

func removeLastGrapheme(value string) (string, bool) {
	graphemes := uniseg.NewGraphemes(value)
	previousStart := -1
	for graphemes.Next() {
		start, _ := graphemes.Positions()
		previousStart = start
	}
	if previousStart < 0 {
		return value, false
	}
	return value[:previousStart], true
}
