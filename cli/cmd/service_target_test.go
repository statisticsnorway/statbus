package cmd

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// STATBUS-564: ./sb stop <service> used to run `docker compose --profile
// <service> down`, which matches no service and exits 0. start and restart had
// the same profile-only assumption. These tests run the real command entry
// points against a docker double on PATH that records its argv and, like
// docker, fails when it cannot find a compose subcommand.

// fakeDocker writes every invocation to a log file and rejects argv that the
// real docker would also reject (no compose subcommand).
type fakeDocker struct {
	binDir string
	log    string
}

func newFakeDocker(t *testing.T) *fakeDocker {
	t.Helper()
	dir := t.TempDir()
	logPath := filepath.Join(dir, "docker-argv.log")
	script := `#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_DOCKER_LOG"
if [ "$1" != "compose" ]; then
  echo "fake docker: unsupported command: $*" >&2
  exit 125
fi
shift
found=0
for a in "$@"; do
  case "$a" in
    down|up|stop|start|restart|ps|config|pull|logs) found=1; break;;
  esac
done
if [ "$found" = 0 ]; then
  echo "fake docker: no compose subcommand in: $*" >&2
  exit 125
fi
exit 0
`
	path := filepath.Join(dir, "docker")
	if err := os.WriteFile(path, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("FAKE_DOCKER_LOG", logPath)
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	return &fakeDocker{binDir: dir, log: logPath}
}

func (d *fakeDocker) calls(t *testing.T) []string {
	t.Helper()
	data, err := os.ReadFile(d.log)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		t.Fatal(err)
	}
	text := strings.TrimSpace(string(data))
	if text == "" {
		return nil
	}
	return strings.Split(text, "\n")
}

func inFakeProject(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".statbus"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	old, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(dir); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chdir(old) })
	return dir
}

func assertDockerCalls(t *testing.T, got, want []string) {
	t.Helper()
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("docker calls = %q, want %q", got, want)
	}
}

func assertUnknownTargetRefusal(t *testing.T, err error, name string) {
	t.Helper()
	if err == nil {
		t.Fatalf("%q was accepted; want a refusal", name)
	}
	for _, want := range []string{name, "all, all_except_app, app", "db, worker, rest, app, proxy"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("refusal %q does not name %q", err, want)
		}
	}
}

func TestStopServiceStopsOnlyThatService(t *testing.T) {
	docker := newFakeDocker(t)
	inFakeProject(t)

	if err := stopCmd.RunE(stopCmd, []string{"worker"}); err != nil {
		t.Fatal(err)
	}
	assertDockerCalls(t, docker.calls(t), []string{"compose stop worker"})
}

func TestStopProfileKeepsDownBehaviour(t *testing.T) {
	for _, tc := range []struct{ name, want string }{
		{"all", "compose --profile all down --remove-orphans"},
		{"all_except_app", "compose --profile all_except_app down --remove-orphans"},
		{"app", "compose down --remove-orphans app"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			docker := newFakeDocker(t)
			inFakeProject(t)
			if err := stopCmd.RunE(stopCmd, []string{tc.name}); err != nil {
				t.Fatal(err)
			}
			assertDockerCalls(t, docker.calls(t), []string{tc.want})
		})
	}
}

func TestStopUnknownTargetRefusesBeforeDocker(t *testing.T) {
	docker := newFakeDocker(t)
	inFakeProject(t)

	err := stopCmd.RunE(stopCmd, []string{"bogus"})
	assertUnknownTargetRefusal(t, err, "bogus")
	if calls := docker.calls(t); len(calls) != 0 {
		t.Fatalf("docker ran %q for an unknown target; want no docker command", calls)
	}
}

func TestStartServiceStartsOnlyThatService(t *testing.T) {
	docker := newFakeDocker(t)
	inFakeProject(t)

	// The test binary is a source build, so start adds --build.
	if err := startCmd.RunE(startCmd, []string{"worker"}); err != nil {
		t.Fatal(err)
	}
	assertDockerCalls(t, docker.calls(t), []string{"compose up -d --build worker"})
}

func TestStartUnknownTargetRefusesBeforeDocker(t *testing.T) {
	docker := newFakeDocker(t)
	inFakeProject(t)

	err := startCmd.RunE(startCmd, []string{"bogus"})
	assertUnknownTargetRefusal(t, err, "bogus")
	if calls := docker.calls(t); len(calls) != 0 {
		t.Fatalf("docker ran %q for an unknown target; want no docker command", calls)
	}
}

func TestRestartServiceUsesServiceArgs(t *testing.T) {
	// The up side follows the same target rules as start: a service is named
	// directly and never behind --profile.
	for _, tc := range []struct{ target, want string }{
		{"worker", "-d --wait --wait-timeout 120 --build worker"},
		{"proxy", "-d --wait --wait-timeout 120 --build proxy"},
		{"all", "--profile all -d --wait --wait-timeout 120 --build"},
	} {
		t.Run(tc.target, func(t *testing.T) {
			var out bytes.Buffer
			args, err := restartUpArgs(t.TempDir(), tc.target, false, "dev", &fakeDockerImageOps{}, &out)
			if err != nil {
				t.Fatal(err)
			}
			if got := strings.Join(args, " "); got != tc.want {
				t.Fatalf("restart up args = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestRestartUnknownTargetRefusesBeforeAnyWork(t *testing.T) {
	dir := t.TempDir()
	ops := restartOperations{unit: "unit", systemctl: func(...string) (string, error) {
		t.Fatal("systemctl reached for an unknown restart target")
		return "", nil
	}, stack: func(string) error {
		t.Fatal("stack reached for an unknown restart target")
		return nil
	}}
	err := restartServicesWith(dir, "bogus", ops)
	assertUnknownTargetRefusal(t, err, "bogus")
}

func TestServiceCommandsDocumentAcceptedTargets(t *testing.T) {
	for _, cmd := range []struct {
		name string
		long string
	}{{"start", startCmd.Long}, {"stop", stopCmd.Long}, {"restart", restartCmd.Long}} {
		for _, want := range []string{"Profiles: all, all_except_app, app", "Services: db, worker, rest, app, proxy"} {
			if !strings.Contains(cmd.long, want) {
				t.Errorf("%s help does not contain %q", cmd.name, want)
			}
		}
	}
}
