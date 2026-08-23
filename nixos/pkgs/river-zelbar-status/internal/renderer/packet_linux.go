package renderer

import (
	"errors"
	"fmt"
	"unicode/utf8"

	"golang.org/x/sys/unix"
)

const MaxPacketBytes = 4096

var (
	ErrFrameSize = errors.New("renderer frame must be between 1 and 4096 bytes")
	ErrFrameUTF8 = errors.New("renderer frame is not valid UTF-8")
	ErrFrameLine = errors.New("renderer frame must end with one newline")
)

func socketPair() ([2]int, error) {
	return unix.Socketpair(unix.AF_UNIX, unix.SOCK_SEQPACKET|unix.SOCK_CLOEXEC, 0)
}

// SendFrame validates the complete frame before making exactly one packet send.
func SendFrame(fd int, frame []byte) error {
	if len(frame) < 1 || len(frame) > MaxPacketBytes {
		return fmt.Errorf("%w: got %d bytes", ErrFrameSize, len(frame))
	}
	if !utf8.Valid(frame) {
		return ErrFrameUTF8
	}
	if frame[len(frame)-1] != '\n' || (len(frame) > 1 && frame[len(frame)-2] == '\n') {
		return ErrFrameLine
	}
	if err := unix.Send(fd, frame, unix.MSG_NOSIGNAL|unix.MSG_DONTWAIT); err != nil {
		return fmt.Errorf("send renderer frame: %w", err)
	}
	return nil
}
