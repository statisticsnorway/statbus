package releasecmd

import "testing"

// This compiles the real CLI module through the release preflight helper. The
// typed authority gate separately pins this as a direct host os/exec Go site and
// rejects rerouting it through upgrade.RunCommandOutput.
func TestRunGoCLIBuildUsesHostToolchain(t *testing.T) {
	out, err := runGoCLIBuild(thisRepoFile(t, "."))
	if err != nil {
		t.Fatalf("release Go-build check failed: %v\n%s", err, out)
	}
}
