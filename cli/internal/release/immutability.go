package release

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
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
//
// BY DESIGN — the release cut is the ONLY bless. Read this before "improving"
// the mismatch handling; the design has been re-derived and re-lost four times
// (STATBUS-072/doc-014 → STATBUS-102 → STATBUS-166's withdrawn first draft),
// so the answer now lives here (King, 2026-07-12):
//
//  1. The bless for a retroactive edit to a released migration happens ONCE,
//     at the release cut, by naming the version in this variable. The cut gate
//     is the single choke point where a human vets such an edit.
//  2. Therefore the EXISTENCE of a cut release/RC whose migrations differ from
//     the previous tag IS the bless: the gate refused every unnamed change, so
//     whatever a release carries was deliberately vetted. Trust the artifact.
//  3. There is deliberately NO second record. No declaration file, no
//     sanctioned list shipped to boxes, no runtime provenance re-check. A
//     file-conveyed declaration set was built once and RETIRED (STATBUS-102):
//     it states the same intent twice — a redundant side channel that drifts.
//     Do not re-introduce it.
//  4. Trust is CONTENT-level, not commit-level (King, STATBUS-166): bytes for
//     version V that any cut release carries are gate-vetted bytes, wherever a
//     box got them. Release-channel boxes trust their whole diet (they apply
//     only releases → blanket re-stamp on mismatch). Edge boxes apply ungated
//     master commits, so they recognize vetted bytes by matching
//     (version, live hash) against cut releases; unvetted bytes still refuse.
//     Any release-tag reading on a deployed box must work on a shallow clone
//     (git ls-remote / tag fetch — local tag-tree probes are unreliable there).
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

// ReleaseTagWithMigrationHash reports the first release-shaped tag whose
// migrations/<version>_*.up.{sql,psql} blob has sha256 (hex) exactly equal to
// wantHash, or "" if no cut release carries those exact bytes.
//
// This is CONTENT-level trust (STATBUS-166, King-approved): it answers "do the
// on-disk bytes for version V match V's bytes in some cut release?" — never "is
// the current commit tagged" and never "does a release merely contain version
// V". A newer, not-yet-gated edit has bytes no release carries → "" → the caller
// refuses (or, on an edge box's latest migration, redoes). It is the runtime
// half of the BY DESIGN contract on IntentionallyFixBrokenImmutableMigrationEnvVar:
// the release cut is the bless, so gate-vetted bytes are recognizable wherever a
// box got them.
//
// SHALLOW-CLONE SAFE (a hard requirement — deployed boxes are `git clone
// --depth 1`, install.go): tag objects/trees are ABSENT locally there, so a
// local tag-tree probe (`git rev-parse <tag>:<path>`) would falsely miss and
// refuse a legitimate bless. Instead this discovers tags with `git ls-remote
// --tags origin` and reads each candidate's blob by FETCHING that tag shallowly
// (`git fetch --depth 1 origin refs/tags/<tag>` → FETCH_HEAD), then `git
// cat-file` — objects the shallow fetch is guaranteed to bring down. Candidates
// are tried newest-first (CalVer descending) so the common heal (bytes just
// blessed in the newest RC) matches on the first fetch; only the rare
// unvetted-edit refuse walks every release tag.
//
// Returns ("", nil) when no release carries the matching bytes. Errors only on
// git/transport failure: an unreachable origin must NOT be silently treated as
// "unvetted" (that would redo/refuse a possibly-vetted migration on a network
// blip) — the caller surfaces the error loudly.
func ReleaseTagWithMigrationHash(projDir string, version int64, wantHash string) (string, error) {
	tags, err := releaseTagsNewestFirst(projDir)
	if err != nil {
		return "", err
	}
	for _, tag := range tags {
		hash, found, err := migrationUpBlobHashInTag(projDir, tag, version)
		if err != nil {
			return "", err
		}
		if found && hash == wantHash {
			return tag, nil
		}
	}
	return "", nil
}

// releaseTagParse extracts a release tag's CalVer components for ordering.
var releaseTagParse = regexp.MustCompile(`^v(\d{4})\.(\d{2})\.(\d+)(?:-rc\.(\d+))?$`)

