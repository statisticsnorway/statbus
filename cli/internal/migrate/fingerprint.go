package migrate

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
)

// UpMigrationsFingerprintUpTo returns a stable sha256 over the ORDERED set of
// up-migration files whose version is <= maxVersion, each contributing one
// "version|sha256(content)" record.
//
// This is the anchor of the STATBUS-116 seed-incremental correctness gate. The
// seed build records this fingerprint (computed over migrations <= the seed's
// own migration version) in seed.json; a later incremental build recomputes it
// over the CURRENT migrations <= the PRIOR seed's version and compares. A
// mismatch means a migration already baked into the prior seed was retroactively
// edited / added / removed — which a ledger-based `migrate up` would NOT reapply
// (it only runs versions absent from db.migration), so restoring the prior seed
// and applying only the delta would silently DRIFT from a full rebuild. On any
// mismatch the build must fall back to a full from-empty rebuild.
//
// Determinism: listMigrationFiles returns version-sorted, version-unique files,
// so the digest is independent of filesystem iteration order. Both *.up.sql and
// *.up.psql are included (both are migrations).
func UpMigrationsFingerprintUpTo(projDir string, maxVersion int64) (string, error) {
	files, err := listMigrationFiles(projDir)
	if err != nil {
		return "", fmt.Errorf("list migrations for fingerprint: %w", err)
	}
	h := sha256.New()
	for _, m := range files {
		if m.Version > maxVersion {
			continue
		}
		content, err := os.ReadFile(m.Path)
		if err != nil {
			return "", fmt.Errorf("read migration %s for fingerprint: %w", m.Path, err)
		}
		fileSum := sha256.Sum256(content)
		// version pins identity/order; content sha pins the bytes; the trailing
		// newline delimits records unambiguously.
		_, _ = fmt.Fprintf(h, "%d|%s\n", m.Version, hex.EncodeToString(fileSum[:])) // hash.Hash.Write never returns an error
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
