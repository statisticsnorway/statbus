package release

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// IntentionallyFixBrokenImmutableMigrationEnvVar names the environment variable that suspends the
// migration-immutability gate for explicitly-listed versions. Operators set
// this only when they MUST modify an already-released migration in place —
// the normal flow is to create a NEW migration via `./sb migrate new`.
//
// Format: comma-separated 14-digit YYYYMMDDHHMMSS version timestamps.
//
//	STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION=20260521112759
//	STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION=20260521112759,20260522080000
//
// The variable affects two layers, both of which call ParseIntentionallyFixBrokenImmutableMigrationVersions:
//
//   - Release preflight (cli/cmd/release.go's checkMigrationImmutability):
//     skips listed versions when diffing against the previous tag. Other
//     unrelated modifications still fail the gate.
//   - Runtime (cli/internal/migrate/migrate.go's eagerContentHashCheck):
//     re-stamps db.migration.content_hash to the current file's hash for
//     listed versions whose stored hash mismatches. Other versions still
//     fail with the standard immutability error.
const IntentionallyFixBrokenImmutableMigrationEnvVar = "STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION"

// ParseIntentionallyFixBrokenImmutableMigrationVersions parses the value of STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION.
//
// Empty/whitespace-only input returns an empty map and no error (no
// broken-migration fix requested — the standard case).
//
// Non-integer entries return a clear error rather than silently allowing
// everything: a typo like "20260521-112759" must be loud, not a backdoor
// that bypasses the entire gate.
func ParseIntentionallyFixBrokenImmutableMigrationVersions(envValue string) (map[int64]bool, error) {
	out := make(map[int64]bool)
	s := strings.TrimSpace(envValue)
	if s == "" {
		return out, nil
	}
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		v, err := strconv.ParseInt(part, 10, 64)
		if err != nil {
			return nil, fmt.Errorf("%s: invalid migration version %q: must be a 14-digit YYYYMMDDHHMMSS integer", IntentionallyFixBrokenImmutableMigrationEnvVar, part)
		}
		out[v] = true
	}
	return out, nil
}

// IntentionallyFixBrokenImmutableMigrationVersions returns the set of migration
// versions the operator has explicitly declared — via the
// STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION env var — as deliberate
// in-place fixes of a GENUINELY BROKEN already-released migration (a
// crash/timeout/OOM fix that PRESERVES THE RESULT; see the cut-gate message).
//
// Read at the RELEASE CUT only (cmd.checkMigrationImmutability /
// release_verify.compareMigrationsForTag): a modified released migration FAILS
// the cut unless its version is named here. The RUNTIME no longer reads this —
// per-host upgrade blessing is decided by CHANNEL (migrate.migrationChannelClass),
// not a per-version list (STATBUS-102: the prior file-conveyed declaration set is
// retired; declared intent lives ONLY in the env var at the cut).
func IntentionallyFixBrokenImmutableMigrationVersions() (map[int64]bool, error) {
	return ParseIntentionallyFixBrokenImmutableMigrationVersions(os.Getenv(IntentionallyFixBrokenImmutableMigrationEnvVar))
}

// ReleaseTagPattern matches the project's release tag shape:
// `vYYYY.MM.PATCH` (stable) and `vYYYY.MM.PATCH-rc.N` (prerelease).
//
// Single source of truth: `cli/cmd/release.go`'s findReleaseTag and
// the migrate runner's mismatch-detection branch both reference this
// exported regex. Lives in `internal/release` so the lower
// `internal/migrate` package can import it (`cli/cmd` is an upper
// package and can't be imported from internals).
var ReleaseTagPattern = regexp.MustCompile(`^v\d{4}\.\d{2}\.\d+(-rc\.\d+)?$`)

