package upgrade

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// archiveBackup writes the pre-upgrade tar to ~/statbus-backups/<version>-pre.tar.gz.
// ATOMIC (task #8): it must tar to a `.tmp` and atomically rename to the final
// name only on tar success, so an interrupted or failed tar NEVER leaves a
// partial file at the final `<version>-pre.tar.gz` path — a partial there is
// indistinguishable from a complete archive to pruneArchives (which keeps the
// 3 newest `.gz` by name) and to an operator inspecting the backups dir. This
// is the canonical crash-safe write pattern; it makes archiveBackup robust to
// ANY interruption (the systemd start-phase SIGTERM that wedged NO/rune, a
// SIGKILL, a disk-full mid-tar), not just one timeout.
//
// The archive is best-effort forensics, NOT the rollback artifact (rollback
// restores from backupPath directly), so a failed archive is loss-free — the
// only requirement is that a FAILED one not masquerade as a COMPLETE one.

// helpers to inspect the scoped archive dir.
func archiveFinalName(version string) string { return version + "-pre.tar.gz" }

func listArchiveDir(t *testing.T, root string) []string {
	t.Helper()
	entries, err := os.ReadDir(root)
	if err != nil {
		t.Fatalf("read archive dir %s: %v", root, err)
	}
	var names []string
	for _, e := range entries {
		names = append(names, e.Name())
	}
	return names
}

// TestArchiveBackup_SuccessLeavesFinalNoTmp: a successful tar leaves exactly
// the final `<version>-pre.tar.gz` and no `.tmp` residue.
func TestArchiveBackup_SuccessLeavesFinalNoTmp(t *testing.T) {
	root := scopedBackupRoot(t)

	// A real backup source to tar: a pre-upgrade-* dir with a file in it.
	proj := t.TempDir()
	backupPath := makeBackupDir(t, root, "pre-upgrade-20260527T000000Z")
	if err := os.WriteFile(filepath.Join(backupPath, "data.txt"), []byte("hi"), 0644); err != nil {
		t.Fatal(err)
	}

	d := &Service{projDir: proj}
	d.archiveBackup(backupPath, "v2026.05.9")

	final := archiveFinalName("v2026.05.9")
	names := listArchiveDir(t, root)
	haveFinal := false
	for _, n := range names {
		if n == final {
			haveFinal = true
		}
		if strings.HasSuffix(n, ".tmp") {
			t.Errorf("archiveBackup left a .tmp residue after a SUCCESSFUL tar: %q (dir: %v)", n, names)
		}
	}
	if !haveFinal {
		t.Errorf("archiveBackup did not produce the final archive %q (dir: %v)", final, names)
	}
}

// TestArchiveBackup_FailedTarLeavesNoFinal is the load-bearing ATOMIC guard.
//
// When tar fails (here: a nonexistent source dir — a real `tar -czf` exits
// non-zero AND, when it writes directly to the final name, leaves a partial
// file there), the final `<version>-pre.tar.gz` MUST NOT exist. Pre-ATOMIC
// (tar -czf <final> directly) this FAILS: the partial sits at the final name.
// Post-ATOMIC (tar to `.tmp`, rename only on success) the final name is never
// created — at most a `.tmp` remains, which pruneArchives ignores (ext != .gz).
func TestArchiveBackup_FailedTarLeavesNoFinal(t *testing.T) {
	root := scopedBackupRoot(t)
	proj := t.TempDir()

	// A backupPath that does NOT exist → tar errors out. archiveBackup is
	// best-effort (warns + returns), so this does not panic; we assert the
	// filesystem invariant.
	missing := filepath.Join(root, "pre-upgrade-DOES-NOT-EXIST")
	d := &Service{projDir: proj}
	d.archiveBackup(missing, "v2026.05.9")

	final := archiveFinalName("v2026.05.9")
	finalPath := filepath.Join(root, final)
	if _, err := os.Stat(finalPath); err == nil {
		names := listArchiveDir(t, root)
		t.Errorf("archiveBackup left a partial at the FINAL name %q after a failed tar — "+
			"a partial there is indistinguishable from a complete archive. ATOMIC requires "+
			"tar→.tmp then rename-on-success so the final name is never a partial. (dir: %v)",
			final, names)
	}
	// A leftover .tmp is acceptable (pruneArchives ignores ext != .gz); we do
	// not assert on it either way.
}

// TestPruneArchives_SweepsStaleTmp: a `<version>-pre.tar.gz.tmp` left by a
// KILLED tar (the process couldn't run archiveBackup's own cleanup) is reaped
// by pruneArchives, so orphan .tmp archives can't accumulate across killed
// upgrades. A real `.gz` is retained.
func TestPruneArchives_SweepsStaleTmp(t *testing.T) {
	root := scopedBackupRoot(t)

	stale := filepath.Join(root, "v2026.05.7-pre.tar.gz.tmp")
	if err := os.WriteFile(stale, []byte("partial"), 0644); err != nil {
		t.Fatal(err)
	}
	keepGz := filepath.Join(root, "v2026.05.8-pre.tar.gz")
	if err := os.WriteFile(keepGz, []byte("complete"), 0644); err != nil {
		t.Fatal(err)
	}

	d := &Service{}
	d.pruneArchives(root, 3)

	if _, err := os.Stat(stale); !os.IsNotExist(err) {
		t.Errorf("pruneArchives did not sweep the stale .tmp %q (err=%v) — orphan .tmp archives must not accumulate", stale, err)
	}
	if _, err := os.Stat(keepGz); err != nil {
		t.Errorf("pruneArchives wrongly removed a complete .gz %q: %v", keepGz, err)
	}
}
