package cmd

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestInstallFailureCauseOperatorTextContainsNoInternalDiagnostics(t *testing.T) {
	forbidden := installOperatorForbiddenDiagnostics(t)
	check := func(name, cause, fix string) {
		t.Helper()
		for field, text := range map[string]string{"cause": cause, "outside fix": fix} {
			if forbidden.MatchString(text) {
				t.Errorf("%s %s contains internal diagnostics: %q", name, field, text)
			}
		}
	}
	for i, entry := range installFailureCauses {
		if entry.pattern == failedPublishedPort {
			// Dynamic port guidance is produced by a separate formatter.
			check(fmt.Sprintf("entry %d (port)", i), servicePortConflictCause(errors.New("port 80 is in use")), entry.fix)
			continue
		}
		check(fmt.Sprintf("entry %d", i), entry.cause, entry.fix)
	}
	cause, fix := classifyInstallFailure("Configuration", errors.New("INVARIANT pgx secret=123"))
	check("unknown fallback", cause, fix)
}

func TestClassifyInstallFailure(t *testing.T) {
	cases := []struct{ name, step, diagnostic, cause, fix string }{
		{"port", "Services", "Error response from daemon: could not publish host port 80/tcp: bind: address already in use", "port 80 is in use by", ""},
		{"disk", "Seed", "write /var/lib/docker/overlay2: no space left on device", "The disk ran out of free space.", "Free space on the installation disk"},
		{"daemon", "Services", "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?", "Docker is not running.", "Start Docker"},
		{"socket", "Services", "permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock", "The installer cannot access Docker.", "Give this user access"},
		{"image registry", "Images", "failed to resolve reference ghcr.io/statisticsnorway/statbus:latest: lookup ghcr.io: no such host", "A required image could not be downloaded.", "Check registry access"},
		{"image auth", "Images", "pull access denied for ghcr.io/statisticsnorway/statbus, repository does not exist", "A required image could not be downloaded.", "Check registry access"},
		{"image fallback", "Images", "image pull failure and local build failure: exit status 1", "A required image could not be downloaded.", "Check registry access"},
		{"database health", "Services", "the database (db) is not healthy; the upgrade service cannot reach it: context deadline exceeded", "The database did not become reachable after it started.", "Check Docker and database service health"},
		{"database start", "Services", "the database did not become ready within 3m0s", "The database did not become reachable after it started.", "Check Docker and database service health"},
		{"database password", "Services", "could not make the database passwords match .env.credentials: pq: password authentication failed for user statbus", "The database rejected its password.", "Check the saved database credentials"},
		{"systemd", "Upgrade service", "systemctl --user daemon-reload: Failed to connect to bus: No medium found", "The user service manager is unavailable.", "Enable linger"},
		{"git", "Source", "git fetch origin abc failed: fatal: unable to access https://github.com: Could not resolve host", "The source update could not be fetched.", "Check network access"},
		{"signature", "Trusted signers", "verify commit signature: gpg: BAD signature from unknown key", "The release signature could not be verified.", "Verify the release signer"},
		{"signer approval", "Trusted signers", "No valid release signer is configured", "The release signature could not be verified.", "Verify the release signer"},
		{"unknown", "Configuration", "INVARIANT pgx secret=123", "The configuration step could not finish; the details are in the support file.", ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			cause, fix := classifyInstallFailure(tc.step, errors.New(tc.diagnostic))
			if !strings.Contains(cause, tc.cause) || !strings.Contains(fix, tc.fix) {
				t.Fatalf("cause=%q fix=%q", cause, fix)
			}
			if strings.Contains(cause, "secret=123") || strings.Contains(fix, "secret=123") {
				t.Fatal("unclassified error leaked")
			}
		})
	}
}

