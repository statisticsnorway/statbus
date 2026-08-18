package cmd

import (
	"crypto/sha256"
	"encoding/hex"
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
		pgRegressResult := checkWorkflowAtCommit(release.WorkflowPgRegress, headFull)

		// STATBUS-219: pg_regress is a verdict about content, so it may ride an
		// exempt-only ancestor's green (same reasoning as
		// checkPrereleaseWorkflowGate; Unknown excluded there and here).
		var pgRide *exemptRide
		pgRideNote := ""
		if pgRegressResult.Status != release.WorkflowCheckGreen && pgRegressResult.Status != release.WorkflowCheckUnknown {
			pgRide, pgRideNote = findExemptRide(projDir, release.WorkflowPgRegress, headFull)
		}
		switch {
		case pgRide != nil:
			printExemptRide("pg_regress", pgRide)
			// Feed the stamp-driven checks below with the RIDE TARGET's SHA, not
			// HEAD's: the truthful claim is "the suite passed at that commit", and
			// the migration/test-expected drift checks then verify ACROSS the ride
			// span on their own (they diff stampSHA..HEAD). Since migrations/ and
			// test/ are not exempt, that diff is empty by construction here — the
			// checks stay honest rather than being special-cased.
			//
			// NOT PERSISTED, unlike the CI-green branch below. The on-disk stamp is
			// a record that a suite RAN at a SHA; a ride is an inference, re-derived
			// in under a second on every invocation. Writing it to disk would let a
			// later reader — or a later code path — mistake the inference for
			// evidence, and would outlive the ancestor's green that justified it.
			latestMig, _ := migrate.LatestOnDiskMigrationVersion(projDir)
			stampBytes = []byte(pgRide.Commit + "\n" + latestMig + "\n")
		case pgRegressResult.Status == release.WorkflowCheckGreen:
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
		case pgRegressResult.Status == release.WorkflowCheckPending:
			fmt.Printf("  ✗ pg_regress is still pending at %s (no local stamp)\n", headShort)
			fmt.Printf("    Watch: gh run watch %d\n", pgRegressResult.RunID)
			fmt.Printf("    URL:   %s\n", pgRegressResult.RunURL)
			fmt.Println("    Fix: wait for the run to complete, then re-run prerelease")
			fmt.Println("    Or:  ./dev.sh migrate-and-test fast   (write local stamp from your machine)")
			allPassed = false
		case pgRegressResult.Status == release.WorkflowCheckFailed:
			fmt.Printf("  ✗ pg_regress failed at %s (conclusion: %s; no local stamp)\n", headShort, pgRegressResult.Detail)
			fmt.Printf("    See: gh run view %d --log-failed\n", pgRegressResult.RunID)
			fmt.Printf("    URL: %s\n", pgRegressResult.RunURL)
			fmt.Println("    Fix:")
			fmt.Printf("      Retry the failed jobs (if transient): gh run rerun --failed %d\n", pgRegressResult.RunID)
			fmt.Println("      Or push a fix to master, then re-run prerelease")
			fmt.Println("      Or run locally: ./dev.sh migrate-and-test fast   (write local stamp)")
			allPassed = false
		case pgRegressResult.Status == release.WorkflowCheckMissing:
			fmt.Printf("  ✗ pg_regress has not run for %s (no local stamp)\n", headShort)
			fmt.Printf("    Trigger: %s\n", release.WorkflowTriggerCommand(release.WorkflowPgRegress, headFull))
			fmt.Printf("    Watch:   %s\n", release.WorkflowURL(release.WorkflowPgRegress))
			fmt.Println("    Fix: run the trigger command above, wait for green, re-run prerelease")
			fmt.Println("    Or:  ./dev.sh migrate-and-test fast   (write local stamp from your machine)")
			allPassed = false
		case pgRegressResult.Status == release.WorkflowCheckUnknown:
			fmt.Printf("  ✗ pg_regress status check failed (GitHub API error; no local stamp)\n")
			fmt.Printf("    Detail: %s\n", pgRegressResult.Detail)
			fmt.Println("    Fix: check network connectivity / GITHUB_TOKEN; or re-run later")
			fmt.Println("    Or:  ./dev.sh migrate-and-test fast   (write local stamp from your machine)")
			allPassed = false
		}
		if pgRide == nil && pgRideNote != "" {
			fmt.Printf("    No earlier green run also covers this commit: %s\n", pgRideNote)
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
	//
	//     IMAGES NEVER RIDES AN EXEMPT-ONLY ANCESTOR — PERMANENTLY EXCLUDED from
	//     the STATBUS-219 mechanism, and this is a category difference, not a
	//     policy preference. Every other preflight gate asks "did this CONTENT
	//     pass?", and content byte-identical to a tested ancestor has provably
	//     passed. This one asks "do the Docker artifacts EXIST at this SHA?" —
	//     a question about the world, not about the code. No argument about
	//     markdown makes an image materialise at a SHA nothing ever published
	//     to, and the consequence is already written down one file over: the
	//     SKIP_IMAGES bypass text warns "Deployments may FAIL on stale ghcr.io
	//     manifest" (workflow_check.go:104-107). fast-tests proves the coupling
	//     empirically — on the chained path it PULLS the commit_short-tagged
	//     images rather than building them. Riding here would cut a release
	//     whose deployment has no images. Do NOT call findExemptRide below.
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

	// 13-15. Commit-scope workflow oracles (STATBUS-199 D1 — the King:
	// "I would rather have the gating for obvious things as early as
	// possible"). These three workflows fire on the COMMIT (master push /
	// PR), so a green run can exist before any tag — they gate here at
	// the cut, blocking a red master workflow at the earliest possible
	// signal instead of at stable promotion. Each has its own loud
	// SKIP_*=1 bypass, same shape as the images check above.
	// releaseStableCmd no longer re-owns these; it prints one line noting
	// it rides this gating instead (see checkPrereleaseWorkflowGate + the
	// stable command below).
	//
	// test-hardening.yaml and test-install.yaml are NOT gated here
	// (STATBUS-205): both trigger ONLY on v*-rc.* tag push (+ manual
	// dispatch). Gating them pre-tag is a deadlock — the preflight would
	// demand runs that only the tag it refuses to cut can start. They are
	// the King's exception clause ("...except where we need the
	// pre-release to actually test the gate") and gate at stable
	// promotion instead, where the RC tag exists and has fired them
	// (checkStableWorkflowGate).
	allPassed = checkPrereleaseWorkflowGate(projDir, release.WorkflowGoTest, "go-test", "SKIP_GO_TEST") && allPassed
	allPassed = checkPrereleaseWorkflowGate(projDir, release.WorkflowAppBuildLint, "app-build-lint", "SKIP_APP_BUILD_LINT") && allPassed
	allPassed = checkPrereleaseWorkflowGate(projDir, release.WorkflowFastTests, "fast-tests", "SKIP_FAST_TESTS") && allPassed

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

// checkPrereleaseWorkflowGate runs one of the HEAD-targeted commit-scope
// workflow gates for preflightChecks (STATBUS-199 D1). Same
// Green/Pending/Failed/Missing/Unknown switch + loud SKIP_*=1 bypass
// shape as the stable-layer gates (checkUpgradeArcHarnessGate,
// checkInstallRecoveryHarnessGate), but keyed on HEAD rather than an RC
// tag/commit — no RC exists yet at prerelease time — so the Missing
// remedy uses dispatchRefForMasterTip (mirrors the images check just
// above) instead of an RC tag ref.
//
// Returns true when the gate is satisfied (Green, or SKIP_*=1 bypass);
// false otherwise (caller aggregates into allPassed).
func checkPrereleaseWorkflowGate(projDir, workflow, label, skipEnv string) bool {
	if os.Getenv(skipEnv) == "1" {
		fmt.Printf("  ⚠ %s SKIPPED (%s=1)\n", label, skipEnv)
		fmt.Printf("    Operator bypass — ensure %s ran via CI or by hand on this commit.\n", label)
		return true
	}
	headOut, _ := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD")
	headFull := strings.TrimSpace(headOut)
	headShort := headFull
	if len(headShort) > 12 {
		headShort = headShort[:12]
	}
	result := checkWorkflowAtCommit(workflow, headFull)
	if result.Status == release.WorkflowCheckGreen {
		fmt.Printf("  ✓ %s green at %s\n", label, headShort)
		fmt.Printf("    Run: %s\n", result.RunURL)
		return true
	}

	// STATBUS-219: this gate is a VERDICT ABOUT CONTENT — "did this code pass?"
	// — so a green run at an ancestor whose entire difference from the tip is
	// test-irrelevant (board markdown) proves exactly the same thing about the
	// tip's code. Try that ride before refusing, on Missing, Pending AND Failed
	// alike: what a board commit does to this gate is make a REDUNDANT run
	// necessary, and which of the three states that shows up as is an accident
	// of timing. Unknown is excluded — an unreachable API cannot verify an
	// ancestor either, and the refusal there is about the check, not the code.
	rideNote := ""
	if result.Status != release.WorkflowCheckUnknown {
		if ride, whyNot := findExemptRide(projDir, workflow, headFull); ride != nil {
			printExemptRide(label, ride)
			return true
		} else {
			rideNote = whyNot
		}
	}

	switch result.Status {
	case release.WorkflowCheckPending:
		fmt.Printf("  ✗ %s is still pending at %s\n", label, headShort)
		fmt.Printf("    Watch: gh run watch %d\n", result.RunID)
		fmt.Printf("    URL:   %s\n", result.RunURL)
		fmt.Println("    Fix: wait for the run to complete, then re-run prerelease")
	case release.WorkflowCheckFailed:
		fmt.Printf("  ✗ %s failed at %s (conclusion: %s)\n", label, headShort, result.Detail)
		fmt.Printf("    See: gh run view %d --log-failed\n", result.RunID)
		fmt.Printf("    URL: %s\n", result.RunURL)
		fmt.Println("    Fix:")
		fmt.Printf("      Retry the failed jobs (if transient): gh run rerun --failed %d\n", result.RunID)
		fmt.Println("      Or push a fix to master, then re-run prerelease")
	case release.WorkflowCheckMissing:
		fmt.Printf("  ✗ %s has not run for %s\n", label, headShort)
		if ref, ok := dispatchRefForMasterTip(projDir, headFull); ok {
			fmt.Printf("    Trigger: %s\n", release.WorkflowTriggerCommand(workflow, ref))
			fmt.Printf("    Watch:   %s\n", release.WorkflowURL(workflow))
			fmt.Println("    Fix: run the trigger command above, wait for green, re-run prerelease")
		} else {
			fmt.Printf("    %s is not origin/master's tip — workflow_dispatch builds a branch/tag tip, not a bare SHA.\n", headShort)
			fmt.Println("    Fix: push this commit to master, then re-run prerelease")
		}
	case release.WorkflowCheckUnknown:
		fmt.Printf("  ✗ %s status check failed (GitHub API error)\n", label)
		fmt.Printf("    Detail: %s\n", result.Detail)
		fmt.Println("    Fix: check network connectivity / GITHUB_TOKEN; or re-run later")
	default:
		fmt.Printf("  ✗ %s returned unexpected status %q\n", label, result.Status)
	}
	if rideNote != "" {
		fmt.Printf("    No earlier green run also covers this commit: %s\n", rideNote)
	}
	return false
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

	return checkImmutabilityGateAgainst(projDir, prevTag)
}

// checkImmutabilityGateAgainst is checkImmutabilityGate's verdict half, split out
// from the predecessor DISCOVERY above so the comparison can be exercised against
// an explicit tag (STATBUS-233). Discovery picks WHICH tag; this decides whether
// comparing against it means anything, and only then compares.
func checkImmutabilityGateAgainst(projDir, prevTag string) bool {
	// STATBUS-233: REFUSE rather than compare across disconnected histories.
	//
	// The immutability comparison only means something when the two releases
	// share ancestry. This repository was rebaselined on 2026-07-14 —
	// 77fa16fb25bfefe is the ROOT commit of the current history — so every
	// stable tag from before it sits on a graph HEAD never descended from.
	// `pickPrereleasePredecessor` can legitimately land on one: with no prior RC
	// for this patch it falls through to findLatestStableTagBeforePrefix
	// (release_verify.go), whose cross-year-month rule is correct and, since the
	// rebaseline, can only reach backwards across that boundary.
	//
	// Git will diff two unrelated trees without complaint; the answer is simply
	// noise. Every migration re-committed in the new root reads as "modified",
	// and a genuine post-release edit would be indistinguishable from that
	// flood. Both directions of the resulting verdict are harmful: a false-
	// positive flood trains an operator to bless past the gate, and a single
	// blanket bless baselines a whole corpus nobody read.
	//
	// So the gate does not answer. It says WHY it cannot, which is the honest
	// state and one an operator can act on. Self-closing: promoting the first
	// stable in THIS history gives the next patch's first RC a connected
	// baseline, and the gate becomes meaningful again.
	connected, ancErr := tagIsAncestorOfHEAD(projDir, prevTag)
	if ancErr != nil {
		fmt.Printf("  ✗ Migration immutability (could not determine whether %s is an ancestor of HEAD: %v)\n", prevTag, ancErr)
		fmt.Println("    Fix: ensure the tag is fetched locally (git fetch --tags), then re-run")
		return false
	}
	if !connected {
		fmt.Printf("  ✗ Migration immutability CANNOT BE CHECKED against %s — that tag is NOT an ancestor of HEAD\n", prevTag)
		fmt.Println("    The two histories are disconnected, so a migration diff between them is noise, not a verdict:")
		fmt.Println("      every migration re-committed under the current root reads as \"modified\",")
		fmt.Println("      and a genuine post-release edit would be indistinguishable from that flood.")
		fmt.Printf("    Verify: git merge-base --is-ancestor %s HEAD   (exits non-zero — no shared ancestry)\n", prevTag)
		fmt.Println("    Why: this repository was rebaselined; the pre-rebaseline stable tags sit on the discarded graph.")
		fmt.Println("    Fix: promote the first stable in THIS history. Its RCs compare against each other (connected,")
		fmt.Println("         and meaningful), and once that stable exists the next patch's first RC has a connected")
		fmt.Println("         baseline — this refusal then disappears on its own.")
		return false
	}

	label := "previous RC"
	if !strings.Contains(prevTag, "-rc.") {
		label = "previous stable"
	}
	if err := checkMigrationImmutability(projDir, prevTag, label); err != nil {
		// checkMigrationImmutability already printed the full per-file
		// explanation (STATBUS-202: inspect-first, bless-declaration last)
		// — nothing to add here.
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
// (no `-rc.` suffix), every modified version is by definition shipped in
// stable — the REFUSAL text carries a coordination line so the operator
// reads it BEFORE declaring the bless (STATBUS-205 Fix 2); a declared
// pass prints only the neutral ⟳ receipt.
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
	type modifiedMigration struct {
		status  string
		file    string
		version int64 // 0 if the filename didn't parse as <14-digit>_...
	}
	var modified []modifiedMigration
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

		// Extract the 14-digit version prefix from the filename — needed both
		// for STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION below and
		// for the STATBUS-202 already-blessed lookup further down.
		var version int64
		base := filepath.Base(file)
		if underscore := strings.Index(base, "_"); underscore > 0 {
			if v, parseErr := strconv.ParseInt(base[:underscore], 10, 64); parseErr == nil {
				version = v
			}
		}

		// Honour STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION: skip if
		// this version is explicitly listed.
		if version != 0 && fixBroken[version] {
			fixedBroken = append(fixedBroken, version)
			continue
		}

		modified = append(modified, modifiedMigration{status: status, file: file, version: version})
	}

	// Log fix-broken activity before the gate decision so the operator
	// sees what they bypassed even on a passing run. Neutral receipt only
	// (STATBUS-205 Fix 2): the stable-shipped coordination warning belongs
	// in the REFUSAL below, where the operator reads BEFORE declaring —
	// printing it after the declaration hedged a decision already made.
	for _, v := range dedupeInt64Sorted(fixedBroken) {
		fmt.Printf("    ⟳ Intentionally fixing broken (immutable) migration %d (declared in %s)\n", v, release.IntentionallyFixBrokenImmutableMigrationEnvVar)
	}

	if len(modified) == 0 {
		fmt.Printf("  ✓ No migrations modified since %s (%s)\n", prevTag, label)
		return nil
	}

	// STATBUS-202: inspect-and-explain BEFORE the remedy. Per modified file:
	// the reframe sentence, then paste-ready `git diff`/`git log` commands
	// against the real tag and real path (no placeholders), then — when the
	// file's CURRENT bytes are already carried by a cut release (STATBUS-166
	// content-level trust) — the already-blessed context naming that tag. The
	// bless-declaration env var is the LAST line of the whole message, framed
	// as the deliberate per-cut declaration it is, never a "Fix:".
	fmt.Printf("  ✗ Migrations modified since %s (%s)\n", prevTag, label)
	fmt.Println()

	// STATBUS-202 AC#5: the `git log` suggestion below assumes prevTag is
	// reachable from HEAD. On a rebaselined line (e.g. the 2026-07-14
	// source-version consolidation) it is not — the log would show the
	// wholesale consolidation commit, not the edit, and mislead the
	// operator. Only offer it when merge-base actually proves the
	// ancestry; prevTag is fixed for this whole call, so check once. The
	// `git diff` line above is history-independent and stays unconditional
	// either way.
	_, ancestorErr := upgrade.RunCommandOutput(projDir, "git", "merge-base", "--is-ancestor", prevTag, "HEAD")
	prevIsAncestor := ancestorErr == nil

	for _, m := range modified {
		fmt.Printf("  %s %s\n", m.status, m.file)
		fmt.Printf("    A released migration differs from its bytes at %s. Inspect and explain the change before deciding:\n", prevTag)
		fmt.Printf("      git diff %s HEAD -- %s\n", prevTag, m.file)
		if prevIsAncestor {
			fmt.Printf("      git log %s..HEAD -- %s\n", prevTag, m.file)
		} else {
			fmt.Printf("    note: %s is not an ancestor of HEAD (history was rebaselined since the stable) — commit-level log cannot isolate this edit; the git diff above is the authoritative comparison.\n", prevTag)
		}

		// A deleted file has no current bytes to hash or bless — this check
		// only applies to files still present at HEAD.
		if m.status != "D" && m.version != 0 {
			if data, readErr := os.ReadFile(filepath.Join(projDir, m.file)); readErr == nil {
				sum := sha256.Sum256(data)
				hash := hex.EncodeToString(sum[:])
				if tag, blessErr := release.ReleaseTagWithMigrationHash(projDir, m.version, hash); blessErr != nil {
					fmt.Printf("    (could not check already-blessed status: %v)\n", blessErr)
				} else if tag != "" {
					fmt.Printf("    These exact bytes are already carried by %s — prior cuts declared this bless; re-declare to proceed.\n", tag)
				}
			}
		}
		fmt.Println()
	}

	fmt.Println("  The ONLY sanctioned reason to change a released migration is to FIX A GENUINELY")
	fmt.Println("  BROKEN one: a crash/timeout/OOM fix that PRESERVES THE RESULT. A result change")
	fmt.Println("  goes in a NEW forward migration (./sb migrate new), never by editing this file.")
	fmt.Println("  If you are NOT certain the migration is genuinely broken AND that your fix")
	fmt.Println("  preserves the result, STOP and consult the maintainer — do not set the var on a guess:")
	fmt.Println("  it silently overrides a safety invariant on every box that already ran the migration.")
	fmt.Printf("  Otherwise, revert to the bytes at %s (see the git diff commands above).\n", prevTag)
	fmt.Println()
	if prevIsStable {
		fmt.Printf("  %s is a STABLE tag — this migration shipped in production; a bless must be\n", prevTag)
		fmt.Println("  coordinated with downstream rollouts (see doc/upgrade-timeline.md).")
		fmt.Println()
	}
	fmt.Println("  ONLY if you have inspected the diff above and are certain this is a deliberate,")
	fmt.Println("  sanctioned fix: declare it. Each cut re-declares intent — there is no stored")
	fmt.Println("  second record; setting this is itself the bless, made fresh at this cut:")
	// STATBUS-206 (202 directive 2): the gate just enumerated the modified
	// versions — print the paste-ready command with them filled in, never a
	// template the operator must assemble at the console. The template form
	// survives only for the no-parsed-version case (unparseable filenames),
	// where there is nothing concrete to fill in.
	var modifiedVersions []int64
	for _, m := range modified {
		if m.version != 0 {
			modifiedVersions = append(modifiedVersions, m.version)
		}
	}
	if versions := dedupeInt64Sorted(modifiedVersions); len(versions) > 0 {
		parts := make([]string, len(versions))
		for i, v := range versions {
			parts[i] = strconv.FormatInt(v, 10)
		}
		fmt.Printf("    %s=%s ./sb release prerelease\n", release.IntentionallyFixBrokenImmutableMigrationEnvVar, strings.Join(parts, ","))
	} else {
		fmt.Printf("    %s=<version>[,...] ./sb release prerelease\n", release.IntentionallyFixBrokenImmutableMigrationEnvVar)
	}

	return fmt.Errorf("migrations modified since %s — deployed migrations are immutable (see per-file explanation above)", prevTag)
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
	Long: `Tag a new release candidate. Pre-flight validates HEAD before tagging.

Includes the commit-scope workflow oracles (STATBUS-199 D1: "gate obvious
things as early as possible" — these need only the commit, not a cut RC
tag, so they belong here rather than at stable promotion):
  - pg_regress (fast pg_regress suite; local-stamp fast path + CI fallback)
  - images (Docker artifacts build)
  - go-test (go vet + go test ./...)
  - app-build-lint (app/ build + lint)
  - fast-tests

test-hardening and test-install are NOT gated here (STATBUS-205): both
fire only on the RC tag push itself, so demanding them pre-tag would be
a deadlock. They gate at stable promotion — the King's exception clause
("...except where we need the pre-release to actually test the gate").

...plus migration immutability, working tree / branch / signing checks,
and the app/types/db-docs stamp chain. See the per-check output for each
one's own Fix guidance.

Operator bypasses (use sparingly — each one is an admission that a gate's
invariant has NOT been verified for the SHA):
  SKIP_GO_TEST=1
  SKIP_APP_BUILD_LINT=1
  SKIP_FAST_TESTS=1
(No SKIP for pg_regress or images by design — see their own checks' comments.)

release stable then RIDES this gating rather than re-checking it — see
` + "`./sb release stable --help`" + ` for what stable still gates on its own
(the checks that genuinely need the RC tag to exist).
`,
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

Commit-scope oracles (images, fast-tests, go-test, app-build-lint) are
gated EARLIER, at the RC cut (prerelease preflight) — a red master
workflow blocks at the cut, the earliest possible signal, not here.
Stable RIDES that gating rather than re-checking it (STATBUS-199 D1).

Pre-flight — only what genuinely needs the RC TAG to exist:
  - Latest RC exists for v<YEAR>.<MONTH>.<NEXT_PATCH>
  - That patch is next-in-sequence for vYYYY.MM
  - test-hardening green at the RC's commit (fires on the RC tag push —
    cannot exist before the tag, so it gates here; STATBUS-205)
  - test-install green at the RC's commit (same tag-fired trigger)
  - upgrade-arc-harness FULL SUITE green at (or since) the RC's commit —
    path-sensitivity walk rides a prior green when nothing upgrade-
    sensitive changed (STATBUS-199 D2)
  - install-recovery-harness FULL SUITE green at the RC's commit
  - RC release artifacts (GitHub assets + ghcr manifests) all present
  - canary convergence (observational; per-slot bypass, see below)

Operator bypasses (use sparingly — each one is an admission that a
gate's invariant has NOT been verified for the SHA):
  SKIP_TEST_HARDENING=1    (install-path hardening not exercised)
  SKIP_TEST_INSTALL=1      (Hetzner VM end-to-end install not exercised)
  SKIP_UPGRADE_ARCS=1      (no upgrade-arc regression net was exercised)
  SKIP_INSTALL_RECOVERY=1  (no recovery regression net was exercised)
  STATBUS_SKIP_CANARY=<label>[,<label>...]  (per-slot canary bypass)

Commit-scope bypasses (SKIP_IMAGES, SKIP_FAST_TESTS, SKIP_GO_TEST,
SKIP_APP_BUILD_LINT) apply at the prerelease cut — see
` + "`./sb release prerelease --help`" + `.
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

		// 3. Commit-scope oracles (images, fast-tests, go-test, app-build-
		//    lint) are gated EARLIER, at the RC cut (prerelease preflight)
		//    — STATBUS-199 D1. Stable no longer re-checks them; it rides
		//    that gating. Only checks that genuinely need the RC TAG to
		//    exist stay here: the tag-fired workflows (test-hardening,
		//    test-install — their only automatic trigger IS the RC tag
		//    push, STATBUS-205), the two VM harnesses, and canary
		//    convergence (below).
		fmt.Println("  ✓ Commit-scope oracles (images/fast-tests/go-test/app-build-lint) were gated at the RC cut (prerelease preflight) — stable rides the RC's gating.")
		allPassed := true
		// test-hardening + test-install (STATBUS-205): both fire only on
		// the v*-rc.* tag push (+ manual dispatch), so no run can exist
		// before the RC tag — gating them at prerelease preflight was a
		// deadlock. They gate here, keyed on the RC's commit, with the RC
		// tag as the dispatch ref for the Missing remedy.
		allPassed = checkStableWorkflowGate(release.WorkflowTestHardening, "test-hardening", "SKIP_TEST_HARDENING", latestRC, rcCommit, rcShort) && allPassed
		allPassed = checkStableWorkflowGate(release.WorkflowTestInstall, "test-install", "SKIP_TEST_INSTALL", latestRC, rcCommit, rcShort) && allPassed
		// Install-recovery harness: every C-class with a paired scenario in
		// test/install-recovery/scenarios/ gets exercised on a dedicated
		// Hetzner cx23. The workflow at .github/workflows/install-recovery-
		// harness.yaml fires on the RC's tag push and is the empirical
		// half of the no-hotfix discipline — without this gate, the
		// "release stable promotes a verified-recovery RC" invariant
		// reduces to "release stable promotes a never-crashed-in-CI RC".
		// STATBUS-199 §5 rider (comment #1, closed by comment #6's
		// scenario-domain ruling): the same any-green softness latent in a
		// plain check — a green workflow_dispatch named-subset run at the
		// RC commit would also satisfy it — closes via the same
		// jobs-completeness treatment as the arc-harness gate below.
		allPassed = checkInstallRecoveryHarnessGate(projDir, latestRC, rcCommit, rcShort) && allPassed
		// Upgrade-arc harness (STATBUS-199 D2): the 31 real-dispatch upgrade
		// arcs (STATBUS-071) — serve-proven writers, park lifecycle, deploy
		// honesty. Path-sensitive: an RC whose diff against the previous RC
		// touches nothing in ops/release/upgrade-sensitive-paths.txt may
		// ride the newest prior FULL-SUITE green instead of requiring a
		// fresh one (the gate computes this itself — never trusts the
		// workflow's own short-circuit judgment call, only its own diff).
		allPassed = checkUpgradeArcHarnessGate(projDir, latestRC, rcCommit, rcShort) && allPassed

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

// upgradeSensitivePathsFile is the checked-in list checkUpgradeArcHarnessGate
// quotes verbatim in its output — see the file's own header for the
// matching rule (substring containment, deliberately over-inclusive).
const upgradeSensitivePathsFile = "ops/release/upgrade-sensitive-paths.txt"

// ciExemptPathsFile is the checked-in list of paths whose changes cannot
// affect any test outcome, build artifact, or runtime behaviour (STATBUS-219,
// doc-030). See the file's own header for the matching rule — an ANCHORED
// PREFIX, deliberately under-inclusive.
const ciExemptPathsFile = "ops/release/ci-exempt-paths.txt"

// ciExemptRideWalkBound caps the first-parent ancestor walk. Bounded for the
// same reason the arc gate's RC walk is: an unbounded walk on a long history
// would issue an API call per exempt-clean candidate. 50 commits is far past
// any plausible run of board-only commits.
const ciExemptRideWalkBound = 50

// loadCIExemptPaths reads ciExemptPathsFile: one path prefix per line, blank
// lines and #-comments ignored. Mirrors loadUpgradeSensitivePaths' shape; the
// MATCHING rule is the inverse (see fileIsCIExempt).
func loadCIExemptPaths(projDir string) ([]string, error) {
	data, err := os.ReadFile(filepath.Join(projDir, ciExemptPathsFile))
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", ciExemptPathsFile, err)
	}
	var paths []string
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		paths = append(paths, line)
	}
	return paths, nil
}

// fileIsCIExempt reports whether one changed file is covered by the exempt
// list, matching an ANCHORED PATH PREFIX.
//
// THE MATCHING RULE IS THE DELIBERATE INVERSE OF diffTouchesSensitivePath, AND
// THE INVERSION IS LOAD-BEARING — do not "unify" the two helpers. That one uses
// substring containment because for a SENSITIVITY list over-inclusive is the
// safe direction: a coincidental hit costs one extra full-suite run. Here the
// failure directions mirror. Over-inclusive matching would treat MORE commits
// as needing no tests, so a sloppy match waves UNTESTED CODE into a release.
// Every ambiguity therefore resolves toward NOT exempt:
//   - `.backlog/` matches `.backlog/tasks/x.md`, never `app/src/.backlog-x.ts`
//     (which substring containment would have wrongly exempted).
//   - an entry without a trailing slash matches that exact file, or that
//     directory's contents — never a sibling sharing its name as a prefix
//     (`doc` must not exempt `docker-compose.yml`).
//   - a path git printed QUOTED (non-ASCII or special characters yield
//     "\303\251...") begins with a quote and matches nothing — it is treated as
//     non-exempt, which is the safe direction.
//
// KEEP THAT LAST CLAUSE — IT IS A BELT, NOT DEAD CODE. findExemptRide reads the
// diff with `-z`, so git emits raw bytes and quoted paths should never reach
// here. That is exactly why the guard must stay: if anyone ever drops the -z,
// this repo's em-dashed board filenames start arriving quoted again, and the
// failure this guard produces is a REFUSED ride (safe, visible) instead of a
// wrongly-exempted path (untested code into a release). Deleting it as
// unreachable would convert a safe failure into a silent one.
func fileIsCIExempt(file string, exempt []string) bool {
	file = strings.TrimSpace(file)
	if file == "" {
		return false
	}
	for _, entry := range exempt {
		if entry == "" {
			continue
		}
		if strings.HasSuffix(entry, "/") {
			if strings.HasPrefix(file, entry) {
				return true
			}
			continue
		}
		if file == entry || strings.HasPrefix(file, entry+"/") {
			return true
		}
	}
	return false
}

// changedFilesAllExempt splits a changed-file list into the files that justify
// a ride (all exempt) and the offenders that forbid it. allExempt is true only
// when EVERY changed file is exempt — including the empty case, where the two
// trees are identical and riding is sound by definition (the add-then-revert
// pair doc-030 calls out; a direct diff, not per-hop induction, is what makes
// that visible).
func changedFilesAllExempt(changed, exempt []string) (allExempt bool, justifying, offenders []string) {
	for _, file := range changed {
		file = strings.TrimSpace(file)
		if file == "" {
			continue
		}
		if fileIsCIExempt(file, exempt) {
			justifying = append(justifying, file)
			continue
		}
		offenders = append(offenders, file)
	}
	return len(offenders) == 0, justifying, offenders
}

// exemptRide is a found ride: a green run for the gate at an ancestor whose
// direct diff to the tip changes only exempt paths.
type exemptRide struct {
	// Commit is the ride target's full SHA — the commit the run actually ran at.
	Commit string
	// Result is that commit's green WorkflowCheckResult (carries the run URL).
	Result release.WorkflowCheckResult
	// CommitsRidden counts the commits between the target and the tip.
	CommitsRidden int
	// Justifying lists every file in the direct diff — all exempt, by
	// construction. Empty means the trees are identical.
	Justifying []string
}

// findExemptRide answers "is there a green run for this VERDICT gate at an
// ancestor whose entire difference from the tip is test-irrelevant?"
// (STATBUS-219 Stage 1). It walks first-parent ancestors NEAREST FIRST, bounded
// at ciExemptRideWalkBound, computing the DIRECT `git diff --name-only
// <candidate>..<tip>` for each — never per-hop induction, the same
// correct-by-construction reasoning checkUpgradeArcHarnessGate documents.
//
// It does NOT stop at the first non-exempt candidate, and that is deliberate:
// a direct diff compares TREES, so a commit that adds code and a later one that
// reverts it leave an OLDER ancestor tree-identical to the tip even though a
// nearer one differs. Stopping early would discard a sound ride. The walk is
// bounded, and only exempt-clean candidates cost an API call.
//
// Returns (nil, reason) when no ride applies; the reason is operator-facing and
// printed under the gate's normal refusal. NEVER call this for the images gate
// — see checkImagesNeverRides' comment at the images check.
func findExemptRide(projDir, workflow, tipFull string) (*exemptRide, string) {
	exempt, err := loadCIExemptPaths(projDir)
	if err != nil {
		return nil, fmt.Sprintf("the exempt-path list could not be read (%v)", err)
	}
	if len(exempt) == 0 {
		return nil, fmt.Sprintf("%s lists no exempt paths — nothing can ride", ciExemptPathsFile)
	}

	out, rerr := upgrade.RunCommandOutput(projDir, "git", "rev-list", "--first-parent",
		fmt.Sprintf("-n%d", ciExemptRideWalkBound+1), tipFull)
	if rerr != nil {
		return nil, fmt.Sprintf("the first-parent ancestor walk could not run (%v)", rerr)
	}
	var ancestors []string
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		commit := strings.TrimSpace(line)
		if commit == "" || commit == tipFull {
			continue
		}
		ancestors = append(ancestors, commit)
	}
	if len(ancestors) == 0 {
		return nil, "the tip has no ancestors to ride"
	}

	firstOffender := ""
	sawExemptCleanCandidate := false
	for i, candidate := range ancestors {
		// -z IS LOAD-BEARING, NOT HYGIENE. Without it `git diff --name-only`
		// QUOTES any path with non-ASCII or special characters
		// (".backlog/…-\342\200\224-….md"), and this repo's board filenames carry
		// em-dashes — so on precisely the board commits this ride exists to
		// unblock, every quoted path would fail the anchored-prefix match, be
		// classed non-exempt, and the ride would be inert. Verified on a real
		// board commit: 2 of 3 paths came back quoted. -z emits raw bytes
		// NUL-separated, which also removes the (latent) newline-in-filename
		// corruption of a newline split.
		diffOut, derr := upgrade.RunCommandOutput(projDir, "git", "diff", "--name-only", "-z", candidate+".."+tipFull)
		if derr != nil {
			// Cannot prove this candidate's diff is exempt-only → it is not a
			// ride target. Keep walking; an older one may still be provable.
			continue
		}
		allExempt, justifying, offenders := changedFilesAllExempt(strings.Split(strings.Trim(diffOut, "\x00"), "\x00"), exempt)
		if !allExempt {
			if firstOffender == "" {
				firstOffender = offenders[0]
			}
			continue
		}
		sawExemptCleanCandidate = true
		result := checkWorkflowAtCommit(workflow, candidate)
		if result.Status != release.WorkflowCheckGreen {
			continue
		}
		return &exemptRide{
			Commit:        candidate,
			Result:        result,
			CommitsRidden: i + 1,
			Justifying:    justifying,
		}, ""
	}

	// Both facts matter to the operator and they are different problems, so
	// report whichever were actually observed. "Exempt-clean but not green"
	// means waiting or re-running will fix it; "non-exempt file" means this code
	// state genuinely has not been tested and no waiting will change that.
	switch {
	case sawExemptCleanCandidate && firstOffender != "":
		return nil, fmt.Sprintf("the ancestors whose diff to the tip is exempt-only have no green run for this workflow, and older ones differ in non-exempt files (e.g. %s) — this code state has not been tested", firstOffender)
	case sawExemptCleanCandidate:
		return nil, fmt.Sprintf("ancestors within %d commits differ from the tip only in exempt paths, but none has a green run for this workflow either", ciExemptRideWalkBound)
	case firstOffender != "":
		return nil, fmt.Sprintf("every ancestor within %d commits differs from the tip in non-exempt files (e.g. %s) — this code state has not been tested", ciExemptRideWalkBound, firstOffender)
	}
	return nil, fmt.Sprintf("no rideable ancestor within %d commits", ciExemptRideWalkBound)
}

