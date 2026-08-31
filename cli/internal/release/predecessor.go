package release

import (
	"fmt"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

// stableTagRE matches vYYYY.MM.PATCH with no rc suffix. Private to this file
// (used only by FindLatestStableTagBeforePrefix) — cli/cmd/release_verify.go
// keeps its OWN copy for its unrelated tag-shape validation call sites
// (ValidateStableTag, assertStableMatchesLatestRC). Both encode the same
// fixed vYYYY.MM.PATCH shape; a project-wide rename of that shape is the only
// thing that could make them drift, and would need touching both anyway.
var stableTagRE = regexp.MustCompile(`^v(\d{4})\.(\d{2})\.(\d+)$`)

// TagExistsLocally reports whether tagName resolves to any object in projDir.
//
// Moved from cli/cmd/release_verify.go (STATBUS-329): cli/internal/migrate's
// migrate-down guard needs the same predecessor-resolution chain
// (PickPrereleasePredecessor -> FindLatestStableTagBeforePrefix -> this) that
// cli/cmd/release.go's checkImmutabilityGate already used, and internal/migrate
// cannot import the cmd package (cmd is the top of the import graph). Moving
// here — the lower internal/release package cmd and migrate BOTH already
// import — avoids a second implementation.
func TagExistsLocally(projDir, tagName string) bool {
	cmd := exec.Command("git", "rev-parse", "--verify", "--quiet", "refs/tags/"+tagName)
	cmd.Dir = projDir
	return cmd.Run() == nil
}

// FindLatestStableTagBeforePrefix returns the most recent stable tag whose
// (year, month) is strictly less than the given vYYYY.MM prefix. Used by
// PickPrereleasePredecessor to keep the migration-immutability chain
// unbroken across year-month boundaries — when rc.1 of a new month is
// cut, this function finds the previous month's last stable to diff
// against, closing the gap that previously existed at year-month rollover.
//
// Returns "" with nil error when no qualifying stable exists (the
// very-first-release base case).
//
// "Before" means strictly less than: never returns the current prefix's
// own stables.
//
// Example: prefix="v2026.05" with stables {v2025.12.4, v2026.04.0,
// v2026.04.5, v2026.05.0} returns "v2026.04.5". Stables in v2026.05 are
// excluded; v2026.04.5 beats v2026.04.0 by patch; v2025.12.4 is older
// year-month.
//
// Moved from cli/cmd/release_verify.go (STATBUS-329) — see TagExistsLocally's
// comment for why.
func FindLatestStableTagBeforePrefix(projDir, prefix string) (string, error) {
	prefixRE := regexp.MustCompile(`^v(\d{4})\.(\d{2})$`)
	pm := prefixRE.FindStringSubmatch(prefix)
	if pm == nil {
		return "", fmt.Errorf("invalid prefix %q (expected vYYYY.MM)", prefix)
	}
	curY, _ := strconv.Atoi(pm[1])
	curM, _ := strconv.Atoi(pm[2])
	curKey := curY*100 + curM

	cmd := exec.Command("git", "tag", "-l", "v*.*.*")
	cmd.Dir = projDir
	outBytes, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("listing stable tags: %w", err)
	}
	bestTag := ""
	bestKey := -1
	bestPatch := -1
	for _, line := range strings.Split(strings.TrimSpace(string(outBytes)), "\n") {
		line = strings.TrimSpace(line)
		sm := stableTagRE.FindStringSubmatch(line)
		if sm == nil {
			continue // skip RC tags and non-stable shapes
		}
		y, _ := strconv.Atoi(sm[1])
		mo, _ := strconv.Atoi(sm[2])
		p, _ := strconv.Atoi(sm[3])
		key := y*100 + mo
		if key >= curKey {
			continue // not strictly less than current prefix
		}
		if key > bestKey || (key == bestKey && p > bestPatch) {
			bestTag = line
			bestKey = key
			bestPatch = p
		}
	}
	return bestTag, nil
}

// ListRCNumbersForPatch returns the sorted list of RC numbers already tagged
// for the given vYYYY.MM.PATCH prefix, excluding excludeTag. Used both to
// compute the next-in-sequence expected number and the previous-tag lookup.
//
// Moved from cli/cmd/release_verify.go (STATBUS-329) — see TagExistsLocally's
// comment for why.
func ListRCNumbersForPatch(projDir, prefix string, patch int, excludeTag string) ([]int, error) {
	pattern := fmt.Sprintf("%s.%d-rc.*", prefix, patch)
	cmd := exec.Command("git", "tag", "-l", pattern)
	cmd.Dir = projDir
	outBytes, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("listing %s: %w", pattern, err)
	}
	var nums []int
	re := regexp.MustCompile(`-rc\.(\d+)$`)
	for _, line := range strings.Split(strings.TrimSpace(string(outBytes)), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || line == excludeTag {
			continue
		}
		m := re.FindStringSubmatch(line)
		if len(m) == 2 {
			if n, err := strconv.Atoi(m[1]); err == nil {
				nums = append(nums, n)
			}
		}
	}
	sort.Ints(nums)
	return nums, nil
}

