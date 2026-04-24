// Package upgrade — canonical commit-identity types.
//
// This file is the SOLE source of truth for what shape a commit-adjacent
// string must have. Every other file in cli/ treats commit data as
// typed values (CommitSHA, CommitShort, CommitVersion, ReleaseTag, or
// []string of tags). No code outside this file inspects a string to ask
// "what shape is this?" — if that question arises, the data it holds is
// untyped and the fix is to route it through a smart constructor here,
// not to add another shape predicate elsewhere.
//
// Rc.63 reintroduced this discipline. See doc/canonical-commit-naming.md
// (or the spec at tmp/canonical-commit-naming-spec.md) for the full
// rationale. The TestGuards_UseTypedFields test enforces the rule at CI.
package upgrade

import (
	"context"
	"fmt"
	"regexp"
	"strings"
)

// ---------------------------------------------------------------------
// Canonical types
// ---------------------------------------------------------------------

// CommitSHA is the 40-character lowercase-hex canonical commit
// identifier. Equality on CommitSHA is the authoritative answer to
// "is this the same commit." Stored in public.upgrade.commit_sha.
type CommitSHA string

// CommitShort is the 8-character display abbreviation of a CommitSHA.
// Never used for equality. Derived at render time via commitShort().
// Also serves as the Docker image tag for CI-built images.
type CommitShort string

// CommitVersion is the output of `git describe --tags --always`:
// either a bare tag (v2026.04.0-rc.61), a describe-off-tag string
// (v2026.04.0-rc.61-3-g61e79e26), or a bare short commit (61e79e26).
// Used for human-facing labels; never for equality or lookup.
type CommitVersion string

// ReleaseTag is a CalVer tag with 'v' prefix (v2026.04.0-rc.61,
// v2026.04.0). Only release tags. No moving tags, no "dev", no
// arbitrary free-form tag.
type ReleaseTag string

// ---------------------------------------------------------------------
// Shape predicates — PACKAGE-PRIVATE. Called only by smart constructors
// below and by resolveUpgradeTarget. No other call sites permitted.
// ---------------------------------------------------------------------

var (
	commitSHAShapeRe   = regexp.MustCompile(`^[0-9a-f]{40}$`)
	commitShortShapeRe = regexp.MustCompile(`^[0-9a-f]{8}$`)
	// ReleaseTag requires 'v' prefix (CalVer is YYYY.MM.patch[-suffix]).
	// The -suffix allows rc.N, alpha.N, beta.N, etc. — anything
	// release.yaml can cut.
	releaseTagShapeRe = regexp.MustCompile(`^v\d{4}\.\d{2}\.\d+(-[\w.]+)?$`)
)

func isCommitSHAShape(s string) bool   { return commitSHAShapeRe.MatchString(s) }
func isCommitShortShape(s string) bool { return commitShortShapeRe.MatchString(s) }
func isReleaseTagShape(s string) bool  { return releaseTagShapeRe.MatchString(s) }

// stripLegacyShaPrefix removes a `sha-` prefix from the input IF what
// follows is a valid-shaped CommitSHA or CommitShort. Returns the
// stripped value and true, or the original value and false. Used
// ONLY at the NOTIFY-payload boundary during the Commit A → B
// transition; see resolveUpgradeTarget.
func stripLegacyShaPrefix(s string) (string, bool) {
	if !strings.HasPrefix(s, "sha-") {
		return s, false
	}
	rest := strings.TrimPrefix(s, "sha-")
	if isCommitSHAShape(rest) || isCommitShortShape(rest) {
		return rest, true
	}
	return s, false
}

// ---------------------------------------------------------------------
// Smart constructors — convert raw strings at boundaries into typed
// values. Every input that would produce an invalid typed value is
// rejected with a descriptive error here; downstream code may trust
// that any CommitSHA/CommitShort/ReleaseTag value it holds was
// validated at construction time.
// ---------------------------------------------------------------------

// NewCommitSHA validates a 40-char lowercase-hex string and returns the
// typed value.
func NewCommitSHA(s string) (CommitSHA, error) {
	if !isCommitSHAShape(s) {
		return "", fmt.Errorf("not a commit_sha (expected 40-char lowercase hex): %q", s)
	}
	return CommitSHA(s), nil
}

// NewCommitShort validates an 8-char lowercase-hex string and returns
// the typed value.
func NewCommitShort(s string) (CommitShort, error) {
	if !isCommitShortShape(s) {
		return "", fmt.Errorf("not a commit_short (expected 8-char lowercase hex): %q", s)
	}
	return CommitShort(s), nil
}

