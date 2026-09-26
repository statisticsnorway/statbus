package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// The upgrade service regenerates config through the MIGRATING entry
// (STATBUS-361): a box installed before the credential split carries legacy
// token placeholders in .env.config, and a strict refusal mid-upgrade
// crash-loops the service (rc.07 smoke, v2026.09.2 → rc.07). Pin both: the
// flag exists on the command, and the service's call sites pass it.
func TestConfigGenerateMigrateFlagExists(t *testing.T) {
	f := configGenerateCmd.Flags().Lookup("migrate-legacy-secrets")
	if f == nil {
		t.Fatal("config generate must accept --migrate-legacy-secrets for the install/upgrade context")
	}
	if f.DefValue != "false" {
		t.Fatal("plain `sb config generate` stays strict; migration is opt-in")
	}
}

func TestUpgradeServiceRegenerationsMigrateLegacySecrets(t *testing.T) {
	src, err := os.ReadFile(filepath.Join(thisRepoFile(t, "cli/internal/upgrade"), "service.go"))
	if err != nil {
		t.Fatal(err)
	}
	// Both new-binary regeneration sites (recovery boot + post-swap target)
	// must use the migrating entry. The only permitted plain sites are the
	// ones running against the SOURCE tree/binary (restore-after-sb.old
	// "park-config-generate", pre-swap "preswap-terminal-config-generate"):
	// those invoke an old binary that predates both the refusal and the flag.
	lines := strings.Split(string(src), "\n")
	withFlag := 0
	var unjustifiedPlain []int
	for i, line := range lines {
		if !strings.Contains(line, `"./sb", "config", "generate"`) {
			continue
		}
		if strings.Contains(line, "--migrate-legacy-secrets") {
			withFlag++
			continue
		}
		window := line
		if i > 0 {
			window = lines[i-1] + window
		}
		if !strings.Contains(window, "park-config-generate") && !strings.Contains(window, "preswap-terminal-config-generate") {
			unjustifiedPlain = append(unjustifiedPlain, i+1)
		}
	}
	if withFlag < 2 {
		t.Fatalf("service.go: %d migrating config-generate sites, want >=2 (recovery boot + post-swap target)", withFlag)
	}
	if len(unjustifiedPlain) != 0 {
		t.Fatalf("service.go: plain (non-migrating) config-generate at lines %v — only the source-tree sites park-config-generate/preswap-terminal-config-generate may stay plain", unjustifiedPlain)
	}
	_ = upgrade.ErrCommandTimeout // keep the import honest
}
