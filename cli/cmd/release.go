package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/release"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

var releaseCmd = &cobra.Command{
	Use:   "release",
	Short: "Create and push release tags",
	Long: `Create and push release tags for StatBus.

Subcommands:
  prerelease  Tag a new release candidate (vYYYY.MM.0-rc.N)
  stable      Tag a new stable release (vYYYY.MM.PATCH)`,
}

// preflightChecks runs all pre-release validations. Returns true if all pass.
func preflightChecks(projDir string) bool {
	allPassed := true

	// 1. Git working tree is clean (excluding explain/performance baselines which drift per environment)
	_, err1 := upgrade.RunCommandOutput(projDir, "git", "diff", "--quiet", "--", ":!test/expected/explain/", ":!test/expected/performance/")
	_, err2 := upgrade.RunCommandOutput(projDir, "git", "diff", "--cached", "--quiet", "--", ":!test/expected/explain/", ":!test/expected/performance/")
	if err1 != nil || err2 != nil {
		fmt.Println("  ✗ Working tree is clean")
		fmt.Println("    Fix: git stash or git commit")
		allPassed = false
	} else {
		fmt.Println("  ✓ Working tree is clean")
	}

	// 2. On master branch
	branchOut, err := upgrade.RunCommandOutput(projDir, "git", "symbolic-ref", "--short", "HEAD")
	branch := strings.TrimSpace(branchOut)
	if err != nil || branch != "master" {
		fmt.Printf("  ✗ On master branch (current: %s)\n", branch)
		fmt.Println("    Fix: git checkout master")
		allPassed = false
	} else {
		fmt.Println("  ✓ On master branch")
	}

	// 3. Up to date with origin — distinguish direction (ahead/behind/diverged)
	// so the fix suggestion is actionable. The old one-line "Fix: git pull"
	// was wrong half the time.
	_, err = upgrade.RunCommandOutput(projDir, "git", "fetch", "origin", "master", "--quiet")
	if err != nil {
		fmt.Println("  ✗ Up to date with origin (fetch failed)")
		fmt.Println("    Fix: check network connectivity")
		allPassed = false
	} else {
		headOut, _ := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD")
		originOut, _ := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "origin/master")
		head := strings.TrimSpace(headOut)
		origin := strings.TrimSpace(originOut)
		if head == origin {
			fmt.Println("  ✓ Up to date with origin")
		} else {
			aheadOut, _ := upgrade.RunCommandOutput(projDir, "git", "rev-list", "--count", "origin/master..HEAD")
			behindOut, _ := upgrade.RunCommandOutput(projDir, "git", "rev-list", "--count", "HEAD..origin/master")
			ahead := strings.TrimSpace(aheadOut)
			behind := strings.TrimSpace(behindOut)
			switch {
			case ahead != "0" && behind == "0":
				fmt.Printf("  ✗ Up to date with origin (%s commit(s) ahead of origin/master)\n", ahead)
				fmt.Println("    Fix: git push origin master")
			case ahead == "0" && behind != "0":
				fmt.Printf("  ✗ Up to date with origin (%s commit(s) behind origin/master)\n", behind)
				fmt.Println("    Fix: git pull --rebase origin master")
			default:
				fmt.Printf("  ✗ Up to date with origin (diverged: %s ahead, %s behind)\n", ahead, behind)
				fmt.Println("    Fix: git pull --rebase origin master, resolve conflicts, then git push")
			}
			allPassed = false
		}
	}

	// 4. HEAD commit is signed — HARD fail. master has `required_signatures`
	// enabled on GitHub; the only reason unsigned commits land at all is
	// admin bypass. Releases must be signed, always. If verification fails
	// because gpg.ssh.allowedSignersFile isn't configured locally, the fix
	// is to configure it (and sign) — not to ignore the warning.
	_, err = upgrade.RunCommandOutput(projDir, "git", "verify-commit", "HEAD")
	if err != nil {
		headSHA, _ := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "--short", "HEAD")
		fmt.Printf("  ✗ HEAD commit is signed (verification failed on %s)\n", strings.TrimSpace(headSHA))
		fmt.Println("    Fix (sign this commit): git commit --amend --no-edit -S")
		fmt.Println("    Fix (sign all future commits): git config --global commit.gpgsign true")
		fmt.Println("         (requires user.signingkey + gpg.format ssh in your global git config)")
		fmt.Println("    Debug: git verify-commit HEAD")
		allPassed = false
	} else {
		fmt.Println("  ✓ HEAD commit is signed")
	}

	// 5. Go CLI builds
	cliDir := filepath.Join(projDir, "cli")
	_, err = upgrade.RunCommandOutput(cliDir, "go", "build", "-o", "/dev/null", "./...")
	if err != nil {
		fmt.Println("  ✗ Go CLI builds")
		fmt.Println("    Fix: cd cli && go build ./...")
		allPassed = false
	} else {
		fmt.Println("  ✓ Go CLI builds")
	}

	// 6. Fast tests cover latest migrations
	stampPath := filepath.Join(projDir, "tmp", "fast-test-passed-sha")
	stampBytes, err := os.ReadFile(stampPath)
	if err != nil {
		// No local stamp — try CI as fallback.
		headOut, _ := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD")
		headSHA := strings.TrimSpace(headOut)
		if ciPassed := checkCITestPassed(headSHA); ciPassed {
			fmt.Printf("  ✓ Fast tests passed in CI for %s (writing local stamp)\n", headSHA[:12])
			os.MkdirAll(filepath.Join(projDir, "tmp"), 0755)
			os.WriteFile(stampPath, []byte(headSHA+"\n"), 0644)
			stampBytes = []byte(headSHA)
		} else {
			fmt.Println("  ✗ Fast tests cover latest migrations (no local stamp, CI not green)")
			fmt.Println("    Fix: ./dev.sh test fast")
			fmt.Println("    Or wait for pg_regress CI to pass on this commit")
			allPassed = false
		}
	}
	if stampBytes != nil {
		stampSHA := strings.TrimSpace(string(stampBytes))

		// Find the last commit that touched actual migration files.
		// Only match versioned files (YYYYMMDDHHMMSS_*.up.*), not helper
		// files like post_restore.sql which live in migrations/ but aren't migrations.
		lastMigrationOut, _ := upgrade.RunCommandOutput(projDir, "git", "log", "-1", "--format=%H", "--", "migrations/*.up.sql", "migrations/*.up.psql")
		lastMigration := strings.TrimSpace(lastMigrationOut)

		if lastMigration == "" {
			// No migrations at all — tests are fine
			fmt.Println("  ✓ Fast tests cover latest migrations (no migrations found)")
		} else {
			// Check if any new migration files exist between stamp and HEAD.
			// Only match *.up.sql / *.up.psql — post_restore.sql and other
			// helper files in migrations/ are not schema migrations.
			newMigrationsOut, _ := upgrade.RunCommandOutput(projDir, "git", "diff", "--name-only", stampSHA+"..HEAD", "--", "migrations/*.up.sql", "migrations/*.up.psql")
			newMigrations := strings.TrimSpace(newMigrationsOut)

			if newMigrations == "" {
				// No new migrations since test stamp. Also check test/expected drift
				// (explain plans, performance baselines) — both must be clean.
				testExpectedOut, _ := upgrade.RunCommandOutput(projDir, "git", "diff", "--name-only", stampSHA+"..HEAD", "--", "test/expected/")
				testExpectedDrift := strings.TrimSpace(testExpectedOut)

				if testExpectedDrift == "" {
					// No new migrations and no test expected file drift — OK
					shortStamp := stampSHA
					if len(shortStamp) > 12 {
						shortStamp = shortStamp[:12]
					}
					shortMig := lastMigration
					if len(shortMig) > 12 {
						shortMig = shortMig[:12]
					}
					fmt.Printf("  ✓ Fast tests cover latest migrations (stamp: %s, last migration: %s)\n", shortStamp, shortMig)
				} else {
					// Test expected files have drifted (explain plans, performance baselines)
					expectedFiles := strings.Split(testExpectedDrift, "\n")
					fmt.Println("  ✗ Fast tests do not cover test expected file drift")
					fmt.Printf("    %d changed expected file(s):\n", len(expectedFiles))
					for _, f := range expectedFiles {
						if f != "" {
							fmt.Printf("      %s\n", f)
						}
					}
					fmt.Println("    Fix: ./dev.sh test fast")
					allPassed = false
				}
			} else {
				// New migrations exist that weren't tested
				migrationFiles := strings.Split(newMigrations, "\n")
				fmt.Println("  ✗ Fast tests do not cover latest migrations")
				fmt.Printf("    %d untested migration(s):\n", len(migrationFiles))
				for _, f := range migrationFiles {
					if f != "" {
						fmt.Printf("      %s\n", filepath.Base(f))
					}
				}
				fmt.Println("    Fix: ./dev.sh test fast")
				allPassed = false
			}
		}
	}

	// 7. TypeScript types cover latest migrations — checked BEFORE app tsc/build
	//    because stale types hide drift: tsc can pass against a stale
	//    app/src/lib/database.types.ts while the real schema has changed.
	//    Regenerating types first ensures tsc/build stamps reflect the
	//    current schema.
	checkMigrationStamp := func(stampFile, label, fixCmd string) {
		failLabel := label
		if strings.Contains(label, " covers ") {
			failLabel = strings.Replace(label, " covers ", " does not cover ", 1)
		} else if strings.Contains(label, " cover ") {
			failLabel = strings.Replace(label, " cover ", " do not cover ", 1)
		}
		sp := filepath.Join(projDir, "tmp", stampFile)
		sb, err := os.ReadFile(sp)
		if err != nil {
			fmt.Printf("  ✗ %s (tmp/%s not found)\n", failLabel, stampFile)
			fmt.Printf("    Fix: %s\n", fixCmd)
			allPassed = false
			return
		}
		stampSHA := strings.TrimSpace(string(sb))
		newMigrationsOut, _ := upgrade.RunCommandOutput(projDir, "git", "diff", "--name-only",
			stampSHA+"..HEAD", "--", "migrations/*.up.sql", "migrations/*.up.psql")
		newMigrations := strings.TrimSpace(newMigrationsOut)
		if newMigrations == "" {
			short := stampSHA
			if len(short) > 12 {
				short = short[:12]
			}
			fmt.Printf("  ✓ %s (stamp: %s)\n", label, short)
		} else {
			migrationFiles := strings.Split(newMigrations, "\n")
			fmt.Printf("  ✗ %s\n", failLabel)
			fmt.Printf("    %d new migration(s) since stamp:\n", len(migrationFiles))
			for _, f := range migrationFiles {
				if f != "" {
					fmt.Printf("      %s\n", filepath.Base(f))
				}
			}
			fmt.Printf("    Fix: %s\n", fixCmd)
			allPassed = false
		}
	}
	checkMigrationStamp("types-passed-sha", "TypeScript types cover latest migrations", "./sb types generate")

	// 8. App tsc covers latest app changes  (check 9 is app build — same helper)
	//    Stamp written by `cd app && pnpm run tsc` (or `pnpm run build`)
	//    via app/scripts/stamp-if-clean.sh. Preflight refuses to tag if
	//    any file in app/ changed since the stamped SHA — avoids tagging
	//    a release whose TypeScript doesn't type-check.
	checkAppStamp := func(stampFile, cmd, label string) {
		stampPath := filepath.Join(projDir, "tmp", stampFile)
		b, err := os.ReadFile(stampPath)
		if err != nil {
			fmt.Printf("  ✗ %s (tmp/%s not found)\n", label, stampFile)
			fmt.Printf("    Fix: cd app && pnpm run %s\n", cmd)
			allPassed = false
			return
		}
		stampSHA := strings.TrimSpace(string(b))
		out, _ := upgrade.RunCommandOutput(projDir, "git", "diff", "--name-only",
			stampSHA+"..HEAD", "--", "app")
		changed := strings.TrimSpace(out)
		short := stampSHA
		if len(short) > 12 {
			short = short[:12]
		}
		if changed == "" {
			fmt.Printf("  ✓ %s (stamp: %s)\n", label, short)
			return
		}
		files := strings.Split(changed, "\n")
		fmt.Printf("  ✗ %s\n", label)
		fmt.Printf("    %d change(s) in app/ since stamp %s:\n", len(files), short)
		for _, f := range files {
			if f != "" {
				fmt.Printf("      %s\n", f)
			}
		}
		fmt.Printf("    Fix: cd app && pnpm run %s\n", cmd)
		allPassed = false
	}
	checkAppStamp("app-tsc-passed-sha", "tsc", "App tsc covers latest app changes")
	checkAppStamp("app-build-passed-sha", "build", "App build covers latest app changes")

	// 10. Seed freshness gate (auto-regen on stale).
	// Previously this block just reported ✗ and pointed the operator at
	// `./dev.sh update-seed`. That invited every release to be a
	// two-command sequence (update-seed, then prerelease) with the
	// lurking bug that operator skips the first step. Now the preflight
	// DETECTS staleness and RUNS the regen, then re-verifies.
	//
	// Single command: `./sb release prerelease` is now the sole operator
	// step for cutting a release from a clean tree.
	if !checkAndRefreshSeed(projDir) {
		allPassed = false
	}

	// 11. DB documentation covers latest migrations
	checkMigrationStamp("db-docs-passed-sha", "DB documentation covers latest migrations", "./dev.sh generate-db-documentation")

	return allPassed
}

