package cmd

import (
	"strings"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

func TestLiveHolderRefusal(t *testing.T) {
	started := time.Date(2026, 9, 25, 7, 0, 0, 0, time.UTC)
	for _, tc := range []struct {
		name, holder, want, notWant string
	}{
		{"install", upgrade.HolderInstall, "an installation started at 2026-09-25T07:00:00Z is still running", "An upgrade is already running"},
		{"service", upgrade.HolderService, "upgrade in progress", "An installation started"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			detail := &install.Detail{Flag: &upgrade.UpgradeFlag{Holder: tc.holder, StartedAt: started}}
			handled, err := dispatchInstallState(t.TempDir(), install.StateLiveUpgrade, detail)
			if !handled || err == nil || !strings.Contains(err.Error(), tc.want) || strings.Contains(err.Error(), tc.notWant) {
				t.Fatalf("handled=%v err=%v, want %q but not %q", handled, err, tc.want, tc.notWant)
			}
			if !strings.Contains(err.Error(), "lsof tmp/upgrade-in-progress.json") {
				t.Fatalf("missing process inspection hint: %v", err)
			}
		})
	}
}
