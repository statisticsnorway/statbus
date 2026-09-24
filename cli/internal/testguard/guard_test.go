package testguard

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

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