// noSameKindTagAtHEAD refuses to tag a same-kind tag on a commit that
// already carries one. Re-tagging the same commit (an RC twice, or a
// stable twice) bumps the version number without any underlying
// change — wasteful and confusing for downstream tooling.
//
// Cross-kind transitions are fine: tagging vX.Y.Z on top of vX.Y.Z-rc.N
// is the legitimate prerelease → release promotion.
func noSameKindTagAtHEAD(projDir string, isPrerelease bool) error {
	out, err := upgrade.RunCommandOutput(projDir, "git", "tag", "--points-at", "HEAD")
	if err != nil {
		// Couldn't list — let the rest of the flow proceed; the tag-create
		// step itself enforces uniqueness anyway.
		return nil
	}
	for _, tag := range strings.Split(strings.TrimSpace(out), "\n") {
		tag = strings.TrimSpace(tag)
		if tag == "" || !strings.HasPrefix(tag, "v") {
			continue
		}
		isRC := strings.Contains(tag, "-rc.")
		switch {
		case isPrerelease && isRC:
			return fmt.Errorf(
				"HEAD already carries a prerelease tag: %s\n"+
					"  Make a new commit before tagging another RC — bumping the\n"+
					"  number without an underlying change is wasteful.",
				tag)
		case !isPrerelease && !isRC:
			return fmt.Errorf(
				"HEAD already carries a stable release tag: %s\n"+
					"  Make a new commit before tagging another release — bumping\n"+
					"  the patch number without an underlying change is wasteful.",
				tag)
		}
	}
	return nil
}

