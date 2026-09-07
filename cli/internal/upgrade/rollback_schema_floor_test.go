package upgrade

import (
	"strings"
	"testing"
)

func TestRestoreRollbackSnapshotWithTargetAssetsPrecedesSourceRestore(t *testing.T) {
	source := readUpgradeServiceSource(t)
	body := extractFuncBody(t, source, "func (d *Service) restoreAndFinalize(")

	restoreSnapshot := strings.Index(body, "d.restoreRollbackSnapshotWithTargetAssets(")
	startDB := strings.Index(body, "d.startRollbackDatabaseOnly(")
	floor := strings.Index(body, "d.reapplyRollbackDaemonSchemaFloor(")
	restoreGit := strings.Index(body, "d.restoreGitState(")
	if restoreSnapshot < 0 || startDB < 0 || floor < 0 || restoreGit < 0 {
		t.Fatalf("restoreAndFinalize is missing the explicit rollback floor boundaries: snapshot=%d db=%d floor=%d git=%d", restoreSnapshot, startDB, floor, restoreGit)
	}
	if !(restoreSnapshot < startDB && startDB < floor && floor < restoreGit) {
		t.Fatalf("rollback order must be snapshot < DB-only start < floor migrate < source restore, got %d < %d < %d < %d", restoreSnapshot, startDB, floor, restoreGit)
	}
}

func TestReapplyRollbackDaemonSchemaFloorUsesTargetBinaryAndOrdinaryLedger(t *testing.T) {
	source := readUpgradeServiceSource(t)
	body := extractFuncBody(t, source, "func (d *Service) reapplyRollbackDaemonSchemaFloor(")
	for _, want := range []string{
		"MigrateUpTimeout",
		"filepath.Join(d.projDir, \"sb\")",
		"\"migrate\", \"up\", \"--to\"",
		"strconv.FormatInt(migrate.DaemonSchemaFloor, 10)",
		"\"--verbose\"",
		"progress.File()",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("reapplyRollbackDaemonSchemaFloor missing %q", want)
		}
	}
	if strings.Contains(body, "ALTER TABLE") || strings.Contains(body, "rollback_finish_pending_at") {
		t.Fatal("rollback schema floor must use only the ordinary migration engine, never inline DDL")
	}
}

func TestRollbackSchemaFloorFailureRetainsTargetAuthority(t *testing.T) {
	source := readUpgradeServiceSource(t)
	body := extractFuncBody(t, source, "func (d *Service) restoreAndFinalize(")
	floor := strings.Index(body, "d.reapplyRollbackDaemonSchemaFloor(")
	failure := strings.Index(body, "PhaseRollbackSchemaFloorFailed")
	restoreGit := strings.Index(body, "d.restoreGitState(")
	restoreBinary := strings.Index(body, "d.restoreBinary(")
	pending := strings.Index(body, "rollback_finish_pending_at = now()")
	if floor < 0 || failure < floor {
		t.Fatalf("floor failure must be handled immediately after migrate: floor=%d failure=%d", floor, failure)
	}
	for name, idx := range map[string]int{"restoreGitState": restoreGit, "restoreBinary": restoreBinary, "pending write": pending} {
		if idx >= 0 && idx < floor {
			t.Errorf("%s precedes daemon floor migrate (%d < %d)", name, idx, floor)
		}
	}
	for _, want := range []string{"ROLLBACK_SCHEMA_FLOOR_FAILED", "releaseUpgradeFlagLockKeepingFile"} {
		if !strings.Contains(body, want) {
			t.Errorf("floor failure contract missing %q", want)
		}
	}
}
