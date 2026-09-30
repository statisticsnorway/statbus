package upgrade

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const canaryTargetSHA = "deadbeefcafe00000000000000000000000000aa"

// canaryShim models the demo: `docker compose ps` shows a bare sha256 for
// every container while Docker Config.Image carries the requested reference.
// configCase is a shell fragment answering `inspect --format {{.Config.Image}} <id>`
// with $4 as the container ID.
func canaryShim(t *testing.T, ps string, configCase string) {
	t.Helper()
	dir := t.TempDir()
	shim := "#!/bin/sh\ncase \"$*\" in\n" +
		"\t\"compose ps --format json\")\n" + ps + "\t\t;;\n" +
		"\t\"inspect --format {{.Config.Image}} \"*)\n" + configCase + "\n\t\t;;\n" +
		"esac\nexit 0\n"
	if err := os.WriteFile(filepath.Join(dir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
}

func canaryPS(ids map[string]string) string {
	bare := "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	var b strings.Builder
	for _, svc := range []string{"db", "app", "worker", "proxy", "rest"} {
		b.WriteString("\t\tprintf '%s\\n' '{\"ID\":\"" + ids[svc] + "\",\"Service\":\"" + svc + "\",\"State\":\"running\",\"Image\":\"" + bare + "\"}'\n")
	}
	return b.String()
}

var canaryIDs = map[string]string{"db": "db-c", "app": "app-c", "worker": "worker-c", "proxy": "proxy-c", "rest": "rest-c"}

func targetConfigCase(tag string) string {
	return `		case "$4" in
			db-c) echo "ghcr.io/statisticsnorway/statbus-db:` + tag + `" ;;
			app-c) echo "ghcr.io/statisticsnorway/statbus-app:` + tag + `" ;;
			worker-c) echo "ghcr.io/statisticsnorway/statbus-worker:` + tag + `" ;;
			proxy-c) echo "ghcr.io/statisticsnorway/statbus-proxy:` + tag + `" ;;
			*) echo "must-not-inspect-rest"; exit 9 ;;
		esac`
}

func canaryRun(t *testing.T) (bool, []containerCheckResult) {
	t.Helper()
	d := &Service{projDir: t.TempDir()}
	return d.containersAtFlagTarget(context.Background(), UpgradeFlag{CommitSHA: canaryTargetSHA})
}

// Demo shape: every compose display is a bare sha256, Config.Image is at target.
// Kills both a skipped-inspection loop and a db skip (db display is a bare sha).
func TestContainersAtFlagTargetBareSHADisplayWithTargetConfigImage(t *testing.T) {
	canaryShim(t, canaryPS(canaryIDs), targetConfigCase("deadbeef"))
	if ok, why := canaryRun(t); !ok {
		t.Fatalf("Config.Image at target must be at target despite bare-SHA displays: %v", why)
	}
}

func TestContainersAtFlagTargetSourceConfigImageIsNotTarget(t *testing.T) {
	canaryShim(t, canaryPS(canaryIDs), targetConfigCase("11111111"))
	if ok, _ := canaryRun(t); ok {
		t.Fatal("source Config.Image must not be reported at target")
	}
}

func TestContainersAtFlagTargetRefusesUnprovableReference(t *testing.T) {
	cases := map[string]struct {
		config string
		want   string
	}{
		"inspect failure": {`		exit 9`, "docker inspect Config.Image failed"},
		"empty":           {`		echo`, "empty or malformed"},
		"malformed":       {`		echo "a:1 b:2"`, "empty or malformed"},
		"bare image id":   {`		echo "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"`, "bare image ID"},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			canaryShim(t, canaryPS(canaryIDs), c.config)
			ok, why := canaryRun(t)
			if ok || len(why) == 0 || !strings.Contains(why[0].Reason, c.want) || strings.Contains(why[0].Reason, "<nil>") {
				t.Fatalf("ok=%v why=%v, want refusal containing %q without <nil>", ok, why, c.want)
			}
		})
	}
}

func TestContainersAtFlagTargetRefusesEmptyContainerID(t *testing.T) {
	ids := map[string]string{"db": "db-c", "app": "", "worker": "worker-c", "proxy": "proxy-c", "rest": "rest-c"}
	canaryShim(t, canaryPS(ids), targetConfigCase("deadbeef"))
	ok, why := canaryRun(t)
	if ok || len(why) == 0 || !strings.Contains(why[0].Reason, "no ID") {
		t.Fatalf("empty container ID must fail closed: ok=%v why=%v", ok, why)
	}
}
