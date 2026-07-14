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
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/release"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// parseTwoLineStamp splits an H1 two-line stamp (task #123) into its
// SHA and migration-version components. Legacy single-line stamps
// return ("<sha>", "") — caller decides how to handle (typically:
// refuse with re-run guidance).
//
//	<head_sha>\n<source_db_migration_max_version>\n
//
// Trailing whitespace on each line is trimmed.
func parseTwoLineStamp(data []byte) (sha, version string) {
	lines := strings.Split(string(data), "\n")
	if len(lines) >= 1 {
		sha = strings.TrimSpace(lines[0])
	}
	if len(lines) >= 2 {
		version = strings.TrimSpace(lines[1])
	}
	return sha, version
}

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

	// 3. Migration immutability — STRUCTURAL gate, surfaced BEFORE any
	// slow checks (origin fetch, GHA images, fast tests, types regen,
	// doc-db regen, seed pin). Operators previously burned 60-90s of
	// preflight only to hit this violation at the very end; hoisting it
	// to the top makes the failure mode actionable in seconds. Uses
	// pickPrereleasePredecessor for the same year-month-rollover-safe
	// predecessor that ValidatePrereleaseTag uses post-creation, so
	// pre-creation diagnostic and post-creation re-validation stay in
	// lock-step.
	if !checkImmutabilityGate(projDir) {
		allPassed = false
	}

	// 4. Up to date with origin — distinguish direction (ahead/behind/diverged)
	// so the fix suggestion is actionable. The old one-line "Fix: git pull"
	// was wrong half the time.
	fetchOut, err := upgrade.RunCommandOutput(projDir, "git", "fetch", "origin", "master", "--quiet")
	if err != nil {
		fmt.Println("  ✗ Up to date with origin (fetch failed)")
		if trimmed := strings.TrimSpace(fetchOut); trimmed != "" {
			fmt.Printf("    git output:\n      %s\n", strings.ReplaceAll(trimmed, "\n", "\n      "))
		}
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
	buildOut, err := upgrade.RunCommandOutput(cliDir, "go", "build", "-o", "/dev/null", "./...")
	if err != nil {
		fmt.Println("  ✗ Go CLI builds")
		if trimmed := strings.TrimSpace(buildOut); trimmed != "" {
			fmt.Printf("    Compiler output:\n      %s\n", strings.ReplaceAll(trimmed, "\n", "\n      "))
		}
		fmt.Println("    Fix: cd cli && go build ./...")
		allPassed = false
	} else {
		fmt.Println("  ✓ Go CLI builds")
	}

	// 7. Fast tests cover latest migrations
	//
	// H1 two-line stamp format (task #123):
	//   line 1: HEAD SHA at test-pass time
	//   line 2: source DB (test template) migration_version at test-pass time
	// Both checked below. Legacy single-line stamps FAIL with re-run guidance.
	//
	// CI fallback (task #129): when no local stamp exists, query GitHub
	// Actions for the pg_regress workflow run at HEAD via the standard
	// WorkflowCheck pattern (same shape as images / test-hardening /
	// test-install gates — Green/Pending/Failed/Missing/Unknown each
	// with URL + run-id + actionable next-step). On Green a fresh local
	// stamp is written so subsequent invocations short-circuit through
	// the local-stamp fast path.
	//
	// No SKIP_PG_REGRESS env var exists by design: the local-stamp
	// fast-path IS the operator's escape valve (`./dev.sh test fast`
	// or `./dev.sh migrate-and-test fast` writes the stamp and the
	// CI-fallback branch is skipped entirely). Adding SKIP would allow
	// release-stable with neither local stamp nor CI green — structurally
	// more dangerous than the other SKIP_* env vars which lack a
	// local-escape.
	stampPath := filepath.Join(projDir, "tmp", "fast-test-passed-sha")
	stampBytes, err := os.ReadFile(stampPath)
	if err != nil {
		headOut, _ := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD")
		headFull := strings.TrimSpace(headOut)
		headShort := headFull
		if len(headShort) > 12 {
			headShort = headShort[:12]
		}
		pgRegressResult := release.CheckWorkflowAtCommit(release.WorkflowPgRegress, headFull)
		switch pgRegressResult.Status {
		case release.WorkflowCheckGreen:
			// CI ran against a freshly-built environment, so source DB is
			// by-construction at HEAD's max migration version. Write a
			// fresh H1 two-line stamp so subsequent invocations
			// short-circuit through the local-stamp fast path.
			latestMig, _ := migrate.LatestOnDiskMigrationVersion(projDir)
			fmt.Printf("  ✓ Fast tests passed in CI for %s (writing local stamp, source version %s)\n", headShort, latestMig)
			fmt.Printf("    Run: %s\n", pgRegressResult.RunURL)
			_ = os.MkdirAll(filepath.Join(projDir, "tmp"), 0755) // best-effort; the WriteFile right after surfaces any real failure
			stampContent := headFull + "\n" + latestMig + "\n"
			_ = os.WriteFile(stampPath, []byte(stampContent), 0644) // best-effort local stamp; a write failure just means the fast path re-checks next time
			stampBytes = []byte(stampContent)
		case release.WorkflowCheckPending:
			fmt.Printf("  ✗ pg_regress is still pending at %s (no local stamp)\n", headShort)
			fmt.Printf("    Watch: gh run watch %d\n", pgRegressResult.RunID)
			fmt.Printf("    URL:   %s\n", pgRegressResult.RunURL)
			fmt.Println("    Fix: wait for the run to complete, then re-run prerelease")
			fmt.Println("    Or:  ./dev.sh migrate-and-test fast   (write local stamp from your machine)")
			allPassed = false
		case release.WorkflowCheckFailed:
			fmt.Printf("  ✗ pg_regress failed at %s (conclusion: %s; no local stamp)\n", headShort, pgRegressResult.Detail)
			fmt.Printf("    See: gh run view %d --log-failed\n", pgRegressResult.RunID)
			fmt.Printf("    URL: %s\n", pgRegressResult.RunURL)
			fmt.Println("    Fix:")
			fmt.Printf("      Retry the failed jobs (if transient): gh run rerun --failed %d\n", pgRegressResult.RunID)
			fmt.Println("      Or push a fix to master, then re-run prerelease")
			fmt.Println("      Or run locally: ./dev.sh migrate-and-test fast   (write local stamp)")
			allPassed = false
		case release.WorkflowCheckMissing:
			fmt.Printf("  ✗ pg_regress has not run for %s (no local stamp)\n", headShort)
			fmt.Printf("    Trigger: %s\n", release.WorkflowTriggerCommand(release.WorkflowPgRegress, headFull))
			fmt.Printf("    Watch:   %s\n", release.WorkflowURL(release.WorkflowPgRegress))
			fmt.Println("    Fix: run the trigger command above, wait for green, re-run prerelease")
			fmt.Println("    Or:  ./dev.sh migrate-and-test fast   (write local stamp from your machine)")
			allPassed = false
		case release.WorkflowCheckUnknown:
			fmt.Printf("  ✗ pg_regress status check failed (GitHub API error; no local stamp)\n")
			fmt.Printf("    Detail: %s\n", pgRegressResult.Detail)
			fmt.Println("    Fix: check network connectivity / GITHUB_TOKEN; or re-run later")
			fmt.Println("    Or:  ./dev.sh migrate-and-test fast   (write local stamp from your machine)")
			allPassed = false
		}
	}
	if stampBytes != nil {
		stampSHA, stampVersion := parseTwoLineStamp(stampBytes)
		if stampVersion == "" {
			fmt.Println("  ✗ Fast tests cover latest migrations (tmp/fast-test-passed-sha is legacy single-line; missing source-DB version)")
			fmt.Println("    Fix: ./dev.sh migrate-and-test fast   (re-run to upgrade stamp to two-line format)")
			allPassed = false
			stampBytes = nil
		}
		_ = stampSHA
	}
	if stampBytes != nil {
		stampSHA, stampVersion := parseTwoLineStamp(stampBytes)

		// Find the last commit that touched actual migration files.
		// Only match versioned files (YYYYMMDDHHMMSS_*.up.*), not helper
		// files like post_restore.sql which live in migrations/ but aren't migrations.
		lastMigrationOut, _ := upgrade.RunCommandOutput(projDir, "git", "log", "-1", "--format=%H", "--", "migrations/*.up.sql", "migrations/*.up.psql")
		lastMigration := strings.TrimSpace(lastMigrationOut)

		// H1: stamp's line-2 version must equal HEAD's current on-disk
		// max. Catches the bypass case where the test ran against a stale
		// template even though the SHA was current.
		latestOnDisk, _ := migrate.LatestOnDiskMigrationVersion(projDir)

		if lastMigration == "" {
			// No migrations at all — tests are fine
			fmt.Println("  ✓ Fast tests cover latest migrations (no migrations found)")
		} else if stampVersion != latestOnDisk {
			fmt.Println("  ✗ Fast tests do not cover latest migrations")
			fmt.Printf("    Stamp's source-DB version %s != HEAD's on-disk max %s.\n", stampVersion, latestOnDisk)
			fmt.Printf("    The tests ran against a stale template even though the SHA is current.\n")
			fmt.Println("    Fix: ./dev.sh migrate-and-test fast")
			allPassed = false
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
					fmt.Printf("  ✓ Fast tests cover latest migrations (stamp: %s, source version: %s, last migration: %s)\n", shortStamp, stampVersion, shortMig)
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
					fmt.Println("    Fix: ./dev.sh migrate-and-test fast")
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
				fmt.Println("    Fix: ./dev.sh migrate-and-test fast")
				allPassed = false
			}
		}
	}

	// 8. TypeScript types cover latest migrations — checked BEFORE app tsc/build
	//    because stale types hide drift: tsc can pass against a stale
	//    app/src/lib/database.types.ts while the real schema has changed.
	//    Regenerating types first ensures tsc/build stamps reflect the
	//    current schema.
	//
	// H1 two-line stamp format (task #123):
	//   line 1: HEAD SHA at generation time
	//   line 2: source DB's migration_version at generation time
	// Preflight verifies BOTH:
	//   (a) no new migration files have landed since line 1
	//   (b) line 2 equals HEAD's max on-disk migration version
	// (b) catches stamps written from a stale source DB even when the
	// SHA happens to be HEAD — the bypass class the per-generator
	// assert_db_at_head gate also closes at write time.
	//
	// Legacy single-line stamps (pre-#123) are treated as "missing
	// version" and FAIL preflight with a re-run guidance — one-time
	// operator disruption, no data loss.
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
		stampSHA, stampVersion := parseTwoLineStamp(sb)
		if stampVersion == "" {
			fmt.Printf("  ✗ %s (tmp/%s is legacy single-line; missing source-DB version)\n", failLabel, stampFile)
			fmt.Printf("    Fix: %s   (re-run to upgrade stamp to two-line format)\n", fixCmd)
			allPassed = false
			return
		}
		newMigrationsOut, _ := upgrade.RunCommandOutput(projDir, "git", "diff", "--name-only",
			stampSHA+"..HEAD", "--", "migrations/*.up.sql", "migrations/*.up.psql")
		newMigrations := strings.TrimSpace(newMigrationsOut)
		// H1 line-2 check: stamp's recorded migration_version must match
		// HEAD's current on-disk max. Catches the bypass case where a
		// generator skipped its at-head guard and wrote a stamp from a
		// stale DB.
		latestOnDisk, _ := migrate.LatestOnDiskMigrationVersion(projDir)
		if newMigrations == "" && stampVersion == latestOnDisk {
			short := stampSHA
			if len(short) > 12 {
				short = short[:12]
			}
			fmt.Printf("  ✓ %s (stamp: %s, source-DB version: %s)\n", label, short, stampVersion)
		} else if newMigrations != "" {
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
		} else {
			fmt.Printf("  ✗ %s\n", failLabel)
			fmt.Printf("    Stamp's source-DB version %s != HEAD's on-disk max %s.\n", stampVersion, latestOnDisk)
			fmt.Printf("    The artifact was generated from a stale DB even though the SHA is current.\n")
			fmt.Printf("    Fix: %s\n", fixCmd)
			allPassed = false
		}
	}
	checkMigrationStamp("types-passed-sha", "TypeScript types cover latest migrations", "./sb types generate")

	// 9. App tsc covers latest app changes  (check 10 is app build — same helper)
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

	// 11. DB documentation covers latest migrations
	checkMigrationStamp("db-docs-passed-sha", "DB documentation covers latest migrations", "./dev.sh generate-doc-db")

	// 12. images workflow green for HEAD — schema-derived stamps cover
	//     Go/TypeScript/SQL, but the Docker artifacts that ship to ghcr.io can
	//     only be validated by actually building them. images.yaml on GitHub
	//     Actions IS that build. We don't replay it locally (the old pre-push
	//     docker-build replay was slow and duplicated CI's work). We query
	//     the workflow's verdict for HEAD instead.
	imagesHeadOut, _ := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD")
	imagesHeadFull := strings.TrimSpace(imagesHeadOut)
	imagesHeadShort := imagesHeadFull
	if len(imagesHeadShort) > 12 {
		imagesHeadShort = imagesHeadShort[:12]
	}
	imagesResult := release.CheckWorkflowAtCommit(release.WorkflowImages, imagesHeadFull)
	switch imagesResult.Status {
	case release.WorkflowCheckGreen:
		if imagesResult.BypassReason != "" {
			// SKIP_IMAGES=1 bypass — print a loud warning before
			// accepting. The bypass is surgical (images-only) but
			// downstream deployments may fail if the SHA's Docker
			// artifacts don't actually exist in ghcr.io.
			fmt.Printf("  ⚠⚠⚠ images BYPASSED at %s\n", imagesHeadShort)
			fmt.Printf("    %s\n", imagesResult.BypassReason)
		} else {
			fmt.Printf("  ✓ images green at %s\n", imagesHeadShort)
			fmt.Printf("    Run: %s\n", imagesResult.RunURL)
		}
	case release.WorkflowCheckPending:
		fmt.Printf("  ✗ images is still pending at %s\n", imagesHeadShort)
		fmt.Printf("    Watch: gh run watch %d\n", imagesResult.RunID)
		fmt.Printf("    URL:   %s\n", imagesResult.RunURL)
		fmt.Println("    Fix: wait for the run to complete, then re-run prerelease")
		allPassed = false
	case release.WorkflowCheckFailed:
		fmt.Printf("  ✗ images failed at %s (conclusion: %s)\n", imagesHeadShort, imagesResult.Detail)
		fmt.Printf("    See: gh run view %d --log-failed\n", imagesResult.RunID)
		fmt.Printf("    URL: %s\n", imagesResult.RunURL)
		fmt.Println("    Fix:")
		fmt.Printf("      Retry the failed jobs (if transient — network, ghcr.io timeout): gh run rerun --failed %d\n", imagesResult.RunID)
		fmt.Println("      Or push a fix to master, then re-run prerelease (if real defect)")
		allPassed = false
	case release.WorkflowCheckMissing:
		fmt.Printf("  ✗ images has not run for %s\n", imagesHeadShort)
		if ref, ok := dispatchRefForMasterTip(projDir, imagesHeadFull); ok {
			fmt.Printf("    Trigger: %s\n", release.WorkflowTriggerCommand(release.WorkflowImages, ref))
			fmt.Printf("    Watch:   %s\n", release.WorkflowURL(release.WorkflowImages))
			fmt.Println("    Fix: run the trigger command above, wait for green, re-run prerelease")
		} else {
			fmt.Printf("    %s is not origin/master's tip — workflow_dispatch builds a branch/tag tip, not a bare SHA.\n", imagesHeadShort)
			fmt.Println("    Fix: push this commit to master (images builds on push), then re-run prerelease")
		}
		allPassed = false
	case release.WorkflowCheckUnknown:
		fmt.Println("  ✗ images status check failed (GitHub API error)")
		fmt.Printf("    Detail: %s\n", imagesResult.Detail)
		fmt.Println("    Fix: check network connectivity / GITHUB_TOKEN; or re-run later")
		allPassed = false
	}

	// Persist outcome for shell scripts that need to inspect the result
	// after the fact (cobra's RunE error → non-zero exit is the human-
	// facing signal; this file is the programmatic one). No echo banner —
	// the per-gate ✗/Fix lines above plus cobra's `Error:` line on stderr
	// already say "failed" once each. Stating it three times was noise.
	resultPath := filepath.Join(projDir, "tmp", "last-preflight-result")
	_ = os.MkdirAll(filepath.Dir(resultPath), 0755)
	if allPassed {
		_ = os.WriteFile(resultPath, []byte("PASS\n"), 0644)
	} else {
		_ = os.WriteFile(resultPath, []byte("FAIL\n"), 0644)
	}

	return allPassed
}

