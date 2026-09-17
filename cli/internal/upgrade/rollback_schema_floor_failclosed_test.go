package upgrade

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestRollbackSchemaFloorFailureMarkerWriteFailureKeepsFlockAndOriginalRoute(t *testing.T) {
	projDir := t.TempDir()
	d := NewService(projDir, true, "test", "")
	if err := d.writeUpgradeFlag(354, "3540000000000000000000000000000000000000", nil, "test", string(TriggerService), false); err != nil {
		t.Fatalf("write held rollback marker: %v", err)
	}
	t.Cleanup(func() {
		d.releaseUpgradeFlagLockKeepingFile()
		_ = os.Remove(flagFilePath(projDir))
	})
	if err := d.mutateHeldFlag(func(flag *UpgradeFlag) { flag.Step = StepRollback }); err != nil {
		t.Fatalf("seed rollback route: %v", err)
	}

	t.Setenv("STATBUS_INJECT_AT", "rollback-floor-failure-marker-write")
	err := d.holdRollbackSchemaFloorFailure(context.Background(), 354, "/backup/354", nil, errors.New("floor failed"), nil)
	var markerErr *RollbackSchemaFloorMarkerWriteError
	if !errors.As(err, &markerErr) {
		t.Fatalf("error = %T %v, want RollbackSchemaFloorMarkerWriteError", err, err)
	}
	if d.flagLock == nil || d.flagLock.file == nil {
		t.Fatal("marker mutation failure released the service-held flock")
	}
	if !IsFlockHeld(projDir) {
		t.Fatal("marker mutation failure must remain alive-idle behind the held flock")
	}
	flag, readErr := ReadFlagFile(projDir)
	if readErr != nil {
		t.Fatalf("read real marker after failed mutation: %v", readErr)
	}
	if flag.Step != StepRollback || flag.Phase == PhaseRollbackSchemaFloorFailed {
		t.Fatalf("failed mutation changed durable route: step=%q phase=%q", flag.Step, flag.Phase)
	}

	if nextLock, _, recoverErr := acquireRecoveryFlock(projDir, *flag); recoverErr == nil {
		if nextLock != nil {
			nextLock.Close()
		}
		t.Fatal("next recovery actor acquired the marker despite the live fail-closed flock")
	}
	flagAfter, readErr := ReadFlagFile(projDir)
	if readErr != nil {
		t.Fatalf("read marker after refused recovery: %v", readErr)
	}
	if flagAfter.Step != StepRollback || flagAfter.Phase == PhaseRollbackSchemaFloorFailed {
		t.Fatalf("refused recovery mutated marker: step=%q phase=%q", flagAfter.Step, flagAfter.Phase)
	}
}

func TestRollbackClientsLiveDurablyRoutesDaemonAliveIdle(t *testing.T) {
	projDir := t.TempDir()
	shimDir := t.TempDir()
	dockerLog := filepath.Join(shimDir, "docker.log")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
  "compose ps -a --format json")
    printf '%s\n' '{"Service":"app","State":"exited"}'
    printf '%s\n' '{"Service":"worker","State":"exited"}'
    printf '%s\n' '{"Service":"rest","State":"exited"}'
    ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", dockerLog)

	d := NewService(projDir, true, "test", "")
	// The rollback path legitimately clears queryConn after stopping the database.
	// The out-of-volume marker must still retain the terminal classification.
	d.queryConn = nil
	if err := d.writeUpgradeFlag(356, "3560000000000000000000000000000000000000", nil, "test", string(TriggerService), false); err != nil {
		t.Fatalf("write held rollback marker: %v", err)
	}
	t.Cleanup(func() { _ = os.Remove(flagFilePath(projDir)) })
	if err := d.mutateHeldFlag(func(flag *UpgradeFlag) { flag.Step = StepRollback }); err != nil {
		t.Fatalf("seed rollback route: %v", err)
	}
	clientsErr := &RecoveryClientsLiveError{Services: []string{"app (running)"}}
	if err := d.holdRollbackClientsLive(356, "/backup/356", 4, nil, clientsErr); err != nil {
		t.Fatalf("persist live-client hold: %v", err)
	}
	if IsFlockHeld(projDir) {
		t.Fatal("durable live-client phase must release the process flock for deliberate ./sb install retry")
	}
	flag, err := ReadFlagFile(projDir)
	if err != nil {
		t.Fatalf("read durable live-client marker: %v", err)
	}
	if flag.Phase != PhaseRollbackClientsLive || flag.Step != StepRollback {
		t.Fatalf("marker = phase %q step %q, want durable live-client hold with rollback identity", flag.Phase, flag.Step)
	}
	if flag.RollbackFailureCode != ErrRollbackServicesNotStopped || !strings.Contains(flag.RollbackFailure, "stopped and positively verified") {
		t.Fatalf("marker classification = %q / %q, want durable stopped-client containment", flag.RollbackFailureCode, flag.RollbackFailure)
	}
	dockerBytes, err := os.ReadFile(dockerLog)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(dockerBytes), "compose stop app worker rest\n") {
		t.Fatalf("live-client hold did not stop the serving tier in place:\n%s", dockerBytes)
	}
}