// printExemptRide prints the ride LOUDLY — never a silent pass. The operator
// sees which commit was actually tested, how far the tip has moved since, and
// every file that justified it, so the claim is auditable at the console
// (the same standard the arc gate's RIDE printing holds).
func printExemptRide(label string, ride *exemptRide) {
	fmt.Printf("  ✓ %s green at %s — also covers this commit: the %d commit(s) since change only test-irrelevant paths\n",
		label, shortCommit(ride.Commit), ride.CommitsRidden)
	fmt.Printf("    Tested commit: %s\n", ride.Commit)
	fmt.Printf("    Run: %s\n", ride.Result.RunURL)
	if len(ride.Justifying) == 0 {
		fmt.Printf("    Files changed since (all exempt per %s): none — the trees are identical\n", ciExemptPathsFile)
		return
	}
	fmt.Printf("    Files changed since (all exempt per %s):\n", ciExemptPathsFile)
	for _, f := range ride.Justifying {
		fmt.Printf("      %s\n", f)
	}
}

// loadUpgradeSensitivePaths reads upgradeSensitivePathsFile: one
// prefix/substring per line, blank lines and #-comments ignored.
func loadUpgradeSensitivePaths(projDir string) ([]string, error) {
	data, err := os.ReadFile(filepath.Join(projDir, upgradeSensitivePathsFile))
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", upgradeSensitivePathsFile, err)
	}
	var paths []string
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		paths = append(paths, line)
	}
	return paths, nil
}

