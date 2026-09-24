package testguard

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestIsolatedDockerInvocationRequiresTemporaryMarkedProject(t *testing.T) {
	dir := t.TempDir()
	name := "statbus-livedocker-test-guard"
	t.Setenv("STATBUS_LIVE_DB_TEST", "1")
	t.Setenv("STATBUS_LIVEDOCKER_PROJECT_DIR", dir)
	t.Setenv("COMPOSE_PROJECT_NAME", name)
	if IsolatedDockerInvocation() {
		t.Fatal("unmarked temporary project authorized Docker")
	}
	if err := os.WriteFile(filepath.Join(dir, ".statbus-livedocker"), []byte(name+"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if !IsolatedDockerInvocation() || Check("docker", "/usr/bin/docker") != nil {
		t.Fatal("marked isolated project did not authorize Docker")
	}
	if err := Check("psql", "/usr/bin/psql"); err == nil {
		t.Fatal("isolated Docker project incorrectly authorized psql")
	}
	t.Setenv("COMPOSE_PROJECT_NAME", "statbus-local")
	if IsolatedDockerInvocation() {
		t.Fatal("developer project authorized Docker")
	}
}

func TestLiveDatabaseFixtureGuardRequiresPinnedTemporaryWorktree(t *testing.T) {
	t.Setenv("STATBUS_LIVEDB_TEST_TIER", "1")
	if liveDatabaseFixtureInvocation() {
		t.Fatal("tier flag alone authorized service commands")
	}
	root, err := os.MkdirTemp("", "statbus-livedb-guard-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(root) })
	project := filepath.Join(root, "project")
	if err := os.Mkdir(project, 0700); err != nil {
		t.Fatal(err)
	}
	pinned := filepath.Join(root, "pinned-sb")
	if err := os.WriteFile(pinned, nil, 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("STATBUS_LIVEDB_PROJECT_DIR", project)
	t.Setenv("STATBUS_LIVEDB_PINNED_SB", pinned)
	if liveDatabaseFixtureInvocation() {
		t.Fatal("unmarked worktree authorized service commands")
	}
	if err := os.WriteFile(filepath.Join(project, ".statbus"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	if !liveDatabaseFixtureInvocation() || Check("psql", "/usr/bin/psql") != nil {
		t.Fatal("pinned temporary live database fixture did not authorize psql")
	}
}

func TestInstallBlocksDirectExec(t *testing.T) {
	cleanup, err := Install()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(cleanup)
	cmd := exec.Command("docker", "compose", "down")
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), "unit test safety guard") {
		t.Fatalf("direct docker invocation escaped guard: %v %s", err, out)
	}
	if _, ok := err.(*exec.ExitError); !ok {
		t.Fatalf("unexpected refusal: %v", err)
	}
}

func TestRealServiceCommandsRefusedAndTempFakesAllowed(t *testing.T) {
	t.Setenv("STATBUS_CLI_UNIT_TEST_GUARD", "1")
	for _, name := range []string{"docker", "psql", "pg_dump", "pg_restore", "systemctl"} {
		if err := Check(name, filepath.Join("/usr/bin", name)); err == nil || !strings.Contains(err.Error(), "unit test safety guard") {
			t.Fatalf("%s escaped guard: %v", name, err)
		}
		if err := Check(name, filepath.Join(t.TempDir(), name)); err != nil {
			t.Fatalf("%s fake rejected: %v", name, err)
		}
	}
	if err := Check("git", filepath.Join("/usr/bin", "git")); err != nil {
		t.Fatal(err)
	}
}
