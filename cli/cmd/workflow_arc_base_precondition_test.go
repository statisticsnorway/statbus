package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

// Check the actual job admission graph, not GitHub runtime scheduling.
// The hosted off-master control rejected A in construct while ramp ran anyway.
func TestArcRampRequiresSuccessfulConstruct(t *testing.T) {
	doc := workflowDoc(t, ".github/workflows/upgrade-arc-harness.yaml")
	jobs := doc["jobs"].(map[string]any)
	ramp := jobs["ramp"].(map[string]any)
	needs, ok := ramp["needs"].([]any)
	if !ok || len(needs) != 2 || needs[0] != "discover" || needs[1] != "construct" {
		t.Errorf("ramp must wait for discover and construct before fleet side effects; needs=%v", ramp["needs"])
	}
	// !cancelled() suppresses implicit success(), so the direct dependency
	// alone does not exclude failed or skipped construction.
	condition, _ := ramp["if"].(string)
	const admission = "${{ !cancelled() && needs.discover.result == 'success' && needs.construct.result == 'success' && needs.discover.outputs.count != '0' }}"
	if condition != admission {
		t.Errorf("ramp must require successful construction and nonzero discovery; if=%q, want %q", condition, admission)
	}
}

// Execute the actual workflow scripts, with real local Git and stubbed external boundaries.
func TestArcBaseImagePrecondition(t *testing.T) {
	const workflow = ".github/workflows/upgrade-arc-harness.yaml"
	script := stepScriptByName(t, workflow, "construct", "Build the shared")
	for _, tc := range []struct {
		name, mode     string
		ancestor, fail bool
	}{
		{"worker unavailable", "worker", false, true},
		{"published divergent base", "present", false, false},
		{"unpublished master ancestor", "worker", true, false},
		{"registry authorization failure", "denied", false, true},
		{"master fetch failure", "fetch", false, true},
		{"ancestry command failure", "ancestry", false, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			runGit := func(args ...string) string {
				t.Helper()
				c := exec.Command("git", testgit.Args(args...)...)
				c.Dir = dir
				c.Env = testgit.Env()
				out, err := c.CombinedOutput()
				if err != nil {
					t.Fatalf("git %v: %v\n%s", args, err, out)
				}
				return strings.TrimSpace(string(out))
			}
			runGit("init", "-b", "master")
			runGit("config", "user.email", "arc@example.invalid")
			runGit("config", "user.name", "Arc test")
			runGit("config", "commit.gpgsign", "false")
			runGit("commit", "--allow-empty", "-m", "root")
			ancestor := runGit("rev-parse", "HEAD")
			runGit("commit", "--allow-empty", "-m", "master")
			master := runGit("rev-parse", "HEAD")
			runGit("checkout", "-b", "feature", ancestor)
			runGit("commit", "--allow-empty", "-m", "divergent A")
			base := runGit("rev-parse", "HEAD")
			origin := filepath.Join(t.TempDir(), "origin.git")
			runGit("clone", "--bare", dir, origin)
			runGit("remote", "add", "origin", origin)
			if tc.ancestor {
				base = ancestor
			}
			if tc.mode == "fetch" {
				runGit("--git-dir="+origin, "update-ref", "-d", "refs/heads/master")
			}
			write := func(path, text string) {
				t.Helper()
				if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(path, []byte(text), 0755); err != nil {
					t.Fatal(err)
				}
			}
			log := filepath.Join(dir, "calls")
			write(filepath.Join(dir, "test/install-recovery/lib/upgrade-target.sh"), `construct_upgrade_target() {
 echo fixture >> "$CALL_LOG"
 B_BRANCH=b; C_BRANCH=c; B_FULL=bbbb; C_FULL=cccc; B_SHORT=bbbb; C_SHORT=cccc
 V_VERSION=v1; V_VERSION_2=v2; V_VERSION_3=v3; ARC_PUBKEY=key
}
`)
			bin := filepath.Join(dir, "bin")
			if tc.mode == "ancestry" {
				realGit, err := exec.LookPath("git")
				if err != nil {
					t.Fatal(err)
				}
				write(filepath.Join(bin, "git"), "#!/bin/bash\nif [ \"$1\" = merge-base ]; then echo 'ancestry object failure' >&2; exit 128; fi\nexec \""+realGit+"\" \"$@\"\n")
			}
			write(filepath.Join(bin, "docker"), `#!/bin/bash
 echo "docker $*" >> "$CALL_LOG"
 if [ "$1" = login ]; then cat >/dev/null; exit 0; fi
 if [ "$MODE" = denied ]; then echo 'unauthorized: access denied' >&2; exit 1; fi
 if [ "$MODE" = worker ] && [[ "$3" == *statbus-worker:* ]]; then echo 'manifest unknown' >&2; exit 1; fi
 exit 0
`)
			write(filepath.Join(bin, "gh"), "#!/bin/bash\necho dispatch >> \"$CALL_LOG\"\n")
			write(filepath.Join(bin, "sleep"), "#!/bin/bash\necho poll >> \"$CALL_LOG\"\nexit 1\n")
			c := exec.Command("bash", "-c", script)
			c.Dir = dir
			c.Env = append(testgit.Env(), "PATH="+bin+":"+os.Getenv("PATH"), "BASE_SHA_INPUT="+base, "GITHUB_SHA="+master, "GH_TOKEN=fake", "ACTOR=test", "REGISTRY=ghcr.io", "ORG=statisticsnorway", "MODE="+tc.mode, "CALL_LOG="+log, "GITHUB_OUTPUT="+filepath.Join(dir, "output"))
			out, err := c.CombinedOutput()
			calls, _ := os.ReadFile(log)
			t.Logf("base=%s exit=%v\n%s\ncalls:\n%s", base, err, out, calls)
			if tc.fail {
				if err == nil || !strings.Contains(string(out), base) || strings.Contains(string(calls), "fixture") || strings.Contains(string(calls), "dispatch") || strings.Contains(string(calls), "poll") {
					t.Fatalf("must refuse before fixtures: exit=%v\n%s\n%s", err, out, calls)
				}
				switch tc.mode {
				case "ancestry":
					if !strings.Contains(string(out), "ancestry check failed") || !strings.Contains(string(out), "128") || strings.Contains(string(out), "off-master base images") || len(calls) != 0 {
						t.Fatalf("ancestry error misclassified: %s\n%s", out, calls)
					}
				case "fetch":
					if !strings.Contains(string(out), "master fetch failed") || strings.Contains(string(out), "off-master base images") || len(calls) != 0 {
						t.Fatalf("fetch error misclassified: %s\n%s", out, calls)
					}
				default:
					for _, svc := range []string{"app", "worker", "db", "proxy", "sb"} {
						if !strings.Contains(string(calls), "statbus-"+svc+":") {
							t.Errorf("did not inspect %s", svc)
						}
					}
					cause := "worker"
					if tc.mode == "denied" {
						cause = "unauthorized"
					}
					if !strings.Contains(string(out), cause) {
						t.Errorf("missing cause %s: %s", cause, out)
					}
				}
			} else if err != nil || strings.Count(string(calls), "fixture") != 7 {
				t.Fatalf("must construct normally: %v\n%s\n%s", err, out, calls)
			}
			if tc.ancestor && strings.Contains(string(calls), "docker") {
				t.Error("master ancestor must bypass registry")
			}
		})
	}
	t.Run("existing image wait retries then succeeds", func(t *testing.T) {
		script := stepScriptByName(t, workflow, "image-wait", "Poll ghcr")
		dir := t.TempDir()
		log := filepath.Join(dir, "calls")
		ready := filepath.Join(dir, "ready")
		for name, text := range map[string]string{
			"docker": `#!/bin/bash
 echo "docker $*" >> "$CALL_LOG"
 if [ "$1" = login ]; then cat >/dev/null; exit 0; fi
 [ -e "$READY" ]
`,
			"sleep": "#!/bin/bash\necho poll >> \"$CALL_LOG\"\ntouch \"$READY\"\n",
		} {
			if err := os.WriteFile(filepath.Join(dir, name), []byte(text), 0755); err != nil {
				t.Fatal(err)
			}
		}
		c := exec.Command("bash", "-c", script)
		c.Env = append(testgit.Env(), "PATH="+dir+":"+os.Getenv("PATH"), "GH_TOKEN=fake", "REGISTRY=ghcr.io", "ORG=statisticsnorway", "ACTOR=test", "SHORTS=aaaa bbbb cccc", "IMAGES_WAIT_BUDGET_S=2400", "IMAGES_WAIT_INTERVAL_S=30", "CALL_LOG="+log, "READY="+ready)
		out, err := c.CombinedOutput()
		calls, _ := os.ReadFile(log)
		t.Logf("exit=%v\n%s\n%s", err, out, calls)
		if err != nil || strings.Count(string(calls), "poll") != 1 || !strings.Contains(string(out), "All per-commit service images present") {
			t.Fatalf("retry failed: %v\n%s\n%s", err, out, calls)
		}
	})
}
