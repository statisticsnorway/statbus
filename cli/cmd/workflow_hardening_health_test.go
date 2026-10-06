package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

// Execute the entire YAML step, refusing every external call except its three
// observed assertions. Docker Compose emits one JSON object per service.
func TestHardeningServiceReadiness(t *testing.T) {
	script := stepScriptByName(t, ".github/workflows/test-hardening.yaml", "install-stack", "Verify services")
	const running = "{\"State\":\"running\"}\n{\"State\":\"running\"}\n"
	for _, tc := range []struct {
		name, json, psExit, dbExit, calls string
		success                           bool
	}{
		{"running NDJSON", running, "0", "0", "readiness\nupgrade\nextension\n", true},
		{"exited service", "{\"State\":\"running\"}\n{\"State\":\"exited\"}\n", "0", "0", "", false},
		{"malformed JSON", running + "not-json\n", "0", "0", "", false},
		{"empty output", "", "0", "0", "", false},
		{"docker command failure", "", "23", "0", "", false},
		{"partial output and docker failure", running, "23", "0", "", false},
		{"database not ready", running, "0", "24", "readiness\n", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			write := func(name, text string) {
				t.Helper()
				if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0700); err != nil {
					t.Fatal(err)
				}
			}
			write("docker", `#!/usr/bin/env bash
set -eu
case "$*" in
 'compose ps --format json') printf '%s' "$PS_JSON"; exit "$PS_EXIT" ;;
 'compose exec db pg_isready -U postgres') echo readiness >> "$CALL_LOG"; exit "$DB_EXIT" ;;
 *) echo "refused docker: $*" >&2; exit 97 ;;
esac
`)
			write("sb", `#!/usr/bin/env bash
set -eu
[[ "$*" == psql ]] || { echo "refused sb: $*" >&2; exit 97; }
read -r sql
case "$sql" in
 'SELECT COUNT(*) FROM public.upgrade;') echo upgrade >> "$CALL_LOG" ;;
 "SELECT extname, extversion FROM pg_extension WHERE extname = 'jsonb_stats';") echo extension >> "$CALL_LOG" ;;
 *) echo "refused SQL: $sql" >&2; exit 97 ;;
esac
`)
			log := filepath.Join(dir, "calls")
			write("calls", "")
			c := exec.Command("bash", "-e", "-c", script)
			c.Dir = dir
			c.Env = append(testgit.Env(), "PATH="+dir+":"+os.Getenv("PATH"), "PS_JSON="+tc.json, "PS_EXIT="+tc.psExit, "DB_EXIT="+tc.dbExit, "CALL_LOG="+log)
			out, err := c.CombinedOutput()
			if (err == nil) != tc.success {
				t.Errorf("success=%v, want %v, error=%v\n%s", err == nil, tc.success, err, out)
			}
			banner := strings.Contains(string(out), "All services")
			if banner != tc.success {
				t.Errorf("success banner=%v, want %v\n%s", banner, tc.success, out)
			}
			if tc.success && !strings.Contains(string(out), "All services running and database ready") {
				t.Errorf("missing accurate success banner\n%s", out)
			}
			calls, err := os.ReadFile(log)
			if err != nil {
				t.Fatal(err)
			}
			if string(calls) != tc.calls {
				t.Errorf("later assertions=%q, want %q", calls, tc.calls)
			}
		})
	}
}
