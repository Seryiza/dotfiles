package renderer

import (
	"errors"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

func TestSocketPairPreservesSeparateQueuedFrames(t *testing.T) {
	fds, err := socketPair()
	if err != nil {
		t.Fatal(err)
	}
	defer unix.Close(fds[0])
	defer unix.Close(fds[1])

	if err := SendFrame(fds[0], []byte("first\n")); err != nil {
		t.Fatal(err)
	}
	if err := SendFrame(fds[0], []byte("second\n")); err != nil {
		t.Fatal(err)
	}

	buffer := make([]byte, MaxPacketBytes)
	first, _, err := unix.Recvfrom(fds[1], buffer, 0)
	if err != nil {
		t.Fatal(err)
	}
	if string(buffer[:first]) != "first\n" {
		t.Fatalf("first packet = %q", buffer[:first])
	}
	second, _, err := unix.Recvfrom(fds[1], buffer, 0)
	if err != nil {
		t.Fatal(err)
	}
	if string(buffer[:second]) != "second\n" {
		t.Fatalf("second packet = %q", buffer[:second])
	}
}

func TestSendFrameAcceptsExactly4096Bytes(t *testing.T) {
	fds, err := socketPair()
	if err != nil {
		t.Fatal(err)
	}
	defer unix.Close(fds[0])
	defer unix.Close(fds[1])
	frame := []byte(strings.Repeat("x", MaxPacketBytes-1) + "\n")
	if err := SendFrame(fds[0], frame); err != nil {
		t.Fatal(err)
	}
	buffer := make([]byte, MaxPacketBytes)
	n, _, err := unix.Recvfrom(fds[1], buffer, 0)
	if err != nil {
		t.Fatal(err)
	}
	if n != MaxPacketBytes {
		t.Fatalf("received %d bytes", n)
	}
}

func TestSendFrameDoesNotBlockBehindStalledRenderer(t *testing.T) {
	fds, err := socketPair()
	if err != nil {
		t.Fatal(err)
	}
	defer unix.Close(fds[0])
	defer unix.Close(fds[1])
	frame := []byte(strings.Repeat("x", MaxPacketBytes-1) + "\n")
	started := time.Now()
	for attempts := 0; ; attempts++ {
		err := SendFrame(fds[0], frame)
		if errors.Is(err, unix.EAGAIN) || errors.Is(err, unix.EWOULDBLOCK) {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		if attempts > 10000 {
			t.Fatal("socket did not apply bounded backpressure")
		}
	}
	if time.Since(started) > time.Second {
		t.Fatal("send blocked behind non-reading renderer")
	}
}

func TestSendFrameRejects4097BytesBeforeSend(t *testing.T) {
	fds, err := socketPair()
	if err != nil {
		t.Fatal(err)
	}
	defer unix.Close(fds[0])
	defer unix.Close(fds[1])
	if err := unix.SetNonblock(fds[1], true); err != nil {
		t.Fatal(err)
	}
	frame := []byte(strings.Repeat("x", MaxPacketBytes) + "\n")
	if err := SendFrame(fds[0], frame); !errors.Is(err, ErrFrameSize) {
		t.Fatalf("got %v", err)
	}
	buffer := make([]byte, MaxPacketBytes+1)
	if _, _, err := unix.Recvfrom(fds[1], buffer, 0); !errors.Is(err, unix.EAGAIN) && !errors.Is(err, unix.EWOULDBLOCK) {
		t.Fatalf("oversize frame reached socket: %v", err)
	}
}
