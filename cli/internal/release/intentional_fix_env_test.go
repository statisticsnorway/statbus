package release

import "testing"

// IntentionallyFixBrokenImmutableMigrationVersions is env-ONLY post-STATBUS-102
// (the file-conveyed declaration set is retired). These cover the cut-gate
// source: declared versions are honoured; unset → empty set.

func TestIntentionallyFixBrokenImmutableMigrationVersions_EnvOnly(t *testing.T) {
	t.Setenv(IntentionallyFixBrokenImmutableMigrationEnvVar, "20260521112759,20260522080000")
	got, err := IntentionallyFixBrokenImmutableMigrationVersions()
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || !got[20260521112759] || !got[20260522080000] {
		t.Errorf("env-only set = %v, want the 2 declared versions", got)
	}
}

func TestIntentionallyFixBrokenImmutableMigrationVersions_Unset(t *testing.T) {
	t.Setenv(IntentionallyFixBrokenImmutableMigrationEnvVar, "")
	got, err := IntentionallyFixBrokenImmutableMigrationVersions()
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Errorf("unset env = %v, want empty set", got)
	}
}
