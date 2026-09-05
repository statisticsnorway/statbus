package releasecmd

import (
	"fmt"
	"os"
	"path/filepath"
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

// dispatchRefForMasterTip resolves the workflow_dispatch ref for building
// targetSHA when the build branch is master. GitHub's workflow_dispatch
// rejects raw commit SHAs (HTTP 422 "No ref found") — the ref must name a
// branch or tag, and GitHub builds that ref's tip. Returns ("master", true)
// only when origin/master's tip is exactly targetSHA (the normal release
// case; prerelease has already fetched origin/master and gated "up to date
// with origin"). Returns ("", false) when they diverge, so the caller can
// print a tip-mismatch diagnostic instead of a command that would dispatch
// a build of the wrong commit.
func dispatchRefForMasterTip(projDir, targetSHA string) (string, bool) {
	out, err := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "origin/master")
	if err != nil || strings.TrimSpace(out) != targetSHA {
		return "", false
	}
	return "master", true
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
//
// The fix-broken set (versions named in STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION,
// STATBUS-102) skips listed versions from the violation set. Same SOURCE as the
// preflight-side checkMigrationImmutability: release.IntentionallyFixBrokenImmutableMigrationVersions
// reads the env var at the cut. So the pre-create gate AND this post-create /
// pre-push validation (via ValidatePrereleaseTag) agree on what's sanctioned.
func compareMigrationsForTag(projDir, prevTag, tag string) error {
	fixBroken, err := release.IntentionallyFixBrokenImmutableMigrationVersions()
	if err != nil {
		return err
	}

	diffOut, err := upgrade.RunCommandOutput(projDir, "git", "diff",
		"--name-status", prevTag+".."+tag, "--", "migrations/")
	if err != nil {
		return fmt.Errorf("git diff %s..%s: %w", prevTag, tag, err)
	}
	var modified []string
	var fixedBroken []int64
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
		file := parts[1]
		// Filter to actual migration content. Directory placeholders (.gitkeep)
		// and other housekeeping files under migrations/ aren't deployed
		// migrations and don't carry the immutability constraint.
		if !strings.HasSuffix(file, ".up.sql") && !strings.HasSuffix(file, ".down.sql") &&
			!strings.HasSuffix(file, ".up.psql") && !strings.HasSuffix(file, ".down.psql") {
			continue
		}

		// Honour STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION (see header comment).
		if len(fixBroken) > 0 {
			base := filepath.Base(file)
			if underscore := strings.Index(base, "_"); underscore > 0 {
				if v, parseErr := strconv.ParseInt(base[:underscore], 10, 64); parseErr == nil && fixBroken[v] {
					fixedBroken = append(fixedBroken, v)
					continue
				}
			}
		}

		modified = append(modified, parts[0]+" "+file)
	}

	// Log fix-broken activity (one line per unique version, sorted) so
	// pre-push hook output and `release verify-tag` output surface the
	// bypass explicitly. dedupeInt64Sorted lives in release.go (same
	// package).
	for _, v := range dedupeInt64Sorted(fixedBroken) {
		fmt.Printf("⟳ Intentionally fixing broken (immutable) migration %d in %s..%s (%s)\n",
			v, prevTag, tag, release.IntentionallyFixBrokenImmutableMigrationEnvVar)
	}

	if len(modified) == 0 {
		return nil
	}
	return fmt.Errorf("tag %s modifies migrations present in %s:\n  %s\n  migrations are immutable after release — create a new migration instead\n  (or, if intentional and coordinated: %s=<version>[,...])",
		tag, prevTag, strings.Join(modified, "\n  "), release.IntentionallyFixBrokenImmutableMigrationEnvVar)
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
	if !release.TagExistsLocally(projDir, tagName) {
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
	if verifyOut, err := upgrade.RunCommandOutput(projDir, "git", "verify-commit", commit); err != nil {
		short := commit
		if len(short) > 12 {
			short = short[:12]
		}
		return "", fmt.Errorf("commit %s (target of %s) failed signature verification — all release commits must be signed.\n  output: %s\n  Fix: sign the commit (git commit --amend --no-edit -S) and re-tag",
			short, tagName, strings.TrimSpace(verifyOut))
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
	if release.TagExistsLocally(projDir, stableTag) {
		return fmt.Errorf("stable tag %s already exists — cannot create another RC for the same patch", stableTag)
	}

	rcNums, err := release.ListRCNumbersForPatch(projDir, prefix, patch, tagName)
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

	// Migration immutability: diff vs the predecessor returned by
	// release.PickPrereleasePredecessor. The helper handles all three cases
	// (prior RC in same patch, prior stable patch, prior year-month
	// stable for rc.1-patch-0) so the cross-year-month induction is
	// unbroken — prior to task #124 this branch had a gap at
	// rc.1-patch-0 (year-month rollover with no prior RC in the new
	// month and patch == 0) that silently skipped the check.
	prevTag, err := release.PickPrereleasePredecessor(projDir, prefix, patch, rcNums)
	if err != nil {
		return err
	}
	if prevTag != "" && release.TagExistsLocally(projDir, prevTag) {
		if err := compareMigrationsForTag(projDir, prevTag, tagName); err != nil {
			return err
		}
	}
	return nil
}

// ValidateStableTag checks that tagName, which must already exist locally,
// matches every TAG-SHAPE invariant ./sb release stable enforces at
// creation time:
//
//   - annotated tag whose subject is exactly "Release <tagName>"
//   - target commit passes git verify-commit
//   - name matches vYYYY.MM.PATCH
//   - PATCH is the next-in-sequence stable patch for vYYYY.MM
//   - at least one RC exists for this patch
//   - stable's target commit equals the latest RC's target commit
//     (enforces the "stable IS a promotion" contract; refuses
//     hand-rolled stable tags at any other commit)
//
// Artifact readiness (the latest RC's GitHub Release assets + ghcr
// manifests) is NOT checked here. That gate fires once in
// releaseStableCmd's pre-flight BEFORE the tag is created
// (checkRCArtifactGate). Folding it into ValidateStableTag is wrong
// for two reasons:
//
//  1. Pre-push-hook usage: the hook validates the tag right before
//     `git push origin <tag>`. By that point CI artifacts must
//     already be there (the stable tag was created from the same RC
//     that triggered them). A second probe here is redundant network
//     I/O and turns transient GitHub API blips into push failures.
//
//  2. Operator flow: failing post-create leaves a dangling local tag
//     that must be deleted before the operator can retry. The right
//     place to refuse on missing artifacts is BEFORE creating the
//     tag, which is exactly what checkRCArtifactGate does.
//
// Migration immutability vs the previous stable is also not checked
// here: the property is guaranteed by induction through the RC chain
// — each RC compares against its predecessor (rc.N vs rc.N-1, or
// rc.1 vs latest prior stable across year-months). Stable at the
// RC's commit inherits the RC's verified chain by construction.
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

	// Every stable must be promoted from an RC series — and not just
	// "an RC exists" but the stable's target commit must EQUAL the
	// latest RC's target commit. Catches hand-rolled stable tags at
	// HEAD or any other commit (bypassing `./sb release stable`).
	if _, err := assertStableMatchesLatestRC(projDir, tagName); err != nil {
		return err
	}
	return nil
}

// assertStableMatchesLatestRC enforces the "stable IS a promotion" contract:
// the stable tag's target commit MUST equal the latest RC's target commit
// for the same year-month-patch. Catches hand-rolled stable tags at
// HEAD or any other commit that bypass `./sb release stable`'s
// promote-from-RC flow.
//
// Returns the latest-RC tag name on success (caller can use it for
// downstream checks like CheckAssets / CheckManifests without re-listing).
//
// Tag-shape parsing is the caller's responsibility — this function
// assumes tagName has already been matched against stableTagRE.
//
// Refactored from inline logic in ValidateStableTag (task #124) so the
// commit-equality rule can be unit-tested without standing up a full
// signed-tag fixture.
func assertStableMatchesLatestRC(projDir, tagName string) (string, error) {
	m := stableTagRE.FindStringSubmatch(tagName)
	if m == nil {
		return "", fmt.Errorf("tag %q does not match vYYYY.MM.PATCH (caller must validate before calling assertStableMatchesLatestRC)", tagName)
	}
	year, _ := strconv.Atoi(m[1])
	monthStr := m[2]
	patch, _ := strconv.Atoi(m[3])
	prefix := fmt.Sprintf("v%d.%s", year, monthStr)

	rcPattern := fmt.Sprintf("%s.%d-rc.*", prefix, patch)
	rcOut, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-l", rcPattern)
	if err != nil {
		return "", fmt.Errorf("listing %s: %w", rcPattern, err)
	}
	if strings.TrimSpace(rcOut) == "" {
		return "", fmt.Errorf("stable %s has no RC series (%s) — every stable must be promoted from an RC", tagName, rcPattern)
	}
	latestRC := resolveLatestRC(rcOut)
	if latestRC == "" {
		return "", fmt.Errorf("stable %s has no parseable RC in %s", tagName, rcPattern)
	}

	rcCommit, err := tagTargetCommit(projDir, latestRC)
	if err != nil {
		return "", fmt.Errorf("resolving %s target commit: %w", latestRC, err)
	}
	stableCommit, err := tagTargetCommit(projDir, tagName)
	if err != nil {
		return "", fmt.Errorf("resolving %s target commit: %w", tagName, err)
	}
	if stableCommit != rcCommit {
		stableShort := stableCommit
		if len(stableShort) > 12 {
			stableShort = stableShort[:12]
		}
		rcShort := rcCommit
		if len(rcShort) > 12 {
			rcShort = rcShort[:12]
		}
		return "", fmt.Errorf(
			"stable %s target commit (%s) does not match latest RC %s target commit (%s).\n"+
				"  A stable release must tag the same commit as the RC it promotes.\n"+
				"  Re-tag at the RC's commit: git tag -d %s && git tag -s -m \"Release %s\" %s %s\n"+
				"  (If the RC tag is missing locally: git fetch origin --tags)",
			tagName, stableShort, latestRC, rcShort, tagName, tagName, tagName, rcCommit)
	}
	return latestRC, nil
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
stable not at the latest RC's commit, modified migrations.

Pure tag-shape validation (no GitHub API calls beyond signature
verification). Artifact readiness — GitHub Release assets, ghcr
manifests — is verified separately by ./sb release check <tag>.

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

// releaseVerifyImagesCmd queries GitHub Actions for the images.yaml workflow
// state at a commit. Replaces the slow local `docker build --target=…-builder`
// replay that used to gate `git push` in .githooks/pre-push: CI is the source
// of truth that the Docker artifacts can actually be built, and the local
// replay duplicated that work.
//
// The guard remains in the hook — the hook just calls this subcommand
// instead of running docker — so the operator sees an explicit "block + guide"
// step rather than a silent fast-path.
var releaseVerifyImagesCmd = &cobra.Command{
	Use:   "verify-images <commit-sha>",
	Short: "Verify the images workflow is green for the given commit",
	Long: `Query GitHub Actions for the images.yaml workflow at <commit-sha>.
Exit 0 if the latest run is completed/success; non-zero with operator-actionable
guidance otherwise. <commit-sha> must be the full 40-char SHA — the GitHub API
silently returns zero matches for short SHAs.

This is the fast tag-push gate in .githooks/pre-push. It does not build, fetch,
or replay anything locally; it just asks GitHub what its own CI said.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		sha := args[0]
		if len(sha) != 40 {
			return fmt.Errorf("commit-sha must be the full 40-char SHA (got %d chars: %q)\n  Fix: pass `git rev-list -1 <ref>` output, not a short SHA", len(sha), sha)
		}
		shortSHA := sha[:12]
		result := release.CheckWorkflowAtCommit(release.WorkflowImages, sha)
		switch result.Status {
		case release.WorkflowCheckGreen:
			if result.BypassReason != "" {
				// SKIP_IMAGES bypass — print a loud warning before
				// returning success. The pre-push hook gates on exit
				// code 0; the warning still lands on stderr so the
				// operator can't miss the bypass in the transcript.
				fmt.Fprintln(os.Stderr, "")
				fmt.Fprintln(os.Stderr, "⚠⚠⚠  images check BYPASSED for "+shortSHA)
				fmt.Fprintln(os.Stderr, "     "+result.BypassReason)
				fmt.Fprintln(os.Stderr, "")
				return nil
			}
			fmt.Printf("OK: images green at %s\n  Run: %s\n", shortSHA, result.RunURL)
			return nil
		case release.WorkflowCheckPending:
			return fmt.Errorf("images is still pending at %s\n  Watch: gh run watch %d\n  URL:   %s\n  Fix: wait for the run to complete, then retry the push", shortSHA, result.RunID, result.RunURL)
		case release.WorkflowCheckFailed:
			return fmt.Errorf("images failed at %s (conclusion: %s)\n  See: gh run view %d --log-failed\n  URL: %s\n  Fix:\n    Retry the failed jobs (if transient — network, ghcr.io timeout): gh run rerun --failed %d\n    Or push a fix to master (if real defect), then retry the push", shortSHA, result.Detail, result.RunID, result.RunURL, result.RunID)
		case release.WorkflowCheckMissing:
			if ref, ok := dispatchRefForMasterTip(config.ProjectDir(), sha); ok {
				return fmt.Errorf("images has not run for %s\n  Trigger: %s\n  Watch:   %s\n  Fix: run the trigger command above, wait for green, then retry the push", shortSHA, release.WorkflowTriggerCommand(release.WorkflowImages, ref), release.WorkflowURL(release.WorkflowImages))
			}
			return fmt.Errorf("images has not run for %s\n  %s is not origin/master's tip — workflow_dispatch builds a branch/tag tip, not a bare SHA.\n  Fix: push this commit to master (images builds on push), then retry the push", shortSHA, shortSHA)
		case release.WorkflowCheckUnknown:
			return fmt.Errorf("images status check failed (GitHub API error)\n  Detail: %s\n  Fix: check network connectivity / GITHUB_TOKEN, or retry shortly", result.Detail)
		}
		return fmt.Errorf("unexpected images status: %q", result.Status)
	},
}

// tagIsAncestorOfHEAD reports whether refs/tags/<tagName> is an ancestor of
// HEAD — i.e. whether the two share the ancestry that makes a tree comparison
// between them mean anything (STATBUS-233).
//
// It exists because git will diff ANY two commits, related or not, and return a
// confident-looking answer. After this repository's 2026-07-14 rebaseline the
// pre-rebaseline stable tags are on a graph HEAD never descended from, so a diff
// against one reports every re-committed file as "modified". A gate that reads
// such a diff as a verdict is asserting something it has no basis for.
//
// `git merge-base --is-ancestor A B` exits 0 when A is an ancestor of B and 1
// when it is not; any OTHER failure (bad ref, unreadable repo) is returned as an
// error so the caller can refuse on the uncertainty rather than silently reading
// "not an ancestor" as a fact.
func tagIsAncestorOfHEAD(projDir, tagName string) (bool, error) {
	if !release.TagExistsLocally(projDir, tagName) {
		return false, fmt.Errorf("tag %s does not exist locally", tagName)
	}
	if _, err := upgrade.RunCommandOutput(projDir, "git", "merge-base", "--is-ancestor", tagName, "HEAD"); err != nil {
		// Distinguish "not an ancestor" (exit 1, the answer) from a real failure.
		// rev-parse of both ends succeeding means the refs are readable, so a
		// non-zero exit here is the honest negative rather than a broken repo.
		if _, rerr := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "--verify", "--quiet", tagName+"^{commit}"); rerr != nil {
			return false, fmt.Errorf("resolve %s: %w", tagName, rerr)
		}
		if _, rerr := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "--verify", "--quiet", "HEAD^{commit}"); rerr != nil {
			return false, fmt.Errorf("resolve HEAD: %w", rerr)
		}
		return false, nil
	}
	return true, nil
}
