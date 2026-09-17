package upgrade

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestStartDBForRecovery_DependencySafeArgvAndHeldClosedCheck(t *testing.T) {
	for _, tc := range []struct {
		name        string
		liveService string
		wantErr     string
	}{
		{name: "clients remain stopped"},
		{name: "negative control catches rest running", liveService: "rest", wantErr: "held-closed recovery invariant violated"},
		{name: "negative control catches app running", liveService: "app", wantErr: "held-closed recovery invariant violated"},
		{name: "negative control catches worker running", liveService: "worker", wantErr: "held-closed recovery invariant violated"},
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
      [ "$service" = "$STATBUS_TEST_LIVE_SERVICE" ] && state=running
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

			d := &Service{projDir: t.TempDir()}
			err := d.StartDBForRecovery(context.Background())
			if tc.wantErr == "" && err != nil {
				t.Fatalf("StartDBForRecovery: %v", err)
			}
			if tc.wantErr != "" && (err == nil || !strings.Contains(err.Error(), tc.wantErr)) {
				t.Fatalf("StartDBForRecovery error = %v, want containing %q", err, tc.wantErr)
			}

			logBytes, readErr := os.ReadFile(logPath)
			if readErr != nil {
				t.Fatal(readErr)
			}
			log := string(logBytes)
			if !strings.Contains(log, "compose start db\n") {
				t.Fatalf("exact dependency-safe compose argv absent from docker log:\n%s", log)
			}
			// Negative control for the rc.16 bug: naming proxy to Compose start
			// would honour proxy->rest depends_on and violate the held-closed window.
			if strings.Contains(log, "compose start db proxy") || strings.Contains(log, "compose start proxy") {
				t.Fatalf("dependency-pulling compose argv present in docker log:\n%s", log)
			}
			if strings.Contains(log, "compose --profile all up") {
				t.Fatalf("held-closed client failure must not issue full-stack compose up:\n%s", log)
			}
			if !strings.Contains(log, "start proxy-container-id\n") {
				t.Fatalf("existing proxy container was not started directly:\n%s", log)
			}
		})
	}
}