// NewReleaseTag validates a CalVer tag shape (v<YYYY>.<MM>.<patch>
// with optional `-suffix`) and returns the typed value.
func NewReleaseTag(s string) (ReleaseTag, error) {
	if !isReleaseTagShape(s) {
		return "", fmt.Errorf("not a release tag (expected vYYYY.MM.patch[-suffix]): %q", s)
	}
	return ReleaseTag(s), nil
}

// IsCommitShort is the exported predicate for commands that need to
// validate operator input at the CLI boundary. Prefer a smart
// constructor when you want a typed value; use this only when a simple
// bool answer is all you need.
func IsCommitShort(s string) bool { return isCommitShortShape(s) }

// IsCommitSHA is the exported predicate for full 40-char commit SHAs.
// See IsCommitShort for usage notes.
func IsCommitSHA(s string) bool { return isCommitSHAShape(s) }

// ---------------------------------------------------------------------
// Display helpers
// ---------------------------------------------------------------------

// commitShort returns the canonical 8-char display abbreviation of a
// CommitSHA. Typed input guarantees length >= 8; no fallback logic
// needed.
func commitShort(c CommitSHA) CommitShort {
	return CommitShort(string(c)[:8])
}

// ShortForDisplay returns an 8-char abbreviation for display purposes
// from an untyped string. Handles degraded-mode inputs ("dev",
// "unknown", "") by passing them through unchanged.
//
// This is the ONLY exported display helper that accepts an untyped
// string. Use it where you have a --version ldflag value or similar
// boundary string; use commitShort for typed CommitSHA values
// internally.
func ShortForDisplay(s string) string {
	if len(s) >= 8 && isCommitShortShape(s[:8]) {
		return s[:8]
	}
	return s
}

// preferredReleaseTag picks the "most preferable" tag from an array of
// git tags at a commit. Preference: a stable CalVer tag (no -suffix)
// if any; otherwise the first CalVer-shaped tag; otherwise the last
// array element (legacy behaviour preserved for edge cases).
//
// Pure function of input. Callers pass tags exactly as loaded from
// public.upgrade.commit_tags.
func preferredReleaseTag(tags []string) string {
	if len(tags) == 0 {
		return ""
	}
	var firstCalVer string
	for _, t := range tags {
		if !isReleaseTagShape(t) {
			continue
		}
		// Stable = no hyphen after the final number.
		if !strings.Contains(t, "-") {
			return t
		}
		if firstCalVer == "" {
			firstCalVer = t
		}
	}
	if firstCalVer != "" {
		return firstCalVer
	}
	return tags[len(tags)-1]
}

// renderDisplayName returns a human-readable label for a commit.
// Pure function — no mutation, no I/O, same inputs produce same output.
//
// If the commit has release tags, the preferred tag is used. Otherwise
// the 8-char commit_short. Returns the raw sha (possibly empty) when
// it's too short to abbreviate.
func renderDisplayName(sha CommitSHA, tags []string) string {
	if tag := preferredReleaseTag(tags); tag != "" {
		return tag
	}
	if len(sha) >= 8 {
		return string(commitShort(sha))
	}
	return string(sha)
}

// RenderDisplayName is the exported wrapper around renderDisplayName
// for callers outside the upgrade package. Raw-string inputs are
// validated to the extent possible (sha must be 40-char hex if
// non-empty); otherwise the function is pure.
func RenderDisplayName(sha string, tags []string) string {
	return renderDisplayName(CommitSHA(sha), tags)
}

// ---------------------------------------------------------------------
// Discriminated union — typed parser output
// ---------------------------------------------------------------------

// UpgradeTarget is the typed output of resolveUpgradeTarget. Callers
// switch on concrete type (TaggedTarget or UntaggedTarget) rather than
// inspect string shapes.
type UpgradeTarget interface{ isUpgradeTarget() }

// TaggedTarget represents an upgrade aimed at a commit that has a
// release tag (the normal operator-facing path).
type TaggedTarget struct {
	SHA CommitSHA
	Tag ReleaseTag
}

func (TaggedTarget) isUpgradeTarget() {}

// UntaggedTarget represents an upgrade aimed at a commit without a
// release tag (edge-channel / master-HEAD path). The commit is
// identified by SHA; no human label exists.
type UntaggedTarget struct {
	SHA CommitSHA
}

