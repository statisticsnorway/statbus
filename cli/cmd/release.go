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
		fmt.Println("  \u2717 Working tree is clean")
		fmt.Println("    Fix: git stash or git commit")
		allPassed = false
	} else {
		fmt.Println("  \u2713 Working tree is clean")
	}

	// 2. On master branch
	branchOut, err := upgrade.RunCommandOutput(projDir, "git", "symbolic-ref", "--short", "HEAD")
	branch := strings.TrimSpace(branchOut)
	if err != nil || branch != "master" {
		fmt.Printf("  \u2717 On master branch (current: %s)\n", branch)
		fmt.Println("    Fix: git checkout master")
		allPassed = false
	} else {
		fmt.Println("  \u2713 On master branch")
	}

	// 3. Up to date with origin
	_, err = upgrade.RunCommandOutput(projDir, "git", "fetch", "origin", "master", "--quiet")
	if err != nil {
		fmt.Println("  \u2717 Up to date with origin (fetch failed)")
		fmt.Println("    Fix: check network connectivity")
		allPassed = false
	} else {
		headOut, _ := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD")
		originOut, _ := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "origin/master")
		head := strings.TrimSpace(headOut)
		origin := strings.TrimSpace(originOut)
		if head != origin {
			fmt.Println("  \u2717 Up to date with origin")
			fmt.Println("    Fix: git pull origin master")
			allPassed = false
		} else {
			fmt.Println("  \u2713 Up to date with origin")
		}
	}

	// 4. HEAD commit is signed
	_, err = upgrade.RunCommandOutput(projDir, "git", "verify-commit", "HEAD")
	if err != nil {
		fmt.Println("  \u26a0 HEAD commit is signed (warning: verification failed, continuing)")
	} else {
		fmt.Println("  \u2713 HEAD commit is signed")
	}

	// 5. Go CLI builds
	cliDir := filepath.Join(projDir, "cli")
	_, err = upgrade.RunCommandOutput(cliDir, "go", "build", "-o", "/dev/null", "./...")
	if err != nil {
		fmt.Println("  \u2717 Go CLI builds")
		fmt.Println("    Fix: cd cli && go build ./...")
		allPassed = false
	} else {
		fmt.Println("  \u2713 Go CLI builds")
	}

	// 6. Fast tests cover latest migrations
	stampPath := filepath.Join(projDir, "tmp", "fast-test-passed-sha")
	stampBytes, err := os.ReadFile(stampPath)
	if err != nil {
		fmt.Println("  \u2717 Fast tests cover latest migrations (tmp/fast-test-passed-sha not found)")
		fmt.Println("    Fix: ./dev.sh test fast")
		allPassed = false
	} else {
		stampSHA := strings.TrimSpace(string(stampBytes))

		// Find the last commit that touched actual migration files.
		// Only match versioned files (YYYYMMDDHHMMSS_*.up.*), not helper
		// files like post_restore.sql which live in migrations/ but aren't migrations.
		lastMigrationOut, _ := upgrade.RunCommandOutput(projDir, "git", "log", "-1", "--format=%H", "--", "migrations/*.up.sql", "migrations/*.up.psql")
		lastMigration := strings.TrimSpace(lastMigrationOut)

		if lastMigration == "" {
			// No migrations at all — tests are fine
			fmt.Println("  \u2713 Fast tests cover latest migrations (no migrations found)")
		} else {
			// Check if any new migration files exist between stamp and HEAD.
			// Only match *.up.sql / *.up.psql — post_restore.sql and other
			// helper files in migrations/ are not schema migrations.
			newMigrationsOut, _ := upgrade.RunCommandOutput(projDir, "git", "diff", "--name-only", stampSHA+"..HEAD", "--", "migrations/*.up.sql", "migrations/*.up.psql")
			newMigrations := strings.TrimSpace(newMigrationsOut)

			if newMigrations == "" {
				// No new migrations since test stamp — OK even if HEAD moved
				shortStamp := stampSHA
				if len(shortStamp) > 12 {
					shortStamp = shortStamp[:12]
				}
				shortMig := lastMigration
				if len(shortMig) > 12 {
					shortMig = shortMig[:12]
				}
				fmt.Printf("  \u2713 Fast tests cover latest migrations (stamp: %s, last migration: %s)\n", shortStamp, shortMig)
			} else {
				// New migrations exist that weren't tested
				migrationFiles := strings.Split(newMigrations, "\n")
				fmt.Println("  \u2717 Fast tests do not cover latest migrations")
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

	// 7. Snapshot covers latest migrations
	// Intent: every release must have a fresh .db-snapshot so installs and CI are fast.
	// If migrations were added since the last snapshot, the developer must run
	// ./dev.sh update-snapshot before releasing.
	snapshotJSON := filepath.Join(projDir, ".db-snapshot", "snapshot.json")
	snapshotBytes, err := os.ReadFile(snapshotJSON)
	if err != nil {
		// No snapshot at all — warn but don't block (first release before any snapshot)
		fmt.Println("  ⚠ No DB snapshot found (.db-snapshot/snapshot.json)")
		fmt.Println("    Create one: ./dev.sh update-snapshot")
	} else {
		// Parse migration_version from JSON (simple string search, no json package needed)
		snapshotContent := string(snapshotBytes)
		// Extract migration_version value
		snapshotVersion := ""
		for _, line := range strings.Split(snapshotContent, "\n") {
			if strings.Contains(line, "migration_version") {
				parts := strings.Split(line, "\"")
				if len(parts) >= 4 {
					snapshotVersion = parts[3]
				}
			}
		}

		// Find latest migration file
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

		if latestMigration == "" {
			fmt.Println("  ✓ Snapshot up to date (no migrations found)")
		} else if snapshotVersion >= latestMigration {
			fmt.Printf("  ✓ Snapshot covers latest migrations (snapshot: %s, latest: %s)\n", snapshotVersion, latestMigration)
		} else {
			fmt.Println("  ✗ Snapshot outdated")
			fmt.Printf("    Snapshot: %s\n", snapshotVersion)
			fmt.Printf("    Latest migration: %s\n", latestMigration)
			fmt.Println("    Fix: ./dev.sh update-snapshot")
			allPassed = false
		}
	}

	return allPassed
}

var releasePrereleaseCmd = &cobra.Command{
	Use:   "prerelease",
	Short: "Tag a new release candidate (vYYYY.MM.0-rc.N)",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()

		fmt.Println("Pre-flight checks:")
		if !preflightChecks(projDir) {
			return fmt.Errorf("pre-flight checks failed")
		}
		fmt.Println()

		// Get current date prefix
		now := time.Now()
		prefix := fmt.Sprintf("v%d.%02d", now.Year(), now.Month())

		// List existing RC tags for this month
		pattern := fmt.Sprintf("%s.*-rc.*", prefix)
		tagsOut, err := upgrade.RunCommandOutput(projDir, "git", "tag", "-l", pattern, "--sort=-version:refname")
		if err != nil {
			return fmt.Errorf("listing tags: %w", err)
		}

		// Parse highest RC number
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
		tagName := fmt.Sprintf("%s.0-rc.%d", prefix, nextRC)

		// Create tag with message (avoids $EDITOR prompt when tag.gpgsign=true)
		_, err = upgrade.RunCommandOutput(projDir, "git", "tag", "-m", "Pre-release "+tagName, tagName)
		if err != nil {
			return fmt.Errorf("creating tag %s: %w", tagName, err)
		}

		// Push tag
		_, err = upgrade.RunCommandOutput(projDir, "git", "push", "origin", tagName)
		if err != nil {
			return fmt.Errorf("pushing tag %s: %w", tagName, err)
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
		if !preflightChecks(projDir) {
			return fmt.Errorf("pre-flight checks failed")
		}
		fmt.Println()

		// Get current date prefix
		now := time.Now()
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

		// Create tag with message (avoids $EDITOR prompt when tag.gpgsign=true)
		_, err = upgrade.RunCommandOutput(projDir, "git", "tag", "-m", "Release "+tagName, tagName)
		if err != nil {
			return fmt.Errorf("creating tag %s: %w", tagName, err)
		}

		// Push tag
		_, err = upgrade.RunCommandOutput(projDir, "git", "push", "origin", tagName)
		if err != nil {
			return fmt.Errorf("pushing tag %s: %w", tagName, err)
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

func init() {
	releaseCmd.AddCommand(releasePrereleaseCmd)
	releaseCmd.AddCommand(releaseStableCmd)
	releaseCmd.AddCommand(releaseListCmd)
	rootCmd.AddCommand(releaseCmd)
}