// PickPrereleasePredecessor returns the tag whose migrations the about-to-
// be-validated (or about-to-be-created) prerelease tag should be diffed
// against for the migration-immutability check. Shared between
// ValidatePrereleaseTag (post-creation re-validation + pre-push hook
// via verify-tag) and releasePrereleaseCmd.RunE (pre-creation
// diagnostic). Single source of truth for the predecessor-finding
// logic — eliminates the prior duplication that let the two call sites
// drift apart on the year-month-rollover edge case.
//
// Behaviour:
//   - rc.N where N > 1 (rcNums non-empty): predecessor is the previous
//     RC in the same year-month-patch series.
//   - rc.1 where patch > 0: predecessor is the stable for the previous
//     patch in the same year-month.
//   - rc.1 where patch == 0: predecessor is the latest stable in any
//     strictly-prior year-month (cross-year-month induction).
//   - rc.1 where patch == 0 with no prior stable anywhere on the
//     repo: returns "" (the very-first-release base case — no
//     immutability comparison possible).
//
// rcNums must be the sorted list of RC numbers already on disk for the
// given prefix/patch combination, EXCLUDING the tag being validated
// (callers obtain via ListRCNumbersForPatch with excludeTag set to the
// current tag at validation time, or "" at pre-creation time).
//
// Moved from cli/cmd/release_verify.go (STATBUS-329) — see TagExistsLocally's
// comment for why.
func PickPrereleasePredecessor(projDir, prefix string, patch int, rcNums []int) (string, error) {
	switch {
	case len(rcNums) > 0:
		// `%02d` matches the canonical zero-padded form used by
		// releasePrereleaseCmd.RunE when creating tags (`-rc.%02d`).
		// Pre-task-#130 this used `%d` and silently constructed
		// non-existent unpadded names — TagExistsLocally returned
		// false and BOTH the pre-creation diagnostic AND
		// ValidatePrereleaseTag's post-creation immutability gate
		// short-circuited their compareMigrationsForTag calls, so the
		// rc.N-vs-rc.(N-1) check was effectively a no-op. The fix is
		// a single-character format-string change, but the consequence
		// was a real (if narrow) safety hole.
		return fmt.Sprintf("%s.%d-rc.%02d", prefix, patch, rcNums[len(rcNums)-1]), nil
	case patch > 0:
		return fmt.Sprintf("%s.%d", prefix, patch-1), nil
	default:
		return FindLatestStableTagBeforePrefix(projDir, prefix)
	}
}

// CurrentImmutabilityBaselineTag resolves the release tag that
// cli/cmd/release.go's checkImmutabilityGate compares HEAD's migrations/
// directory against RIGHT NOW — the single "previous release" for
// immutability purposes, independent of any specific candidate being cut.
//
// STATBUS-329: exported here, not left inline in checkImmutabilityGate, so
// cli/internal/migrate's migrate-down guard can ask the IDENTICAL question
// ("what does 'released' mean, as of today?") instead of re-deriving it a
// second way — two independently-computed answers to "is this migration
// released" would drift silently, which is exactly the failure class this
// function exists to close. checkImmutabilityGate itself now calls this
// function rather than carrying its own copy of the resolution.
//
// Mirrors checkImmutabilityGate's original inline logic exactly: the highest
// STABLE patch tagged this year-month, that next patch's already-tagged RCs,
// and PickPrereleasePredecessor's resolution across its three cases (mid-RC
// series; first RC of a new patch; first RC of a new year-month, via
// FindLatestStableTagBeforePrefix's cross-year-month induction).
//
// Returns ("", nil) when there is no previous release to compare against at
// all (the very-first-release base case) — the same "nothing to check" state
// checkImmutabilityGate treats as an automatic pass.
func CurrentImmutabilityBaselineTag(projDir string) (string, error) {
	now := time.Now()
	prefix := fmt.Sprintf("v%d.%02d", now.Year(), now.Month())

	cmd := exec.Command("git", "tag", "-l", fmt.Sprintf("%s.*", prefix))
	cmd.Dir = projDir
	outBytes, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("listing stable tags: %w", err)
	}
	highestStablePatch := -1
	patchRegex := regexp.MustCompile(fmt.Sprintf(`^%s\.(\d+)$`, regexp.QuoteMeta(prefix)))
	for _, line := range strings.Split(strings.TrimSpace(string(outBytes)), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.Contains(line, "-rc") {
			continue
		}
		if matches := patchRegex.FindStringSubmatch(line); len(matches) == 2 {
			n, _ := strconv.Atoi(matches[1])
			if n > highestStablePatch {
				highestStablePatch = n
			}
		}
	}
	nextPatch := highestStablePatch + 1
	if highestStablePatch < 0 {
		nextPatch = 0
	}

	rcNums, err := ListRCNumbersForPatch(projDir, prefix, nextPatch, "")
	if err != nil {
		return "", fmt.Errorf("listing RC numbers: %w", err)
	}
	prevTag, err := PickPrereleasePredecessor(projDir, prefix, nextPatch, rcNums)
	if err != nil {
		return "", fmt.Errorf("predecessor lookup: %w", err)
	}
	if prevTag == "" || !TagExistsLocally(projDir, prevTag) {
		return "", nil
	}
	return prevTag, nil
}