// Keep the actual grep ERE used by the standalone bootstrap in sync with Go's
// operator-facing sentences. grep, rather than Go regexp, checks POSIX ERE
// backreferences as they are interpreted by install.sh on the target host.
func TestInstallCauseAndFixMatchShellAllowlist(t *testing.T) {
	bootstrap, err := os.ReadFile("../../install.sh")
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(string(bootstrap), "\n")
	patternAfter := func(marker, prefix string) string {
		t.Helper()
		for i, line := range lines {
			if !strings.Contains(line, marker) {
				continue
			}
			if i+1 >= len(lines) || !strings.Contains(lines[i+1], prefix) {
				t.Fatalf("%s not followed by shell grep", marker)
			}
			line = strings.TrimSpace(lines[i+1])
			start := strings.Index(line, "grep -E '")
			end := strings.LastIndex(line, "' \"$install_output\"")
			if start < 0 || end <= start {
				t.Fatalf("cannot extract ERE after %s: %q", marker, line)
			}
			return strings.ReplaceAll(line[start+len("grep -E '"):end], `'"'"'`, "'")
		}
		t.Fatalf("missing marker %s", marker)
		return ""
	}
	causePattern := patternAfter("INSTALL_CAUSE_ALLOWLIST:", "failure_detail=$(grep -E")
	// The fix grep is adjacent to the cause grep. Extract its actual ERE too.
	fixPattern := ""
	for _, line := range lines {
		if strings.Contains(line, "failure_fix=$(grep -E '") {
			start := strings.Index(line, "grep -E '") + len("grep -E '")
			end := strings.LastIndex(line, "' \"$install_output\"")
			if end <= start {
				t.Fatalf("cannot extract fix ERE: %q", line)
			}
			fixPattern = line[start:end]
			break
		}
	}
	if fixPattern == "" {
		t.Fatal("missing INSTALL_FIX grep")
	}
	match := func(pattern, value string) bool {
		t.Helper()
		cmd := exec.Command("grep", "-E", "-q", pattern)
		cmd.Stdin = strings.NewReader(value + "\n")
		return cmd.Run() == nil
	}
	check := func(cause, fix string) {
		t.Helper()
		if !match(causePattern, "INSTALL_CAUSE: "+cause) {
			t.Errorf("cause not permitted by install.sh: %q", cause)
		}
		if fix != "" && !match(fixPattern, "INSTALL_FIX: "+fix) {
			t.Errorf("fix not permitted by install.sh: %q", fix)
		}
	}
	for _, entry := range installFailureCauses {
		if entry.pattern != failedPublishedPort {
			check(entry.cause, entry.fix)
		}
	}
	for _, host := range []string{"127.0.0.1", "localhost", "[::1]"} {
		cause, fix := classifyInstallFailure("Upgrade service", errors.New("dial tcp "+host+":5431: connect: connection refused"))
		check(cause, fix)
	}
	cause, fix := classifyInstallFailure("Upgrade service", errors.New("unrecognized failure"))
	check(cause, fix)
	unitDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(unitDir, "systemctl"), []byte("#!/bin/sh\nif [ \"$2\" = apache2.service ]; then echo loaded; else echo not-found; fi\n"), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", unitDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	for _, owner := range []string{"apache2", "python3", "another program", "unexpected text secret=foo", "bad.name"} {
		check(portConflictGuidance(80, owner), "")
	}
	oldOwner := occupiedPortOwner
	t.Cleanup(func() { occupiedPortOwner = oldOwner })
	occupiedPortOwner = func(installPort) string { return "apache2" }
	cause, fix = classifyInstallFailure("Services", errors.New("could not publish host port 443/tcp"))
	check(cause, fix)
}

func TestInstallCommandDiagnosticFeedsClassifier(t *testing.T) {
	err := runInstallCommandWithDiagnostic(exec.Command("sh", "-c", "echo 'Cannot connect to the Docker daemon at unix:///var/run/docker.sock' >&2; exit 1"))
	if err == nil {
		t.Fatal("command unexpectedly succeeded")
	}
	cause, fix := classifyInstallFailure("Services", err)
	if cause != "Docker is not running." || !strings.Contains(fix, "Start Docker") {
		t.Fatalf("cause=%q fix=%q", cause, fix)
	}
}

func TestInstallDiagnosticCaptureKeepsRecentFailure(t *testing.T) {
	capture := &installDiagnosticCapture{}
	_, _ = capture.Write([]byte(strings.Repeat("x", 70000)))
	_, _ = capture.Write([]byte("no space left on device"))
	if len(capture.text) != 65536 || !strings.HasSuffix(string(capture.text), "no space left on device") {
		t.Fatal("verbose progress displaced the underlying failure")
	}
}
