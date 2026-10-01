package hostrepair

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestWritableProbe(t *testing.T) {
	dir := t.TempDir()
	if !Writable(dir) {
		t.Fatalf("Writable(%s) = false on a fresh writable temp dir", dir)
	}
	if Writable(filepath.Join(dir, "missing")) {
		t.Fatal("Writable() = true on a missing directory")
	}
	if os.Getuid() == 0 {
		t.Skip("root ignores directory permission bits; cannot force EACCES")
	}
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
	if Writable(dir) {
		t.Fatal("Writable() = true on a read-only directory")
	}
}

func TestPreferredProxyImage(t *testing.T) {
	projDir := t.TempDir()
	if got := PreferredProxyImage(projDir); got != "" {
		t.Errorf("PreferredProxyImage() with no .env = %q, want empty", got)
	}
	if err := os.WriteFile(filepath.Join(projDir, ".env"), []byte("OTHER=1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if got := PreferredProxyImage(projDir); got != "" {
		t.Errorf("PreferredProxyImage() with no COMMIT_SHORT = %q, want empty", got)
	}
	if err := os.WriteFile(filepath.Join(projDir, ".env"), []byte("COMMIT_SHORT=deadbeef\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	want := "ghcr.io/statisticsnorway/statbus-proxy:deadbeef"
	if got := PreferredProxyImage(projDir); got != want {
		t.Errorf("PreferredProxyImage() = %q, want %q", got, want)
	}
}

// installFakeDocker puts a fake `docker` on PATH that records every
// invocation's argv to argvLog and runs effectScript against the mounted
// parent directory. failImages makes matching invocations exit 125.
func installFakeDocker(t *testing.T, argvLog string, failImages []string, effectScript string) {
	t.Helper()
	bin := t.TempDir()
	var fails strings.Builder
	for _, img := range failImages {
		fmt.Fprintf(&fails, "  *%s*) echo 'fake docker: no such image' >&2; exit 125 ;;\n", img)
	}
	script := fmt.Sprintf(`#!/bin/sh
printf '%%s\n' "$*" >> %s
case "$*" in
%s  *)
%s
    exit 0
    ;;
esac
`, "'"+argvLog+"'", fails.String(), effectScript)
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
}

func readArgvLog(t *testing.T, argvLog string) []string {
	t.Helper()
	raw, err := os.ReadFile(argvLog)
	if err != nil {
		t.Fatalf("fake docker was not invoked: %v", err)
	}
	return strings.Split(strings.TrimSpace(string(raw)), "\n")
}

// TestEnsureWritableRepairsUnwritableDir covers the STATBUS-431 shape: the
// directory's parent exists but is not writable by this user (as when Docker
// created ~/statbus-maintenance as root), the repair runs through the box's
// proxy image with --pull=never, and the post-repair probe observes the fix.
func TestEnsureWritableRepairsUnwritableDir(t *testing.T) {
	if os.Getuid() == 0 {
		t.Skip("root ignores directory permission bits; cannot force EACCES")
	}
	projDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(projDir, ".env"), []byte("COMMIT_SHORT=deadbeef\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	home := t.TempDir()
	parent := home
	target := filepath.Join(home, "statbus-maintenance")
	if err := os.Chmod(parent, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(parent, 0o755) })

	argvLog := filepath.Join(t.TempDir(), "docker-argv.txt")
	// The fake performs what a real root container would: open up the parent
	// (root bypasses the owner-write check this test process is subject to),
	// then create and open up the target, exactly as the repair shell command.
	effect := fmt.Sprintf("chmod 0755 '%s' 2>/dev/null || true\n    mkdir -p '%s'\n    chmod 0755 '%s'", parent, target, target)
	installFakeDocker(t, argvLog, nil, effect)

	if err := EnsureWritable(projDir, target); err != nil {
		t.Fatalf("EnsureWritable: %v", err)
	}
	lines := readArgvLog(t, argvLog)
	if len(lines) != 1 {
		t.Fatalf("expected exactly 1 docker invocation (proxy image present); got %d:\n%s", len(lines), lines)
	}
	argv := lines[0]
	wantPrefix := "run --rm --network none --pull=never -v " + parent + ":/data ghcr.io/statisticsnorway/statbus-proxy:deadbeef sh -c mkdir -p /data/statbus-maintenance && chmod u+rwx /data/statbus-maintenance && chown "
	if !strings.HasPrefix(argv, wantPrefix) {
		t.Errorf("docker argv = %q, want prefix %q", argv, wantPrefix)
	}
	if strings.Contains(argv, "-R") || strings.Contains(argv, "statbus-backups") {
		t.Errorf("repair must never be recursive or touch siblings: %q", argv)
	}
	if !Writable(target) {
		t.Fatal("target still not writable after the repair")
	}
}

// TestEnsureWritableFallsBackToAlpine: when the proxy image is unavailable
// locally, the repair must still succeed via the pinned alpine fallback,
// which is pulled if needed (no --pull=never).
func TestEnsureWritableFallsBackToAlpine(t *testing.T) {
	if os.Getuid() == 0 {
		t.Skip("root ignores directory permission bits; cannot force EACCES")
	}
	projDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(projDir, ".env"), []byte("COMMIT_SHORT=deadbeef\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	home := t.TempDir()
	target := filepath.Join(home, "statbus-backups")
	if err := os.Chmod(home, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(home, 0o755) })

	argvLog := filepath.Join(t.TempDir(), "docker-argv.txt")
	effect := fmt.Sprintf("chmod 0755 '%s' 2>/dev/null || true\n    mkdir -p '%s'\n    chmod 0755 '%s'", home, target, target)
	installFakeDocker(t, argvLog, []string{"statbus-proxy:deadbeef"}, effect)

	if err := EnsureWritable(projDir, target); err != nil {
		t.Fatalf("expected the alpine fallback to succeed: %v", err)
	}
	lines := readArgvLog(t, argvLog)
	if len(lines) != 2 {
		t.Fatalf("expected exactly 2 docker invocations (proxy attempt then alpine fallback); got %d:\n%s", len(lines), lines)
	}
	if !strings.Contains(lines[0], "statbus-proxy:deadbeef") || !strings.Contains(lines[0], "--pull=never") {
		t.Errorf("first invocation must be the proxy image with --pull=never; got %q", lines[0])
	}
	if !strings.Contains(lines[1], FallbackImage) || strings.Contains(lines[1], "--pull=never") {
		t.Errorf("second invocation must be the alpine fallback without --pull=never; got %q", lines[1])
	}
}

// TestEnsureWritableRepairFailureIsLoud: when the repair container cannot
// run at all, the error is a *NotWritableError with the plain administrator
// remedy, never a bare "exit status N".
func TestEnsureWritableRepairFailureIsLoud(t *testing.T) {
	if os.Getuid() == 0 {
		t.Skip("root ignores directory permission bits; cannot force EACCES")
	}
	projDir := t.TempDir() // no .env: straight to the alpine fallback
	home := t.TempDir()
	target := filepath.Join(home, "statbus-maintenance")
	if err := os.Chmod(home, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(home, 0o755) })

	argvLog := filepath.Join(t.TempDir(), "docker-argv.txt")
	installFakeDocker(t, argvLog, []string{FallbackImage}, "exit 1")

	err := EnsureWritable(projDir, target)
	var nw *NotWritableError
	if !errors.As(err, &nw) {
		t.Fatalf("EnsureWritable error = %v (%T), want *NotWritableError", err, err)
	}
	msg := err.Error()
	for _, want := range []string{"is not writable by this user", "sudo install -d", target, "Docker could not run the repair container"} {
		if !strings.Contains(msg, want) {
			t.Errorf("error message missing %q:\n%s", want, msg)
		}
	}
}

// TestEnsureWritableStillUnwritableAfterRepair: a repair container that exits
// 0 but leaves the directory unwritable must not be reported as success
// (STATBUS-429 R-b re-probe).
func TestEnsureWritableStillUnwritableAfterRepair(t *testing.T) {
	if os.Getuid() == 0 {
		t.Skip("root ignores directory permission bits; cannot force EACCES")
	}
	projDir := t.TempDir()
	home := t.TempDir()
	target := filepath.Join(home, "statbus-maintenance")
	if err := os.MkdirAll(target, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(target, 0o755) })

	argvLog := filepath.Join(t.TempDir(), "docker-argv.txt")
	installFakeDocker(t, argvLog, nil, "true") // exits 0, changes nothing

	err := EnsureWritable(projDir, target)
	var nw *NotWritableError
	if !errors.As(err, &nw) {
		t.Fatalf("EnsureWritable error = %v (%T), want *NotWritableError", err, err)
	}
	if !strings.Contains(err.Error(), "the repair ran but the directory is still not writable") {
		t.Errorf("error should name the still-unwritable outcome: %v", err)
	}
}

// TestEnsureWritableFreshDirNeedsNoDocker: on a healthy path (directory
// creatable by this user) no container ever runs.
func TestEnsureWritableFreshDirNeedsNoDocker(t *testing.T) {
	projDir := t.TempDir()
	home := t.TempDir()
	target := filepath.Join(home, "statbus-maintenance")

	marker := filepath.Join(t.TempDir(), "docker-invoked")
	bin := t.TempDir()
	script := fmt.Sprintf("#!/bin/sh\ntouch '%s'\nexit 1\n", marker)
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))

	if err := EnsureWritable(projDir, target); err != nil {
		t.Fatalf("EnsureWritable on a fresh path: %v", err)
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatal("docker was invoked on the fresh-creation path")
	}
	if !Writable(target) {
		t.Fatal("fresh directory is not writable after EnsureWritable")
	}
}

// TestShellWord: product constants stay bare (pinned argv compatibility),
// unsafe names are single-quoted.
func TestShellWord(t *testing.T) {
	for _, safe := range []string{"statbus-maintenance", "statbus-backups", "custom-certs", "a.b_c-1"} {
		if got := shellWord(safe); got != safe {
			t.Errorf("shellWord(%q) = %q, want bare", safe, got)
		}
	}
	if got := shellWord("a b"); got != "'a b'" {
		t.Errorf("shellWord with space = %q, want single-quoted", got)
	}
	if got := shellWord("a'b"); got != `'a'\''b'` {
		t.Errorf("shellWord with quote = %q, want escaped", got)
	}
	if got := shellWord("$(rm -rf /)"); got != "'$(rm -rf /)'" {
		t.Errorf("shellWord with substitution = %q, want single-quoted", got)
	}
}
