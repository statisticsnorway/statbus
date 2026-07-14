package upgrade

import (
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestEmitHeartbeat_WritesAllSignals verifies the unified emitHeartbeat
// fires WATCHDOG=1 to NOTIFY_SOCKET and writes the timestamp to the
// heartbeat file.
//
// (Historical note: this file also held four
// TestSdNotifyExtendTimeout_* cases until 2026-05-23, when
// sdNotifyExtendTimeout was deleted alongside the Race B watchdog
// fix. Active-phase tickers use sdNotify("WATCHDOG=1") directly;
// the EXTEND_TIMEOUT_USEC primitive had no remaining production
// caller after the migrate-ticker replacement, so the function and
// its tests were removed rather than preserved as defensive cover.)
func TestEmitHeartbeat_WritesAllSignals(t *testing.T) {
	// Use a short /tmp path — macOS's sockaddr_un caps the unix
	// socket path at ~104 bytes; t.TempDir() paths exceed that on Darwin.
	dir, err := os.MkdirTemp("/tmp", "wd")
	if err != nil {
		t.Fatalf("mkdir tmp: %v", err)
	}
	defer func() { _ = os.RemoveAll(dir) }()
	socketPath := filepath.Join(dir, "n.sock")
	addr, err := net.ResolveUnixAddr("unixgram", socketPath)
	if err != nil {
		t.Fatalf("resolve: %v", err)
	}
	conn, err := net.ListenUnixgram("unixgram", addr)
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer func() { _ = conn.Close() }()

	t.Setenv("NOTIFY_SOCKET", socketPath)

	// Pre-create tmp/ so the WriteFile's first attempt succeeds; otherwise
	// emitHeartbeat falls back to MkdirAll which is also valid but
	// branches differently.
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0755); err != nil {
		t.Fatalf("mkdir tmp: %v", err)
	}

	emitHeartbeat(dir)

	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
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

// TestSdNotifyWatchdog_WritesPayload verifies the ad-hoc
// sdNotify("WATCHDOG=1") path used by the applyNewSbUpgrading migrate
// ticker. The migrate ticker bypasses emitHeartbeat (which also
// writes the heartbeat file + logs a journal line — overkill for
// the per-30s subprocess-keepalive cadence) and just resets the
// watchdog. This test confirms the active-phase primitive is on
// the socket exactly as systemd expects to receive it.
func TestSdNotifyWatchdog_WritesPayload(t *testing.T) {
	dir, err := os.MkdirTemp("/tmp", "wd")
	if err != nil {
		t.Fatalf("mkdir tmp: %v", err)
	}
	defer func() { _ = os.RemoveAll(dir) }()
	socketPath := filepath.Join(dir, "n.sock")
	addr, err := net.ResolveUnixAddr("unixgram", socketPath)
	if err != nil {
		t.Fatalf("resolve: %v", err)
	}
	conn, err := net.ListenUnixgram("unixgram", addr)
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer func() { _ = conn.Close() }()

	t.Setenv("NOTIFY_SOCKET", socketPath)

	sdNotify("WATCHDOG=1")

	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	buf := make([]byte, 256)
	n, _, err := conn.ReadFromUnix(buf)
	if err != nil {
		t.Fatalf("read socket: %v", err)
	}
	if got := string(buf[:n]); got != "WATCHDOG=1" {
		t.Errorf("socket payload = %q, want %q", got, "WATCHDOG=1")
	}
}

// TestSdNotify_NoOpWithoutSocket verifies the no-op branch: when
// NOTIFY_SOCKET is unset (./sb invoked from a non-systemd shell),
// the call returns silently without panicking. Was implicit in
// the prior TestSdNotifyExtendTimeout_NoOpWithoutSocket; re-asserted
// here against the primitive that replaced it.
func TestSdNotify_NoOpWithoutSocket(t *testing.T) {
	t.Setenv("NOTIFY_SOCKET", "")
	sdNotify("WATCHDOG=1")
}
