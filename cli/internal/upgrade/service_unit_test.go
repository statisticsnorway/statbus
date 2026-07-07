package upgrade

import (
	"os"
	"strings"
	"testing"
)

// TestStatbusUpgradeServiceUnit_StartLimitDirectives pins the start-limit
// cap: ops/statbus-upgrade.service MUST declare StartLimitIntervalSec +
// StartLimitBurst so a daemon that cannot reach READY=1 (e.g. DB down at boot)
// surfaces as `failed` within minutes instead of `activating` forever.
//
// The cap guards ONLY repeated daemon-START failures — it is NOT an
// upgrade-retry budget: the upgrade is one-shot (a death during the post-swap
// resume rolls back via the PhaseNewSbUpgrading latch rather than re-running).
// burst=5 rides out a legitimate ~3-start transient (a DB restart in a
// maintenance window) while tripping a persistent start failure in ~150s; the
// recovery path is `./sb install` (routes through StateDBUnreachable →
// step-table), not manual reset-failed.
func TestStatbusUpgradeServiceUnit_StartLimitDirectives(t *testing.T) {
	body := readUnitFile(t)

	expectKV(t, body, "StartLimitIntervalSec", "600")
	expectKV(t, body, "StartLimitBurst", "5")
}

// TestStatbusUpgradeServiceUnit_RestartBehaviorPreserved pins the
// existing restart contract so a future edit can't accidentally drop
// Restart=always or RestartSec=30 (which together with the start-limit
// give the legitimate-transient grace window).
func TestStatbusUpgradeServiceUnit_RestartBehaviorPreserved(t *testing.T) {
	body := readUnitFile(t)

	expectKV(t, body, "Restart", "always")
	expectKV(t, body, "RestartSec", "30")
	expectKV(t, body, "Type", "notify")
	expectKV(t, body, "SuccessExitStatus", "42")
	expectKV(t, body, "RestartForceExitStatus", "42")
}

// TestStatbusUpgradeServiceUnit_StartLimitInUnitSection: the start-limit
// directives are [Unit]-section properties on systemd ≥230. Placing them
// in [Service] is silently ignored by some systemd versions. This test
// pins the section.
func TestStatbusUpgradeServiceUnit_StartLimitInUnitSection(t *testing.T) {
	body := readUnitFile(t)

	unitStart := strings.Index(body, "[Unit]")
	serviceStart := strings.Index(body, "[Service]")
	if unitStart < 0 || serviceStart < 0 {
		t.Fatalf("unit file missing required sections (unit=%d service=%d)",
			unitStart, serviceStart)
	}
	unitSection := body[unitStart:serviceStart]
	for _, key := range []string{"StartLimitIntervalSec", "StartLimitBurst"} {
		if !strings.Contains(unitSection, key+"=") {
			t.Errorf("%s= must live in the [Unit] section (currently absent there); "+
				"found in [Service] or elsewhere is a no-op on some systemd versions.", key)
		}
	}
}

func readUnitFile(t *testing.T) string {
	t.Helper()
	path := thisRepoFile(t, "ops/statbus-upgrade.service")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(data)
}

// expectKV asserts that the unit file contains a `key=value` line. Comments
// (lines starting with `#`) are skipped — directive lines only.
func expectKV(t *testing.T, body, key, value string) {
	t.Helper()
	want := key + "=" + value
	for _, line := range strings.Split(body, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "#") {
			continue
		}
		if trimmed == want {
			return
		}
	}
	t.Errorf("ops/statbus-upgrade.service missing directive %q", want)
}
