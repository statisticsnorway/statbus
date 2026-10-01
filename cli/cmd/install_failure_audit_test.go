package cmd

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/install"
)

func TestFailedInstallWritesOneQuietFailClosedRecordAndRealRecoveryOutcome(t *testing.T) {
	const (
		credential = "postgres://admin:fixture-password-403@db/statbus"
		rerun      = "curl -fsSL https://statbus.org/install.sh | bash -s -- --version v2026.09.3 --slot no"
	)

	for _, tc := range []struct {
		name        string
		configure   func(t *testing.T, installDir string)
		wantClass   string
		wantCause   string
		wantSupport func(installDir string) string
	}{
		{
			name: "preflight failure",
			configure: func(t *testing.T, installDir string) {
				bundlePath := filepath.Join(installDir, "support-bundle-test.txt")
				detectInstallState = func(string, string) (install.State, *install.Detail, error) {
					return 0, nil, errors.New("probe command argument " + credential)
				}
				writeDetectionSupportBundle = func(string) (string, error) {
					if err := os.WriteFile(bundlePath, []byte("diagnostics"), 0o600); err != nil {
						t.Fatal(err)
					}
					return bundlePath, nil
				}
			},
			wantClass: "preflight",
			wantCause: "the install state could not be determined safely; nothing was changed",
			wantSupport: func(installDir string) string {
				return filepath.Join(installDir, "support-bundle-test.txt")
			},
		},
		{
			name: "step failure",
			configure: func(t *testing.T, _ string) {
				detectInstallState = func(string, string) (install.State, *install.Detail, error) {
					return install.StateFreshDBIncomplete, &install.Detail{}, nil
				}
				runInstallStepTableTestHook = func() error {
					return errors.New("failing command argument " + credential)
				}
			},
			wantClass: "step",
			wantCause: "The installation stopped before it could finish. Check the installation log, correct the problem",
			wantSupport: func(installDir string) string {
				return filepath.Join(installDir, "tmp", "install-last-run-output.txt")
			},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			installDir := withRunInstallDetectionHooks(t)
			t.Setenv("STATBUS_INSTALL_RERUN_COMMAND", rerun)
			// The record must remain safe even when the credential file needed for
			// value-based redaction is absent and the failing argument contains a URI.
			if err := os.Remove(filepath.Join(installDir, ".env.credentials")); err != nil && !os.IsNotExist(err) {
				t.Fatal(err)
			}
			tc.configure(t, installDir)

			err := runInstall()
			if err == nil {
				t.Fatal("runInstall unexpectedly succeeded")
			}
			var terminal bytes.Buffer
			reportInstallFailure(&terminal, err)

			logPath := filepath.Join(installDir, "tmp", "install-last-run-output.txt")
			logData, readErr := os.ReadFile(logPath)
			if readErr != nil {
				t.Fatalf("read production install log: %v", readErr)
			}
			logText := string(logData)
			if got := strings.Count(logText, "install_failed_no_row:"); got != 1 {
				t.Fatalf("failed-install records = %d, want exactly one:\n%s", got, logText)
			}
			if !strings.Contains(logText, "install_failed_no_row: class="+tc.wantClass) {
				t.Fatalf("record missing class %q:\n%s", tc.wantClass, logText)
			}
			var record string
			for _, line := range strings.Split(logText, "\n") {
				if strings.HasPrefix(line, "install_failed_no_row:") {
					record = line
				}
			}
			if strings.Contains(record, credential) {
				t.Fatalf("production failure record contains credential-shaped failing argument: %s", record)
			}

			terminalText := terminal.String()
			for _, forbidden := range []string{"audit", "install_failed_no_row", credential} {
				if strings.Contains(strings.ToLower(terminalText), strings.ToLower(forbidden)) {
					t.Fatalf("terminal contains private/internal wording %q:\n%s", forbidden, terminalText)
				}
			}
			for _, want := range []string{tc.wantCause, rerun, tc.wantSupport(installDir)} {
				if !strings.Contains(terminalText, want) {
					t.Fatalf("terminal missing %q:\n%s", want, terminalText)
				}
			}
		})
	}
}
