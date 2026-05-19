package upgrade

import (
	"os"
	"path/filepath"
	"testing"
)

// TestParseRecoveryMode covers the operator-facing --recovery flag
// parser. Wrong values must fail fast before any DB or filesystem
// state is touched.
func TestParseRecoveryMode(t *testing.T) {
	cases := []struct {
		in   string
		want RecoveryMode
		ok   bool
	}{
		{"", RecoveryAuto, true},
		{"auto", RecoveryAuto, true},
		{"forward", RecoveryForward, true},
		{"restore", RecoveryRestore, true},
		{"AUTO", "", false},   // case-sensitive on purpose
		{"reset", "", false},  // adjacent typo
		{"force", "", false},  // adjacent typo
		{" auto", "", false},  // no whitespace tolerance
		{"auto ", "", false},  // no whitespace tolerance
		{"forward,restore", "", false},
	}
	for _, tc := range cases {
		got, err := ParseRecoveryMode(tc.in)
		if tc.ok {
			if err != nil {
				t.Errorf("ParseRecoveryMode(%q) = err %v; want %v, nil", tc.in, err, tc.want)
				continue
			}
			if got != tc.want {
				t.Errorf("ParseRecoveryMode(%q) = %v; want %v", tc.in, got, tc.want)
			}
			continue
		}
		if err == nil {
			t.Errorf("ParseRecoveryMode(%q) = %v, nil; want error", tc.in, got)
		}
	}
}

// TestAutoChooseRecovery_BackupAbsent covers the most common path:
// pre-swap-crash flag has no BackupPath stamped → forward.
func TestAutoChooseRecovery_BackupAbsent(t *testing.T) {
	got, rationale := autoChooseRecovery(UpgradeFlag{})
	if got != RecoveryForward {
		t.Errorf("empty BackupPath: got %v, want %v", got, RecoveryForward)
	}
	if rationale == "" {
		t.Errorf("expected non-empty rationale, got empty")
	}
}

// TestAutoChooseRecovery_BackupMissing covers the "operator pruned the
// backup directory but flag still references it" case → forward.
func TestAutoChooseRecovery_BackupMissing(t *testing.T) {
	flag := UpgradeFlag{BackupPath: "/nonexistent/path/that/cannot/exist-12345"}
	got, rationale := autoChooseRecovery(flag)
	if got != RecoveryForward {
		t.Errorf("missing BackupPath: got %v, want %v", got, RecoveryForward)
	}
	if rationale == "" {
		t.Errorf("expected non-empty rationale, got empty")
	}
}

// TestAutoChooseRecovery_BackupNotDir covers the (unlikely) case
// where BackupPath points at a file → forward.
func TestAutoChooseRecovery_BackupNotDir(t *testing.T) {
	tmp := t.TempDir()
	notDir := filepath.Join(tmp, "regular-file")
	if err := os.WriteFile(notDir, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, rationale := autoChooseRecovery(UpgradeFlag{BackupPath: notDir})
	if got != RecoveryForward {
		t.Errorf("file (not dir): got %v, want %v", got, RecoveryForward)
	}
	if rationale == "" {
		t.Errorf("expected non-empty rationale, got empty")
	}
}

// TestAutoChooseRecovery_BackupEmpty covers the "partial-truncation
// husk" case: directory exists but holds no backup contents → forward.
func TestAutoChooseRecovery_BackupEmpty(t *testing.T) {
	tmp := t.TempDir()
	got, rationale := autoChooseRecovery(UpgradeFlag{BackupPath: tmp})
	if got != RecoveryForward {
		t.Errorf("empty dir: got %v, want %v", got, RecoveryForward)
	}
	if rationale == "" {
		t.Errorf("expected non-empty rationale, got empty")
	}
}

// TestAutoChooseRecovery_BackupReadable covers the affirmative path:
// directory with contents → restore (safer for non-idempotent migrations).
func TestAutoChooseRecovery_BackupReadable(t *testing.T) {
	tmp := t.TempDir()
	if err := os.WriteFile(filepath.Join(tmp, "toc.dat"), []byte("fake-dump"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, rationale := autoChooseRecovery(UpgradeFlag{BackupPath: tmp})
	if got != RecoveryRestore {
		t.Errorf("readable dir with entries: got %v, want %v", got, RecoveryRestore)
	}
	if rationale == "" {
		t.Errorf("expected non-empty rationale, got empty")
	}
}
