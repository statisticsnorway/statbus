package upgrade

import (
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestSdNotifyExtendTimeout_WritesPayload verifies the EXTEND_TIMEOUT_USEC
// payload is correctly formatted and sent to NOTIFY_SOCKET. Sets up a
// fake unixgram listener (mimicking systemd's NOTIFY_SOCKET) and asserts
// the received message matches the documented sd_notify protocol.
//
// Per `man sd_notify(3)`:
//
//	EXTEND_TIMEOUT_USEC=...
//	    Tells the service manager to extend the startup, runtime or
//	    shutdown service timeout corresponding to the current state.
//	    The value specified is a time in microseconds during which the
//	    service must send a new message.
func TestSdNotifyExtendTimeout_WritesPayload(t *testing.T) {
	// Use a short /tmp path — macOS's sockaddr_un caps the unix
	// socket path at ~104 bytes; t.TempDir() paths exceed that on Darwin.
	dir, err := os.MkdirTemp("/tmp", "wd")
	if err != nil {
		t.Fatalf("mkdir tmp: %v", err)
	}
	defer os.RemoveAll(dir)
	socketPath := filepath.Join(dir, "n.sock")

	addr, err := net.ResolveUnixAddr("unixgram", socketPath)
	if err != nil {
		t.Fatalf("resolve unix addr: %v", err)
	}
	conn, err := net.ListenUnixgram("unixgram", addr)
	if err != nil {
		t.Fatalf("listen unixgram: %v", err)
	}
	defer conn.Close()

	t.Setenv("NOTIFY_SOCKET", socketPath)

	sdNotifyExtendTimeout(120 * time.Second)

	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	buf := make([]byte, 256)
	n, _, err := conn.ReadFromUnix(buf)
	if err != nil {
		t.Fatalf("read from socket: %v", err)
	}

	got := string(buf[:n])
	want := "EXTEND_TIMEOUT_USEC=120000000"
	if got != want {
		t.Errorf("payload = %q, want %q", got, want)
	}
}

// TestSdNotifyExtendTimeout_NoOpWithoutSocket verifies the no-op branch:
// when NOTIFY_SOCKET is unset (e.g. running outside systemd), the call
// returns silently without panicking. Critical for `./sb` invoked from a
// non-systemd shell — must not break local development.
func TestSdNotifyExtendTimeout_NoOpWithoutSocket(t *testing.T) {
	t.Setenv("NOTIFY_SOCKET", "")
	// Should not panic, should not error. A 30s argument exercises the
	// usec conversion path without any side effect because the env var
	// is empty.
	sdNotifyExtendTimeout(30 * time.Second)
}

// TestSdNotifyExtendTimeout_NegativeDurationNoOp verifies that negative
// durations don't produce malformed payloads (negative microseconds are
// nonsense for systemd; callers passing them are likely buggy and we
// shouldn't propagate to systemd).
func TestSdNotifyExtendTimeout_NegativeDurationNoOp(t *testing.T) {
	// Use a short /tmp path — macOS's sockaddr_un caps the unix
	// socket path at ~104 bytes; t.TempDir() paths exceed that on Darwin.
	dir, err := os.MkdirTemp("/tmp", "wd")
	if err != nil {
		t.Fatalf("mkdir tmp: %v", err)
	}
	defer os.RemoveAll(dir)
	socketPath := filepath.Join(dir, "n.sock")

	addr, err := net.ResolveUnixAddr("unixgram", socketPath)
	if err != nil {
		t.Fatalf("resolve unix addr: %v", err)
	}
	conn, err := net.ListenUnixgram("unixgram", addr)
	if err != nil {
		t.Fatalf("listen unixgram: %v", err)
	}
	defer conn.Close()

	t.Setenv("NOTIFY_SOCKET", socketPath)

	sdNotifyExtendTimeout(-1 * time.Second)

	conn.SetReadDeadline(time.Now().Add(200 * time.Millisecond))
	buf := make([]byte, 256)
	if n, _, err := conn.ReadFromUnix(buf); err == nil && n > 0 {
		t.Errorf("unexpected payload received: %q (negative duration should be a no-op)", string(buf[:n]))
	}
}

// TestSdNotifyExtendTimeout_VariousDurations verifies the usec scaling
// is correct for a range of input durations. Edge cases: zero, sub-second,
// multi-minute.
func TestSdNotifyExtendTimeout_VariousDurations(t *testing.T) {
	cases := []struct {
		name string
		d    time.Duration
		want string
	}{
		{"zero", 0, "EXTEND_TIMEOUT_USEC=0"},
		{"500ms", 500 * time.Millisecond, "EXTEND_TIMEOUT_USEC=500000"},
		{"5m", 5 * time.Minute, "EXTEND_TIMEOUT_USEC=300000000"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			dir, err := os.MkdirTemp("/tmp", "wd")
			if err != nil {
				t.Fatalf("mkdir tmp: %v", err)
			}
			defer os.RemoveAll(dir)
			socketPath := filepath.Join(dir, "n.sock")

			addr, err := net.ResolveUnixAddr("unixgram", socketPath)
			if err != nil {
				t.Fatalf("resolve: %v", err)
			}
			conn, err := net.ListenUnixgram("unixgram", addr)
			if err != nil {
				t.Fatalf("listen: %v", err)
			}
			defer conn.Close()

			t.Setenv("NOTIFY_SOCKET", socketPath)

			sdNotifyExtendTimeout(tc.d)

			conn.SetReadDeadline(time.Now().Add(2 * time.Second))
			buf := make([]byte, 256)
			n, _, err := conn.ReadFromUnix(buf)
			if err != nil {
				t.Fatalf("read: %v", err)
			}
			got := string(buf[:n])
			if got != tc.want {
				t.Errorf("payload = %q, want %q", got, tc.want)
			}
		})
	}
}

