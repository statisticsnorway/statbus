package migrate

import (
	"testing"
)

func TestParseMigrationFile(t *testing.T) {
	valid := []struct {
		path        string
		version     int64
		description string
		isUp        bool
		extension   string
	}{
		{"migrations/20260311174120_add_upgrade_tracking.up.sql", 20260311174120, "add_upgrade_tracking", true, "sql"},
		{"migrations/20260204234245_btree_optimization.down.sql", 20260204234245, "btree_optimization", false, "sql"},
		{"/abs/path/20260101000000_initial.up.psql", 20260101000000, "initial", true, "psql"},
		{"20261231235959_end_of_year.down.psql", 20261231235959, "end_of_year", false, "psql"},
		{"20260101120000_multi_word_description.up.sql", 20260101120000, "multi_word_description", true, "sql"},
		{"20260601000000_ab.up.sql", 20260601000000, "ab", true, "sql"},
	}
	for _, tc := range valid {
		mf, err := parseMigrationFile(tc.path)
		if err != nil {
			t.Errorf("parseMigrationFile(%q) error: %v", tc.path, err)
			continue
		}
		if mf.Version != tc.version {
			t.Errorf("%q: version = %d, want %d", tc.path, mf.Version, tc.version)
		}
		if mf.Description != tc.description {
			t.Errorf("%q: description = %q, want %q", tc.path, mf.Description, tc.description)
		}
		if mf.IsUp != tc.isUp {
			t.Errorf("%q: isUp = %v, want %v", tc.path, mf.IsUp, tc.isUp)
		}
		if mf.Extension != tc.extension {
			t.Errorf("%q: extension = %q, want %q", tc.path, mf.Extension, tc.extension)
		}
	}

	invalid := []string{
		"not_a_migration.sql",
		"20260311_missing_seconds.up.sql",
		"12345_too_short.up.sql",
		"20260311174120_desc.up.txt",          // wrong extension
		"20260311174120_desc.sql",             // missing direction
		"20261301000000_bad_month.up.sql",     // month 13 invalid
		"20260230000000_bad_day.up.sql",       // Feb 30 invalid
		"99991232000000_bad_timestamp.up.sql", // Dec 32 invalid
	}
	for _, path := range invalid {
		_, err := parseMigrationFile(path)
		if err == nil {
			t.Errorf("parseMigrationFile(%q) expected error, got nil", path)
		}
	}
}