// diffTouchesSensitivePath runs `git diff --name-only fromRef..toRef` and
// reports whether any changed file contains any sensitivePaths entry as a
// substring. Returns the matched CHANGED FILES (not the matched
// sensitivity-list entries) so the caller can print exactly what tripped
// it.
func diffTouchesSensitivePath(projDir, fromRef, toRef string, sensitivePaths []string) (touched bool, matchedFiles []string, err error) {
	out, err := upgrade.RunCommandOutput(projDir, "git", "diff", "--name-only", fromRef+".."+toRef)
	if err != nil {
		return false, nil, fmt.Errorf("git diff %s..%s: %w", fromRef, toRef, err)
	}
	for _, file := range strings.Split(strings.TrimSpace(out), "\n") {
		file = strings.TrimSpace(file)
		if file == "" {
			continue
		}
		for _, p := range sensitivePaths {
			if strings.Contains(file, p) {
				matchedFiles = append(matchedFiles, file)
				break
			}
		}
	}
	return len(matchedFiles) > 0, matchedFiles, nil
}

// upgradeArcDir and upgradeArcSuffix are the arc scenario domain's
// coordinates. The SAME two strings appear in
// .github/workflows/upgrade-arc-harness.yaml's discover job, which builds
// the test matrix from them — two readers of one folder, and the gate's
// promise ("promotion means every arc ran") is only true while they agree.
// TestUpgradeArcDomainPathMatchesWorkflow pins them to the workflow file so
// a move fails LOUDLY here instead of silently emptying one side
// (STATBUS-216 AC#4, the STATBUS-199 comment #6 duplication-guard pattern).
const (
	upgradeArcDir    = "test/install-recovery/arcs/"
	upgradeArcSuffix = "-arc.sh"
)

