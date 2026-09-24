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
