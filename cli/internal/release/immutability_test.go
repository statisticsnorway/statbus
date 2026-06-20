package release

import (
	"strings"
	"testing"
)

func TestParseIntentionallyFixBrokenImmutableMigrationVersions_Empty(t *testing.T) {
	cases := []string{"", "   ", "\t\n", ",", "  ,  ,  "}
	for _, in := range cases {
		got, err := ParseIntentionallyFixBrokenImmutableMigrationVersions(in)
		if err != nil {
			t.Errorf("input %q: unexpected error: %v", in, err)
		}
		if len(got) != 0 {
			t.Errorf("input %q: expected empty map, got %v", in, got)
		}
	}
}

func TestParseIntentionallyFixBrokenImmutableMigrationVersions_Single(t *testing.T) {
	got, err := ParseIntentionallyFixBrokenImmutableMigrationVersions("20260521112759")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 1 || !got[20260521112759] {
		t.Errorf("expected {20260521112759: true}, got %v", got)
	}
}

func TestParseIntentionallyFixBrokenImmutableMigrationVersions_Multi(t *testing.T) {
	got, err := ParseIntentionallyFixBrokenImmutableMigrationVersions("20260521112759,20260522080000")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 2 {
		t.Errorf("expected 2 entries, got %d (%v)", len(got), got)
	}
	if !got[20260521112759] || !got[20260522080000] {
		t.Errorf("missing expected entries: got %v", got)
	}
}

func TestParseIntentionallyFixBrokenImmutableMigrationVersions_Whitespace(t *testing.T) {
	got, err := ParseIntentionallyFixBrokenImmutableMigrationVersions("  20260521112759  ,  20260522080000  ")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !got[20260521112759] || !got[20260522080000] {
		t.Errorf("expected both entries; got %v", got)
	}
}

func TestParseIntentionallyFixBrokenImmutableMigrationVersions_Garbage(t *testing.T) {
	cases := []string{
		"not-a-number",
		"20260521-112759",    // dash inside (typo a real operator might make)
		"20260521112759,abc", // mixed valid + garbage
		"abc,20260521112759", // garbage first
		"20260521112759.99",  // float-like
		"0x123",              // hex
	}
	for _, in := range cases {
		_, err := ParseIntentionallyFixBrokenImmutableMigrationVersions(in)
		if err == nil {
			t.Errorf("input %q: expected error, got nil", in)
			continue
		}
		if !strings.Contains(err.Error(), IntentionallyFixBrokenImmutableMigrationEnvVar) {
			t.Errorf("input %q: error %q missing env-var name", in, err.Error())
		}
		if !strings.Contains(err.Error(), "14-digit") {
			t.Errorf("input %q: error %q missing format hint", in, err.Error())
		}
	}
}

func TestParseIntentionallyFixBrokenImmutableMigrationVersions_DuplicatesIgnored(t *testing.T) {
	got, err := ParseIntentionallyFixBrokenImmutableMigrationVersions("20260521112759,20260521112759")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 1 || !got[20260521112759] {
		t.Errorf("expected single entry, got %v", got)
	}
}

func TestIntentionallyFixBrokenImmutableMigrationEnvVar_Constant(t *testing.T) {
	// Lock the env-var name. If someone renames it, this test surfaces
	// the change loudly — every doc/operator reference points at the
	// exact string below.
	want := "STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION"
	if IntentionallyFixBrokenImmutableMigrationEnvVar != want {
		t.Errorf("IntentionallyFixBrokenImmutableMigrationEnvVar = %q, want %q", IntentionallyFixBrokenImmutableMigrationEnvVar, want)
	}
}
