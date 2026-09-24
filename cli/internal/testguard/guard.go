// Package testguard prevents CLI unit tests from reaching the developer's live services.
package testguard

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Install shadows direct exec.Command calls that bypass the central command
// constructors. Tests may replace PATH with their own fake executable directory.
// The shell sentinel never delegates to a real service executable.
func Install() (func(), error) {
	dir, err := os.MkdirTemp("", "statbus-cli-command-guard-")
	if err != nil {
		return nil, err
	}
	for _, name := range []string{"docker", "psql", "pg_dump", "pg_restore", "systemctl"} {
		body := "#!/bin/sh\nprintf '%s\\n' 'unit test safety guard: refusing real " + name + "; inject a fake command runner' >&2\nexit 97\n"
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0700); err != nil {
			_ = os.RemoveAll(dir)
			return nil, err
		}
	}
	previous := os.Getenv("PATH")
	if err := os.Setenv("PATH", dir+string(os.PathListSeparator)+previous); err != nil {
		_ = os.RemoveAll(dir)
		return nil, err
	}
	return func() { _ = os.Setenv("PATH", previous); _ = os.RemoveAll(dir) }, nil
}

// Check refuses external service commands from a Go test process unless their
// executable is a fixture under the OS temporary directory. A fake docker or
// psql placed on PATH by a test is permitted, but the host binary is not.
// Check is deliberately active for every package's .test binary, even if its
// TestMain forgot to set the sentinel.
func Check(name, resolvedPath string) error {
	if name == "docker" && IsolatedDockerInvocation() {
		return nil
	}
	if liveDatabaseFixtureInvocation() {
		return nil
	}
	if os.Getenv("STATBUS_CLI_UNIT_TEST_GUARD") != "1" && !strings.HasSuffix(filepath.Base(os.Args[0]), ".test") {
		return nil
	}
	switch name {
	case "docker", "psql", "pg_dump", "pg_restore", "systemctl":
	default:
		return nil
	}
	path, err := filepath.EvalSymlinks(resolvedPath)
	if err != nil {
		path = resolvedPath
	}
	tmp, err := filepath.EvalSymlinks(os.TempDir())
	if err != nil {
		tmp = os.TempDir()
	}
	if filepath.IsAbs(path) && strings.HasPrefix(path, tmp+string(os.PathSeparator)) {
		return nil
	}
	return fmt.Errorf("unit test safety guard: refusing real %s (%s); inject a command runner in a temporary project directory", name, resolvedPath)
}

// Live DB tests created by livedbtest.Setup operate on a detached temporary
// worktree and dedicated database. The ordinary unit suite has none of these
// fixture handles; a lone livedb build tag or environment opt-in is insufficient.
func liveDatabaseFixtureInvocation() bool {
	if os.Getenv("STATBUS_LIVEDB_TEST_TIER") != "1" {
		return false
	}
	project := os.Getenv("STATBUS_LIVEDB_PROJECT_DIR")
	pinned := os.Getenv("STATBUS_LIVEDB_PINNED_SB")
	if project == "" || pinned == "" {
		return false
	}
	realProject, err := filepath.EvalSymlinks(project)
	if err != nil {
		return false
	}
	tmp, err := filepath.EvalSymlinks(os.TempDir())
	if err != nil || !strings.HasPrefix(realProject, tmp+string(os.PathSeparator)+"statbus-livedb-") {
		return false
	}
	if pinned != filepath.Join(filepath.Dir(project), "pinned-sb") {
		return false
	}
	if _, err := os.Stat(filepath.Join(project, ".statbus")); err != nil {
		return false
	}
	_, err = os.Stat(pinned)
	return err == nil
}

// IsolatedDockerInvocation authorizes only the explicitly selected Docker
// probes, in a temporary Compose project provisioned by dev.sh test-livedb.
// Neither the ordinary .test suffix nor a single opt-in variable suffices.
func IsolatedDockerInvocation() bool {
	if os.Getenv("STATBUS_LIVE_DB_TEST") != "1" {
		return false
	}
	dir := os.Getenv("STATBUS_LIVEDOCKER_PROJECT_DIR")
	name := os.Getenv("COMPOSE_PROJECT_NAME")
	if name == "" || !strings.HasPrefix(name, "statbus-livedocker-") || dir == "" {
		return false
	}
	realDir, err := filepath.EvalSymlinks(dir)
	if err != nil {
		return false
	}
	tmp, err := filepath.EvalSymlinks(os.TempDir())
	if err != nil || !strings.HasPrefix(realDir, tmp+string(os.PathSeparator)) {
		return false
	}
	marker, err := os.ReadFile(filepath.Join(realDir, ".statbus-livedocker"))
	return err == nil && strings.TrimSpace(string(marker)) == name
}