// A live-client invariant failure is intercepted immediately after the
// database-only start and returns from restoreAndFinalize. It must never fall
// through to source restoration or any serving startup.
func TestRestoreAndFinalizeClientsLiveReturnsBeforeFullStackStartup(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatal(err)
	}
	body := extractFuncBody(t, string(src), "func (d *Service) restoreAndFinalize(")
	if strings.Contains(body, `"docker", "compose", "--profile", "all", "up"`) {
		t.Fatal("restoreAndFinalize must never use an unscoped full-profile compose up; source-tier convergence belongs only in startSourceApplicationStack")
	}
	startIdx := strings.Index(body, "d.startRollbackDatabaseOnly(ctx, progress)")
	holdIdx := strings.Index(body, "d.holdRollbackClientsLive(id, backupPath, attemptsAtCall, progress, clientsLiveErr)")
	returnIdx := -1
	if holdIdx >= 0 {
		returnIdx = strings.Index(body[holdIdx:], "return true, nil")
	}
	restoreSourceIdx := strings.Index(body, `d.restoreGitState("", progress)`)
	sourceStartIdx := strings.Index(body, "d.startSourceApplicationStack(ctx, progress)")
	if startIdx < 0 || holdIdx < 0 || returnIdx < 0 || restoreSourceIdx < 0 || sourceStartIdx < 0 {
		t.Fatalf("control-flow pin is stale: start=%d hold=%d return=%d restoreSource=%d sourceStart=%d", startIdx, holdIdx, returnIdx, restoreSourceIdx, sourceStartIdx)
	}
	returnIdx += holdIdx
	if startIdx >= holdIdx || holdIdx >= returnIdx || returnIdx >= restoreSourceIdx || restoreSourceIdx >= sourceStartIdx {
		t.Fatalf("live-client hold must return before source restore/start: start=%d hold=%d return=%d restoreSource=%d sourceStart=%d", startIdx, holdIdx, returnIdx, restoreSourceIdx, sourceStartIdx)
	}
}

func TestRestoreAndFinalizeSnapshotFailureHoldsWithoutStartingServingTier(t *testing.T) {
	projDir := t.TempDir()
	shimDir := t.TempDir()
	dockerLog := filepath.Join(shimDir, "docker.log")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", dockerLog)
	t.Setenv("STATBUS_INJECT_AT", "rollback-snapshot-restore")

	d := NewService(projDir, true, "test", "")
	if err := d.writeUpgradeFlag(357, "3570000000000000000000000000000000000000", nil, "test", string(TriggerService), false); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Remove(flagFilePath(projDir)) })
	if err := d.mutateHeldFlag(func(flag *UpgradeFlag) {
		flag.Step = StepRollback
		flag.BackupPath = "/backup/357"
	}); err != nil {
		t.Fatal(err)
	}
	progress := NewUpgradeLog(projDir, 357, "restore-failure", time.Now().UTC())
	degraded, err := d.restoreAndFinalize(context.Background(), 357, "restore-failure", nil, "injected restore failure", "/backup/357", 3, progress)
	progress.Close()
	if err != nil {
		t.Fatalf("restoreAndFinalize returned typed error instead of a durable hold: %v", err)
	}
	if !degraded {
		t.Fatal("snapshot restore failure was not classified degraded")
	}
	flag, err := ReadFlagFile(projDir)
	if err != nil {
		t.Fatal(err)
	}
	if flag.Phase != PhaseRollbackRestoreFailed || flag.Step != StepRollback || flag.RollbackFailureCode != ErrRollbackDBRestore {
		t.Fatalf("marker = phase %q step %q code %q, want durable restore-failed hold", flag.Phase, flag.Step, flag.RollbackFailureCode)
	}
	if !strings.Contains(flag.RollbackFailure, "injected failure: rollback-snapshot-restore") {
		t.Fatalf("marker lost restore failure detail: %q", flag.RollbackFailure)
	}
	if dockerBytes, readErr := os.ReadFile(dockerLog); readErr == nil {
		log := string(dockerBytes)
		if strings.Contains(log, "compose start") || strings.Contains(log, "compose up") || strings.Contains(log, "docker start") {
			t.Fatalf("snapshot failure started or recreated containers:\n%s", dockerBytes)
		}
	}
}

func TestRollbackSchemaFloorFailureDurablyRoutesDaemonAliveIdle(t *testing.T) {
	projDir := t.TempDir()
	d := NewService(projDir, true, "test", "")
	if err := d.writeUpgradeFlag(355, "3550000000000000000000000000000000000000", nil, "test", string(TriggerService), false); err != nil {
		t.Fatalf("write held rollback marker: %v", err)
	}
	t.Cleanup(func() { _ = os.Remove(flagFilePath(projDir)) })
	if err := d.mutateHeldFlag(func(flag *UpgradeFlag) { flag.Step = StepRollback }); err != nil {
		t.Fatalf("seed rollback route: %v", err)
	}
	if err := d.holdRollbackSchemaFloorFailure(context.Background(), 355, "/backup/355", nil, errors.New("floor failed"), nil); err != nil {
		t.Fatalf("persist floor failure hold: %v", err)
	}
	if IsFlockHeld(projDir) {
		t.Fatal("durable floor-failure phase must release the process flock for deliberate ./sb install retry")
	}
	flag, err := ReadFlagFile(projDir)
	if err != nil {
		t.Fatalf("read durable floor-failure marker: %v", err)
	}
	if flag.Phase != PhaseRollbackSchemaFloorFailed || flag.Step != StepRollback {
		t.Fatalf("marker = phase %q step %q, want durable alive-idle phase with rollback identity", flag.Phase, flag.Step)
	}
}
