package upgrade

import (
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

// CHANGE 2 (task #12): the rsync backup target is a SINGLE PERSISTENT dir
// committed by atomic directory rename (active↔syncing). The dir NAME is the
// clean/dirty state:
//   pre-upgrade-active   — a complete, restorable snapshot (the incremental base)
//   pre-upgrade-syncing  — an in-flight / killed-mid-rsync partial (NOT restorable)
// A killed run resumes by rsyncing into the leftover `syncing` (never deleted);
// only `rename(syncing→active)` publishes it. The restore is identity-keyed
// (STATBUS-039/-031): restoreDatabase consumes ONLY the path the recovered
// upgrade recorded (flag.BackupPath / row.backup_path) — a partial `syncing`
// is never recorded, so it can never be a restore source.
//
// These guards pin the parts that are unit-testable without a real rsync/docker:
// the name constants, the identity-keyed restore dispositions, and
// reconcileBackupDir skipping the two managed dirs.

// TestBackupDirNames pins the well-known managed dir names so the rename state
// machine, the recorded backup paths, and reconcileBackupDir all agree.
func TestBackupDirNames(t *testing.T) {
	if backupActiveName != "pre-upgrade-active" {
		t.Errorf("backupActiveName = %q, want pre-upgrade-active", backupActiveName)
	}
	if backupSyncingName != "pre-upgrade-syncing" {
		t.Errorf("backupSyncingName = %q, want pre-upgrade-syncing", backupSyncingName)
	}
}

// TestRestoreDatabase_AsideRenameWindow_NeverSelectsByRecency reconstructs
// the EXACT hazard the identity key closes (STATBUS-039): a kill during the
// aside-rename window of a backup on a migrated box. On-disk shape: legacy
// per-stamp dirs present (pruneBackups keeps the last 3 forever), syncing
// present (the partial), active ABSENT (consumed by the aside-rename). The
// killed upgrade recorded NO snapshot (updateFlagPostSwap never ran →
// identity empty). The pre-039 recency scan returned the newest LEGACY dir
// here — another upgrade's months-old backup, rsync --delete'd over the
// UNTOUCHED live volume, silently, with a green rolled_back row. The
// identity-keyed restore must no-op (nil) and leave everything alone.
func TestRestoreDatabase_AsideRenameWindow_NeverSelectsByRecency(t *testing.T) {
	root := scopedBackupRoot(t)
	legacyOld := makeBackupDir(t, root, "pre-upgrade-20260101T120000Z")
	legacyNew := makeBackupDir(t, root, "pre-upgrade-20260615T060000Z") // the recency trap
	syncing := makeBackupDir(t, root, backupSyncingName)                // the partial
	// NO active dir — consumed by the aside-rename.

	d := &Service{}
	p := &ProgressLog{projDir: t.TempDir()}
	if err := d.restoreDatabase(p, ""); err != nil {
		t.Errorf("identity-empty restore in the aside-rename window must no-op (nil); got %v", err)
	}
	for _, dir := range []string{legacyOld, legacyNew, syncing} {
		if _, err := os.Stat(dir); err != nil {
			t.Errorf("restore must leave %s alone: %v", dir, err)
		}
	}
}

// TestRestoreDatabase_RecordedActiveMissing_NoLegacyFallback: the upgrade
// recorded the active path (post_swap flag) and the dir is gone. The pre-039
// scan would silently fall back to the newest legacy dir; the identity key
// must FAIL LOUD instead — restoring another upgrade's backup is the one
// thing this contract forbids.
func TestRestoreDatabase_RecordedActiveMissing_NoLegacyFallback(t *testing.T) {
	root := scopedBackupRoot(t)
	makeBackupDir(t, root, "pre-upgrade-20260615T060000Z") // tempting fallback

	d := &Service{}
	p := &ProgressLog{projDir: t.TempDir()}
	recorded := filepath.Join(root, backupActiveName)
	if err := d.restoreDatabase(p, recorded); err == nil {
		t.Fatal("restore of a missing recorded snapshot must FAIL loud, never fall back to a legacy dir")
	}
}

// TestIsManagedBackupDir: the pure predicate both reconcileBackupDir and
// pruneBackups consult to EXCLUDE the two managed dirs (active/syncing) from
// reference-counted orphan/prune handling. Without it, a stale-mtime syncing
// would be purged as a 90-day orphan — destroying the incremental base / a live
// partial. Legacy per-stamp dirs (and .tmp) are NOT managed → still handled by
// the orphan/prune logic (migration cleanup).
func TestIsManagedBackupDir(t *testing.T) {
	cases := []struct {
		name string
		want bool
	}{
		{backupActiveName, true},
		{backupSyncingName, true},
		{"pre-upgrade-20260101T000000Z", false},     // legacy finalised
		{"pre-upgrade-20260101T000000Z.tmp", false}, // legacy tmp
		{"upgrade-logs-20260101T000000Z", false},    // logs sibling
		{"some-other-thing", false},
	}
	for _, c := range cases {
		if got := isManagedBackupDir(c.name); got != c.want {
			t.Errorf("isManagedBackupDir(%q) = %v, want %v", c.name, got, c.want)
		}
	}
}

// TestReconcileSkipsManagedDirs: an integration check that a reconcile pass with
// a live (stubbed) enumerate does NOT purge active/syncing even when their mtime
// is well past the 90-day grace. Driven through the pure classifier so it does
// not need a DB: we assert the dirs survive after aging them 200 days and
// running the orphan-classification over the on-disk set.
func TestReconcileSkipsManagedDirs(t *testing.T) {
	root := scopedBackupRoot(t)
	active := makeBackupDir(t, root, backupActiveName)
	syncing := makeBackupDir(t, root, backupSyncingName)
	legacy := makeBackupDir(t, root, "pre-upgrade-20260101T000000Z") // unreferenced legacy → orphan-eligible
	old := time.Now().Add(-200 * 24 * time.Hour)
	for _, p := range []string{active, syncing, legacy} {
		if err := os.Chtimes(p, old, old); err != nil {
			t.Fatal(err)
		}
	}

	// purgeOrphanBackups is the DB-free core of reconcileBackupDir's orphan
	// pass: it purges unreferenced, past-grace, NON-managed dirs. (referenced is
	// empty here — no DB rows.) active+syncing must be skipped via
	// isManagedBackupDir; the legacy dir (200d, unreferenced) must be purged.
	d := &Service{}
	d.purgeOrphanBackups(map[string]int{}, time.Now())

	if _, err := os.Stat(active); err != nil {
		t.Errorf("reconcile orphan pass must not purge pre-upgrade-active: %v", err)
	}
	if _, err := os.Stat(syncing); err != nil {
		t.Errorf("reconcile orphan pass must not purge pre-upgrade-syncing: %v", err)
	}
	if _, err := os.Stat(legacy); !os.IsNotExist(err) {
		t.Errorf("reconcile orphan pass MUST purge an unreferenced 200-day legacy dir (migration cleanup); stat err=%v", err)
	}
	_ = filepath.Join
}

// The rename state machine (prepareBackupSnapshotDir) is the DB-free, docker-free
// step 1 of backupDatabase. These guards pin it deterministically (calling
// backupDatabase directly would run a real docker rsync on a dev box that HAS
// docker, racing the assertions against a destructive rsync --delete).

// TestPrepareSnapshot_CoexistenceFailsFast: active + syncing must NEVER coexist
// from our rename sequence. If they somehow do (external tampering, a bug),
// prepareBackupSnapshotDir must fail LOUD — never silently rm one or guess which
// is authoritative. Fail-safe by construction.
func TestPrepareSnapshot_CoexistenceFailsFast(t *testing.T) {
	root := scopedBackupRoot(t)
	active := makeBackupDir(t, root, backupActiveName)
	syncing := makeBackupDir(t, root, backupSyncingName)

	d := &Service{}
	_, err := d.prepareBackupSnapshotDir(nil)
	if err == nil {
		t.Fatal("prepareBackupSnapshotDir must FAIL when both active and syncing exist (corrupt state)")
	}
	if !strings.Contains(err.Error(), "both") || !strings.Contains(err.Error(), "coexist") {
		t.Errorf("error should name the active+syncing coexistence; got: %v", err)
	}
	if _, e := os.Stat(active); e != nil {
		t.Errorf("fail-fast must NOT delete active: %v", e)
	}
	if _, e := os.Stat(syncing); e != nil {
		t.Errorf("fail-fast must NOT delete syncing: %v", e)
	}
}

// TestPrepareSnapshot_MovesActiveAside: only active exists → rename to syncing
// with content PRESERVED (the incremental base), active gone.
func TestPrepareSnapshot_MovesActiveAside(t *testing.T) {
	root := scopedBackupRoot(t)
	active := makeBackupDir(t, root, backupActiveName)
	if err := os.WriteFile(filepath.Join(active, "base-marker"), []byte("incremental-base"), 0644); err != nil {
		t.Fatal(err)
	}

	d := &Service{}
	got, err := d.prepareBackupSnapshotDir(nil)
	if err != nil {
		t.Fatalf("prepareBackupSnapshotDir: %v", err)
	}
	wantSyncing := filepath.Join(root, backupSyncingName)
	if got != wantSyncing {
		t.Errorf("returned syncing path = %q, want %q", got, wantSyncing)
	}
	if b, err := os.ReadFile(filepath.Join(wantSyncing, "base-marker")); err != nil || string(b) != "incremental-base" {
		t.Errorf("active must be renamed to syncing with content preserved; marker read=%q err=%v", b, err)
	}
	if _, err := os.Stat(active); !os.IsNotExist(err) {
		t.Errorf("active must be GONE after the aside-rename (consumed into syncing); stat err=%v", err)
	}
}

// TestPrepareSnapshot_ReusesBaseInodeNotRecopy is the STATBUS-114 reuse-invariant
// guard. TestPrepareSnapshot_MovesActiveAside above only checks that the base's
// CONTENT carries into syncing — which a copy-then-delete refactor would also
// satisfy while silently full-copying the whole volume. This pins the stronger
// property the incremental speedup actually rests on: the active→syncing move is
// a RENAME of the SAME on-disk object, so inode AND mtime are preserved. A local
// `rsync -a --delete` defaults to --whole-file (block delta OFF), so its only
// speedup is skipping files whose size+mtime match — which works only if the base
// dir IS the prior dir, mtimes intact. If a refactor swapped the rename for
// rm+mkdir or copy-then-delete (new inode, possibly fresh mtime), every big-DB
// backup would full-copy; this test goes red on that change.
func TestPrepareSnapshot_ReusesBaseInodeNotRecopy(t *testing.T) {
	root := scopedBackupRoot(t)
	active := makeBackupDir(t, root, backupActiveName)
	marker := filepath.Join(active, "base-marker")
	if err := os.WriteFile(marker, []byte("incremental-base"), 0644); err != nil {
		t.Fatal(err)
	}
	// Age the marker so a wipe-and-recreate (fresh mtime) is detectable even if
	// inode reuse happened to collide.
	aged := time.Now().Add(-72 * time.Hour).Truncate(time.Second)
	if err := os.Chtimes(marker, aged, aged); err != nil {
		t.Fatal(err)
	}
	wantIno, ok := inodeOf(t, marker)
	if !ok {
		t.Skip("inode unavailable on this platform; mtime/content guards cover the rest")
	}

	d := &Service{}
	got, err := d.prepareBackupSnapshotDir(nil)
	if err != nil {
		t.Fatalf("prepareBackupSnapshotDir: %v", err)
	}

	syncingMarker := filepath.Join(got, "base-marker")
	fi, err := os.Stat(syncingMarker)
	if err != nil {
		t.Fatalf("base marker must carry into syncing (the reused incremental base); got %v — "+
			"a rm+mkdir refactor would leave it absent and full-copy every run", err)
	}
	gotIno, _ := inodeOfInfo(fi)
	if gotIno != wantIno {
		t.Errorf("active→syncing must be a RENAME (inode preserved) so rsync reuses the base; "+
			"inode changed %d→%d — a wipe-and-recreate/copy-then-delete makes every big-DB backup full-copy", wantIno, gotIno)
	}
	if !fi.ModTime().Equal(aged) {
		t.Errorf("rename must preserve mtime (rsync skips unchanged files by size+mtime); mtime changed %v→%v", aged, fi.ModTime())
	}
}

// inodeOf returns the inode number of path, or ok=false if the platform does not
// expose one (non-Unix). Used by the snapshot reuse-invariant guard to prove the
// active→syncing transition is a rename, not a recopy.
func inodeOf(t *testing.T, path string) (uint64, bool) {
	t.Helper()
	fi, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat %s: %v", path, err)
	}
	return inodeOfInfo(fi)
}

