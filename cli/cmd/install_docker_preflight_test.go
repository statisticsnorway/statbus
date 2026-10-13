package cmd

import (
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/diskpolicy"
)

// STATBUS-487. OBSERVED on the owner's Uganda box, 2026-10-13: Docker was
// installed and its daemon was running, but the install user was not in the
// docker group. `curl -fsSL https://statbus.org/install.sh | bash` downloaded
// the binary, fetched and checked out the release, and then stopped with
//
//	cannot check disk space at Docker storage: Docker root unavailable
//
// which names neither Docker's real problem nor a remedy. These tests run the
// REAL install.sh with stub docker/git/curl and pin that each of the three
// Docker causes is refused FIRST (before curl or git ever run, before
// ~/statbus exists) with its own sentence, and that the Uganda line is gone.

const ugandaDenied = "permission denied while trying to connect to the docker API at unix:///var/run/docker.sock"

// installShPathWithout builds a PATH directory that mirrors the caller's PATH
// but omits the named commands, so a test can make docker genuinely absent
// even on a CI runner that has /usr/bin/docker.
func installShPathWithout(t *testing.T, omit ...string) string {
	t.Helper()
	dir := t.TempDir()
	skip := map[string]bool{}
	for _, name := range omit {
		skip[name] = true
	}
	for _, p := range filepath.SplitList(os.Getenv("PATH")) {
		entries, err := os.ReadDir(p)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if skip[e.Name()] {
				continue
			}
			link := filepath.Join(dir, e.Name())
			if _, err := os.Lstat(link); err == nil {
				continue
			}
			_ = os.Symlink(filepath.Join(p, e.Name()), link)
		}
	}
	return dir
}

type dockerPreflightRun struct {
	output   string
	exitCode int
	home     string
	trace    string
}

// runInstallShWithDocker runs install.sh end to end. dockerScript == "" means
// no docker on PATH at all. git and curl are stubs that record any call.
func runInstallShWithDocker(t *testing.T, dockerScript string) dockerPreflightRun {
	t.Helper()
	home := t.TempDir()
	stubs := t.TempDir()
	trace := filepath.Join(t.TempDir(), "trace")
	for _, name := range []string{"git", "curl"} {
		body := "#!/bin/sh\necho \"" + name + " $*\" >> \"$STATBUS_TEST_TRACE\"\nexit 1\n"
		if err := os.WriteFile(filepath.Join(stubs, name), []byte(body), 0o700); err != nil {
			t.Fatal(err)
		}
	}
	if dockerScript != "" {
		if err := os.WriteFile(filepath.Join(stubs, "docker"), []byte("#!/bin/sh\necho \"docker $*\" >> \"$STATBUS_TEST_TRACE\"\n"+dockerScript), 0o700); err != nil {
			t.Fatal(err)
		}
	}
	base := installShPathWithout(t, "docker", "git", "curl")
	cmd := exec.Command("bash", thisRepoFile(t, "install.sh"))
	cmd.Dir = home
	cmd.Env = []string{
		"HOME=" + home,
		"PATH=" + stubs + string(os.PathListSeparator) + base,
		"STATBUS_TEST_TRACE=" + trace,
	}
	out, err := cmd.CombinedOutput()
	code := 0
	if exitErr, ok := err.(*exec.ExitError); ok {
		code = exitErr.ExitCode()
	} else if err != nil {
		t.Fatal(err)
	}
	return dockerPreflightRun{output: string(out), exitCode: code, home: home, trace: trace}
}

func installUserName(t *testing.T) string {
	t.Helper()
	u, err := user.Current()
	if err != nil {
		t.Fatal(err)
	}
	return u.Username
}

const publicRerun = "curl -fsSL https://statbus.org/install.sh | bash"