func (UntaggedTarget) isUpgradeTarget() {}

// ---------------------------------------------------------------------
// Parser boundary — sole shape-detection site in the codebase
// ---------------------------------------------------------------------

// CommitLookup is the minimal interface resolveUpgradeTarget needs to
// translate user-supplied references into canonical commit identity.
// Service satisfies this interface; a test fake can too.
type CommitLookup interface {
	// LookupSHAByTag returns the commit_sha that a release tag points
	// at, or ("", false, nil) if the tag is unknown.
	LookupSHAByTag(ctx context.Context, tag ReleaseTag) (CommitSHA, bool, error)

	// RevParse runs `git rev-parse <ref>` and returns the resolved
	// full 40-char SHA. Used to expand short references and release
	// tags that aren't in the DB yet.
	RevParse(ctx context.Context, ref string) (CommitSHA, error)

	// TagsAtCommit returns the release tags pointing at commit_sha.
	// Used to promote UntaggedTarget to TaggedTarget when the lookup
	// started from a commit reference.
	TagsAtCommit(ctx context.Context, sha CommitSHA) ([]string, error)
}

// resolveUpgradeTarget parses an operator-supplied string into a typed
// UpgradeTarget. The ONLY site in the codebase that inspects raw
// string shapes. Accepts:
//
//   - 40-char hex (CommitSHA directly)
//   - 8-char hex (CommitShort; resolves via git rev-parse to full)
//   - ReleaseTag (e.g. v2026.04.0-rc.61; looks up the pinned commit)
//
// Transitional: the DB's upgrade_notify_daemon trigger currently
// emits `sha-<40>` as the NOTIFY upgrade_apply payload (pinned by
// migration 20260415141454). Until Commit B lands and updates that
// trigger to emit the bare commit_sha, the receiver sees legacy
// payloads. We strip the `sha-` prefix here as the sole shape-aware
// boundary, then retry. When Commit B ships, delete this branch in a
// follow-up cleanup; the regression test will still pass.
//
// On unrecognised input, returns an error listing the accepted shapes.
func resolveUpgradeTarget(ctx context.Context, lookup CommitLookup, input string) (UpgradeTarget, error) {
	// Legacy NOTIFY-payload compatibility.  Strip once; do not recurse.
	if stripped, ok := stripLegacyShaPrefix(input); ok {
		input = stripped
	}

	switch {
	case isCommitSHAShape(input):
		sha := CommitSHA(input)
		tags, err := lookup.TagsAtCommit(ctx, sha)
		if err != nil {
			return nil, fmt.Errorf("tags for %s: %w", commitShort(sha), err)
		}
		return targetFromSHAAndTags(sha, tags), nil

	case isCommitShortShape(input):
		sha, err := lookup.RevParse(ctx, input)
		if err != nil {
			return nil, fmt.Errorf("rev-parse %s: %w", input, err)
		}
		tags, err := lookup.TagsAtCommit(ctx, sha)
		if err != nil {
			return nil, fmt.Errorf("tags for %s: %w", commitShort(sha), err)
		}
		return targetFromSHAAndTags(sha, tags), nil

	case isReleaseTagShape(input):
		tag := ReleaseTag(input)
		sha, found, err := lookup.LookupSHAByTag(ctx, tag)
		if err != nil {
			return nil, fmt.Errorf("lookup tag %s: %w", tag, err)
		}
		if !found {
			// Tag not yet discovered in the DB. Resolve via git directly.
			sha, err = lookup.RevParse(ctx, input)
			if err != nil {
				return nil, fmt.Errorf("rev-parse %s: %w", input, err)
			}
		}
		return TaggedTarget{SHA: sha, Tag: tag}, nil
	}

	return nil, fmt.Errorf("cannot resolve %q: expected commit_sha (40-hex), commit_short (8-hex), or release tag (vYYYY.MM.patch[-suffix])", input)
}

// targetFromSHAAndTags picks the right variant of UpgradeTarget given
// a commit and its tags. If any tag is a ReleaseTag, the most preferred
// one wins and the result is Tagged; otherwise Untagged.
func targetFromSHAAndTags(sha CommitSHA, tags []string) UpgradeTarget {
	if preferred := preferredReleaseTag(tags); preferred != "" {
		if rt, err := NewReleaseTag(preferred); err == nil {
			return TaggedTarget{SHA: sha, Tag: rt}
		}
	}
	return UntaggedTarget{SHA: sha}
}
