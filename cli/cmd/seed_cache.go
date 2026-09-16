package cmd

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// validateCachedSeedForRestore is the fail-closed, read-only gate immediately
// before pg_restore. A cached seed may be restored only when its metadata proves
// that every migration baked into it is byte-for-byte identical to this
// checkout. In particular, removing and retimestamping a baked migration changes
// the ordered fingerprint and is rejected before the target database is touched.
//
// The caller deliberately leaves the incompatible cache in place for diagnosis.
// Install treats this rejection as a lost seed fast path and safely continues
// with full migrations against the still-untouched fresh database.
func validateCachedSeedForRestore(projDir string, meta *seedMeta) error {
	versionText := strings.TrimSpace(meta.MigrationVersion)
	version, err := strconv.ParseInt(versionText, 10, 64)
	if err != nil || version <= 0 {
		return fmt.Errorf("invalid migration_version %q in seed.json", meta.MigrationVersion)
	}
	if meta.MigrationsFingerprint == "" {
		return fmt.Errorf("seed.json has no migrations_fingerprint (legacy or malformed cache)")
	}

	currentFingerprint, err := migrate.UpMigrationsFingerprintUpTo(projDir, version)
	if err != nil {
		return fmt.Errorf("fingerprint current migrations through %d: %w", version, err)
	}
	if currentFingerprint != meta.MigrationsFingerprint {
		return fmt.Errorf("migrations through seed version %d differ from the cached seed fingerprint; fetch a seed for this checkout or run full migrations", version)
	}

	if meta.PostRestoreSHA == "" {
		return fmt.Errorf("seed.json has no post_restore_sha (legacy or malformed cache)")
	}
	currentPostRestoreSHA, err := postRestoreFileSHA(projDir)
	if err != nil {
		return fmt.Errorf("fingerprint current post_restore.sql: %w", err)
	}
	if currentPostRestoreSHA != meta.PostRestoreSHA {
		return fmt.Errorf("post_restore.sql differs from the cached seed fingerprint; fetch a seed for this checkout or run full migrations")
	}

	return nil
}