func inodeOfInfo(fi os.FileInfo) (uint64, bool) {
	st, ok := fi.Sys().(*syscall.Stat_t)
	if !ok {
		return 0, false
	}
	return uint64(st.Ino), true
}

// TestPrepareSnapshot_ResumesIntoLeftoverSyncing: a killed run's leftover syncing
// IS the incremental base — RESUME into it (keep it + content), never rm, no
// active produced.
func TestPrepareSnapshot_ResumesIntoLeftoverSyncing(t *testing.T) {
	root := scopedBackupRoot(t)
	syncing := makeBackupDir(t, root, backupSyncingName)
	if err := os.WriteFile(filepath.Join(syncing, "partial-marker"), []byte("resume-me"), 0644); err != nil {
		t.Fatal(err)
	}

	d := &Service{}
	got, err := d.prepareBackupSnapshotDir(nil)
	if err != nil {
		t.Fatalf("prepareBackupSnapshotDir: %v", err)
	}
	if got != syncing {
		t.Errorf("returned path = %q, want the existing syncing %q", got, syncing)
	}
	if b, err := os.ReadFile(filepath.Join(syncing, "partial-marker")); err != nil || string(b) != "resume-me" {
		t.Errorf("leftover syncing must be RESUMED into (kept, content intact), never deleted; marker read=%q err=%v", b, err)
	}
	if _, err := os.Stat(filepath.Join(root, backupActiveName)); !os.IsNotExist(err) {
		t.Errorf("prepare must NOT produce an active dir; stat err=%v", err)
	}
}

