package diskpolicy

import (
	"context"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func TestSharedThresholdAcrossCallers(t *testing.T) {
	for _, caller := range []string{"first install", "rerun", "upgrade", "fixup"} {
		for _, tc := range []struct {
			free    uint64
			allowed bool
			text    string
		}{{12, false, "at least 20 GB"}, {20, true, "40 GB is recommended"}, {39, true, "40 GB is recommended"}, {40, true, "recommendation is met"}} {
			message, ok := Evaluate(Measurement{Path: "/var/lib/docker", FreeGB: tc.free})
			if ok != tc.allowed || !strings.Contains(message, tc.text) || !strings.Contains(message, "/var/lib/docker") {
				t.Errorf("%s %d: %s %t", caller, tc.free, message, ok)
			}
		}
	}
}

func TestSavedDiskPolicySurvivesNewProcess(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte(PolicyConfig), 0600); err != nil {
		t.Fatal(err)
	}
	policy, err := Load(dir)
	if err != nil || policy.MinimumGB != 20 || policy.RecommendedGB != 40 {
		t.Fatalf("reload: %+v %v", policy, err)
	}
	for _, free := range []uint64{19, 20, 39, 40} {
		_, allowed := policy.Evaluate(Measurement{Path: "/var/lib/docker", FreeGB: free})
		if allowed != (free >= 20) {
			t.Fatalf("%d GB: allowed=%t", free, allowed)
		}
	}
}

func TestDockerRootUnavailableFailsClosed(t *testing.T) {
	bin := t.TempDir()
	docker := filepath.Join(bin, "docker")
	if err := os.WriteFile(docker, []byte("#!/bin/sh\nprintf '/nonexistent/docker-storage\\n'\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	_, err := DockerRoot(context.Background(), t.TempDir())
	if err == nil || err.Error() != "cannot check disk space at Docker storage: Docker root unavailable" {
		t.Fatalf("unavailable root: %v", err)
	}
}

func TestDiskRefusalRetainsOperatorRerun(t *testing.T) {
	command := "curl -fsSL https://statbus.org/install.sh | env STATBUS_ENV_CONFIG=/home/operator/answers bash -s -- --channel prerelease --non-interactive"
	t.Setenv("STATBUS_INSTALL_RERUN_COMMAND", command)
	message, ok := Evaluate(Measurement{Path: "/docker", FreeGB: 1})
	if ok || !strings.Contains(message, command) {
		t.Fatalf("refusal: %q allowed=%t", message, ok)
	}
}

// A direct `./sb install` has no saved install.sh invocation. Its rerun is the
// same local program on the same checkout, never the public stable installer,
// which would replace ./sb and move a prerelease or pinned box to another
// release.
func TestRerunWithoutSavedCommandKeepsTheLocalProgram(t *testing.T) {
	t.Setenv("STATBUS_INSTALL_RERUN_COMMAND", "")
	got := RerunCommand()
	if !strings.HasPrefix(got, "cd ") || !strings.HasSuffix(got, " && ./sb install") {
		t.Fatalf("fallback rerun = %q, want `cd <checkout> && ./sb install`", got)
	}
	if strings.Contains(got, "curl") || strings.Contains(got, "install.sh") {
		t.Fatalf("fallback rerun must not be the public installer: %q", got)
	}
}

// STATBUS-487: the Uganda box (2026-10-13) had Docker installed and running, but
// the install user was not in the docker group. `docker info` answered with the
// daemon's permission sentence on stderr, and the installer printed only the
// generic "Docker root unavailable" line, which names no cause and no remedy.
// Each of the three Docker causes must get its own sentence instead.
const ugandaDockerDenied = "permission denied while trying to connect to the docker API at unix:///var/run/docker.sock"
const genericDockerRootLine = "cannot check disk space at Docker storage: Docker root unavailable"

func fakeDocker(t *testing.T, stderr string, rc int) {
	t.Helper()
	bin := t.TempDir()
	script := "#!/bin/sh\nprintf '%s\\n' '" + stderr + "' >&2\nexit " + strconv.Itoa(rc) + "\n"
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin)
}

func TestDockerRootNamesTheUgandaPermissionCause(t *testing.T) {
	const rerun = "curl -fsSL https://statbus.org/install.sh | bash"
	t.Setenv("STATBUS_INSTALL_RERUN_COMMAND", rerun)
	t.Setenv("USER", "statbus")
	fakeDocker(t, ugandaDockerDenied, 1)
	_, err := DockerRoot(context.Background(), t.TempDir())
	if err == nil {
		t.Fatal("DockerRoot succeeded although docker refused the user")
	}
	got := err.Error()
	if got == genericDockerRootLine || strings.Contains(got, "Docker root unavailable") {
		t.Fatalf("the Uganda permission cause is still masked by the disk sentence: %q", got)
	}
	for _, want := range []string{
		"may not use Docker",
		"(Docker said: " + ugandaDockerDenied + ")",
		"getent group docker",
		"sudo usermod -aG docker",
		"log out and log in again",
		"id -nG",
		"run the same install command again: " + rerun,
	} {
		if !strings.Contains(got, want) {
			t.Errorf("permission refusal missing %q:\n%s", want, got)
		}
	}
	if strings.Count(got, "\n") != 0 {
		t.Errorf("refusal must be one line for the install-log allow-list: %q", got)
	}
}

func TestDockerRootNamesAStoppedDaemon(t *testing.T) {
	const rerun = "curl -fsSL https://statbus.org/install.sh | bash"
	t.Setenv("STATBUS_INSTALL_RERUN_COMMAND", rerun)
	fakeDocker(t, "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?", 1)
	_, err := DockerRoot(context.Background(), t.TempDir())
	if err == nil || err.Error() != DockerStoppedRefusal(rerun) {
		t.Fatalf("stopped daemon: %v", err)
	}
	if !strings.Contains(err.Error(), "sudo systemctl enable --now docker") {
		t.Fatalf("stopped daemon remedy missing: %v", err)
	}
}

func TestDockerRootNamesAMissingDocker(t *testing.T) {
	const rerun = "curl -fsSL https://statbus.org/install.sh | bash"
	t.Setenv("STATBUS_INSTALL_RERUN_COMMAND", rerun)
	t.Setenv("PATH", t.TempDir()) // no docker anywhere
	_, err := DockerRoot(context.Background(), t.TempDir())
	if err == nil || err.Error() != DockerAbsentRefusal(rerun) {
		t.Fatalf("absent docker: %v", err)
	}
	if !strings.Contains(err.Error(), DockerSetupGuide) {
		t.Fatalf("absent docker must point at the documented prerequisite: %v", err)
	}
}

// An unrecognised docker failure keeps the honest generic refusal: it is not one
// of the three named causes, and guessing a remedy would be worse.
func TestDockerRootKeepsGenericLineForUnknownFailure(t *testing.T) {
	fakeDocker(t, "some unrelated docker failure", 1)
	_, err := DockerRoot(context.Background(), t.TempDir())
	if err == nil || err.Error() != genericDockerRootLine {
		t.Fatalf("unknown failure: %v", err)
	}
}
