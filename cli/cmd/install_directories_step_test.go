package cmd

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// TestCheckDirectoriesDone covers the outcome-based done-check's truth table
// (STATBUS-431): only "exists AND a directory AND owned AND writable" is done.
func TestCheckDirectoriesDone(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	if checkDirectoriesDone("") {
		t.Fatal("done with both directories missing")
	}
	if err := os.MkdirAll(filepath.Join(home, "statbus-maintenance"), 0o755); err != nil {
		t.Fatal(err)
	}
	if checkDirectoriesDone("") {
		t.Fatal("done with statbus-backups missing")
	}
	if err := os.MkdirAll(filepath.Join(home, "statbus-backups"), 0o755); err != nil {
		t.Fatal(err)
	}
	if !checkDirectoriesDone("") {
		t.Fatal("not done with both directories present, owned and writable")
	}

	// A file where a directory belongs is not done.
	if err := os.RemoveAll(filepath.Join(home, "statbus-backups")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, "statbus-backups"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if checkDirectoriesDone("") {
		t.Fatal("done with statbus-backups as a regular file")
	}
	if err := os.Remove(filepath.Join(home, "statbus-backups")); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(home, "statbus-backups"), 0o755); err != nil {
		t.Fatal(err)
	}

	if os.Getuid() == 0 {
		t.Skip("root ignores directory permission bits; cannot force the unwritable case")
	}
	if err := os.Chmod(filepath.Join(home, "statbus-maintenance"), 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(filepath.Join(home, "statbus-maintenance"), 0o755) })
	if checkDirectoriesDone("") {
		t.Fatal("done with statbus-maintenance present but not writable")
	}
}

// TestRunEnsureDirectoriesCreatesBoth covers the fresh-install path: both
// directories appear, owned by this user, writable — and the step's own check
// then reports done. No container runs on this path (hostrepair's own tests
// pin the no-docker-on-fresh-path guarantee).
func TestRunEnsureDirectoriesCreatesBoth(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	if err := runEnsureDirectories(t.TempDir()); err != nil {
		t.Fatalf("runEnsureDirectories: %v", err)
	}
	for _, name := range installerManagedHomeDirs {
		info, err := os.Stat(filepath.Join(home, name))
		if err != nil || !info.IsDir() {
			t.Fatalf("%s not created: %v", name, err)
		}
	}
	if !checkDirectoriesDone("") {
		t.Fatal("checkDirectoriesDone false after runEnsureDirectories")
	}
	// Idempotent: a second run on the now-existing directories is a no-op.
	if err := runEnsureDirectories(t.TempDir()); err != nil {
		t.Fatalf("runEnsureDirectories second run: %v", err)
	}
}

// TestRunGenerateEnvHasNoDirectorySideEffect is the STATBUS-431 structural
// pin: runGenerateEnv (the Settings step) must never again create the managed
// home directories, because its done-check (generated files match) is
// satisfied by the Credentials step on every fresh install — side effects
// riding on it are silently skipped.
func TestRunGenerateEnvHasNoDirectorySideEffect(t *testing.T) {
	source, err := os.ReadFile("install.go")
	if err != nil {
		t.Fatalf("read install.go: %v", err)
	}
	parts := strings.SplitN(string(source), "func runGenerateEnv(", 2)
	if len(parts) != 2 {
		t.Fatal("runGenerateEnv not found")
	}
	body := strings.SplitN(parts[1], "\nfunc ", 2)[0]
	for _, forbidden := range []string{"statbus-maintenance", "statbus-backups", "MkdirAll"} {
		if strings.Contains(body, forbidden) {
			t.Errorf("runGenerateEnv contains %q — directory creation belongs to the Directories step (STATBUS-431)", forbidden)
		}
	}
}

// TestDirectoriesStepPosition pins the Directories step between Credentials
// and Settings — before Images/Services, the first steps whose containers
// bind-mount the managed directories — in the install step table.
func TestDirectoriesStepPosition(t *testing.T) {
	source, err := os.ReadFile("install.go")
	if err != nil {
		t.Fatalf("read install.go: %v", err)
	}
	stepTable := strings.SplitN(string(source), "steps := []step{", 2)
	if len(stepTable) != 2 {
		t.Fatal("step table not found")
	}
	stepTable[1] = strings.SplitN(stepTable[1], "total := len(steps)", 2)[0]
	names := regexp.MustCompile(`(?m)^\s*\{"([A-Za-z +]+)",`).FindAllStringSubmatch(stepTable[1], -1)
	order := make([]string, 0, len(names))
	for _, m := range names {
		order = append(order, m[1])
	}
	indexOf := func(name string) int {
		for i, n := range order {
			if n == name {
				return i
			}
		}
		t.Fatalf("step %q not found in %v", name, order)
		return -1
	}
	directories := indexOf("Directories")
	if !(indexOf("Credentials") < directories && directories < indexOf("Settings")) {
		t.Errorf("Directories must sit between Credentials and Settings; order: %v", order)
	}
	if !(directories < indexOf("Services")) {
		t.Errorf("Directories must precede Services (first compose up); order: %v", order)
	}
}
