package upgrade

import (
	"io"
	"testing"
	"time"
)

// CHANGE 1 (task #11): archiveBackup's tar emits per-checkpoint output that
// flows through the PrefixWriter onLine callback to bump ProgressLog
// .lastAdvanceAt, feeding the #3 progress-gated watchdog. A write-hang stops
// the records → stops the checkpoints → stops the bumps → the gate closes →
// WatchdogSec fires. Checkpoint-REAL (per N records PROCESSED), not a blind
// wall-clock ticker.
//
// Two flavor-INDEPENDENT contracts are pinned here (no real tar invocation):
//   1. tarSupportsCheckpoint parses `tar --version` output correctly — GNU tar
//      supports --checkpoint; bsd/libarchive tar does not. (Drives the
//      capability-gate so an inline upgrade on a bsdtar host doesn't fail on an
//      unknown flag — the "one path" portability fix.)
//   2. a checkpoint-shaped output line, fed through a PrefixWriter whose onLine
//      is ProgressLog.bump, advances lastAdvanceAt — the wiring that makes a
//      live tar survive the watchdog.

func TestTarSupportsCheckpoint(t *testing.T) {
	cases := []struct {
		name    string
		version string
		want    bool
	}{
		{"gnu-tar", "tar (GNU tar) 1.35\nCopyright (C) 2023 Free Software Foundation, Inc.", true},
		{"gnu-tar-lowercase-noise", "tar (GNU tar) 1.30", true},
		{"bsdtar", "bsdtar 3.5.3 - libarchive 3.7.4 zlib/1.2.12", false},
		{"libarchive-only", "tar (libarchive) 3.7.4", false},
		{"empty", "", false},
		{"unknown", "some other tar 9.9", false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := tarSupportsCheckpoint(c.version); got != c.want {
				t.Errorf("tarSupportsCheckpoint(%q) = %v, want %v", c.version, got, c.want)
			}
		})
	}
}

// TestCheckpointLineBumpsLastAdvance: the integration contract — a GNU-tar
// checkpoint line ("archive: 1000 records") written through a PrefixWriter
// wired to onLine=p.bump moves sinceLastAdvance to ~0 from a stale clock. This
// is exactly how a live tar keeps the #3 gate open.
func TestCheckpointLineBumpsLastAdvance(t *testing.T) {
	p := &ProgressLog{projDir: t.TempDir()}
	p.setLastAdvanceForTest(time.Now().Add(-10 * time.Minute)) // stale: a hung tar
	w := NewPrefixWriter("E", "archive-tar", io.Discard, p.bump)
	// tar --checkpoint-action=echo writes the checkpoint message as a line.
	w.Write([]byte("archive: 1000 records\n"))
	if d := p.sinceLastAdvance(); d > time.Second {
		t.Errorf("a tar checkpoint line must bump lastAdvanceAt (live tar survives the watchdog); sinceLastAdvance=%v", d)
	}
}
