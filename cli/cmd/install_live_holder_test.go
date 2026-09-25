package cmd

import (
	"io"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

func TestLiveHolderRefusal(t *testing.T) {
	started := time.Date(2026, 9, 25, 7, 0, 0, 0, time.UTC)
	for _, tc := range []struct {
		name, holder, trigger, want, notWant string
	}{
		{"install", upgrade.HolderInstall, "install", "an installation started at 2026-09-25T07:00:00Z (process 4242) is still running", "lsof"},
		{"restart", upgrade.HolderInstall, "restart", "an installation started at 2026-09-25T07:00:00Z (process 4242) is still running", "lsof"},
		{"start guard", upgrade.HolderInstall, "start", "an installation started at 2026-09-25T07:00:00Z (process 4242) is still running", "lsof"},
		{"restore authorization", upgrade.HolderInstall, "install-cli", "an installation started at 2026-09-25T07:00:00Z (process 4242) is still running", "lsof"},
		{"rollback authorization", upgrade.HolderInstall, "recovery", "an installation started at 2026-09-25T07:00:00Z (process 4242) is still running", "lsof"},
		{"service", upgrade.HolderService, "scheduled", "upgrade in progress", "an installation started"},
		{"legacy install without PID", upgrade.HolderInstall, "install", "an installation started at", "(process 0)"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			pid := 4242
			if tc.name == "legacy install without PID" {
				pid = 0
			}
			detail := &install.Detail{Flag: &upgrade.UpgradeFlag{Holder: tc.holder, Trigger: tc.trigger, StartedAt: started, PID: pid}}
			handled, err := dispatchInstallState(t.TempDir(), install.StateLiveUpgrade, detail)
			if !handled || err == nil || !strings.Contains(err.Error(), tc.want) || strings.Contains(err.Error(), tc.notWant) {
				t.Fatalf("handled=%v err=%v, want %q but not %q", handled, err, tc.want, tc.notWant)
			}
			if strings.Contains(err.Error(), "lsof") {
				t.Fatalf("operator refusal contains an internal inspection command: %v", err)
			}
		})
	}
}

func TestLiveInstallStateLogNamesHolder(t *testing.T) {
	started := time.Date(2026, 9, 25, 7, 0, 0, 0, time.UTC)
	for _, tc := range []struct {
		name, holder, want string
	}{
		{"install", upgrade.HolderInstall, "an installation started at 2026-09-25T07:00:00Z (process 4242) is still running"},
		{"service", upgrade.HolderService, "An upgrade is already running. Wait for it to finish, then retry if needed."},
	} {
		t.Run(tc.name, func(t *testing.T) {
			reader, writer, err := os.Pipe()
			if err != nil {
				t.Fatal(err)
			}
			stdout := os.Stdout
			os.Stdout = writer
			defer func() { os.Stdout = stdout }()
			logInstallState(t.TempDir(), install.StateLiveUpgrade, &install.Detail{Flag: &upgrade.UpgradeFlag{
				Holder: tc.holder, PID: 4242, StartedAt: started,
			}})
			if err := writer.Close(); err != nil {
				t.Fatal(err)
			}
			output, err := io.ReadAll(reader)
			if closeErr := reader.Close(); closeErr != nil {
				t.Fatal(closeErr)
			}
			if err != nil {
				t.Fatal(err)
			}
			got := string(output)
			if !strings.Contains(got, tc.want) || strings.Contains(got, "lsof") || strings.Contains(got, "docker") || strings.Count(got, tc.want) != 1 {
				t.Fatalf("state log = %q, want exactly one %q and no internal commands", got, tc.want)
			}
		})
	}
}