// checkImmutabilityGate is the preflight wrapper around
// checkMigrationImmutability. Computes the year-month-rollover-safe
// predecessor via pickPrereleasePredecessor (single source of truth shared
// with ValidatePrereleaseTag) and reports the result inline with the
// other preflight checks. Returns true on PASS so the caller can OR
// it into the allPassed accumulator.
//
// Both prerelease and stable paths benefit from the early failure mode:
// stable cuts also require a clean predecessor diff. For stable, the
// predecessor is the prior RC of the same patch — same helper handles it.
func checkImmutabilityGate(projDir string) bool {
	now := time.Now()
	prefix := fmt.Sprintf("v%d.%02d", now.Year(), now.Month())

	// Mirror the patch-resolution logic from releasePrereleaseCmd.RunE:
	// the predecessor is keyed to the PATCH this RC targets, not just
	// "the latest tag in current year-month". Same helper signature as
	// the post-creation re-validation at ValidatePrereleaseTag.
	stableTagsOut, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-l", fmt.Sprintf("%s.*", prefix))
	if err != nil {
		fmt.Println("  ✗ Migration immutability (listing stable tags failed)")
		fmt.Printf("    git output:\n      %s\n", strings.ReplaceAll(strings.TrimSpace(stableTagsOut), "\n", "\n      "))
		return false
	}
	highestStablePatch := -1
	patchRegex := regexp.MustCompile(fmt.Sprintf(`^%s\.(\d+)$`, regexp.QuoteMeta(prefix)))
	for _, line := range strings.Split(strings.TrimSpace(stableTagsOut), "\n") {
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

	rcNums, err := listRCNumbersForPatch(projDir, prefix, nextPatch, "")
	if err != nil {
		fmt.Printf("  ✗ Migration immutability (listing RC numbers failed: %v)\n", err)
		return false
	}
	prevTag, err := pickPrereleasePredecessor(projDir, prefix, nextPatch, rcNums)
	if err != nil {
		fmt.Printf("  ✗ Migration immutability (predecessor lookup failed: %v)\n", err)
		return false
	}
	if prevTag == "" || !tagExistsLocally(projDir, prevTag) {
		fmt.Println("  ✓ No previous tag to check migrations against (very first release)")
		return true
	}

	label := "previous RC"
	if !strings.Contains(prevTag, "-rc.") {
		label = "previous stable"
	}
	if err := checkMigrationImmutability(projDir, prevTag, label); err != nil {
		// checkMigrationImmutability already printed the per-file
		// rejection list. Surface the actionable fix on its own line.
		fmt.Printf("    Fix: see message above; or set %s=<version>[,...] to bypass for listed versions.\n", release.IntentionallyFixBrokenImmutableMigrationEnvVar)
		return false
	}
	return true
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
					"  number without an underlying change is wasteful",
				tag)
		case !isPrerelease && !isRC:
			return fmt.Errorf(
				"HEAD already carries a stable release tag: %s\n"+
					"  Make a new commit before tagging another release — bumping\n"+
					"  the patch number without an underlying change is wasteful",
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
//
// STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION (release.IntentionallyFixBrokenImmutableMigrationEnvVar) lets an
// operator explicitly bypass the gate for listed versions when an
// already-released migration MUST be rewritten in place. Listed versions
// are skipped from the modified[] set with an explicit log line; non-listed
// modifications still fail the gate normally. If prevTag is a STABLE tag
// (no `-rc.` suffix), every intentionally-fixed version is by definition shipped
// in stable — emit an extra warning so the operator knows what they're
// agreeing to (the env var itself is the acknowledgment; the warning is
// the receipt).
func checkMigrationImmutability(projDir, prevTag, label string) error {
	// STATBUS-102: fix-broken set = the versions named in
	// STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION at the cut. This is the
	// ONLY place declared intent is read; per-host upgrade blessing is by channel
	// (migrate.migrationChannelClass), not this list.
	fixBroken, err := release.IntentionallyFixBrokenImmutableMigrationVersions()
	if err != nil {
		return err
	}

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

	prevIsStable := !strings.Contains(prevTag, "-rc.")

	// Parse the diff output. Format: "M\tmigrations/file" or "D\tmigrations/file"
	// A (added) = new migration, fine. M (modified) or D (deleted) = immutability violation.
	var modified []string
	var fixedBroken []int64
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

		// Honour STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION: extract the
		// 14-digit version prefix from the filename and skip if listed.
		if len(fixBroken) > 0 {
			base := filepath.Base(file)
			if underscore := strings.Index(base, "_"); underscore > 0 {
				if v, parseErr := strconv.ParseInt(base[:underscore], 10, 64); parseErr == nil && fixBroken[v] {
					fixedBroken = append(fixedBroken, v)
					continue
				}
			}
		}

		modified = append(modified, fmt.Sprintf("  %s %s", status, file))
	}

	// Log fix-broken activity before the gate decision so the operator
	// sees what they bypassed even on a passing run.
	for _, v := range dedupeInt64Sorted(fixedBroken) {
		fmt.Printf("    ⟳ Intentionally fixing broken (immutable) migration %d (declared in %s)\n", v, release.IntentionallyFixBrokenImmutableMigrationEnvVar)
		if prevIsStable {
			fmt.Printf("      ⚠ %s is a STABLE tag — this version shipped in production.\n", prevTag)
			fmt.Println("        Operators bypassing stable-shipped migrations: confirm the change is")
			fmt.Println("        coordinated with downstream rollouts (see doc/upgrade-timeline.md).")
		}
	}

	if len(modified) == 0 {
		fmt.Printf("  ✓ No migrations modified since %s (%s)\n", prevTag, label)
		return nil
	}

	fmt.Printf("  ✗ Migrations modified since %s (%s)\n", prevTag, label)
	for _, m := range modified {
		fmt.Println("   ", m)
	}
	return fmt.Errorf("migrations modified since %s — deployed migrations are immutable.\n"+
		"  The ONLY sanctioned reason to change a released migration is to FIX A GENUINELY\n"+
		"  BROKEN one: a crash/timeout/OOM fix that PRESERVES THE RESULT. A result change\n"+
		"  goes in a NEW forward migration (./sb migrate new), never by editing this file.\n"+
		"  If you are NOT certain the migration is genuinely broken AND that your fix\n"+
		"  preserves the result, STOP and consult the maintainer — do not set the var on a guess:\n"+
		"  it silently overrides a safety invariant on every box that already ran the migration.\n"+
		"  ONLY if you are certain, and deliberately fixing a broken migration, declare each version:\n"+
		"    %s=<version>[,...] ./sb release prerelease\n"+
		"  Otherwise, revert your change to the original file:\n"+
		"    git checkout %s -- migrations/<file>",
		prevTag, release.IntentionallyFixBrokenImmutableMigrationEnvVar, prevTag)
}

// dedupeInt64Sorted returns the input with duplicates removed and entries
// sorted ascending. Used to produce a stable log order regardless of git
// diff ordering or per-call iteration.
func dedupeInt64Sorted(in []int64) []int64 {
	if len(in) == 0 {
		return nil
	}
	seen := make(map[int64]struct{}, len(in))
	out := make([]int64, 0, len(in))
	for _, v := range in {
		if _, ok := seen[v]; ok {
			continue
		}
		seen[v] = struct{}{}
		out = append(out, v)
	}
	sort.Slice(out, func(i, j int) bool { return out[i] < out[j] })
	return out
}

var releasePrereleaseCmd = &cobra.Command{
	Use:   "prerelease",
	Short: "Tag a new release candidate (vYYYY.MM.PATCH-rc.N)",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		fmt.Println("Pre-flight checks:")
		if !preflightChecks(projDir) {
			return fmt.Errorf("pre-flight checks failed")
		}
		if err := noSameKindTagAtHEAD(projDir, true); err != nil {
			return err
		}

		// Compute the patch this RC targets BEFORE the immutability check —
		// the helper picks a predecessor keyed to that specific patch, not
		// to "latest RC in the current year-month" (the prior shape from
		// findPreviousTag). The reorder closes the year-month-rollover gap
		// that previously let migrations modified between April's last
		// stable and May's first RC pass undetected (task #124 Part B).
		now := time.Now()
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

		// List existing RC numbers for this patch — used both for the
		// next-in-sequence computation below AND as input to
		// pickPrereleasePredecessor (which uses the highest existing RC
		// in the same patch as the immutability predecessor).
		rcNums, err := listRCNumbersForPatch(projDir, prefix, nextPatch, "")
		if err != nil {
			return fmt.Errorf("listing RC numbers: %w", err)
		}

		// Migration immutability is now checked at preflight top via
		// checkImmutabilityGate — keeps the structural gate ahead of all
		// slow checks. See preflightChecks step 3.

		highestRC := 0
		if len(rcNums) > 0 {
			highestRC = rcNums[len(rcNums)-1]
		}
		nextRC := highestRC + 1
		tagName := fmt.Sprintf("%s.%d-rc.%02d", prefix, nextPatch, nextRC)

		// Safety: verify tag doesn't already exist locally or on remote
		if _, err := upgrade.RunCommandOutput(projDir, "git", "rev-parse", tagName); err == nil {
			return fmt.Errorf("tag %s already exists locally — tags are immutable, cannot recreate", tagName)
		}

		// Create tag with message (avoids $EDITOR prompt when tag.gpgsign=true)
		tagOut, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-m", "Pre-release "+tagName, tagName)
		if err != nil {
			return fmt.Errorf("creating tag %s: %w\n  output: %s", tagName, err, strings.TrimSpace(tagOut))
		}

		// Post-create re-validation REMOVED: every invariant ValidatePrereleaseTag
		// re-checked is already gated at the pre-create layer:
		//   - tag-shape (vYYYY.MM.PATCH-rc.N regex + annotated/signed) — git tag -m + tag.gpgsign
		//   - RC-number sequence (next-in-sequence) — local computation at lines above
		//   - migration immutability — checkImmutabilityGate at preflightChecks step 3
		// The pre-push hook still calls ValidatePrereleaseTag through
		// release verify-tag, so the protection survives. The duplicate
		// call was wasteful at best, and at worst (as King hit during
		// v2026.05.4-rc.01) bypassed STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION
		// because compareMigrationsForTag didn't read the env var. Both
		// are now fixed: redundant call removed + compareMigrationsForTag
		// honors the env var so pre-push hook respects the bypass too.

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
	Long: `Tag a new stable release. Stable is a PURE PROMOTION of the latest RC
for the next-in-sequence patch — it tags the RC's commit, not HEAD.

The operator's local state is irrelevant: working tree, current branch,
unstamped tests, missing seed/types/db-docs stamps, even being on a
feature branch — none of it matters. The RC was validated; stable just
promotes it.

Pre-flight (~8 checks):
  - Latest RC exists for v<YEAR>.<MONTH>.<NEXT_PATCH>
  - That patch is next-in-sequence for vYYYY.MM
  - images workflow green at the RC's commit
  - fast-tests workflow green at the RC's commit
  - go-test workflow green at the RC's commit
  - test-hardening workflow green at the RC's commit
  - test-install workflow green at the RC's commit
  - install-recovery-harness workflow green at the RC's commit
  - RC release artifacts (GitHub assets + ghcr manifests) all present

Operator bypasses (use sparingly — each one is an admission that a
gate's invariant has NOT been verified for the SHA):
  SKIP_IMAGES=1            (Docker artifacts may not exist; deploys may FAIL)
  SKIP_FAST_TESTS=1        (fast pg_regress suite was not exercised)
  SKIP_GO_TEST=1           (Go unit tests were not exercised)
  SKIP_TEST_HARDENING=1
  SKIP_TEST_INSTALL=1
  SKIP_INSTALL_RECOVERY=1  (no recovery regression net was exercised)
`,
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		// Auto-fetch so multi-operator workflows are first-class: dev A
		// cuts the RC on her box, pushes it; dev B promotes to stable on
		// his box without ever needing local stamps or even a recent
		// pull. Both fetches are quiet (~100ms total when nothing new).
		// Failures are logged but do not block — the operator can still
		// promote if local tags are already current.
		if _, err := upgrade.RunCommandOutput(projDir, "git", "fetch", "origin", "--tags", "--quiet"); err != nil {
			fmt.Fprintf(os.Stderr, "  warn: git fetch origin --tags failed: %v (proceeding with local tag state)\n", err)
		}
		if _, err := upgrade.RunCommandOutput(projDir, "git", "fetch", "origin", "master", "--quiet"); err != nil {
			fmt.Fprintf(os.Stderr, "  warn: git fetch origin master failed: %v (proceeding with local master state)\n", err)
		}

		now := time.Now()
		prefix := fmt.Sprintf("v%d.%02d", now.Year(), now.Month())

		fmt.Println("Pre-flight checks (promotion of latest RC):")

		// 1. Compute the next-in-sequence stable patch for this month.
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
			if m := patchRegex.FindStringSubmatch(line); len(m) == 2 {
				n, _ := strconv.Atoi(m[1])
				if n > highestPatch {
					highestPatch = n
				}
			}
		}
		nextPatch := highestPatch + 1
		tagName := fmt.Sprintf("%s.%d", prefix, nextPatch)

		// Safety: refuse to recreate an existing stable.
		if _, err := upgrade.RunCommandOutput(projDir, "git", "rev-parse", tagName); err == nil {
			return fmt.Errorf("tag %s already exists locally — tags are immutable, cannot recreate", tagName)
		}

		// 2. Find the latest RC for this patch — the one we're promoting.
		rcNums, err := listRCNumbersForPatch(projDir, prefix, nextPatch, "")
		if err != nil {
			return fmt.Errorf("listing RC numbers for %s.%d: %w", prefix, nextPatch, err)
		}
		if len(rcNums) == 0 {
			return fmt.Errorf("no pre-release candidates for %s.\n"+
				"  Stable is a promotion of an RC. Tag a prerelease first:\n"+
				"    ./sb release prerelease",
				tagName)
		}
		latestRC := fmt.Sprintf("%s.%d-rc.%02d", prefix, nextPatch, rcNums[len(rcNums)-1])
		rcCommit, err := tagTargetCommit(projDir, latestRC)
		if err != nil {
			return fmt.Errorf("resolving %s target commit: %w", latestRC, err)
		}
		rcShort := rcCommit
		if len(rcShort) > 12 {
			rcShort = rcShort[:12]
		}
		fmt.Printf("  ✓ Latest RC %s (target %s) exists\n", latestRC, rcShort)
		fmt.Printf("  ✓ Stable patch %d is next-in-sequence for %s\n", nextPatch, prefix)

		// 3. Three workflow gates AT THE RC's commit (not HEAD). Each is
		//    independent — all three always run, all three must pass
		//    (modulo SKIP_*=1 operator bypass). The gates check the
		//    invariants that the RC tag's push triggered: image build,
		//    setup hardening, end-to-end install.
		//
		//    Workflows run FIRST in the chain because every downstream
		//    check has a workflow precondition: canary upgrade-service
		//    runs `images`-built binaries; RC artifacts come from the
		//    same workflow batch. A red workflow guarantees a red
		//    canary, so checking the workflow first surfaces the
		//    actionable root cause before the operator stares at a
		//    guaranteed-fail canary diagnostic.
		allPassed := checkStableWorkflowGate(release.WorkflowImages, "images", latestRC, rcCommit, rcShort, "SKIP_IMAGES")
		// fast-tests runs the pg_regress fast suite on every master push, so a
		// run exists at the RC's commit (the RC tags a master commit). Gates
		// stable against derivation/baseline drift that lands silently red —
		// images builds artifacts but does NOT run pg_regress.
		allPassed = checkStableWorkflowGate(release.WorkflowFastTests, "fast-tests", latestRC, rcCommit, rcShort, "SKIP_FAST_TESTS") && allPassed
		// go-test runs `go vet` + `go test ./...` on every master push, so a
		// run exists at the RC's commit (the RC tags a master commit). Gates
		// stable against a Go-layer regression — the CLI's upgrade/recovery,
		// install, and release unit tests — landing silently red; neither
		// images nor fast-tests runs go test (fast-tests is pg_regress only).
		allPassed = checkStableWorkflowGate(release.WorkflowGoTest, "go-test", latestRC, rcCommit, rcShort, "SKIP_GO_TEST") && allPassed
		allPassed = checkStableWorkflowGate(release.WorkflowTestHardening, "test-hardening", latestRC, rcCommit, rcShort, "SKIP_TEST_HARDENING") && allPassed
		allPassed = checkStableWorkflowGate(release.WorkflowTestInstall, "test-install", latestRC, rcCommit, rcShort, "SKIP_TEST_INSTALL") && allPassed
		// Install-recovery harness: every C-class with a paired scenario in
		// test/install-recovery/scenarios/ gets exercised on a dedicated
		// Hetzner cx23. The workflow at .github/workflows/install-recovery-
		// harness.yaml fires on the RC's tag push and is the empirical
		// half of the no-hotfix discipline — without this gate, the
		// "release stable promotes a verified-recovery RC" invariant
		// reduces to "release stable promotes a never-crashed-in-CI RC".
		allPassed = checkStableWorkflowGate(release.WorkflowInstallRecoveryHarness, "install-recovery", latestRC, rcCommit, rcShort, "SKIP_INSTALL_RECOVERY") && allPassed

		// 4. RC release artifacts MUST be present BEFORE the stable tag
		//    is created. release.yaml (triggered by the RC's tag push)
		//    builds the sb binaries + uploads GitHub Release assets +
		//    publishes ghcr manifests. Until those land, promoting to
		//    stable would tag a half-baked RC.
		//
		//    Historical: this check used to fire post-create inside
		//    ValidateStableTag, which meant the operator hit "tag
		//    created, validation failed, tag deleted" — an awkward
		//    create-then-delete dance when release.yaml was still mid-
		//    build. Moving the gate forward restores the invariant that
		//    nothing is tagged before everything is checked.
		allPassed = checkRCArtifactGate(latestRC) && allPassed

		// 5. Canary observational gates. Verifies that the RC's commit has
		//    actually deployed AND reached `state='completed'` on every
		//    canary slot before we tag stable. The check observes; it does
		//    NOT trigger upgrades — operators choose how (web UI, CLI,
		//    push-to-deploy branch, manual psql). Implicitly verifies
		//    every esoteric interaction (systemd timeouts, OS compat,
		//    OOM, worker drain, post-restore fixups) because all of them
		//    are upstream of the 'completed' state.
		//
		//    Canary checks run AFTER the workflow + artifact gates
		//    because canary 'completed' state is downstream of those:
		//    the slot's upgrade-service consumes ghcr images that
		//    `images` builds, and operators don't typically push-to-
		//    deploy a slot until test-hardening + test-install go
		//    green. Reordering surfaced this — pre-fix canary fired
		//    first and gave the operator a guaranteed-fail diagnostic
		//    before the actionable workflow result. Canary checks
		//    still run unconditionally (not short-circuited on
		//    workflow result) so the operator gets the FULL status
		//    picture, but they now appear in the chain after the
		//    upstream signals they depend on.
		//
		//    Bypass per slot: STATBUS_SKIP_CANARY=<label>[,<label>...].
		allPassed = checkCanaryGates(rcCommit) && allPassed

		if !allPassed {
			return fmt.Errorf("pre-flight checks failed")
		}

		// 5. Tag at the RC's commit (NOT HEAD). The -s flag is explicit
		//    (rather than relying on tag.gpgsign=true) so this works
		//    regardless of operator git config.
		fmt.Println()
		fmt.Printf("Tagging %s at %s (promoted from %s)\n", tagName, rcShort,
			fmt.Sprintf("rc.%02d", rcNums[len(rcNums)-1]))
		tagOut, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-s", "-m", "Release "+tagName, tagName, rcCommit)
		if err != nil {
			return fmt.Errorf("creating tag %s at %s: %w\n  output: %s",
				tagName, rcShort, err, strings.TrimSpace(tagOut))
		}

		// 6. Re-validate the freshly created tag via the same shape gate
		//    the pre-push hook uses. ValidateStableTag is pure tag-shape
		//    now (annotated/signed/named correctly, next-in-sequence,
		//    target commit matches latest RC) — artifact readiness was
		//    already gated at step 4 above. If ValidateStableTag fails
		//    here it means the freshly created tag itself is malformed
		//    (e.g. signing config drift); delete it locally and abort
		//    rather than push a broken tag.
		if err := ValidateStableTag(projDir, tagName); err != nil {
			_, _ = upgrade.RunCommandOutput(projDir, "git", "tag", "-d", tagName)
			return fmt.Errorf("post-create validation of %s failed: %w", tagName, err)
		}

		pushOut, err := upgrade.RunCommandOutput(projDir, "git", "push", "origin", tagName)
		if err != nil {
			return fmt.Errorf("pushing tag %s: %w\n  output: %s", tagName, err, strings.TrimSpace(pushOut))
		}
		fmt.Printf("Pushed %s to origin.\n", tagName)
		return nil
	},
}

