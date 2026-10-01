package cmd

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/install"
)

func TestFailedInstallWritesOneQuietRedactedRecordAndPlainRecoveryOutcome(t *testing.T) {
	const (
		credential = "fixture-password-403"
		rerun      = "curl -fsSL https://statbus.org/install.sh | bash -s -- --version v2026.09.3 --slot no"
	)

	for _, tc := range []struct {
		name        string
		state       install.State
		cause       string
		supportPath string
	}{
		{
			name:        "preflight failure",
			state:       install.StateNothingScheduled,
			cause:       "The custom certificate settings are invalid.",
			supportPath: "/srv/statbus/tmp/install-last-run-output.txt",
		},
		{
			name:        "step failure",
			state:       install.StateFreshDBIncomplete,
			cause:       "The services step could not finish; the details are in the support file.",
			supportPath: "/srv/statbus/support-bundle-20261001-175555.txt",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			installDir := t.TempDir()
			if err := os.WriteFile(filepath.Join(installDir, ".env.credentials"), []byte("POSTGRES_ADMIN_PASSWORD="+credential+"\n"), 0o600); err != nil {
				t.Fatal(err)
			}

			var log bytes.Buffer
			writeFailedInstallRecord(&log, installDir, tc.state, errors.New(tc.cause+" detail="+credential))
			record := log.String()
			if got := strings.Count(record, "install_failed_no_row:"); got != 1 {
				t.Fatalf("failed-install records = %d, want exactly one:\n%s", got, record)
			}
			if strings.Contains(record, credential) {
				t.Fatalf("failed-install record contains fixture credential:\n%s", record)
			}
			if !strings.Contains(record, tc.cause) {
				t.Fatalf("failed-install record missing plain cause %q:\n%s", tc.cause, record)
			}

			terminal := fmt.Sprintf("Installation failed: %s\nThen run: %s\nInstallation diagnostics: %s\n", tc.cause, rerun, tc.supportPath)
			for _, forbidden := range []string{"audit", "install_failed_no_row", credential} {
				if strings.Contains(strings.ToLower(terminal), strings.ToLower(forbidden)) {
					t.Fatalf("terminal output contains private/internal wording %q:\n%s", forbidden, terminal)
				}
			}
			for _, want := range []string{tc.cause, rerun, tc.supportPath} {
				if !strings.Contains(terminal, want) {
					t.Fatalf("terminal output missing %q:\n%s", want, terminal)
				}
			}
		})
	}
}
