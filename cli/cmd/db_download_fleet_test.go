package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

// downloadRegistryFixture mirrors the fleet registry shape cloud.sh owns.
const downloadRegistryFixture = `#!/bin/bash
FLEET_REGISTRY=(
    "dev|cloud|statbus_dev@niue.statbus.org|dev.statbus.org|token"
    "no|standalone|statbus@rune.statbus.org|no.statbus.org|anon"
)
`

func writeDownloadRegistry(t *testing.T, body string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "cloud.sh"), []byte(body), 0o644); err != nil {
		t.Fatalf("write cloud.sh: %v", err)
	}
	return dir
}

// TestResolveFleetSlotUsesRegistry is STATBUS-562 at the command boundary:
// `sb db download` (and the remote restore path) must ask the fleet registry
// for the box instead of synthesizing statbus_<code>@niue.statbus.org.
func TestResolveFleetSlotUsesRegistry(t *testing.T) {
	dir := writeDownloadRegistry(t, downloadRegistryFixture)

	for code, want := range map[string]string{
		"dev": "statbus_dev@niue.statbus.org",
		"no":  "statbus@rune.statbus.org",
	} {
		slot, err := resolveFleetSlot(dir, code)
		if err != nil {
			t.Fatalf("resolveFleetSlot(%q): %v", code, err)
		}
		if slot.SSHTarget != want {
			t.Errorf("slot %q target = %q, want %q", code, slot.SSHTarget, want)
		}
		if got, wantDB := slot.Database(), "statbus_"+code; got != wantDB {
			t.Errorf("slot %q database = %q, want %q", code, got, wantDB)
		}
	}
}

// TestResolveFleetSlotRefusesUnknownCode keeps a typo from reaching SSH.
func TestResolveFleetSlotRefusesUnknownCode(t *testing.T) {
	dir := writeDownloadRegistry(t, downloadRegistryFixture)
	if _, err := resolveFleetSlot(dir, "mars"); err == nil {
		t.Fatal("resolveFleetSlot(mars) succeeded, want an unknown-slot error")
	}
}

// TestResolveFleetSlotRefusesUnsafeCode protects the remote database name
// from a value that could not have come from the registry anyway.
func TestResolveFleetSlotRefusesUnsafeCode(t *testing.T) {
	dir := writeDownloadRegistry(t, downloadRegistryFixture)
	if _, err := resolveFleetSlot(dir, "no;rm -rf"); err == nil {
		t.Fatal("resolveFleetSlot accepted a non-identifier slot code")
	}
}