// TestPrepareSnapshot_FirstEverCreatesSyncing: neither dir → create an empty
// syncing for rsync to populate.
func TestPrepareSnapshot_FirstEverCreatesSyncing(t *testing.T) {
	root := scopedBackupRoot(t)
	d := &Service{}
	got, err := d.prepareBackupSnapshotDir(nil)
	if err != nil {
		t.Fatalf("prepareBackupSnapshotDir: %v", err)
	}
	wantSyncing := filepath.Join(root, backupSyncingName)
	if got != wantSyncing {
		t.Errorf("returned path = %q, want %q", got, wantSyncing)
	}
	if !dirExists(wantSyncing) {
		t.Errorf("first-ever backup must create an empty syncing dir at %q", wantSyncing)
	}
}

// TestH2_BackupDatabaseSingleCallSiteNotInResume is the load-bearing H2
// invariant guard (architect-verified HYP1, plan piece #12). pre-upgrade-active
// is a MUTABLE pointer; it stays stable — never rsync-overwritten — from
// backupDatabase-completion until flag-removal BECAUSE the exit-42 resume
// re-enters applyPostSwap POST-backup and NEVER re-runs backupDatabase. If a
// future refactor added a backupDatabase call inside applyPostSwap /
// resumePostSwap (the resume re-entry path), a resume would overwrite the
// rollback snapshot the in-flight upgrade still needs. This pins that
// structurally: backupDatabase is called from exactly ONE site, and it is NOT
// in the resume path.
//
// (The full behavioural assertions — resume-keeps-active byte-identical,
// concurrent-actor-in-crash-window-resumes, kill-mid-initial-rsync-no-restore —
// need real systemd+docker and live in the install-recovery harness; this guard
// pins the code-level invariant they rest on, deterministically.)
func TestH2_BackupDatabaseSingleCallSiteNotInResume(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	s := string(src)

	// Exactly one call site of d.backupDatabase( across service.go.
	if n := strings.Count(s, "d.backupDatabase("); n != 1 {
		t.Errorf("d.backupDatabase( must have exactly ONE call site (the pre-swap backup in executeUpgrade); found %d. "+
			"A second call site — especially in the resume path — would let a resume rsync-overwrite pre-upgrade-active, "+
			"destroying the rollback snapshot the in-flight upgrade still needs (H2).", n)
	}

	// That one call site must NOT be inside applyPostSwap or resumePostSwap —
	// the exit-42 resume re-entry path. If it were, a resume would re-run the
	// backup over active.
	for _, fn := range []string{
		"func (d *Service) applyPostSwap(",
		"func (d *Service) resumePostSwap(",
	} {
		body := extractFuncBody(t, s, fn)
		if strings.Contains(body, "d.backupDatabase(") {
			t.Errorf("%s must NOT call d.backupDatabase( — the resume must re-enter POST-backup and reuse "+
				"pre-upgrade-active, never re-run the backup (H2 invariant).", fn)
		}
	}
}