// TestEmitHeartbeat_WritesAllSignals verifies the unified emitHeartbeat
// fires WATCHDOG=1 to NOTIFY_SOCKET and writes the timestamp to the
// heartbeat file. (Existing behaviour, but no test covered it; adding
// for symmetry with the new sdNotifyExtendTimeout coverage.)
func TestEmitHeartbeat_WritesAllSignals(t *testing.T) {
	// Use a short /tmp path — macOS's sockaddr_un caps the unix
	// socket path at ~104 bytes; t.TempDir() paths exceed that on Darwin.
	dir, err := os.MkdirTemp("/tmp", "wd")
	if err != nil {
		t.Fatalf("mkdir tmp: %v", err)
	}
	defer os.RemoveAll(dir)
	socketPath := filepath.Join(dir, "n.sock")
	addr, err := net.ResolveUnixAddr("unixgram", socketPath)
	if err != nil {
		t.Fatalf("resolve: %v", err)
	}
	conn, err := net.ListenUnixgram("unixgram", addr)
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer conn.Close()

	t.Setenv("NOTIFY_SOCKET", socketPath)

	// Pre-create tmp/ so the WriteFile's first attempt succeeds; otherwise
	// emitHeartbeat falls back to MkdirAll which is also valid but
	// branches differently.
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0755); err != nil {
		t.Fatalf("mkdir tmp: %v", err)
	}

	emitHeartbeat(dir)

	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	buf := make([]byte, 256)
	n, _, err := conn.ReadFromUnix(buf)
	if err != nil {
		t.Fatalf("read socket: %v", err)
	}
	if got := string(buf[:n]); got != "WATCHDOG=1" {
		t.Errorf("socket payload = %q, want %q", got, "WATCHDOG=1")
	}

	hbPath := heartbeatPath(dir)
	content, err := os.ReadFile(hbPath)
	if err != nil {
		t.Fatalf("read heartbeat: %v", err)
	}
	if !strings.HasPrefix(string(content), "1") && !strings.HasPrefix(string(content), "2") {
		t.Errorf("heartbeat content %q does not look like a unix timestamp", string(content))
	}
}