// upgradeArcNamesAtCommit lists the arc scenario domain AT commit —
// STATBUS-199 comment #4's completeness check needs the arc set as it
// existed when the workflow ran, not rcCommit's set (they can differ:
// arcs get added over time). Single source of truth, matching the
// workflow's own discover job exactly: every
// test/install-recovery/arcs/<scenario>-arc.sh IS a scenario, no
// exclusions.
//
// An EMPTY domain is an error, never an empty list (STATBUS-216): the
// completeness check answers "is every required arc present?" with a
// trivial yes for an empty required set, so a renamed directory or a path
// typo here would disarm the gate while it printed a 0/0 pass. There is no
// legitimate state of this repository with zero arcs.
func upgradeArcNamesAtCommit(projDir, commit string) ([]string, error) {
	out, err := upgrade.RunCommandOutput(projDir, "git", "ls-tree", "-r", "--name-only",
		commit, "--", upgradeArcDir)
	if err != nil {
		return nil, fmt.Errorf("git ls-tree %s -- %s: %w", commit, upgradeArcDir, err)
	}
	var names []string
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		base := filepath.Base(strings.TrimSpace(line))
		if strings.HasSuffix(base, upgradeArcSuffix) {
			names = append(names, strings.TrimSuffix(base, upgradeArcSuffix))
		}
	}
	if len(names) == 0 {
		return nil, fmt.Errorf("no arc scenarios found at %s: `git ls-tree %s -- %s` matched no *%s file. "+
			"The arc domain cannot legitimately be empty — the directory was moved/renamed, or this path is a typo. "+
			"Refusing to check completeness against an empty domain (it would pass trivially and prove nothing). "+
			"Fix: point %s at the arcs directory as it exists at that commit, keeping it identical to the discover job's path in .github/workflows/upgrade-arc-harness.yaml",
			commit, commit, upgradeArcDir, upgradeArcSuffix, upgradeArcDir)
	}
	return names, nil
}