// checkStableWorkflowGate runs one of the RC-targeted workflow gates for
// releaseStableCmd. Centralizes the switch over WorkflowCheck* statuses
// + the SKIP_* env-var bypass printing.
//
// Returns true when the gate is satisfied (Green, or bypass set);
// false otherwise (caller aggregates into allPassed).
func checkStableWorkflowGate(workflow, label, rcTag, rcCommit, rcShort, skipEnv string) bool {
	if skipEnv != "SKIP_IMAGES" && os.Getenv(skipEnv) == "1" {
		// SKIP_TEST_HARDENING / SKIP_TEST_INSTALL / SKIP_INSTALL_RECOVERY —
		// print the existing tailored guidance text (matches the
		// prerelease pattern).
		fmt.Printf("  ⚠ %s SKIPPED (%s=1)\n", label, skipEnv)
		fmt.Printf("    Operator bypass — ensure %s ran via CI or by hand on this commit.\n", label)
		return true
	}
	result := release.CheckWorkflowAtCommit(workflow, rcCommit)
	switch result.Status {
	case release.WorkflowCheckGreen:
		if result.BypassReason != "" {
			// SKIP_IMAGES — handled inside CheckWorkflowAtCommit.
			// Louder warning (the bypass is more dangerous than the
			// test-* bypasses; missing Docker artifacts kill deploys).
			fmt.Printf("  ⚠⚠⚠ %s BYPASSED at %s\n", label, rcShort)
			fmt.Printf("    %s\n", result.BypassReason)
			return true
		}
		fmt.Printf("  ✓ %s green at %s\n", label, rcShort)
		fmt.Printf("    Run: %s\n", result.RunURL)
		return true
	case release.WorkflowCheckPending:
		fmt.Printf("  ✗ %s is still pending at %s\n", label, rcShort)
		fmt.Printf("    Watch: gh run watch %d\n", result.RunID)
		fmt.Printf("    URL:   %s\n", result.RunURL)
		fmt.Println("    Fix: wait for the run to complete, then re-run stable")
		return false
	case release.WorkflowCheckFailed:
		fmt.Printf("  ✗ %s failed at %s (conclusion: %s)\n", label, rcShort, result.Detail)
		fmt.Printf("    See: gh run view %d --log-failed\n", result.RunID)
		fmt.Printf("    URL: %s\n", result.RunURL)
		fmt.Println("    Fix:")
		fmt.Printf("      Retry the failed jobs (if transient): gh run rerun --failed %d\n", result.RunID)
		fmt.Println("      Or push a fix to master, cut a new RC, then re-run stable")
		return false
	case release.WorkflowCheckMissing:
		fmt.Printf("  ✗ %s has not run for %s\n", label, rcShort)
		// Dispatch against the RC tag, not rcCommit: workflow_dispatch
		// rejects bare SHAs. The RC tag points exactly at rcCommit and is
		// already on origin (it was pushed when the RC was cut).
		fmt.Printf("    Trigger: %s\n", release.WorkflowTriggerCommand(workflow, rcTag))
		fmt.Printf("    Watch:   %s\n", release.WorkflowURL(workflow))
		fmt.Println("    Fix: run the trigger command above, wait for green, re-run stable")
		return false
	case release.WorkflowCheckUnknown:
		fmt.Printf("  ✗ %s status check failed (GitHub API error)\n", label)
		fmt.Printf("    Detail: %s\n", result.Detail)
		fmt.Println("    Fix: check network connectivity / GITHUB_TOKEN; or re-run later")
		return false
	}
	fmt.Printf("  ✗ %s returned unexpected status %q\n", label, result.Status)
	return false
}

