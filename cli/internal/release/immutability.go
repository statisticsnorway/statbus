package release

import (
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

// AmendmentsFileName is the repo-relative path of the committed declaration of
// migrations amended in place after release (STATBUS-072). It is the durable,
// AUTO-CONVEYED source for the intentional-fix set: it travels with
// `git checkout <target>` (which the upgrade does before `./sb migrate up`), so
// every host's automatic upgrade reads the same declared intent with NO per-host
// env var. One row per amendment, tab-separated:
//
//	version<TAB>amending_release<TAB>reason
//
// Only `version` (the 14-digit YYYYMMDDHHMMSS of the amended migration) is
// load-bearing; amending_release + reason are AUDIT metadata (PR review, log,
// ledger) the gate never reads. Append-only: a listed version is re-stamped
// only on a hash MISMATCH (a no-op once re-stamped or freshly applied), so
// historical rows are a permanent, zero-cost audit ledger — never prune them.
const AmendmentsFileName = "migrations/amendments.tsv"

// ParseAmendmentsFile reads AmendmentsFileName under projDir and returns the set
// of amended migration versions. A MISSING file is the normal case (no
// amendments declared) → empty set, no error. A malformed version field fails
// LOUDLY (mirrors ParseIntentionallyFixBrokenImmutableMigrationVersions — a typo must never silently widen the
// immutability gate). Lines beginning with '#' and blank lines are ignored; the
// version is the first whitespace-separated token, the remainder is audit text.
func ParseAmendmentsFile(projDir string) (map[int64]bool, error) {
	out := make(map[int64]bool)
	path := filepath.Join(projDir, AmendmentsFileName)
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return out, nil
		}
		return nil, fmt.Errorf("read %s: %w", AmendmentsFileName, err)
	}
	for i, raw := range strings.Split(string(data), "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		// First whitespace-separated token is the load-bearing version; any
		// remaining tokens (amending_release, reason) are audit metadata.
		versionTok := strings.Fields(line)[0]
		v, perr := strconv.ParseInt(versionTok, 10, 64)
		if perr != nil {
			return nil, fmt.Errorf("%s line %d: invalid migration version %q: must be a 14-digit YYYYMMDDHHMMSS integer", AmendmentsFileName, i+1, versionTok)
		}
		out[v] = true
	}
	return out, nil
}

// IntentionallyFixBrokenImmutableMigrationVersions returns the full set of migration versions whose in-place
// amendment is sanctioned (STATBUS-072): the committed declaration file
// (AmendmentsFileName — the durable, auto-conveyed production source) UNION the
// STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION env var (a local-dev override for
// iterating on an amendment before committing the declaration). BOTH the
// runtime immutability gate (migrate.eagerContentHashCheck) and the release-cut
// preflight (cmd.checkMigrationImmutability) call this, so they agree on ONE
// source of truth. The env var is a distinct dev affordance, NOT a back-compat
// shim — production hosts leave it unset and rely on the committed file.
func IntentionallyFixBrokenImmutableMigrationVersions(projDir string) (map[int64]bool, error) {
	out, err := ParseAmendmentsFile(projDir)
	if err != nil {
		return nil, err
	}
	envSet, err := ParseIntentionallyFixBrokenImmutableMigrationVersions(os.Getenv(IntentionallyFixBrokenImmutableMigrationEnvVar))
	if err != nil {
		return nil, err
	}
	for v := range envSet {
		out[v] = true
	}
	return out, nil
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
