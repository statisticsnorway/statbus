package upgrade

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestEnsureRecoveryClientsStoppedObservesBeforeNarrating(t *testing.T) {
	tests := []struct {
		name      string
		initial   string
		stopFails bool
		wantErr   bool
		wantStop  bool
	}{
		{name: "already stopped is verified without stop", initial: "exited"},
		{name: "live clients are contained then verified", initial: "running", wantStop: true},
		{name: "failed containment remains unverified", initial: "running", stopFails: true, wantErr: true, wantStop: true},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			projDir := t.TempDir()
			shimDir := t.TempDir()
			logPath := filepath.Join(shimDir, "docker.log")
			stoppedPath := filepath.Join(shimDir, "stopped")
			shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	"compose ps -a --format json")
		state="$STATBUS_TEST_INITIAL_STATE"
		if [ -f "$STATBUS_TEST_STOPPED" ]; then state=exited; fi
		printf '%s\n' '{"Service":"app","State":"'"$state"'"}'
		printf '%s\n' '{"Service":"worker","State":"'"$state"'"}'
		printf '%s\n' '{"Service":"rest","State":"'"$state"'"}'
		;;
	"compose stop app worker rest")
		if [ "$STATBUS_TEST_STOP_FAILS" = 1 ]; then exit 1; fi
		touch "$STATBUS_TEST_STOPPED"
		;;
esac
exit 0
`
			if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
				t.Fatal(err)
			}
			t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
			t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)
			t.Setenv("STATBUS_TEST_STOPPED", stoppedPath)
			t.Setenv("STATBUS_TEST_INITIAL_STATE", tc.initial)
			if tc.stopFails {
				t.Setenv("STATBUS_TEST_STOP_FAILS", "1")
			} else {
				t.Setenv("STATBUS_TEST_STOP_FAILS", "0")
			}

			d := &Service{projDir: projDir}
			err := d.ensureRecoveryClientsStopped(context.Background(), nil)
			if (err != nil) != tc.wantErr {
				t.Fatalf("ensureRecoveryClientsStopped error = %v, wantErr=%v", err, tc.wantErr)
			}
			logBytes, readErr := os.ReadFile(logPath)
			if readErr != nil {
				t.Fatal(readErr)
			}
			log := string(logBytes)
			verifyIdx := strings.Index(log, "compose ps -a --format json")
			stopIdx := strings.Index(log, "compose stop app worker rest")
			if verifyIdx < 0 {
				t.Fatalf("containment did not first observe docker state:\n%s", log)
			}
			if tc.wantStop {
				if stopIdx < verifyIdx {
					t.Fatalf("containment stop must follow observation: verify=%d stop=%d\n%s", verifyIdx, stopIdx, log)
				}
			} else if stopIdx >= 0 {
				t.Fatalf("already-stopped clients must not be stopped again:\n%s", log)
			}
		})
	}
}

func TestRollbackFailureNarrationRequiresContainmentEvidence(t *testing.T) {
	source := readUpgradeServiceSource(t)
	restore := extractFuncBody(t, source, "func (d *Service) restoreAndFinalize(")
	for _, forbidden := range []string{
		"No source application services were started.",
		"Application services remain stopped.",
		"serving tier remained closed",
	} {
		if strings.Contains(restore, forbidden) || strings.Contains(source, forbidden) {
			t.Errorf("recovery retains unverified stopped-service claim %q", forbidden)
		}
	}
	if got := strings.Count(restore, "d.ensureRecoveryClientsStopped(ctx, progress)"); got != 2 {
		t.Fatalf("restoreAndFinalize must observe/contain clients at both restore-failure and floor-failure terminals; got %d calls", got)
	}
	ensure := extractFuncBody(t, source, "func (d *Service) ensureRecoveryClientsStopped(")
	verifyIdx := strings.Index(ensure, "d.verifyRecoveryClientsStopped(ctx)")
	successNarrativeIdx := strings.Index(ensure, "stopped and verified")
	containIdx := strings.Index(ensure, "d.stopAndVerifyRecoveryClients(progress)")
	if verifyIdx < 0 || successNarrativeIdx < verifyIdx || containIdx < verifyIdx {
		t.Fatalf("containment evidence order must be verify -> truthful success or narrow containment; verify=%d narrative=%d contain=%d", verifyIdx, successNarrativeIdx, containIdx)
	}
	contain := extractFuncBody(t, source, "func (d *Service) stopAndVerifyRecoveryClients(")
	stopIdx := strings.Index(contain, `"compose", "stop"`)
	postVerifyIdx := strings.Index(contain, "compose.VerifyStopped(")
	if stopIdx < 0 || postVerifyIdx < stopIdx {
		t.Fatalf("narrow containment must stop then positively re-verify; stop=%d postVerify=%d", stopIdx, postVerifyIdx)
	}
}
