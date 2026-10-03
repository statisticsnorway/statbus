package cmd

import (
	"path/filepath"
	"reflect"
	"testing"
)

func TestCrashRecoveryConfigGenerationMigratesLegacySecrets(t *testing.T) {
	projDir := t.TempDir()
	var gotDir, gotName string
	var gotArgs []string

	run := func(dir, name string, args ...string) error {
		gotDir = dir
		gotName = name
		gotArgs = append([]string(nil), args...)
		return nil
	}

	if err := regenerateCrashRecoveryConfig(projDir, run); err != nil {
		t.Fatalf("regenerate crash recovery config: %v", err)
	}
	if gotDir != projDir {
		t.Fatalf("command dir = %q, want %q", gotDir, projDir)
	}
	if want := filepath.Join(projDir, "sb"); gotName != want {
		t.Fatalf("command name = %q, want %q", gotName, want)
	}
	if want := []string{"config", "generate", "--migrate-legacy-secrets"}; !reflect.DeepEqual(gotArgs, want) {
		t.Fatalf("command args = %q, want %q", gotArgs, want)
	}
}