// installRecoveryHarnessSkipDefaultMarker mirrors
// test/install-recovery/run.sh's SKIP_DEFAULT_MARKER ("HARNESS_SKIP_DEFAULT",
// run.sh:31) — a scenario file containing this string is excluded from the
// default (blank-selector) full suite, though still individually
// selectable. Pinned byte-identical to the harness's own literal by
// TestInstallRecoveryHarnessSkipDefaultMarkerMatchesHarness: if the harness
// marker ever changes, that test fails loudly instead of this constant
// silently diverging (STATBUS-199 comment #6 duplication guard).
const installRecoveryHarnessSkipDefaultMarker = "HARNESS_SKIP_DEFAULT"

// installRecoveryScenarioNamesAtCommit reproduces run.sh's default-suite
// scenario domain AT commit — STATBUS-199 comment #6 ruling:
// COMMIT-ACCURATE REPRODUCTION, never the working tree (the gate is a pure
// function of the RC commit everywhere else; deriving from whatever tree
// happens to be checked out would reintroduce the exact drift class this
// gate exists to kill). Every test/install-recovery/scenarios/<name>.sh IS
// a scenario UNLESS its bytes at commit contain
// installRecoveryHarnessSkipDefaultMarker — read via `git show
// <commit>:<path>`, no checkout.
//
// An EMPTY domain is an error, never an empty list (STATBUS-216) — same
// reasoning as upgradeArcNamesAtCommit: a 0/0 completeness check passes
// trivially. Here emptiness has a second cause worth naming in the
// refusal: every scenario carrying the skip-default marker would also
// leave the default suite with nothing to run.
func installRecoveryScenarioNamesAtCommit(projDir, commit string) ([]string, error) {
	const scenarioDir = "test/install-recovery/scenarios/"
	out, err := upgrade.RunCommandOutput(projDir, "git", "ls-tree", "-r", "--name-only",
		commit, "--", scenarioDir)
	if err != nil {
		return nil, fmt.Errorf("git ls-tree %s -- %s: %w", commit, scenarioDir, err)
	}
	var names []string
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		path := strings.TrimSpace(line)
		if !strings.HasSuffix(path, ".sh") {
			continue
		}
		content, cerr := upgrade.RunCommandOutput(projDir, "git", "show", commit+":"+path)
		if cerr != nil {
			return nil, fmt.Errorf("git show %s:%s: %w", commit, path, cerr)
		}
		if strings.Contains(content, installRecoveryHarnessSkipDefaultMarker) {
			continue // excluded from the default full suite
		}
		names = append(names, strings.TrimSuffix(filepath.Base(path), ".sh"))
	}
	if len(names) == 0 {
		return nil, fmt.Errorf("no default-suite scenarios found at %s: `git ls-tree %s -- %s` matched no .sh file that lacks the %s marker. "+
			"The scenario domain cannot legitimately be empty — the directory was moved/renamed, this path is a typo, or every scenario is now marked skip-default. "+
			"Refusing to check completeness against an empty domain (it would pass trivially and prove nothing). "+
			"Fix: point %s at the scenarios directory as it exists at that commit, or un-mark at least one scenario in test/install-recovery/run.sh's default suite",
			commit, commit, scenarioDir, installRecoveryHarnessSkipDefaultMarker, scenarioDir)
	}
	return names, nil
}

