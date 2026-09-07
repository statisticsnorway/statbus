package upgrade

import (
	"os"
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

func TestReattemptRestore_AuthorizesUnderBothLocksBeforeStoppingServices(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])
	body := extractFuncBody(t, src, "func (d *Service) ReattemptRestore(")

	freshFlock := strings.Index(body, "acquireFreshFlock")
	begin := strings.Index(body, "d.queryConn.Begin(ctx)")
	advisory := strings.Index(body, "pg_try_advisory_xact_lock(hashtext('upgrade_daemon'))")
	rowLock := strings.Index(body, "FOR UPDATE")
	gitRestore := strings.Index(body, "d.restoreGitState(")
	serviceStop := strings.Index(body, `runCommand(d.projDir, "docker"`)
	for name, idx := range map[string]int{
		"fresh replay flock":        freshFlock,
		"authorization transaction": begin,
		"daemon advisory lock":      advisory,
		"row FOR UPDATE":            rowLock,
		"git restore":               gitRestore,
		"data-plane service stop":   serviceStop,
	} {
		if idx < 0 {
			t.Fatalf("ReattemptRestore is missing %s", name)
		}
	}
	ordered := freshFlock < begin && begin < advisory && advisory < rowLock && rowLock < gitRestore && gitRestore < serviceStop
	if !ordered {
		t.Fatalf("ReattemptRestore authorization order drifted: flock=%d begin=%d advisory=%d row=%d git=%d stop=%d",
			freshFlock, begin, advisory, rowLock, gitRestore, serviceStop)
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