// releaseTagsNewestFirst lists the remote's release-shaped tags (via
// `git ls-remote --tags origin`, so it is correct on a shallow clone where the
// local tag set is incomplete) sorted newest-first. Order is an EFFICIENCY
// concern only — ReleaseTagWithMigrationHash scans until a content match, so any
// order is correct — but newest-first makes the common heal a single fetch.
func releaseTagsNewestFirst(projDir string) ([]string, error) {
	cmd := exec.Command("git", "ls-remote", "--tags", "origin")
	cmd.Dir = projDir
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("git ls-remote --tags origin: %w", err)
	}
	seen := make(map[string]bool)
	var tags []string
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		// "<sha>\trefs/tags/<tag>" or "...^{}" (peeled annotated-tag line).
		tag := strings.TrimSuffix(strings.TrimPrefix(fields[1], "refs/tags/"), "^{}")
		if !ReleaseTagPattern.MatchString(tag) || seen[tag] {
			continue
		}
		seen[tag] = true
		tags = append(tags, tag)
	}
	sort.Slice(tags, func(i, j int) bool { return releaseTagLess(tags[j], tags[i]) })
	return tags, nil
}

// releaseTagLess orders release tags chronologically (older < newer): by year,
// month, patch, then rc — with a final release (no -rc.N) newer than every
// -rc.N of the same patch line (a cut release supersedes its candidates).
func releaseTagLess(a, b string) bool {
	ay, am, ap, arc := releaseTagKey(a)
	by, bm, bp, brc := releaseTagKey(b)
	switch {
	case ay != by:
		return ay < by
	case am != bm:
		return am < bm
	case ap != bp:
		return ap < bp
	default:
		return arc < brc
	}
}

// releaseTagKey parses a release tag into comparable components. A final release
// gets an rc rank above any real -rc.N so it sorts as the newest of its patch.
func releaseTagKey(tag string) (year, month, patch, rc int) {
	m := releaseTagParse.FindStringSubmatch(tag)
	if m == nil {
		return 0, 0, 0, 0
	}
	year, _ = strconv.Atoi(m[1])
	month, _ = strconv.Atoi(m[2])
	patch, _ = strconv.Atoi(m[3])
	if m[4] == "" {
		rc = int(^uint(0) >> 1) // MaxInt: a final release is newer than any -rc.N
	} else {
		rc, _ = strconv.Atoi(m[4])
	}
	return
}

// migrationUpBlobHashInTag fetches `tag` shallowly and returns the sha256 (hex)
// of its migrations/<version>_*.up.{sql,psql} blob. found=false (no error) when
// that release predates version V (no such file in its tree). The hash is the
// sha256 of the raw blob bytes — identical to migrate.sha256File — so it is
// directly comparable to a db.migration.content_hash.
func migrationUpBlobHashInTag(projDir, tag string, version int64) (hash string, found bool, err error) {
	fetch := exec.Command("git", "fetch", "--depth", "1", "origin", "refs/tags/"+tag)
	fetch.Dir = projDir
	if out, ferr := fetch.CombinedOutput(); ferr != nil {
		return "", false, fmt.Errorf("git fetch --depth 1 origin refs/tags/%s: %w: %s", tag, ferr, strings.TrimSpace(string(out)))
	}
	ls := exec.Command("git", "ls-tree", "--name-only", "-r", "FETCH_HEAD", "--", "migrations")
	ls.Dir = projDir
	lsOut, lerr := ls.Output()
	if lerr != nil {
		return "", false, fmt.Errorf("git ls-tree FETCH_HEAD migrations (tag %s): %w", tag, lerr)
	}
	prefix := fmt.Sprintf("migrations/%d_", version)
	var rel string
	for _, name := range strings.Split(strings.TrimSpace(string(lsOut)), "\n") {
		name = strings.TrimSpace(name)
		if strings.HasPrefix(name, prefix) && (strings.HasSuffix(name, ".up.sql") || strings.HasSuffix(name, ".up.psql")) {
			rel = name
			break
		}
	}
	if rel == "" {
		return "", false, nil
	}
	blob := exec.Command("git", "cat-file", "blob", "FETCH_HEAD:"+rel)
	blob.Dir = projDir
	content, berr := blob.Output()
	if berr != nil {
		return "", false, fmt.Errorf("git cat-file blob FETCH_HEAD:%s (tag %s): %w", rel, tag, berr)
	}
	sum := sha256.Sum256(content)
	return hex.EncodeToString(sum[:]), true, nil
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