// checkMigrationImmutability diffs the migrations/ directory between prevTag
// and HEAD. If any migration file that EXISTED in prevTag has been modified
// or deleted, the check fails. New migrations (only in HEAD) are fine.
//
// The diff is tag-to-HEAD, NOT commit-by-commit. A modify+revert sequence
// shows no diff in total — which is correct (the end result is clean).
func checkMigrationImmutability(projDir, prevTag, label string) error {
	// List files in migrations/ that changed between prevTag and HEAD.
	diffOut, err := upgrade.RunCommandOutput(projDir, "git", "diff",
		"--name-status", prevTag+"..HEAD", "--", "migrations/")
	if err != nil {
		return fmt.Errorf("git diff %s..HEAD failed: %w", prevTag, err)
	}
	diff := strings.TrimSpace(diffOut)
	if diff == "" {
		fmt.Printf("  ✓ No migrations modified since %s (%s)\n", prevTag, label)
		return nil
	}

	// Parse the diff output. Format: "M\tmigrations/file" or "D\tmigrations/file"
	// A (added) = new migration, fine. M (modified) or D (deleted) = immutability violation.
	var modified []string
	for _, line := range strings.Split(diff, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, "\t", 2)
		if len(parts) != 2 {
			continue
		}
		status := parts[0]
		file := parts[1]
		if status == "A" {
			continue // new migration — always allowed
		}
		// Filter to actual migration content. Directory placeholders (.gitkeep)
		// and other housekeeping files under migrations/ aren't deployed
		// migrations and don't carry the immutability constraint.
		if !strings.HasSuffix(file, ".up.sql") && !strings.HasSuffix(file, ".down.sql") &&
			!strings.HasSuffix(file, ".up.psql") && !strings.HasSuffix(file, ".down.psql") {
			continue
		}
		modified = append(modified, fmt.Sprintf("  %s %s", status, file))
	}

	if len(modified) == 0 {
		fmt.Printf("  ✓ No migrations modified since %s (%s)\n", prevTag, label)
		return nil
	}

	fmt.Printf("  ✗ Migrations modified since %s (%s)\n", prevTag, label)
	for _, m := range modified {
		fmt.Println("   ", m)
	}
	return fmt.Errorf("migrations modified since %s.\n"+
		"  Deployed migrations are immutable — create a NEW migration instead.\n"+
		"  If the change was intentional, create a corrective migration\n"+
		"  and revert the modification to the original file:\n"+
		"    git checkout %s -- migrations/<file>\n"+
		"    ./sb migrate new --description \"fix_<description>\"", prevTag, prevTag)
}

