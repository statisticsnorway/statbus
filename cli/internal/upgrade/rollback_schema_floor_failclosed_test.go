package upgrade

import (
	"context"
	"errors"
	"os"
	"strings"
	"testing"
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
	err := d.holdRollbackSchemaFloorFailure(context.Background(), 354, "/backup/354", nil, errors.New("floor failed"))
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
	d := NewService(projDir, true, "test", "")
	if err := d.writeUpgradeFlag(356, "3560000000000000000000000000000000000000", nil, "test", string(TriggerService), false); err != nil {
		t.Fatalf("write held rollback marker: %v", err)
	}
	t.Cleanup(func() { _ = os.Remove(flagFilePath(projDir)) })
	if err := d.mutateHeldFlag(func(flag *UpgradeFlag) { flag.Step = StepRollback }); err != nil {
		t.Fatalf("seed rollback route: %v", err)
	}
	clientsErr := &RecoveryClientsLiveError{Services: []string{"app (running)"}}
	if err := d.holdRollbackClientsLive(context.Background(), 356, "/backup/356", nil, clientsErr); err != nil {
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
}

// A live-client invariant failure is intercepted immediately after the
// database-only start and returns from restoreAndFinalize. It must never fall
// through to source restoration or `docker compose --profile all up`.
func TestRestoreAndFinalizeClientsLiveReturnsBeforeFullStackStartup(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatal(err)
	}
	body := extractFuncBody(t, string(src), "func (d *Service) restoreAndFinalize(")
	startIdx := strings.Index(body, "d.startRollbackDatabaseOnly(ctx, progress)")
	holdIdx := strings.Index(body, "d.holdRollbackClientsLive(ctx, id, backupPath, progress, clientsLiveErr)")
	returnIdx := -1
	if holdIdx >= 0 {
		returnIdx = strings.Index(body[holdIdx:], "return true, nil")
	}
	restoreSourceIdx := strings.Index(body, `d.restoreGitState("", progress)`)
	fullStackIdx := strings.Index(body, `"docker", "compose", "--profile", "all", "up"`)
	if startIdx < 0 || holdIdx < 0 || returnIdx < 0 || restoreSourceIdx < 0 || fullStackIdx < 0 {
		t.Fatalf("control-flow pin is stale: start=%d hold=%d return=%d restoreSource=%d fullStack=%d", startIdx, holdIdx, returnIdx, restoreSourceIdx, fullStackIdx)
	}
	returnIdx += holdIdx
	if startIdx >= holdIdx || holdIdx >= returnIdx || returnIdx >= restoreSourceIdx || restoreSourceIdx >= fullStackIdx {
		t.Fatalf("live-client hold must return before source restore/full-stack startup: start=%d hold=%d return=%d restoreSource=%d fullStack=%d", startIdx, holdIdx, returnIdx, restoreSourceIdx, fullStackIdx)
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
	if err := d.holdRollbackSchemaFloorFailure(context.Background(), 355, "/backup/355", nil, errors.New("floor failed")); err != nil {
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
