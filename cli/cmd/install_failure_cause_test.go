package cmd

import (
	"errors"
	"fmt"
	"os/exec"
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
