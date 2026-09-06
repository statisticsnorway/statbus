package releasecmd

import (
	"os/exec"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

func TestNoSameKindTagAtHEADIgnoresUnknownReleaseShapes(t *testing.T) {
	dir := t.TempDir()
	for _, args := range [][]string{{"init"}, {"config", "user.email", "test@example.com"}, {"config", "user.name", "Test"}, {"commit", "--allow-empty", "-m", "initial"}, {"tag", "v2026.09.1-beta.1"}} {
		cmd := exec.Command("git", testgit.Args(args...)...)
		cmd.Dir = dir
		cmd.Env = testgit.Env()
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v: %s", args, err, out)
		}
	}
	if err := noSameKindTagAtHEAD(dir, false); err != nil {
		t.Fatalf("unknown beta tag must not block a stable release: %v", err)
	}
}