// TestH2_FlagBackupPathSetOnlyAtPostSwap pins HYP3: flag.BackupPath is populated
// only at post_swap (updateFlagPostSwap), AFTER the backup succeeds — so a kill
// during the INITIAL rsync (syncing exists, no active, flag NOT yet post_swap)
// leaves a flag that never references an absent active, and recovery never tries
// to restore from one. Structurally: only updateFlagPostSwap assigns
// flag.BackupPath, and it sets Phase = PhaseNewSbSwapped in the same function.
func TestH2_FlagBackupPathSetOnlyAtPostSwap(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	s := string(src)

	// The only assignment to the BackupPath field is in updateFlagPostSwap.
	if n := strings.Count(s, "flag.BackupPath ="); n != 1 {
		t.Errorf("flag.BackupPath must be assigned in exactly ONE place (updateFlagPostSwap, at post_swap); found %d assignments. "+
			"Setting it earlier (pre-backup) would let recovery reference an active that a killed initial rsync never produced (H2/HYP3).", n)
	}
	body := extractFuncBody(t, s, "func (d *Service) updateFlagPostSwap(")
	if !strings.Contains(body, "flag.BackupPath =") {
		t.Error("updateFlagPostSwap must be the function that sets flag.BackupPath (post_swap only)")
	}
	if !strings.Contains(body, "PhaseNewSbSwapped") {
		t.Error("updateFlagPostSwap must set Phase = PhaseNewSbSwapped alongside BackupPath — the two must move together so a pre-post_swap kill never references active")
	}
}
