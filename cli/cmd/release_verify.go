package cmd

import (
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/release"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// prereleaseTagRE matches vYYYY.MM.PATCH-rc.N. Month is two digits.
// Patch and RC number are unbounded positive integers.
var prereleaseTagRE = regexp.MustCompile(`^v(\d{4})\.(\d{2})\.(\d+)-rc\.(\d+)$`)

// stableTagRE matches vYYYY.MM.PATCH with no rc suffix.
var stableTagRE = regexp.MustCompile(`^v(\d{4})\.(\d{2})\.(\d+)$`)

// tagExistsLocally reports whether tagName resolves to any object in projDir.
func tagExistsLocally(projDir, tagName string) bool {
	_, err := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "--verify", "--quiet", "refs/tags/"+tagName)
	return err == nil
}

// tagIsAnnotated reports whether refs/tags/<tagName> points at a tag object
// (annotated tag) rather than a commit object (lightweight tag).
func tagIsAnnotated(projDir, tagName string) bool {
	out, err := upgrade.RunCommandOutput(projDir, "git", "cat-file", "-t", "refs/tags/"+tagName)
	if err != nil {
		return false
	}
	return strings.TrimSpace(out) == "tag"
}

// tagTargetCommit returns the commit SHA that tagName points at, peeling
// through the tag object for annotated tags.
func tagTargetCommit(projDir, tagName string) (string, error) {
	out, err := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "refs/tags/"+tagName+"^{commit}")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

// tagMessageSubject returns the first line (subject) of an annotated tag's
// message. Returns "" for lightweight tags.
func tagMessageSubject(projDir, tagName string) (string, error) {
	out, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-l", "--format=%(contents:subject)", tagName)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

// compareMigrationsForTag diffs the migrations/ directory between prevTag
// and tag. Additions are allowed; modifications or deletions of files that
// existed in prevTag are immutability violations and surface as an error.
func compareMigrationsForTag(projDir, prevTag, tag string) error {
	diffOut, err := upgrade.RunCommandOutput(projDir, "git", "diff",
		"--name-status", prevTag+".."+tag, "--", "migrations/")
	if err != nil {
		return fmt.Errorf("git diff %s..%s: %w", prevTag, tag, err)
	}
	var modified []string
	for _, line := range strings.Split(strings.TrimSpace(diffOut), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "\t", 2)
		if len(parts) != 2 {
			continue
		}
		if parts[0] == "A" {
			continue
		}
		modified = append(modified, parts[0]+" "+parts[1])
	}
	if len(modified) == 0 {
		return nil
	}
	return fmt.Errorf("tag %s modifies migrations present in %s:\n  %s\n  migrations are immutable after release — create a new migration instead",
		tag, prevTag, strings.Join(modified, "\n  "))
}

