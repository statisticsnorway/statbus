package upgrade

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestStartDatabaseRouteServingMayRun_DependencySafeArgvAllowsLiveServingTier(t *testing.T) {
	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
  "compose ps -a --format json")
    printf '%s\n' '{"Service":"proxy","State":"running"}'
    printf '%s\n' '{"Service":"rest","State":"running"}'
    printf '%s\n' '{"Service":"app","State":"running"}'
    printf '%s\n' '{"Service":"worker","State":"running"}'
    ;;
  "compose ps -a -q proxy") echo proxy-container-id ;;
  "compose exec db pg_isready -U postgres") echo accepting connections ;;
  *) echo "shim: $*" ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)

	d := &Service{projDir: t.TempDir()}
	if err := d.StartDatabaseRouteServingMayRun(context.Background()); err != nil {
		t.Fatalf("StartDatabaseRouteServingMayRun must allow an already-running serving tier: %v", err)
	}

	logBytes, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	assertDependencySafeRecoveryRouteArgv(t, string(logBytes))
}

func TestStartDatabaseRouteServingMustBeStopped_DependencySafeArgvAndStrictServingCheck(t *testing.T) {
	for _, tc := range []struct {
		name         string
		liveService  string
		serviceState string
		wantErr      string
	}{
		{name: "serving tier remains stopped"},
		{name: "accepted terminal state exited", liveService: "rest", serviceState: "exited"},
		{name: "accepted terminal state created", liveService: "app", serviceState: "created"},
		{name: "accepted terminal state dead", liveService: "worker", serviceState: "dead"},
		{name: "negative control catches rest running", liveService: "rest", serviceState: "running", wantErr: "held-closed recovery invariant violated"},
		{name: "negative control catches app paused", liveService: "app", serviceState: "paused", wantErr: "held-closed recovery invariant violated"},
		{name: "negative control catches worker restarting", liveService: "worker", serviceState: "restarting", wantErr: "held-closed recovery invariant violated"},
		{name: "negative control catches unknown empty state", liveService: "rest", serviceState: "", wantErr: "held-closed recovery invariant violated"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			shimDir := t.TempDir()
			logPath := filepath.Join(shimDir, "docker.log")
			shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
  "compose ps -a --format json")
	    printf '%s\n' '{"Service":"proxy","State":"running"}'
	    for service in rest app worker; do
	      state=exited
	      [ "$service" = "$STATBUS_TEST_LIVE_SERVICE" ] && state=$STATBUS_TEST_SERVICE_STATE
      printf '{"Service":"%s","State":"%s"}\n' "$service" "$state"
    done
    ;;
  "compose ps -a -q proxy") echo proxy-container-id ;;
  "compose exec db pg_isready -U postgres") echo accepting connections ;;
  *) echo "shim: $*" ;;
esac
exit 0
`
			if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
				t.Fatal(err)
			}
			t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
			t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)
			t.Setenv("STATBUS_TEST_LIVE_SERVICE", tc.liveService)
			t.Setenv("STATBUS_TEST_SERVICE_STATE", tc.serviceState)

			projDir := t.TempDir()
			lock, lockErr := acquireFreshFlock(projDir, UpgradeFlag{ID: 17, Holder: HolderService, Trigger: "recovery", Phase: PhaseNewSbSwapped})
			if lockErr != nil {
				t.Fatal(lockErr)
			}
			t.Cleanup(func() {
				_ = os.Remove(flagFilePath(projDir))
				lock.Close()
			})
			d := &Service{projDir: projDir, flagLock: lock}
			err := d.StartDatabaseRouteServingMustBeStopped(context.Background())
			if tc.wantErr == "" && err != nil {
				t.Fatalf("StartDatabaseRouteServingMustBeStopped: %v", err)
			}
			if tc.wantErr != "" && (err == nil || !strings.Contains(err.Error(), tc.wantErr)) {
				t.Fatalf("StartDatabaseRouteServingMustBeStopped error = %v, want containing %q", err, tc.wantErr)
			}

			logBytes, readErr := os.ReadFile(logPath)
			if readErr != nil {
				t.Fatal(readErr)
			}
			log := string(logBytes)
			if tc.wantErr == "" {
				assertDependencySafeRecoveryRouteArgv(t, log)
			} else if strings.Contains(log, "compose start db") || strings.Contains(log, "start proxy-container-id") {
				t.Fatalf("held-closed pre-start verifier must refuse before opening the database route:\n%s", log)
			}
			if strings.Contains(log, "compose --profile all up") {
				t.Fatalf("held-closed serving-tier failure must not issue full-stack compose up:\n%s", log)
			}
		})
	}
}

func TestStartDatabaseRouteServingMustBeStoppedRequiresCanonicalRecoveryFlock(t *testing.T) {
	d := &Service{projDir: t.TempDir()}
	err := d.StartDatabaseRouteServingMustBeStopped(context.Background())
	if err == nil || !strings.Contains(err.Error(), "requires the recovery marker flock") {
		t.Fatalf("held-closed start without recovery flock = %v, want refusal", err)
	}
}

func TestStartDatabaseRouteServingMustBeStoppedHoldsCanonicalFlockContinuously(t *testing.T) {
	shimDir := t.TempDir()
	startEntered := filepath.Join(shimDir, "start-entered")
	startRelease := filepath.Join(shimDir, "start-release")
	postcheckEntered := filepath.Join(shimDir, "postcheck-entered")
	postcheckRelease := filepath.Join(shimDir, "postcheck-release")
	healthEntered := filepath.Join(shimDir, "health-entered")
	healthRelease := filepath.Join(shimDir, "health-release")
	psCount := filepath.Join(shimDir, "ps-count")
	shim := `#!/bin/sh