// findPreviousTag finds the most recent tag matching the pattern that is
// an ancestor of HEAD. Returns "" if none found.
func findPreviousTag(projDir, pattern string, isRC bool) string {
	tagsOut, _ := upgrade.RunCommandOutput(projDir, "git", "tag", "-l", pattern, "--sort=-version:refname")
	for _, tag := range strings.Split(strings.TrimSpace(tagsOut), "\n") {
		tag = strings.TrimSpace(tag)
		if tag == "" {
			continue
		}
		// Skip non-RC tags when looking for RC, and vice versa
		tagIsRC := strings.Contains(tag, "-rc.")
		if isRC != tagIsRC {
			continue
		}
		// Check if this tag is an ancestor of HEAD (i.e., already deployed)
		if _, err := upgrade.RunCommandOutput(projDir, "git", "merge-base", "--is-ancestor", tag, "HEAD"); err == nil {
			return tag
		}
	}
	return ""
}

var releasePrereleaseCmd = &cobra.Command{
	Use:   "prerelease",
	Short: "Tag a new release candidate (vYYYY.MM.PATCH-rc.N)",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		// Sweep stale seed/<sha> branches published by prior releases
		// and operator-local dev-tip runs. See cleanupSeedBranches
		// for the full retention policy (released-and-published → delete;
		// in-flight tagged → retain; untagged ephemeral peer → delete).
		// preserveSHA = HEAD so the seed just generated for this
		// release cut survives the sweep.
		headSHAOut, _ := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD")
		cleanupSeedBranches(projDir, strings.TrimSpace(headSHAOut))

		fmt.Println("Pre-flight checks:")
		if !preflightChecks(projDir) {
			return fmt.Errorf("pre-flight checks failed")
		}
		if err := noSameKindTagAtHEAD(projDir, true); err != nil {
			return err
		}

		// Migration immutability: no modifications to migrations that existed
		// in the previous RC. New migrations are fine.
		now := time.Now()
		immPattern := fmt.Sprintf("v%d.%02d.*-rc.*", now.Year(), now.Month())
		prevRC := findPreviousTag(projDir, immPattern, true)
		if prevRC != "" {
			if err := checkMigrationImmutability(projDir, prevRC, "previous RC"); err != nil {
				return err
			}
		} else {
			fmt.Println("  ✓ No previous RC to check migrations against (first RC this month)")
		}
		fmt.Println()

		// Get current date prefix
		prefix := fmt.Sprintf("v%d.%02d", now.Year(), now.Month())

		// Find the highest stable patch for this month.
		// If v2026.03.0 exists, the next prerelease must be v2026.03.1-rc.1
		// (not another RC for the already-released .0).
		stablePattern := fmt.Sprintf("%s.*", prefix)
		stableTagsOut, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-l", stablePattern)
		if err != nil {
			return fmt.Errorf("listing stable tags: %w", err)
		}

		highestStablePatch := -1
		patchRegex := regexp.MustCompile(fmt.Sprintf(`^%s\.(\d+)$`, regexp.QuoteMeta(prefix)))
		for _, line := range strings.Split(strings.TrimSpace(stableTagsOut), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.Contains(line, "-rc") {
				continue
			}
			matches := patchRegex.FindStringSubmatch(line)
			if len(matches) == 2 {
				n, _ := strconv.Atoi(matches[1])
				if n > highestStablePatch {
					highestStablePatch = n
				}
			}
		}

		// The patch version for the next RC: if no stable exists, use 0.
		// If v2026.03.0 exists, next RC is for patch 1. If v2026.03.1 exists, patch 2.
		nextPatch := highestStablePatch + 1
		if highestStablePatch < 0 {
			nextPatch = 0 // no stable yet — RC for .0
		}

		// List existing RC tags for this patch version
		rcPattern := fmt.Sprintf("%s.%d-rc.*", prefix, nextPatch)
		tagsOut, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-l", rcPattern, "--sort=-version:refname")
		if err != nil {
			return fmt.Errorf("listing tags: %w", err)
		}

		// Parse highest RC number for this patch
		highestRC := 0
		rcRegex := regexp.MustCompile(`-rc\.(\d+)$`)
		for _, line := range strings.Split(strings.TrimSpace(tagsOut), "\n") {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			matches := rcRegex.FindStringSubmatch(line)
			if len(matches) == 2 {
				n, _ := strconv.Atoi(matches[1])
				if n > highestRC {
					highestRC = n
				}
			}
		}

		nextRC := highestRC + 1
		tagName := fmt.Sprintf("%s.%d-rc.%02d", prefix, nextPatch, nextRC)

		// Safety: verify tag doesn't already exist locally or on remote
		if _, err := upgrade.RunCommandOutput(projDir, "git", "rev-parse", tagName); err == nil {
			return fmt.Errorf("tag %s already exists locally — tags are immutable, cannot recreate", tagName)
		}

		// Create tag with message (avoids $EDITOR prompt when tag.gpgsign=true)
		_, err = upgrade.RunCommandOutput(projDir, "git", "tag", "-m", "Pre-release "+tagName, tagName)
		if err != nil {
			return fmt.Errorf("creating tag %s: %w", tagName, err)
		}

		// Re-validate the just-created tag through the same gate the pre-push
		// hook uses. If ValidatePrereleaseTag disagrees with the compute-tag
		// logic above, delete the tag and abort — better to fail locally than
		// to push a malformed tag.
		if err := ValidatePrereleaseTag(projDir, tagName); err != nil {
			_, _ = upgrade.RunCommandOutput(projDir, "git", "tag", "-d", tagName)
			return fmt.Errorf("post-create validation of %s failed: %w", tagName, err)
		}

		// Push tag
		pushOut, err := upgrade.RunCommandOutput(projDir, "git", "push", "origin", tagName)
		if err != nil {
			return fmt.Errorf("pushing tag %s: %w\n  output: %s", tagName, err, strings.TrimSpace(pushOut))
		}

		fmt.Printf("Tagged %s and pushed to origin\n", tagName)
		return nil
	},
}