// checkStableWorkflowGate runs one of the RC-commit-keyed stable gates for
// the TAG-FIRED workflows (STATBUS-205): test-hardening.yaml and
// test-install.yaml trigger only on v*-rc.* tag push (+ manual dispatch),
// so no run can exist before the RC tag — they cannot gate at prerelease
// preflight (that was a deadlock: the preflight demanded runs only the tag
// it refused to cut could start). Same Green/Pending/Failed/Missing/
// Unknown switch + loud SKIP_*=1 bypass shape as
// checkPrereleaseWorkflowGate, but keyed on the RC's commit, with the RC
// tag as the workflow_dispatch ref in the Missing remedy.
//
// No jobs-completeness verification (unlike the two harness gates): these
// workflows have a fixed job set — no selector input can produce a
// green-but-subset run.
func checkStableWorkflowGate(workflow, label, skipEnv, rcTag, rcCommit, rcShort string) bool {
	if os.Getenv(skipEnv) == "1" {
		fmt.Printf("  ⚠ %s SKIPPED (%s=1)\n", label, skipEnv)
		fmt.Printf("    Operator bypass — ensure %s ran via CI or by hand on this commit.\n", label)
		return true
	}
	result := release.CheckWorkflowAtCommit(workflow, rcCommit)
	switch result.Status {
	case release.WorkflowCheckGreen:
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

// checkWorkflowAtCommit and workflowJobsComplete are the two GitHub-API
// reads the harness completeness gates depend on, held as package vars so
// a test can supply the API's answer directly. Without this seam a gate's
// VERDICT (its returned bool) can only be exercised against the live API:
// with no network every call returns Unknown and every gate returns false,
// which would make a refusal test pass for the wrong reason and pin
// nothing (STATBUS-216 AC#2 requires the assertion to be on the gate's
// boolean). Production code must never assign these; tests restore them
// via t.Cleanup. Scope: the seam covers the COMPLETENESS gates only, not
// every GitHub read in package cmd — verify-images and its kin have no
// completeness verdict and deliberately call release.* directly.
var (
	checkWorkflowAtCommit = release.CheckWorkflowAtCommit
	workflowJobsComplete  = release.WorkflowJobsCompleteAtCommit
)

// printJobsCompletenessRefusal prints the per-job detail of a failed
// completeness check for both harness gates. The two buckets print under
// distinct labels (STATBUS-217 AC#2) because their remedies differ: a
// MISSING job means the run never contained it (subset dispatch, matrix
// did not expand) — re-run the full suite; a job that DID NOT RUN was
// present and skipped/cancelled — the run stayed green while the scenario
// never executed, so the condition that skipped it is the thing to fix.
func printJobsCompletenessRefusal(jobs release.JobsCompleteness) {
	for _, m := range jobs.Missing {
		fmt.Printf("      MISSING (never in the run): %s\n", m)
	}
	for _, u := range jobs.Unsuccessful {
		fmt.Printf("      DID NOT RUN (present, no green): %s\n", u)
	}
}

// checkInstallRecoveryHarnessGate is the STATBUS-199 §5-rider stable gate
// for install-recovery-harness.yaml. Unlike the arc-harness gate, there is
// no path-sensitivity walk-back: the workflow's own tag-push trigger
// (v*-rc.*) already guarantees a full-suite run exists for every RC, so
// the gate only needs to confirm the run AT rcCommit is genuinely that
// full run, not a workflow_dispatch named-subset run that happens to land
// on the same SHA (comment #1 §5's "same any-green softness").
func checkInstallRecoveryHarnessGate(projDir, rcTag, rcCommit, rcShort string) bool {
	const skipEnv = "SKIP_INSTALL_RECOVERY"
	if os.Getenv(skipEnv) == "1" {
		fmt.Printf("  ⚠ install-recovery SKIPPED (%s=1)\n", skipEnv)
		fmt.Println("    Operator bypass — ensure install-recovery-harness ran via CI or by hand on this commit.")
		return true
	}

	result := checkWorkflowAtCommit(release.WorkflowInstallRecoveryHarness, rcCommit)
	switch result.Status {
	case release.WorkflowCheckGreen:
		requiredScenarios, err := installRecoveryScenarioNamesAtCommit(projDir, rcCommit)
		if err != nil {
			fmt.Printf("  ✗ install-recovery is green at %s, but its scenario domain could not be derived\n", rcShort)
			fmt.Printf("    Error: %v\n", err)
			return false
		}
		jobs, jerr := workflowJobsComplete(result.RunID, requiredScenarios)
		if jerr != nil {
			fmt.Printf("  ✗ install-recovery is green at %s, but its job list could not be verified\n", rcShort)
			fmt.Printf("    Error: %v\n", jerr)
			return false
		}
		if jobs.Complete {
			fmt.Printf("  ✓ install-recovery FULL SUITE green at %s (%d/%d scenario jobs ran and succeeded)\n", rcShort, len(requiredScenarios), len(requiredScenarios))
			fmt.Printf("    Run: %s\n", result.RunURL)
			return true
		}
		fmt.Printf("  ✗ install-recovery is green at %s, but %d/%d required scenario jobs are not proof — a subset or skipped run cannot satisfy this gate:\n",
			rcShort, len(jobs.Missing)+len(jobs.Unsuccessful), len(requiredScenarios))
		printJobsCompletenessRefusal(jobs)
		fmt.Printf("    Trigger: %s\n", release.WorkflowTriggerCommand(release.WorkflowInstallRecoveryHarness, rcTag))
		fmt.Printf("    Watch:   %s\n", release.WorkflowURL(release.WorkflowInstallRecoveryHarness))
		fmt.Println("    Fix: run the trigger command above (blank selector = full suite), wait for green, re-run stable")
		return false
	case release.WorkflowCheckPending:
		fmt.Printf("  ✗ install-recovery is still pending at %s\n", rcShort)
		fmt.Printf("    Watch: gh run watch %d\n", result.RunID)
		fmt.Printf("    URL:   %s\n", result.RunURL)
		fmt.Println("    Fix: wait for the run to complete, then re-run stable")
		return false
	case release.WorkflowCheckFailed:
		fmt.Printf("  ✗ install-recovery failed at %s (conclusion: %s)\n", rcShort, result.Detail)
		fmt.Printf("    See: gh run view %d --log-failed\n", result.RunID)
		fmt.Printf("    URL: %s\n", result.RunURL)
		fmt.Println("    Fix:")
		fmt.Printf("      Retry the failed jobs (if transient): gh run rerun --failed %d\n", result.RunID)
		fmt.Println("      Or push a fix to master, cut a new RC, then re-run stable")
		return false
	case release.WorkflowCheckMissing:
		fmt.Printf("  ✗ install-recovery has not run for %s\n", rcShort)
		fmt.Printf("    Trigger: %s\n", release.WorkflowTriggerCommand(release.WorkflowInstallRecoveryHarness, rcTag))
		fmt.Printf("    Watch:   %s\n", release.WorkflowURL(release.WorkflowInstallRecoveryHarness))
		fmt.Println("    Fix: run the trigger command above, wait for green, re-run stable")
		return false
	case release.WorkflowCheckUnknown:
		fmt.Println("  ✗ install-recovery status check failed (GitHub API error)")
		fmt.Printf("    Detail: %s\n", result.Detail)
		fmt.Println("    Fix: check network connectivity / GITHUB_TOKEN; or re-run later")
		return false
	}
	fmt.Printf("  ✗ install-recovery returned unexpected status %q\n", result.Status)
	return false
}

// checkUpgradeArcHarnessGate is the STATBUS-199 D2 stable gate for the
// upgrade-arc harness (STATBUS-071's 31 real-dispatch arcs — serve-proven
// writers, park lifecycle, deploy honesty).
//
// Two ways to pass: (1) a green run at rcCommit itself whose job set is
// COMPLETE against the arcs present in the tree at rcCommit (comment #4:
// "the gate verifies what ran, not what the run claims" — a subset
// dispatch or a decide-only ride/skip run fails this by construction,
// no run-name label needed), or (2) an RC whose diff against the newest
// prior RC that DOES have such a complete green touches nothing in
// ops/release/upgrade-sensitive-paths.txt — it may RIDE that prior green
// instead, printed loudly (the inherited tag + the full path list, never
// silent). The walk is bounded (20 RC tags) and computed HERE via a
// direct candidate..rcCommit diff — no per-hop induction, correct by
// construction. It never trusts the workflow's own short-circuit
// judgment call for the RIDE decision; that's a CI cost optimization
// only, not a correctness source — see the workflow's own "decide" job
// comments.
func checkUpgradeArcHarnessGate(projDir, rcTag, rcCommit, rcShort string) bool {
	const skipEnv = "SKIP_UPGRADE_ARCS"
	if os.Getenv(skipEnv) == "1" {
		fmt.Printf("  ⚠ upgrade-arc-harness SKIPPED (%s=1)\n", skipEnv)
		fmt.Println("    Operator bypass — ensure the arc suite ran via CI or by hand on this commit.")
		return true
	}

	result := checkWorkflowAtCommit(release.WorkflowUpgradeArcHarness, rcCommit)
	switch result.Status {
	case release.WorkflowCheckGreen:
		requiredArcs, err := upgradeArcNamesAtCommit(projDir, rcCommit)
		if err != nil {
			fmt.Printf("  ✗ upgrade-arc-harness is green at %s, but the arc domain at that commit could not be listed\n", rcShort)
			fmt.Printf("    Error: %v\n", err)
			return false
		}
		jobs, jerr := workflowJobsComplete(result.RunID, requiredArcs)
		if jerr != nil {
			fmt.Printf("  ✗ upgrade-arc-harness is green at %s, but its job list could not be verified\n", rcShort)
			fmt.Printf("    Error: %v\n", jerr)
			return false
		}
		if jobs.Complete {
			fmt.Printf("  ✓ upgrade-arc-harness FULL SUITE green at %s (%d/%d arc jobs ran and succeeded)\n", rcShort, len(requiredArcs), len(requiredArcs))
			fmt.Printf("    Run: %s\n", result.RunURL)
			return true
		}
		fmt.Printf("  … upgrade-arc-harness is green at %s, but %d/%d required arc jobs are not proof — not a full-suite proof, falling through to the path-sensitivity walk:\n",
			rcShort, len(jobs.Missing)+len(jobs.Unsuccessful), len(requiredArcs))
		printJobsCompletenessRefusal(jobs)
		// Fall through to the walk below — same as Missing.
	case release.WorkflowCheckPending:
		fmt.Printf("  ✗ upgrade-arc-harness is still pending at %s\n", rcShort)
		fmt.Printf("    Watch: gh run watch %d\n", result.RunID)
		fmt.Printf("    URL:   %s\n", result.RunURL)
		fmt.Println("    Fix: wait for the run to complete, then re-run stable")
		return false
	case release.WorkflowCheckFailed:
		fmt.Printf("  ✗ upgrade-arc-harness failed at %s (conclusion: %s)\n", rcShort, result.Detail)
		fmt.Printf("    See: gh run view %d --log-failed\n", result.RunID)
		fmt.Printf("    URL: %s\n", result.RunURL)
		fmt.Println("    Fix:")
		fmt.Printf("      Retry the failed jobs (if transient): gh run rerun --failed %d\n", result.RunID)
		fmt.Println("      Or push a fix to master, cut a new RC, then re-run stable")
		return false
	case release.WorkflowCheckUnknown:
		fmt.Println("  ✗ upgrade-arc-harness status check failed (GitHub API error)")
		fmt.Printf("    Detail: %s\n", result.Detail)
		fmt.Println("    Fix: check network connectivity / GITHUB_TOKEN; or re-run later")
		return false
	case release.WorkflowCheckMissing:
		// No proof at rcCommit itself (genuinely never ran). Fall through
		// to the path-sensitivity walk below.
	default:
		fmt.Printf("  ✗ upgrade-arc-harness returned unexpected status %q\n", result.Status)
		return false
	}

	missingRemedy := func() {
		fmt.Printf("    Trigger: %s\n", release.WorkflowTriggerCommand(release.WorkflowUpgradeArcHarness, rcTag))
		fmt.Printf("    Watch:   %s\n", release.WorkflowURL(release.WorkflowUpgradeArcHarness))
	}

	sensitivePaths, err := loadUpgradeSensitivePaths(projDir)
	if err != nil {
		fmt.Printf("  ✗ upgrade-arc-harness has no FULL SUITE proof at %s, and the sensitivity-path walk could not load its list\n", rcShort)
		fmt.Printf("    Error: %v\n", err)
		missingRemedy()
		return false
	}

	tags, err := release.ReleaseTagsNewestFirst(projDir)
	if err != nil {
		fmt.Printf("  ✗ upgrade-arc-harness has no FULL SUITE proof at %s, and the prior-RC walk could not list release tags\n", rcShort)
		fmt.Printf("    Error: %v\n", err)
		missingRemedy()
		return false
	}
	var rcTags []string
	for _, t := range tags {
		if strings.Contains(t, "-rc.") {
			rcTags = append(rcTags, t)
		}
	}
	// rcTags is newest-first. Walk everything STRICTLY OLDER than rcTag —
	// i.e. everything after its own position. If rcTag isn't found (e.g.
	// not yet visible via `git ls-remote` at check time), walk the whole
	// RC-tag list newest-first as a defensive fallback rather than refusing
	// outright.
	startIdx := 0
	for i, t := range rcTags {
		if t == rcTag {
			startIdx = i + 1
			break
		}
	}
	const walkBound = 20
	candidates := rcTags[startIdx:]
	if len(candidates) > walkBound {
		candidates = candidates[:walkBound]
	}

	fmt.Printf("  … upgrade-arc-harness has no FULL SUITE proof at %s — checking whether it may ride a prior green (STATBUS-199 path-sensitivity)\n", rcShort)
	fmt.Println("    Sensitive paths (ops/release/upgrade-sensitive-paths.txt):")
	for _, p := range sensitivePaths {
		fmt.Printf("      %s\n", p)
	}

	foundAnyFullSuiteCandidate := false
	for _, candidate := range candidates {
		candCommit, cerr := tagTargetCommit(projDir, candidate)
		if cerr != nil {
			fmt.Printf("    (could not resolve %s's target commit: %v — skipping)\n", candidate, cerr)
			continue
		}
		candResult := checkWorkflowAtCommit(release.WorkflowUpgradeArcHarness, candCommit)
		if candResult.Status != release.WorkflowCheckGreen {
			continue
		}
		candArcs, aerr := upgradeArcNamesAtCommit(projDir, candCommit)
		if aerr != nil {
			fmt.Printf("    (could not list %s's arc domain: %v — skipping)\n", candidate, aerr)
			continue
		}
		candJobs, jerr := workflowJobsComplete(candResult.RunID, candArcs)
		if jerr != nil {
			fmt.Printf("    (could not verify %s's job completeness: %v — skipping)\n", candidate, jerr)
			continue
		}
		if !candJobs.Complete {
			// Green but not a full suite (subset dispatch, or a
			// decide-only ride/skip run at that tag) — not a valid
			// full-suite anchor. Keep walking further back.
			continue
		}
		foundAnyFullSuiteCandidate = true
		touched, matched, derr := diffTouchesSensitivePath(projDir, candidate, rcCommit, sensitivePaths)
		if derr != nil {
			fmt.Printf("    (could not diff %s..%s: %v — skipping this candidate)\n", candidate, rcShort, derr)
			continue
		}
		if !touched {
			fmt.Printf("  ✓ upgrade-arc-harness: no upgrade-sensitive changes since %s (FULL SUITE green there) — riding it\n", candidate)
			fmt.Printf("    %s run: %s\n", candidate, candResult.RunURL)
			return true
		}
		// The NEWEST prior FULL-SUITE green is the only one that matters
		// (STATBUS-199 D2): its diff range to rcCommit is the SMALLEST of
		// any candidate's, so if a sensitive path changed since it, that
		// same change is necessarily also within every OLDER candidate's
		// (bigger) diff range. No older candidate can ever be ridable
		// either — stop walking rather than re-derive the same BLOCK N
		// more times.
		fmt.Printf("  ✗ upgrade-arc-harness: %s is FULL-SUITE green, but %d upgrade-sensitive file(s) changed since then — cannot ride it:\n", candidate, len(matched))
		for _, f := range matched {
			fmt.Printf("      %s\n", f)
		}
		break
	}

	if !foundAnyFullSuiteCandidate {
		fmt.Printf("  ✗ upgrade-arc-harness: no FULL SUITE green found within the last %d RC tag(s) either\n", walkBound)
	}
	missingRemedy()
	fmt.Println("    Fix: run the trigger command above, wait for green, re-run stable")
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
