package upgrade

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestAcquireFreshFlock_RefusesExistingMarkerWithoutRewrite(t *testing.T) {
	dir := t.TempDir()
	existing := UpgradeFlag{
		ID:         91,
		CommitSHA:  "9100000000000000000000000000000000000000",
		Holder:     HolderService,
		Phase:      PhaseNewSbUpgrading,
		BackupPath: "/snapshot/91",
	}
	first, err := acquireFlock(dir, existing)
	if err != nil {
		t.Fatal(err)
	}
	first.Close()

	claim := UpgradeFlag{ID: 92, Holder: HolderInstall}
	lock, err := acquireFreshFlock(dir, claim)
	if err == nil || lock != nil {
		t.Fatalf("fresh claim over existing marker = (%v, %v), want refusal", lock, err)
	}
	held, readErr := ReadFlagFile(dir)
	if readErr != nil || held == nil {
		t.Fatalf("read existing marker after refusal: flag=%v err=%v", held, readErr)
	}
	if held.ID != existing.ID || held.Phase != existing.Phase || held.BackupPath != existing.BackupPath {
		t.Fatalf("fresh claim rewrote durable intent: %+v", held)
	}
	if _, statErr := os.Stat(flagFilePath(dir)); statErr != nil {
		t.Fatalf("existing marker disappeared after refusal: %v", statErr)
	}
}

// Regression proof for STATBUS-134/-136/-181, lost in 66c9d61b6. The old code
// fails this test because ReattemptRestore has no non-mutating git preflight and
// no refusal UPDATE carrying ROLLBACK_FAILED_GIT_CORRUPT. The ordering assertion
// is the safety property: corruption is detected and recorded before marker
// authorization, docker stop, snapshot restore, or daemon-floor replay.
func TestReattemptRestore_GitCorruptRefusesBeforeDestructiveWorkAndRecordsFailureCode(t *testing.T) {
	fix := newGitRepoFixture(t)
	if out, err := exec.Command("git", "-C", fix.dir, "branch", "-D", fix.branchOnOld).CombinedOutput(); err != nil {
		t.Fatalf("delete pre-upgrade branch: %v\n%s", err, out)
	}

	before, err := exec.Command("git", "-C", fix.dir, "rev-parse", "HEAD").Output()
	if err != nil {
		t.Fatal(err)
	}
	_, _, err = resolveGitRestoreTarget(fix.dir, "")
	if err == nil || !strings.Contains(err.Error(), "pre-upgrade resolves") {
		t.Fatalf("git-corrupt preflight error = %v, want missing pre-upgrade refusal", err)
	}
	after, err := exec.Command("git", "-C", fix.dir, "rev-parse", "HEAD").Output()
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(before) {
		t.Fatalf("non-mutating preflight changed HEAD: before=%q after=%q", before, after)
	}

	src := string(packageGoSources(t)["service.go"])
	body := extractFuncBody(t, src, "func (d *Service) ReattemptRestore(")
	preflight := strings.Index(body, `resolveGitRestoreTarget(d.projDir, "")`)
	failureUpdate := strings.Index(body, "SET failure_code = $1")
	authorizeMarker := strings.Index(body, "d.mutateHeldFlag")
	serviceStop := strings.Index(body, `runCommand(d.projDir, "docker"`)
	restore := strings.Index(body, "d.restoreAndFinalize(")
	for name, idx := range map[string]int{
		"git restore-target preflight":    preflight,
		"git-corrupt failure-code update": failureUpdate,
		"authorized marker mutation":      authorizeMarker,
		"service stop":                    serviceStop,
		"snapshot restore tail":           restore,
	} {
		if idx < 0 {
			t.Fatalf("ReattemptRestore is missing %s", name)
		}
	}
	if preflight >= failureUpdate || failureUpdate >= authorizeMarker ||
		authorizeMarker >= serviceStop || serviceStop >= restore {
		t.Fatalf("git-corrupt refusal order drifted: preflight=%d update=%d marker=%d stop=%d restore=%d",
			preflight, failureUpdate, authorizeMarker, serviceStop, restore)
	}
	for _, want := range []string{
		"ErrRollbackGitCorrupt",
		"the git tree is corrupt",
		"do NOT proceed",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("git-corrupt refusal is missing %q", want)
		}
	}
}

func TestReattemptRestore_AuthorizesUnderBothLocksBeforeStoppingServices(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])
	body := extractFuncBody(t, src, "func (d *Service) ReattemptRestore(")

	freshFlock := strings.Index(body, "acquireFreshFlock")
	begin := strings.Index(body, "d.queryConn.Begin(ctx)")
	advisory := strings.Index(body, "pg_try_advisory_xact_lock(hashtext('upgrade_daemon'))")
	rowLock := strings.Index(body, "FOR UPDATE")
	serviceStop := strings.Index(body, `runCommand(d.projDir, "docker"`)
	for name, idx := range map[string]int{
		"fresh replay flock":        freshFlock,
		"authorization transaction": begin,
		"daemon advisory lock":      advisory,
		"row FOR UPDATE":            rowLock,
		"data-plane service stop":   serviceStop,
	} {
		if idx < 0 {
			t.Fatalf("ReattemptRestore is missing %s", name)
		}
	}
	ordered := freshFlock < begin && begin < advisory && advisory < rowLock && rowLock < serviceStop
	if !ordered {
		t.Fatalf("ReattemptRestore authorization order drifted: flock=%d begin=%d advisory=%d row=%d stop=%d",
			freshFlock, begin, advisory, rowLock, serviceStop)
	}
	if strings.Contains(body, "d.restoreGitState(") {
		t.Fatal("ReattemptRestore must retain the target worktree through snapshot restore and daemon-floor replay")
	}
	for _, predicate := range []string{
		"state = 'failed'",
		"backup_path IS NOT NULL",
		"rollback_finish_pending_at IS NULL",
	} {
		if !strings.Contains(body, predicate) {
			t.Errorf("ReattemptRestore durable row authorization is missing %q", predicate)
		}
	}
	if strings.Contains(body, "rowID int64, backupPath string") {
		t.Error("ReattemptRestore must consume backup_path from the row locked after mutex acquisition, not from the detector's stale caller value")
	}
}