var releaseStableCmd = &cobra.Command{
	Use:   "stable",
	Short: "Tag a new stable release (vYYYY.MM.PATCH)",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		fmt.Println("Pre-flight checks:")
		allPassed := preflightChecks(projDir)

		// Stable releases also require a passing install test (Multipass VM).
		// Prereleases skip this — too slow for rapid iteration.
		installStampPath := filepath.Join(projDir, "tmp", "install-test-passed-sha")
		installStampBytes, err := os.ReadFile(installStampPath)
		if err != nil {
			fmt.Println("  ✗ Install test passed (tmp/install-test-passed-sha not found)")
			fmt.Println("    Fix: ./dev.sh test-install")
			allPassed = false
		} else {
			installStamp := strings.TrimSpace(string(installStampBytes))
			headOut, _ := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD")
			head := strings.TrimSpace(headOut)
			if installStamp != head {
				shortStamp := installStamp
				if len(shortStamp) > 12 {
					shortStamp = shortStamp[:12]
				}
				shortHead := head
				if len(shortHead) > 12 {
					shortHead = shortHead[:12]
				}
				fmt.Printf("  ✗ Install test does not cover HEAD (stamp: %s, HEAD: %s)\n", shortStamp, shortHead)
				fmt.Println("    Fix: ./dev.sh test-install")
				allPassed = false
			} else {
				fmt.Printf("  ✓ Install test passed (stamp: %s)\n", installStamp[:12])
			}
		}

		if !allPassed {
			return fmt.Errorf("pre-flight checks failed")
		}
		if err := noSameKindTagAtHEAD(projDir, false); err != nil {
			return err
		}

		// Migration immutability: no modifications to migrations that existed
		// in the previous stable release. New migrations are fine.
		now := time.Now()
		stableImmPattern := fmt.Sprintf("v%d.*", now.Year())
		prevStable := findPreviousTag(projDir, stableImmPattern, false)
		if prevStable != "" {
			if err := checkMigrationImmutability(projDir, prevStable, "previous release"); err != nil {
				return err
			}
		} else {
			fmt.Println("  ✓ No previous release to check migrations against (first release)")
		}
		fmt.Println()

		// Get current date prefix (already computed above for immutability check)
		prefix := fmt.Sprintf("v%d.%02d", now.Year(), now.Month())

		// Check that at least one RC exists for this month
		rcPattern := fmt.Sprintf("%s.*-rc.*", prefix)
		rcTagsOut, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-l", rcPattern)
		if err != nil {
			return fmt.Errorf("listing RC tags: %w", err)
		}
		rcTags := strings.TrimSpace(rcTagsOut)
		if rcTags == "" {
			return fmt.Errorf("no pre-release candidates for %s. Tag a prerelease first", prefix)
		}

		// Gate: verify the latest RC's CI artifacts are all published.
		// A stable release that promotes a broken RC is worse than no release.
		latestRC := resolveLatestRC(rcTags)
		if latestRC != "" {
			fmt.Printf("  Checking CI artifacts for %s...\n", latestRC)
			assetResults := release.CheckAssets(latestRC)
			manifestResults := release.CheckManifests(latestRC)
			artifactsOK := true
			for _, r := range assetResults {
				if !r.OK {
					fmt.Printf("  ✗ %s (%s)\n", r.Name, r.Err)
					artifactsOK = false
				}
			}
			for _, r := range manifestResults {
				if !r.OK {
					fmt.Printf("  ✗ %s (%s)\n", r.Name, r.Err)
					artifactsOK = false
				}
			}
			if !artifactsOK {
				return fmt.Errorf("latest RC %s has missing CI artifacts.\n"+
					"  Fix: wait for CI to finish, or cut a new RC and retry.\n"+
					"  Check: ./sb release check --tag %s", latestRC, latestRC)
			}
			fmt.Printf("  ✓ All CI artifacts verified for %s\n", latestRC)
		}

		// Find the patch number from existing stable tags
		stablePattern := fmt.Sprintf("%s.*", prefix)
		stableTagsOut, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-l", stablePattern)
		if err != nil {
			return fmt.Errorf("listing stable tags: %w", err)
		}

		highestPatch := -1
		patchRegex := regexp.MustCompile(fmt.Sprintf(`^%s\.(\d+)$`, regexp.QuoteMeta(prefix)))
		for _, line := range strings.Split(strings.TrimSpace(stableTagsOut), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.Contains(line, "-rc") {
				continue
			}
			matches := patchRegex.FindStringSubmatch(line)
			if len(matches) == 2 {
				n, _ := strconv.Atoi(matches[1])
				if n > highestPatch {
					highestPatch = n
				}
			}
		}

		nextPatch := highestPatch + 1
		tagName := fmt.Sprintf("%s.%d", prefix, nextPatch)

		// Safety: verify tag doesn't already exist locally or on remote
		if _, err := upgrade.RunCommandOutput(projDir, "git", "rev-parse", tagName); err == nil {
			return fmt.Errorf("tag %s already exists locally — tags are immutable, cannot recreate", tagName)
		}

		// Create tag with message (avoids $EDITOR prompt when tag.gpgsign=true)
		_, err = upgrade.RunCommandOutput(projDir, "git", "tag", "-m", "Release "+tagName, tagName)
		if err != nil {
			return fmt.Errorf("creating tag %s: %w", tagName, err)
		}

		// Re-validate the just-created tag through the same gate the pre-push
		// hook uses, so drift between the compute-tag logic and the validator
		// fails locally instead of on push.
		if err := ValidateStableTag(projDir, tagName); err != nil {
			_, _ = upgrade.RunCommandOutput(projDir, "git", "tag", "-d", tagName)
			return fmt.Errorf("post-create validation of %s failed: %w", tagName, err)
		}

		// Push tag
		pushOut, err := upgrade.RunCommandOutput(projDir, "git", "push", "origin", tagName)
		if err != nil {
			return fmt.Errorf("pushing tag %s: %w\n  output: %s", tagName, err, strings.TrimSpace(pushOut))
		}

		fmt.Printf("Tagged %s and pushed to origin\n", tagName)
		return nil
	},
}

