package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

func TestInstallSeedNoFetchSkipsFetchAndRestore(t *testing.T) {
	dir := t.TempDir()
	marker := filepath.Join(dir, "invoked")
	if err := os.WriteFile(filepath.Join(dir, "sb"), []byte("#!/bin/sh\necho invoked >> '"+marker+"'\nexit 1\n"), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("STATBUS_DB_SEED_NO_FETCH", "1")
	if !checkSeedRestored(dir) {
		t.Fatal("Seed step must be skipped when STATBUS_DB_SEED_NO_FETCH=1")
	}
	if err := runSeedRestore(dir); err != nil {
		t.Fatalf("direct seed invocation with no-fetch control: %v", err)
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatalf("seed fetch/restore invoked despite no-fetch control: marker stat = %v", err)
	}

	// The override is opt-in; without it the fetch path is still reached.
	t.Setenv("STATBUS_DB_SEED_NO_FETCH", "0")
	_ = runSeedRestore(dir)
	if _, err := os.Stat(marker); err != nil {
		t.Fatalf("expected seed fetch invocation without override: %v", err)
	}
}
