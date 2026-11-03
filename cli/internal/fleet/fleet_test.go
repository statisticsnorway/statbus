package fleet

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// registryFixture keeps the parser tests independent of the live fleet: the
// point of this package is that cloud.sh's FLEET_REGISTRY is the only table,
// so a fixture must be able to express both deployment shapes.
const registryFixture = `#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# A comment above the registry.
FLEET_REGISTRY=(
    "dev|cloud|statbus_dev@niue.statbus.org|dev.statbus.org|token"
    "demo|cloud|statbus_demo@niue.statbus.org|demo.statbus.org|anon"
    "no|standalone|statbus@rune.statbus.org|no.statbus.org|anon"
)
INSTALL_URL="https://statbus.org/install.sh"
`

func writeFixture(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "cloud.sh")
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
	return path
}

// TestResolveSlotFromRegistry is the regression for STATBUS-562: Norway moved
// to a standalone box, so a slot's SSH target comes from the registry rather
// than being synthesized as statbus_<code>@niue.statbus.org.
func TestResolveSlotFromRegistry(t *testing.T) {
	registry, err := LoadFile(writeFixture(t, registryFixture))
	if err != nil {
		t.Fatalf("LoadFile: %v", err)
	}

	cases := []struct {
		code   string
		target string
		db     string
	}{
		{"no", "statbus@rune.statbus.org", "statbus_no"},
		{"dev", "statbus_dev@niue.statbus.org", "statbus_dev"},
	}
	for _, c := range cases {
		t.Run(c.code, func(t *testing.T) {
			slot, err := registry.Lookup(c.code)
			if err != nil {
				t.Fatalf("Lookup(%q): %v", c.code, err)
			}
			if slot.SSHTarget != c.target {
				t.Errorf("SSHTarget = %q, want %q", slot.SSHTarget, c.target)
			}
			if got := slot.Database(); got != c.db {
				t.Errorf("Database() = %q, want %q", got, c.db)
			}
			user, host, err := slot.SSHUserHost()
			if err != nil {
				t.Fatalf("SSHUserHost: %v", err)
			}
			wantUser := strings.Split(c.target, "@")[0]
			wantHost := strings.Split(c.target, "@")[1]
			if user != wantUser || host != wantHost {
				t.Errorf("SSHUserHost() = %q, %q, want %q, %q", user, host, wantUser, wantHost)
			}
		})
	}
}

// TestLookupUnknownSlotRefuses keeps an operator typo from becoming an SSH
// attempt against a synthesized host.
func TestLookupUnknownSlotRefuses(t *testing.T) {
	registry, err := LoadFile(writeFixture(t, registryFixture))
	if err != nil {
		t.Fatalf("LoadFile: %v", err)
	}
	if _, err := registry.Lookup("mars"); err == nil {
		t.Fatal("Lookup(mars) succeeded, want an unknown-slot error")
	}
}

// TestLoadFileRejectsMalformedEntry ensures a registry edit that breaks the
// five-field contract fails loudly at resolution time instead of silently
// falling back to a wrong host.
func TestLoadFileRejectsMalformedEntry(t *testing.T) {
	body := strings.Replace(registryFixture,
		`"no|standalone|statbus@rune.statbus.org|no.statbus.org|anon"`,
		`"no|standalone|statbus@rune.statbus.org|no.statbus.org"`, 1)
	if _, err := LoadFile(writeFixture(t, body)); err == nil {
		t.Fatal("LoadFile accepted a four-field registry entry")
	}
}

// TestLoadFileRequiresRegistry proves an unreadable fleet file is an error,
// not an empty registry that would send every lookup down a default path.
func TestLoadFileRequiresRegistry(t *testing.T) {
	if _, err := LoadFile(writeFixture(t, "#!/bin/bash\n")); err == nil {
		t.Fatal("LoadFile accepted a file without FLEET_REGISTRY")
	}
}

// TestRepoCloudRegistryResolvesLiveFleet pins the real fleet registry: dev
// stays on the multi-tenant niue cloud, Norway lives on its standalone box.
// This is what `./sb db download` resolves in production.
func TestRepoCloudRegistryResolvesLiveFleet(t *testing.T) {
	registry, err := LoadFile(filepath.Join("..", "..", "..", "cloud.sh"))
	if err != nil {
		t.Fatalf("load repo cloud.sh: %v", err)
	}
	cases := map[string]string{
		"dev": "statbus_dev@niue.statbus.org",
		"no":  "statbus@rune.statbus.org",
	}
	for code, want := range cases {
		slot, err := registry.Lookup(code)
		if err != nil {
			t.Fatalf("Lookup(%q): %v", code, err)
		}
		if slot.SSHTarget != want {
			t.Errorf("slot %q target = %q, want %q", code, slot.SSHTarget, want)
		}
	}
}