// releaseListCmd lists existing release tags for quick reference.
var releaseListCmd = &cobra.Command{
	Use:   "list",
	Short: "List recent release tags",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		tagsOut, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-l", "v*", "--sort=-version:refname")
		if err != nil {
			return fmt.Errorf("listing tags: %w", err)
		}

		tags := strings.Split(strings.TrimSpace(tagsOut), "\n")
		if len(tags) == 0 || (len(tags) == 1 && tags[0] == "") {
			fmt.Println("No release tags found")
			return nil
		}

		// Show up to 20 most recent
		sort.Slice(tags, func(i, j int) bool { return tags[i] > tags[j] })
		limit := 20
		if len(tags) < limit {
			limit = len(tags)
		}
		for _, tag := range tags[:limit] {
			tag = strings.TrimSpace(tag)
			if tag != "" {
				fmt.Println(tag)
			}
		}
		return nil
	},
}

// Release check accepts either --tag (explicit tag to check) or
// --channel (resolve channel → latest tag, then check). Exactly one
// must be set; neither defaults to --channel prerelease for
// backward-compat with pre-rc.63 callers that used the bare `check`
// form.
var (
	releaseCheckTag     string
	releaseCheckChannel string
)

// releaseCheckCmd verifies that all release artifacts (GitHub assets including
// seed, Docker images) exist for a given tag. Intended as a gate in
// cloud.sh and in CI to avoid installing a release that is still being published.
//
// Exit 0: all checks passed.
// Exit 1: one or more checks failed (with "Retry in ~5 minutes" guidance).
var releaseCheckCmd = &cobra.Command{
	Use:   "check",
	Short: "Verify release artifacts are fully published",
	Long: `Check that all artifacts for a release are ready:
  - GitHub Release assets (binaries, checksums, manifest, seed)
  - ghcr.io Docker manifests (app, db, worker, proxy)

Input forms:
  --tag vX                  check a specific tag
  --channel stable          check the latest stable release
  --channel prerelease      check the latest pre-release (default for bare invocation)
  --channel edge            skip — edge builds from source; no release artifacts

Exit 0 when all checks pass (or when --channel edge short-circuits);
exit 1 with retry advice when any check fails.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if releaseCheckTag != "" && releaseCheckChannel != "" {
			return fmt.Errorf("--tag and --channel are mutually exclusive")
		}

		// Edge channel short-circuits: nothing to verify.
		if releaseCheckChannel == "edge" {
			fmt.Println("edge channel builds from source; no release artifacts to verify.")
			return nil
		}

		tag := releaseCheckTag
		if tag == "" {
			// Resolve from channel (defaults to prerelease for
			// backward-compat with pre-rc.63 callers).
			channel := releaseCheckChannel
			if channel == "" {
				channel = "prerelease"
			}
			resolved, err := upgrade.ResolveChannelToLatestTag(channel)
			if err != nil {
				return fmt.Errorf("resolve channel %q: %w", channel, err)
			}
			if resolved == "" {
				// Only edge returns empty; handled above.
				return fmt.Errorf("channel %q resolved to empty tag (unexpected)", channel)
			}
			tag = resolved
			fmt.Printf("Checking release: %s → %s\n", channel, tag)
		} else {
			fmt.Printf("Checking release: %s\n", tag)
		}

		fmt.Println()

		// Run both probes — collect results from each.
		assetResults := release.CheckAssets(tag)
		manifestResults := release.CheckManifests(tag)

		allPassed := true
		printResults := func(results []release.CheckResult) {
			for _, r := range results {
				if r.OK {
					fmt.Printf("  ✓ %s\n", r.Name)
				} else {
					fmt.Printf("  ✗ %s (%s)\n", r.Name, r.Err)
					allPassed = false
				}
			}
		}

		fmt.Println("GitHub Release assets:")
		printResults(assetResults)
		fmt.Println()
		fmt.Println("Docker images (ghcr.io):")
		printResults(manifestResults)
		fmt.Println()

		if allPassed {
			fmt.Printf("All artifacts ready for %s\n", tag)
			return nil
		}
		fmt.Println("Some artifacts are not yet available.")
		fmt.Println("Retry in ~5 minutes — CI may still be publishing.")
		os.Exit(1)
		return nil // unreachable; os.Exit above carries the exit code
	},
}

// seedCreator is the regenerator the preflight invokes when it detects
// a stale seed. Package-level function variable for test injection:
// tests override it with a mock that writes a canned seed.json without
// hitting docker/pg_dump. Production default is CreateSeed.
var seedCreator = CreateSeed

// checkSeedFresh evaluates the current .db-seed/seed.json
// against on-disk migrations and HEAD SHA.
//
// Returns (fresh, reason). `reason` describes why staleness was detected
// (operator-visible log message); empty when fresh == true.
//
// Failure modes:
//   - seed.json missing → stale, reason "no seed.json found"
//   - commit_sha missing from JSON → stale
//   - migration_version < latest on-disk migration → stale, versions in reason
//   - commit_sha != HEAD SHA → stale, both SHAs in reason
//   - git rev-parse HEAD fails → (false, err text); caller decides treatment
func checkSeedFresh(projDir string) (fresh bool, reason string) {
	seedJSON := filepath.Join(projDir, ".db-seed", "seed.json")
	seedBytes, err := os.ReadFile(seedJSON)
	if err != nil {
		return false, "seed.json not found or unreadable"
	}
	seedContent := string(seedBytes)

	// Parse migration_version and commit_sha via the same line-split
	// pattern the prior preflight used — avoids pulling in a JSON dep
	// just for two string fields.
	seedVersion := ""
	seedCommitSHA := ""
	for _, line := range strings.Split(seedContent, "\n") {
		if strings.Contains(line, "migration_version") {
			parts := strings.Split(line, "\"")
			if len(parts) >= 4 {
				seedVersion = parts[3]
			}
		}
		if strings.Contains(line, "commit_sha") {
			parts := strings.Split(line, "\"")
			if len(parts) >= 4 {
				seedCommitSHA = parts[3]
			}
		}
	}

	// migration_version vs latest on-disk migration
	migrationsDir := filepath.Join(projDir, "migrations")
	entries, _ := os.ReadDir(migrationsDir)
	latestMigration := ""
	for _, e := range entries {
		name := e.Name()
		if strings.HasSuffix(name, ".up.sql") {
			version := strings.Split(name, "_")[0]
			if version > latestMigration {
				latestMigration = version
			}
		}
	}
	if latestMigration != "" && seedVersion < latestMigration {
		return false, fmt.Sprintf("migration_version %s older than latest %s", seedVersion, latestMigration)
	}

	// commit_sha vs HEAD
	headSHAOut, err := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD")
	if err != nil {
		return false, fmt.Sprintf("git rev-parse HEAD failed: %v", err)
	}
	headSHA := strings.TrimSpace(headSHAOut)
	if seedCommitSHA == "" {
		return false, "commit_sha missing from seed.json"
	}
	if seedCommitSHA != headSHA {
		return false, fmt.Sprintf("commit_sha %s != HEAD %s", seedCommitSHA, headSHA)
	}

	return true, ""
}

// checkAndRefreshSeed gates the release on seed freshness. If
// the seed is stale, it invokes seedCreator to regenerate, then
// re-checks once. Logs each decision + outcome so the operator's
// preflight log reads as a coherent narrative.
//
// Returns true when the seed is fresh (on first try OR after regen);
// false when regeneration failed or the re-check still shows staleness.
func checkAndRefreshSeed(projDir string) bool {
	fresh, reason := checkSeedFresh(projDir)
	if fresh {
		headSHAOut, _ := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD")
		headSHA := strings.TrimSpace(headSHAOut)
		if len(headSHA) > 12 {
			headSHA = headSHA[:12]
		}
		fmt.Printf("  ✓ Seed fresh (pinned to HEAD: %s)\n", headSHA)
		return true
	}

	fmt.Printf("  → Seed stale: %s — regenerating...\n", reason)
	if err := seedCreator(projDir); err != nil {
		fmt.Printf("  ✗ Seed regeneration failed: %v\n", err)
		return false
	}

	fresh2, reason2 := checkSeedFresh(projDir)
	if !fresh2 {
		fmt.Printf("  ✗ Seed still stale after regeneration: %s\n", reason2)
		return false
	}
	fmt.Println("  ✓ Seed regenerated and verified fresh")
	return true
}

// findReleaseTag returns the first release-shaped tag in a newline-separated
// string of tag names, or "" if none match. `git tag --points-at <sha>` may
// return multiple tags (release + local markers + signing tags); we only
// act on the release-shaped one.
//
// The release-shape regex lives at `cli/internal/release.ReleaseTagPattern`
// (single source of truth — the migrate runner needs the same pattern from
// a lower package and cannot import cli/cmd).
func findReleaseTag(tags string) string {
	for _, t := range strings.Split(strings.TrimSpace(tags), "\n") {
		t = strings.TrimSpace(t)
		if release.ReleaseTagPattern.MatchString(t) {
			return t
		}
	}
	return ""
}

// seedBranchPattern matches branches of the form `seed/<12-hex>`
// written by `./sb db seed create`. The SHA portion is the short
// (seedSHALen-char) project commit the seed pins to.
var seedBranchPattern = regexp.MustCompile(`^seed/[0-9a-f]{12}$`)

// cleanupSeedBranches sweeps origin's `seed/<sha>` branches and
// deletes those whose retention no longer serves any purpose:
//
//   - Tagged with a release AND release-check passes → canonical store
//     (GitHub release assets) is live. Branch's staging role is done.
//   - Untagged AND <sha> ≠ preserveSHA → ephemeral dev peer superseded
//     by any subsequent seed; safe to drop.
//
// Retained:
//   - <sha> == preserveSHA → the seed the caller is about to write
//     (or just wrote) and MUST survive this sweep.
//   - Tagged with a release AND release-check fails → in-flight release,
//     workflow may still need this branch to upload the asset.
//   - Anything that doesn't match `seed/<12-hex>` — forward-compat
//     for future naming, and avoids surprising deletes.
//
// Two callers share this function:
//   - `./sb db seed create` — preserveSHA = new seed's project
//     commit, so the just-written slot is never deleted.
//   - `./sb release prerelease` — preserveSHA = HEAD, so the seed
//     the operator just generated for this release cut is never deleted.
//
// Failures inside this sweep are warnings, not fatal — a network/auth
// blip on `git ls-remote` or a transient release-check failure must not
// block a legitimate release cut or seed refresh.
func cleanupSeedBranches(projDir, preserveSHA string) {
	staleOut, err := upgrade.RunCommandOutput(projDir, "git", "ls-remote", "--heads", "origin", "seed/*")
	if err != nil {
		fmt.Printf("warning: list remote seed branches: %v\n", err)
		return
	}
	trimmed := strings.TrimSpace(staleOut)
	if trimmed == "" {
		return
	}
	for _, line := range strings.Split(trimmed, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		// ls-remote lines: "<sha>\trefs/heads/seed/<12-hex>"
		parts := strings.SplitN(line, "\t", 2)
		if len(parts) != 2 {
			continue
		}
		ref := strings.TrimPrefix(parts[1], "refs/heads/")
		if !seedBranchPattern.MatchString(ref) {
			// Unknown shape (legacy `seed/v…` or future schema) —
			// leave alone. Migration/pruning is a separate concern.
			continue
		}
		branchSHA := strings.TrimPrefix(ref, "seed/")
		if preserveSHA != "" && strings.HasPrefix(preserveSHA, branchSHA) {
			continue // self or caller-asserted keeper
		}

		// Tagged with a release?
		tagsOut, _ := upgrade.RunCommandOutput(projDir, "git", "tag", "--points-at", branchSHA)
		tag := findReleaseTag(tagsOut)
		if tag != "" {
			// Gate: all release artifacts must be published before delete.
			allPassed := true
			for _, r := range release.CheckAssets(tag) {
				if !r.OK {
					allPassed = false
					break
				}
			}
			if allPassed {
				for _, r := range release.CheckManifests(tag) {
					if !r.OK {
						allPassed = false
						break
					}
				}
			}
			if !allPassed {
				fmt.Printf("  %s retained (release %s not fully published)\n", ref, tag)
				fmt.Printf("    To force-prune: git push origin :refs/heads/%s\n", ref)
				continue
			}
			fmt.Printf("  Cleaning up %s (release %s fully published)\n", ref, tag)
		} else {
			// Untagged ephemeral dev peer — supersede.
			fmt.Printf("  Cleaning up %s (untagged ephemeral peer)\n", ref)
		}

		if _, delErr := upgrade.RunCommandOutput(projDir, "git", "push", "origin", "--delete", ref); delErr != nil {
			fmt.Printf("    warning: git push origin --delete %s: %v\n", ref, delErr)
			continue
		}
		_, _ = upgrade.RunCommandOutput(projDir, "git", "branch", "-D", ref)
	}
}

// calVerRCKey returns a sortable int64 for tags of the form vYYYY.MM.PATCH-rc.N.
// Larger value = newer version. Non-conforming tags return 0 and sort last.
// Encoding: year*1e8 + month*1e6 + patch*1e4 + rc
func calVerRCKey(tag string) int64 {
	s := strings.TrimPrefix(tag, "v")
	parts := strings.SplitN(s, "-rc.", 2)
	if len(parts) != 2 {
		return 0
	}
	rc, err := strconv.Atoi(parts[1])
	if err != nil {
		return 0
	}
	vparts := strings.SplitN(parts[0], ".", 3)
	if len(vparts) != 3 {
		return 0
	}
	year, e1 := strconv.Atoi(vparts[0])
	month, e2 := strconv.Atoi(vparts[1])
	patch, e3 := strconv.Atoi(vparts[2])
	if e1 != nil || e2 != nil || e3 != nil {
		return 0
	}
	return int64(year)*100_000_000 + int64(month)*1_000_000 + int64(patch)*10_000 + int64(rc)
}

// checkCITestPassed queries GitHub Actions to see if pg_regress passed for the given SHA.
// Uses the `gh` CLI if available. Returns false if gh is not installed, the API fails,
// or no successful run exists for this SHA.
func checkCITestPassed(commitSHA string) bool {
	// gh api returns workflow runs for a specific head_sha.
	out, err := upgrade.RunCommandOutput(".", "gh", "api",
		fmt.Sprintf("repos/statisticsnorway/statbus/actions/workflows/pg_regress-workflow.yaml/runs?head_sha=%s&status=completed&per_page=5", commitSHA),
		"--jq", ".workflow_runs[] | select(.conclusion == \"success\") | .id")
	if err != nil {
		return false
	}
	return strings.TrimSpace(out) != ""
}

// resolveLatestRC takes newline-separated RC tags and returns the highest by CalVer sort.
func resolveLatestRC(rcTagsNewlineSep string) string {
	var tags []string
	for _, t := range strings.Split(rcTagsNewlineSep, "\n") {
		t = strings.TrimSpace(t)
		if t != "" && strings.Contains(t, "-rc.") {
			tags = append(tags, t)
		}
	}
	if len(tags) == 0 {
		return ""
	}
	sort.Slice(tags, func(i, j int) bool {
		return calVerRCKey(tags[i]) > calVerRCKey(tags[j])
	})
	return tags[0]
}

func init() {
	releaseCheckCmd.Flags().StringVar(&releaseCheckTag, "tag", "", "specific tag to check (mutually exclusive with --channel)")
	releaseCheckCmd.Flags().StringVar(&releaseCheckChannel, "channel", "", "channel to check: stable | prerelease | edge (mutually exclusive with --tag)")
	releaseCmd.AddCommand(releasePrereleaseCmd)
	releaseCmd.AddCommand(releaseStableCmd)
	releaseCmd.AddCommand(releaseListCmd)
	releaseCmd.AddCommand(releaseCheckCmd)
	rootCmd.AddCommand(releaseCmd)
}