// checkRCArtifactGate is the pre-flight asset/manifest gate for
// releaseStableCmd. Verifies that the latest RC's release.yaml has
// published every GitHub Release asset (binaries + checksums + manifest
// + seed) and every ghcr.io Docker manifest (app, db, worker, proxy).
//
// Strategy: probe release.yaml FIRST (it's the workflow that produces
// both asset sets). On Pending/Failed/Missing/Unknown the diagnostic is
// the run URL + `gh run watch`/`rerun --failed` command — far more
// actionable than the raw "asset not uploaded" list that derives from
// the underlying workflow state. Only on Green do we also probe
// CheckAssets+CheckManifests; if the workflow succeeded but a probe
// still fails that's a true asset bug worth surfacing per-item.
//
// Returns true when ALL artifacts (and the workflow that produced them)
// are present and green; false otherwise (caller aggregates into
// allPassed).
func checkRCArtifactGate(rcTag string) bool {
	wf := release.CheckReleaseWorkflowAtTag(rcTag)
	switch wf.Status {
	case release.ReleaseWorkflowGreen:
		// Workflow done — verify the assets it should have produced
		// actually landed. Most of the time this is the happy path:
		// one summary line.
		assetResults := release.CheckAssets(rcTag)
		manifestResults := release.CheckManifests(rcTag)
		assetsOK, manifestsOK := 0, 0
		var failures []string
		// CheckResult.Name is already namespaced ("asset: <name>" /
		// "image: <name>"), so we use r.Name verbatim — prefixing
		// again here would produce "asset asset: <name>: <err>".
		for _, r := range assetResults {
			if r.OK {
				assetsOK++
			} else {
				failures = append(failures, fmt.Sprintf("    %s: %s", r.Name, r.Err))
			}
		}
		for _, r := range manifestResults {
			if r.OK {
				manifestsOK++
			} else {
				failures = append(failures, fmt.Sprintf("    %s: %s", r.Name, r.Err))
			}
		}
		if len(failures) == 0 {
			fmt.Printf("  ✓ RC %s artifacts present (%d release assets, %d ghcr manifests)\n",
				rcTag, assetsOK, manifestsOK)
			fmt.Printf("    release.yaml: %s\n", wf.RunURL)
			return true
		}
		// Workflow green but probes still failing — rare, but worth a
		// detailed per-asset breakdown so the operator can investigate.
		// Surface the release.yaml run links too: even though the run
		// itself reported success, the logs / job timeline are where
		// the operator looks to understand why an asset upload silently
		// dropped (most common cause: ghcr / GH Releases eventual-
		// consistency window between the API marking success and the
		// resource becoming visible on the public read paths).
		fmt.Printf("  ✗ RC %s release.yaml is green but artifact probes fail (%d assets, %d manifests OK; %d missing)\n",
			rcTag, assetsOK, manifestsOK, len(failures))
		fmt.Printf("    Watch: gh run watch %d\n", wf.RunID)
		fmt.Printf("    View:  gh run view %d --log-failed\n", wf.RunID)
		fmt.Printf("    URL:   %s\n", wf.RunURL)
		for _, f := range failures {
			fmt.Println(f)
		}
		fmt.Println("    Fix: retry in ~5 minutes (eventual-consistency on GHCR/Releases),")
		fmt.Println("         then if still missing, inspect: ./sb release check --tag " + rcTag)
		return false
	case release.ReleaseWorkflowPending:
		fmt.Printf("  ✗ RC %s release.yaml is still running\n", rcTag)
		fmt.Printf("    Watch: gh run watch %d\n", wf.RunID)
		fmt.Printf("    URL:   %s\n", wf.RunURL)
		fmt.Println("    Fix: wait for the run to complete, then re-run stable")
		return false
	case release.ReleaseWorkflowFailed:
		fmt.Printf("  ✗ RC %s release.yaml failed (conclusion: %s)\n", rcTag, wf.Detail)
		fmt.Printf("    See: gh run view %d --log-failed\n", wf.RunID)
		fmt.Printf("    URL: %s\n", wf.RunURL)
		fmt.Println("    Fix:")
		fmt.Printf("      Retry the failed jobs (if transient): gh run rerun --failed %d\n", wf.RunID)
		fmt.Println("      Or push a fix to master, cut a new RC, then re-run stable")
		return false
	case release.ReleaseWorkflowMissing:
		fmt.Printf("  ✗ RC %s release.yaml has not run yet\n", rcTag)
		fmt.Printf("    Workflow: %s\n", release.ReleaseWorkflowURL())
		fmt.Println("    Fix: release.yaml is triggered by the RC tag push — confirm the RC tag")
		fmt.Println("         was pushed to origin (git push origin " + rcTag + "), then wait")
		return false
	case release.ReleaseWorkflowUnknown:
		fmt.Printf("  ✗ RC %s release.yaml status check failed (GitHub API error)\n", rcTag)
		fmt.Printf("    Detail: %s\n", wf.Detail)
		fmt.Println("    Fix: check network connectivity / GITHUB_TOKEN; or re-run later")
		return false
	}
	fmt.Printf("  ✗ RC %s release.yaml returned unexpected status %q\n", rcTag, wf.Status)
	return false
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

		// Surface the release.yaml workflow state for the tag so the
		// operator gets a runnable command to monitor or retry rather
		// than navigating the Actions UI by hand.
		fmt.Println("Release workflow:")
		wf := release.CheckReleaseWorkflowAtTag(tag)
		switch wf.Status {
		case release.ReleaseWorkflowGreen:
			fmt.Printf("  ✓ %s — completed/success\n", tag)
			fmt.Printf("    URL: %s\n", wf.RunURL)
		case release.ReleaseWorkflowPending:
			fmt.Printf("  ⏳ %s — still running\n", tag)
			fmt.Printf("    Watch: gh run watch %d\n", wf.RunID)
			fmt.Printf("    URL:   %s\n", wf.RunURL)
			allPassed = false
		case release.ReleaseWorkflowFailed:
			fmt.Printf("  ✗ %s — failed (conclusion: %s)\n", tag, wf.Detail)
			fmt.Printf("    See: gh run view %d --log-failed\n", wf.RunID)
			fmt.Printf("    URL: %s\n", wf.RunURL)
			fmt.Printf("    Retry the failed jobs (if transient): gh run rerun --failed %d\n", wf.RunID)
			allPassed = false
		case release.ReleaseWorkflowMissing:
			fmt.Printf("  ✗ %s — workflow has not yet started for this tag\n", tag)
			fmt.Printf("    Workflow: %s\n", release.ReleaseWorkflowURL())
			allPassed = false
		case release.ReleaseWorkflowUnknown:
			fmt.Printf("  ⚠ %s — workflow check failed (GitHub API error)\n", tag)
			fmt.Printf("    Detail: %s\n", wf.Detail)
			// Don't flip allPassed for unknown — could be transient.
		}
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