case "$*" in
  "compose ps -a --format json")
    count=0
    [ ! -f "$STATBUS_TEST_PS_COUNT" ] || read -r count < "$STATBUS_TEST_PS_COUNT"
    count=$((count + 1))
    printf '%s\n' "$count" > "$STATBUS_TEST_PS_COUNT"
    if [ "$count" -eq 3 ]; then
      : > "$STATBUS_TEST_POSTCHECK_ENTERED"
      while [ ! -f "$STATBUS_TEST_POSTCHECK_RELEASE" ]; do sleep 0.01; done
    fi
    printf '%s\n' '{"Service":"proxy","State":"running"}'
    for service in rest app worker; do
      printf '{"Service":"%s","State":"exited"}\n' "$service"
    done
    ;;
  "compose start db")
    : > "$STATBUS_TEST_START_ENTERED"
    while [ ! -f "$STATBUS_TEST_START_RELEASE" ]; do sleep 0.01; done
    ;;
  "compose ps -a -q proxy") echo proxy-container-id ;;
  "compose exec db pg_isready -U postgres")
    : > "$STATBUS_TEST_HEALTH_ENTERED"
    while [ ! -f "$STATBUS_TEST_HEALTH_RELEASE" ]; do sleep 0.01; done
    echo accepting connections
    ;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_PS_COUNT", psCount)
	t.Setenv("STATBUS_TEST_START_ENTERED", startEntered)
	t.Setenv("STATBUS_TEST_START_RELEASE", startRelease)
	t.Setenv("STATBUS_TEST_POSTCHECK_ENTERED", postcheckEntered)
	t.Setenv("STATBUS_TEST_POSTCHECK_RELEASE", postcheckRelease)
	t.Setenv("STATBUS_TEST_HEALTH_ENTERED", healthEntered)
	t.Setenv("STATBUS_TEST_HEALTH_RELEASE", healthRelease)

	projDir := t.TempDir()
	lock, err := acquireFreshFlock(projDir, UpgradeFlag{ID: 17, Holder: HolderService, Trigger: "recovery", Phase: PhaseNewSbSwapped})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		for _, release := range []string{startRelease, postcheckRelease, healthRelease} {
			_ = os.WriteFile(release, nil, 0o600)
		}
		lock.Close()
		_ = os.Remove(flagFilePath(projDir))
	})

	d := &Service{projDir: projDir, flagLock: lock}
	result := make(chan error, 1)
	go func() {
		callErr := d.StartDatabaseRouteServingMustBeStopped(context.Background())
		lock.Close()
		result <- callErr
	}()

	waitForRecoveryRouteTestFile(t, startEntered)
	assertOperatorStartGuardContended(t, projDir, "while database route startup is blocked")
	if err := os.WriteFile(startRelease, nil, 0o600); err != nil {
		t.Fatal(err)
	}

	waitForRecoveryRouteTestFile(t, postcheckEntered)
	assertOperatorStartGuardContended(t, projDir, "while the post-start stopped-client verification is blocked")
	if err := os.WriteFile(postcheckRelease, nil, 0o600); err != nil {
		t.Fatal(err)
	}

	waitForRecoveryRouteTestFile(t, healthEntered)
	assertOperatorStartGuardContended(t, projDir, "after the post-start stopped-client verification completed")
	if err := os.WriteFile(healthRelease, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	select {
	case callErr := <-result:
		if callErr != nil {
			t.Fatalf("StartDatabaseRouteServingMustBeStopped: %v", callErr)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for held-closed database route start to return")
	}

	guard, err := AcquireOperatorStartGuard(projDir, "test:after-held-closed-route")
	if err != nil {
		t.Fatalf("operator start guard remained contended after recovery returned and released its flock: %v", err)
	}
	if err := guard.Release(); err != nil {
		t.Fatal(err)
	}
}

func waitForRecoveryRouteTestFile(t *testing.T, path string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(path); err == nil {
			return
		} else if !os.IsNotExist(err) {
			t.Fatal(err)
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for recovery route test signal %s", filepath.Base(path))
}

func assertOperatorStartGuardContended(t *testing.T, projDir, phase string) {
	t.Helper()
	guard, err := AcquireOperatorStartGuard(projDir, "test:competing-start")
	if guard != nil {
		_ = guard.Release()
		t.Fatalf("operator start acquired the canonical recovery flock %s", phase)
	}
	if err == nil || !strings.Contains(err.Error(), "holds the recovery lock") {
		t.Fatalf("operator start contention %s = %v, want live recovery-lock refusal", phase, err)
	}
}

func assertDependencySafeRecoveryRouteArgv(t *testing.T, log string) {
	t.Helper()
	if !strings.Contains(log, "compose start db\n") {
		t.Fatalf("exact dependency-safe compose argv absent from docker log:\n%s", log)
	}
	// Negative control for the rc.16 bug: naming proxy to Compose start
	// would honour proxy->rest depends_on and violate the held-closed window.
	if strings.Contains(log, "compose start db proxy") || strings.Contains(log, "compose start proxy") {
		t.Fatalf("dependency-pulling compose argv present in docker log:\n%s", log)
	}
	if !strings.Contains(log, "start proxy-container-id\n") {
		t.Fatalf("existing proxy container was not started directly:\n%s", log)
	}
}