func TestInstallShRefusesEachDockerCauseBeforeAnyWork(t *testing.T) {
	for _, tc := range []struct {
		name   string
		docker string
		want   string
	}{
		{"docker absent", "", diskpolicy.DockerAbsentRefusal(publicRerun)},
		{"daemon stopped", "echo 'Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?' >&2\nexit 1\n", diskpolicy.DockerStoppedRefusal(publicRerun)},
		{"user not permitted (Uganda)", "echo '" + ugandaDenied + "' >&2\nexit 1\n", diskpolicy.DockerDeniedRefusal(installUserName(t), ugandaDenied, publicRerun)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			run := runInstallShWithDocker(t, tc.docker)
			if run.exitCode == 0 {
				t.Fatalf("install.sh succeeded without a usable Docker:\n%s", run.output)
			}
			lines := strings.Split(strings.TrimRight(run.output, "\n"), "\n")
			found := false
			for _, line := range lines {
				if line == tc.want {
					found = true
				}
			}
			if !found {
				t.Errorf("install.sh did not print the exact Docker sentence\n  want: %s\n  got:\n%s", tc.want, run.output)
			}
			for _, banned := range []string{"Docker root unavailable", "is required but not installed", "install.sh FAILED at line"} {
				if strings.Contains(run.output, banned) {
					t.Errorf("output still carries %q:\n%s", banned, run.output)
				}
			}
			trace, _ := os.ReadFile(run.trace)
			for _, line := range strings.Split(string(trace), "\n") {
				if strings.HasPrefix(line, "git ") || strings.HasPrefix(line, "curl ") {
					t.Errorf("work started before the Docker refusal: %q", line)
				}
			}
			if _, err := os.Stat(filepath.Join(run.home, "statbus")); err == nil {
				t.Error("~/statbus was created before the Docker refusal")
			}
		})
	}
}

// A working Docker passes the preflight: install.sh goes on to its next step
// (resolving the release with curl), so the check is not a blanket refusal.
func TestInstallShDockerPreflightLetsAWorkingDockerThrough(t *testing.T) {
	run := runInstallShWithDocker(t, "echo /var/lib/docker\nexit 0\n")
	trace, _ := os.ReadFile(run.trace)
	if !strings.Contains(string(trace), "curl ") {
		t.Fatalf("a working Docker did not reach the release lookup:\n%s\ntrace:\n%s", run.output, trace)
	}
	if strings.Contains(run.output, "Docker") && strings.Contains(run.output, "run the same install command again") {
		t.Fatalf("a working Docker was refused:\n%s", run.output)
	}
}

// When ./sb install itself meets a Docker cause (e.g. a rescue rerun where
// the shell preflight passed but the group was then removed), its sentence
// must cross install.sh's exit-78 boundary verbatim and FULL-LINE anchored,
// and nothing may trail it.
func TestExit78AllowlistCarriesDockerSentences(t *testing.T) {
	const rerun = "curl -fsSL https://statbus.org/install.sh | bash -s --version v2026.10.0"
	dir := t.TempDir()
	for name, line := range map[string]string{
		"absent":  diskpolicy.DockerAbsentRefusal(rerun),
		"stopped": diskpolicy.DockerStoppedRefusal(rerun),
		"denied":  diskpolicy.DockerDeniedRefusal("statbus", ugandaDenied, rerun),
	} {
		t.Run(name, func(t *testing.T) {
			got := installShFailureTailIn(t, dir, rerun, line+"\n", 78)
			if !strings.Contains(got, line) {
				t.Errorf("Docker sentence did not cross the boundary:\n  sentence: %s\n  output:   %s", line, got)
			}
			if strings.Contains(got, "Correct the settings") {
				t.Errorf("Docker sentence fell through to the generic settings refusal:\n%s", got)
			}
			trailing := installShFailureTailIn(t, dir, rerun, line+" ; rm -rf /\n", 78)
			if strings.Contains(trailing, "rm -rf") {
				t.Errorf("arbitrary text trailed the Docker sentence across the boundary:\n%s", trailing)
			}
		})
	}
}
