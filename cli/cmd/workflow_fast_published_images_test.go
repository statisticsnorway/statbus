package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

// Execute the whole service step with literal event substitution, not an
// Actions expression evaluator. External Docker calls are refusing doubles.
func TestFastPublishedImagesServices(t *testing.T) {
	script := stepScriptByName(t, ".github/workflows/fast-tests.yaml", "fast-tests", "Start services")
	for _, tc := range []struct {
		name, event, pullExit, calls string
		exit                         int
	}{
		{"tag", "push", "0", "compose pull --quiet\ncompose --profile all up -d\n", 0},
		{"tag pull failure", "push", "42", "compose pull --quiet\n", 42},
		{"images completion", "workflow_run", "0", "compose pull --quiet\ncompose --profile all up -d\n", 0},
		{"images pull failure", "workflow_run", "42", "compose pull --quiet\n", 42},
		{"PR", "pull_request", "0", "compose --profile all up -d --build\n", 0},
		{"manual", "workflow_dispatch", "0", "compose --profile all up -d --build\n", 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			docker := `#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$CALL_LOG"
case "$*" in
 'compose pull --quiet') exit "$PULL_EXIT" ;;
 'compose --profile all up -d') exit 0 ;;
 'compose --profile all up -d --build') [[ "$EVENT" != push && "$EVENT" != workflow_run ]] || exit 91 ;;
 *) echo "refused docker: $*" >&2; exit 97 ;;
esac
`
			if err := os.WriteFile(filepath.Join(dir, "docker"), []byte(docker), 0700); err != nil {
				t.Fatal(err)
			}
			log := filepath.Join(dir, "calls")
			c := exec.Command("bash", "-e", "-c", strings.ReplaceAll(script, "${{ github.event_name }}", tc.event))
			c.Dir = dir
			c.Env = append(testgit.Env(), "PATH="+dir+":"+os.Getenv("PATH"), "CALL_LOG="+log, "PULL_EXIT="+tc.pullExit, "EVENT="+tc.event)
			out, err := c.CombinedOutput()
			exit := 0
			if err != nil {
				if e, ok := err.(*exec.ExitError); ok {
					exit = e.ExitCode()
				} else {
					t.Fatal(err)
				}
			}
			if exit != tc.exit {
				t.Errorf("exit=%d want %d\n%s", exit, tc.exit, out)
			}
			calls, err := os.ReadFile(log)
			if err != nil {
				t.Fatal(err)
			}
			if string(calls) != tc.calls {
				t.Errorf("calls=%q want %q\n%s", calls, tc.calls, out)
			}
		})
	}
}

// Declarative pins only: hosted Actions evaluates these expressions. The push
// selector is appropriate because the existing push trigger is RC tags only.
func TestFastPublishedImagesSelectors(t *testing.T) {
	const path = ".github/workflows/fast-tests.yaml"
	foundLogin, foundSeed := false, false
	for _, step := range jobSteps(t, path, "fast-tests") {
		switch step["name"] {
		case "Log in to GHCR":
			foundLogin = true
			if step["if"] != "github.event_name == 'workflow_run' || github.event_name == 'push'" {
				t.Errorf("login selector=%v", step["if"])
			}
		case "Run fast test suite":
			foundSeed = true
			env, ok := step["env"].(map[string]interface{})
			if !ok {
				t.Fatalf("seed env type=%T", step["env"])
			}
			if env["STATBUS_DB_SEED_NO_FETCH"] != "${{ (github.event_name == 'workflow_run' || github.event_name == 'push') && '0' || '1' }}" {
				t.Errorf("seed selector=%v", env["STATBUS_DB_SEED_NO_FETCH"])
			}
		}
	}
	if !foundLogin || !foundSeed {
		t.Fatalf("login=%v seed=%v", foundLogin, foundSeed)
	}
}