// MigrationInReleasedTag returns the first release-shaped tag whose
// tree contains the file `migrations/<version>_*.up.sql`, or "" if no
// release tag contains it.
//
// Used by the migrate runner to gate `content_hash` mismatch handling:
//   - Hash mismatch + version IS in a released tag → immutability
//     violation (hard fail; the migration is published, no edits allowed).
//   - Hash mismatch + version NOT in any released tag → WIP edit; the
//     operator can recover via `./sb migrate redo <version>`.
//
// Implementation: enumerates `git tag -l v*`, filters by
// ReleaseTagPattern, and probes each tag's tree with
// `git rev-parse --quiet --verify <tag>:<path>`. First hit wins; the
// tags from `git tag -l` print in alphabetic order which equals
// chronological order for our CalVer scheme — so the returned tag is
// the EARLIEST release containing the migration (most-informative for
// the operator: "this shipped in <oldest tag>, you cannot edit it").
//
// Returns "" (no error) when:
//   - the file doesn't exist at HEAD (already deleted; not our concern here)
//   - no release-shaped tag contains the file (genuine WIP)
//
// Returns the tag (no error) when at least one release-shaped tag
// contains the file. Errors only on git command failure.
func MigrationInReleasedTag(projDir string, version int64) (string, error) {
	pattern := filepath.Join(projDir, "migrations", fmt.Sprintf("%d_*.up.sql", version))
	matches, _ := filepath.Glob(pattern)
	if len(matches) == 0 {
		return "", nil
	}
	rel := "migrations/" + filepath.Base(matches[0])

	tagsCmd := exec.Command("git", "tag", "-l", "v*")
	tagsCmd.Dir = projDir
	tagsOut, err := tagsCmd.Output()
	if err != nil {
		return "", fmt.Errorf("git tag -l v*: %w", err)
	}

	for _, tag := range strings.Split(strings.TrimSpace(string(tagsOut)), "\n") {
		tag = strings.TrimSpace(tag)
		if !ReleaseTagPattern.MatchString(tag) {
			continue
		}
		probe := exec.Command("git", "rev-parse", "--quiet", "--verify", tag+":"+rel)
		probe.Dir = projDir
		if probe.Run() == nil {
			return tag, nil
		}
	}
	return "", nil
}

// FileIsDirty reports whether relPath (relative to projDir, e.g.
// "migrations/20260218215337_foo.up.sql") has uncommitted changes against
// HEAD — the signal that distinguishes a LIVE human edit from a file whose
// current on-disk bytes are exactly what's committed (STATBUS-156).
//
// Used by the migrate runner's content_hash mismatch handling: a mismatch on
// a CLEAN file cannot be a live edit — it means the caller's cached state
// (e.g. a restored prior seed) predates a legitimately committed change to
// that file, not that someone is mid-edit on it right now.
//
// `git diff --quiet HEAD -- <path>` exits 0 for no difference, 1 for a
// difference; any other exit status (or a non-*exec.ExitError failure, e.g.
// git itself missing) is a genuine error the caller must not silently paper
// over. Caveat (verified empirically): `git diff` never reports on an
// UNTRACKED path — it returns "clean" (exit 0) for one, same as a genuinely
// clean tracked file. Not a concern for this function's actual call site:
// eagerContentHashCheck only calls it after confirming the migration is
// already IN a released tag, so the file is necessarily tracked.
func FileIsDirty(projDir, relPath string) (bool, error) {
	// A missing repo (or no HEAD commit) also makes `git diff` exit 1 — the
	// SAME code a real dirty-file diff produces — so exit-code alone can't
	// tell them apart. Verify the repo exists FIRST via a separate, dedicated
	// probe; that failure is unambiguous and never confusable with "dirty".
	verify := exec.Command("git", "rev-parse", "--is-inside-work-tree")
	verify.Dir = projDir
	if err := verify.Run(); err != nil {
		return false, fmt.Errorf("not a git repository (%s): %w", projDir, err)
	}
	cmd := exec.Command("git", "diff", "--quiet", "HEAD", "--", relPath)
	cmd.Dir = projDir
	err := cmd.Run()
	if err == nil {
		return false, nil
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) && exitErr.ExitCode() == 1 {
		return true, nil
	}
	return false, fmt.Errorf("git diff --quiet HEAD -- %s: %w", relPath, err)
}