// listRCNumbersForPatch returns the sorted list of RC numbers already tagged
// for the given vYYYY.MM.PATCH prefix, excluding excludeTag. Used both to
// compute the next-in-sequence expected number and the previous-tag lookup.
func listRCNumbersForPatch(projDir, prefix string, patch int, excludeTag string) ([]int, error) {
	pattern := fmt.Sprintf("%s.%d-rc.*", prefix, patch)
	out, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-l", pattern)
	if err != nil {
		return nil, fmt.Errorf("listing %s: %w", pattern, err)
	}
	var nums []int
	re := regexp.MustCompile(`-rc\.(\d+)$`)
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
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

// listStablePatchesForPrefix returns the sorted list of stable patch numbers
// tagged for the given vYYYY.MM prefix, excluding excludeTag.
func listStablePatchesForPrefix(projDir, prefix, excludeTag string) ([]int, error) {
	pattern := fmt.Sprintf("%s.*", prefix)
	out, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-l", pattern)
	if err != nil {
		return nil, fmt.Errorf("listing %s: %w", pattern, err)
	}
	var nums []int
	re := regexp.MustCompile(fmt.Sprintf(`^%s\.(\d+)$`, regexp.QuoteMeta(prefix)))
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || line == excludeTag || strings.Contains(line, "-rc") {
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

// verifyCommonTagShape validates the properties every release tag must have
// regardless of kind: exists locally, is annotated, subject matches the
// expected pattern for its kind, and the target commit is signed.
func verifyCommonTagShape(projDir, tagName, expectedSubject string) (commit string, err error) {
	if !tagExistsLocally(projDir, tagName) {
		return "", fmt.Errorf("tag %s does not exist locally", tagName)
	}
	if !tagIsAnnotated(projDir, tagName) {
		return "", fmt.Errorf("tag %s is a lightweight tag — release tags must be annotated (created with 'git tag -m ...')", tagName)
	}
	subj, err := tagMessageSubject(projDir, tagName)
	if err != nil {
		return "", fmt.Errorf("reading tag subject for %s: %w", tagName, err)
	}
	if subj != expectedSubject {
		return "", fmt.Errorf("tag %s subject is %q, expected %q", tagName, subj, expectedSubject)
	}
	commit, err = tagTargetCommit(projDir, tagName)
	if err != nil {
		return "", fmt.Errorf("resolving %s^{commit}: %w", tagName, err)
	}
	if _, err := upgrade.RunCommandOutput(projDir, "git", "verify-commit", commit); err != nil {
		short := commit
		if len(short) > 12 {
			short = short[:12]
		}
		return "", fmt.Errorf("commit %s (target of %s) failed signature verification — all release commits must be signed.\n  Fix: sign the commit (git commit --amend --no-edit -S) and re-tag.", short, tagName)
	}
	return commit, nil
}

// ValidatePrereleaseTag checks that tagName, which must already exist locally,
// matches every invariant ./sb release prerelease enforces at creation time:
//
//   - annotated tag whose subject is exactly "Pre-release <tagName>"
//   - target commit passes git verify-commit (signed)
//   - name matches vYYYY.MM.PATCH-rc.N
//   - N equals the next-in-sequence RC number for vYYYY.MM.PATCH
//   - no stable vYYYY.MM.PATCH already exists
//   - migrations between the previous RC (or previous stable if this is rc.1
//     for patch > 0) and this tag are additions only
//
// Returns nil on success; a detailed error on failure.
func ValidatePrereleaseTag(projDir, tagName string) error {
	m := prereleaseTagRE.FindStringSubmatch(tagName)
	if m == nil {
		return fmt.Errorf("tag %q does not match vYYYY.MM.PATCH-rc.N", tagName)
	}
	year, _ := strconv.Atoi(m[1])
	monthStr := m[2]
	patch, _ := strconv.Atoi(m[3])
	rcNum, _ := strconv.Atoi(m[4])

	if _, err := verifyCommonTagShape(projDir, tagName, "Pre-release "+tagName); err != nil {
		return err
	}

	prefix := fmt.Sprintf("v%d.%s", year, monthStr)
	stableTag := fmt.Sprintf("%s.%d", prefix, patch)
	if tagExistsLocally(projDir, stableTag) {
		return fmt.Errorf("stable tag %s already exists — cannot create another RC for the same patch", stableTag)
	}

	rcNums, err := listRCNumbersForPatch(projDir, prefix, patch, tagName)
	if err != nil {
		return err
	}
	expected := 1
	if len(rcNums) > 0 {
		expected = rcNums[len(rcNums)-1] + 1
	}
	if rcNum != expected {
		return fmt.Errorf("tag %s is rc.%d but next-in-sequence is rc.%d (existing RCs for %s.%d: %v)",
			tagName, rcNum, expected, prefix, patch, rcNums)
	}

	// Migration immutability: compare vs previous RC (if any) or previous
	// stable patch (if this is rc.1 for patch > 0).
	var prevTag string
	switch {
	case len(rcNums) > 0:
		prevTag = fmt.Sprintf("%s.%d-rc.%d", prefix, patch, rcNums[len(rcNums)-1])
	case patch > 0:
		prevTag = fmt.Sprintf("%s.%d", prefix, patch-1)
	}
	if prevTag != "" && tagExistsLocally(projDir, prevTag) {
		if err := compareMigrationsForTag(projDir, prevTag, tagName); err != nil {
			return err
		}
	}
	return nil
}

// ValidateStableTag checks that tagName, which must already exist locally,
// matches every invariant ./sb release stable enforces at creation time:
//
//   - annotated tag whose subject is exactly "Release <tagName>"
//   - target commit passes git verify-commit
//   - name matches vYYYY.MM.PATCH
//   - PATCH is the next-in-sequence stable patch for vYYYY.MM
//   - at least one RC exists for this patch
//   - the latest RC's CI artifacts (GitHub assets + ghcr manifests) are all present
//   - migrations between the previous stable and this tag are additions only
func ValidateStableTag(projDir, tagName string) error {
	m := stableTagRE.FindStringSubmatch(tagName)
	if m == nil {
		return fmt.Errorf("tag %q does not match vYYYY.MM.PATCH", tagName)
	}
	year, _ := strconv.Atoi(m[1])
	monthStr := m[2]
	patch, _ := strconv.Atoi(m[3])

	if _, err := verifyCommonTagShape(projDir, tagName, "Release "+tagName); err != nil {
		return err
	}

	prefix := fmt.Sprintf("v%d.%s", year, monthStr)

	patches, err := listStablePatchesForPrefix(projDir, prefix, tagName)
	if err != nil {
		return err
	}
	expected := 0
	if len(patches) > 0 {
		expected = patches[len(patches)-1] + 1
	}
	if patch != expected {
		return fmt.Errorf("tag %s uses patch %d but next-in-sequence is %d (existing stable patches for %s: %v)",
			tagName, patch, expected, prefix, patches)
	}

	// Every stable must be promoted from an RC series.
	rcPattern := fmt.Sprintf("%s.%d-rc.*", prefix, patch)
	rcOut, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-l", rcPattern)
	if err != nil {
		return fmt.Errorf("listing %s: %w", rcPattern, err)
	}
	if strings.TrimSpace(rcOut) == "" {
		return fmt.Errorf("stable %s has no RC series (%s) — every stable must be promoted from an RC", tagName, rcPattern)
	}
	latestRC := resolveLatestRC(rcOut)
	if latestRC == "" {
		return fmt.Errorf("stable %s has no parseable RC in %s", tagName, rcPattern)
	}

	// CI artifacts for the latest RC must all be present.
	var missing []string
	for _, r := range release.CheckAssets(latestRC) {
		if !r.OK {
			missing = append(missing, "asset "+r.Name+": "+r.Err)
		}
	}
	for _, r := range release.CheckManifests(latestRC) {
		if !r.OK {
			missing = append(missing, "manifest "+r.Name+": "+r.Err)
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("latest RC %s is missing CI artifacts — cannot promote to stable:\n  %s\n  Fix: wait for CI to finish, or cut a new RC and retry",
			latestRC, strings.Join(missing, "\n  "))
	}

	if len(patches) > 0 {
		prevStable := fmt.Sprintf("%s.%d", prefix, patches[len(patches)-1])
		if tagExistsLocally(projDir, prevStable) {
			if err := compareMigrationsForTag(projDir, prevStable, tagName); err != nil {
				return err
			}
		}
	}
	return nil
}

// releaseVerifyTagCmd is the thin CLI wrapper around ValidatePrereleaseTag /
// ValidateStableTag. Intended for use by the pre-push hook and any CI that
// wants to gate on "would this tag have been created by ./sb release ...?".
var releaseVerifyTagCmd = &cobra.Command{
	Use:   "verify-tag <tag>",
	Short: "Validate an existing tag matches what ./sb release would have created",
	Long: `Validate that <tag> — which must already exist locally — looks like
something ./sb release prerelease or ./sb release stable would have created.

Catches hand-rolled tags that bypass pre-creation checks: unsigned commit,
lightweight tag, wrong subject, wrong name format, skipped RC number,
stable before RC, modified migrations, missing CI artifacts.

Exit 0 on success, 1 with diagnostic on failure. No side effects.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		tag := args[0]
		if strings.Contains(tag, "-rc.") {
			if err := ValidatePrereleaseTag(projDir, tag); err != nil {
				return err
			}
			fmt.Printf("OK: %s is a valid prerelease tag\n", tag)
			return nil
		}
		if err := ValidateStableTag(projDir, tag); err != nil {
			return err
		}
		fmt.Printf("OK: %s is a valid stable tag\n", tag)
		return nil
	},
}

func init() {
	releaseCmd.AddCommand(releaseVerifyTagCmd)
}
