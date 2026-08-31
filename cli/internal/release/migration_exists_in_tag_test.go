package release

import "testing"

// TestMigrationExistsInTag_And_MigrationInReleasedTag (STATBUS-329) — added
// alongside the MigrationExistsInTag extraction from MigrationInReleasedTag's
// body: neither function had a direct test before, and the extraction must
// not change MigrationInReleasedTag's observable behavior.
func TestMigrationExistsInTag_And_MigrationInReleasedTag(t *testing.T) {
	dir := makeTagRepo(t) // commits migrations/20260101000000_init.up.sql
	tagAnnotated(t, dir, "v2026.01.0", "Release v2026.01.0")

	t.Run("MigrationExistsInTag true for a version in the tag", func(t *testing.T) {
		exists, rel, err := MigrationExistsInTag(dir, 20260101000000, "v2026.01.0")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !exists {
			t.Error("expected exists=true")
		}
		if rel != "migrations/20260101000000_init.up.sql" {
			t.Errorf("got rel=%q, want migrations/20260101000000_init.up.sql", rel)
		}
	})

	t.Run("MigrationExistsInTag false for a version with no file on disk", func(t *testing.T) {
		exists, rel, err := MigrationExistsInTag(dir, 99999999999999, "v2026.01.0")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if exists || rel != "" {
			t.Errorf("got exists=%v rel=%q, want false/\"\"", exists, rel)
		}
	})

	t.Run("MigrationExistsInTag false for a nonexistent tag", func(t *testing.T) {
		exists, _, err := MigrationExistsInTag(dir, 20260101000000, "v2026.99.0")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if exists {
			t.Error("expected exists=false for a tag that doesn't exist")
		}
	})

	t.Run("MigrationInReleasedTag finds the tag containing the version", func(t *testing.T) {
		got, err := MigrationInReleasedTag(dir, 20260101000000)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "v2026.01.0" {
			t.Errorf("got %q, want v2026.01.0", got)
		}
	})

	t.Run("MigrationInReleasedTag returns empty for a version no release tag has", func(t *testing.T) {
		got, err := MigrationInReleasedTag(dir, 99999999999999)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "" {
			t.Errorf("got %q, want \"\"", got)
		}
	})
}
