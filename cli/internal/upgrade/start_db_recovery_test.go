package upgrade

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
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

			d := &Service{projDir: t.TempDir()}
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
			assertDependencySafeRecoveryRouteArgv(t, log)
			if strings.Contains(log, "compose --profile all up") {
				t.Fatalf("held-closed serving-tier failure must not issue full-stack compose up:\n%s", log)
			}
		})
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
