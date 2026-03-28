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

	// 1. Git working tree is clean
	_, err1 := upgrade.RunCommandOutput(projDir, "git", "diff", "--quiet")
	_, err2 := upgrade.RunCommandOutput(projDir, "git", "diff", "--cached", "--quiet")
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

	// 6. Test stamp matches HEAD
	stampPath := filepath.Join(projDir, "tmp", "test-passed-sha")
	stampBytes, err := os.ReadFile(stampPath)
	if err != nil {
		fmt.Println("  \u2717 Test stamp matches HEAD (tmp/test-passed-sha not found)")
		fmt.Println("    Fix: ./dev.sh test fast")
		allPassed = false
	} else {
		stamp := strings.TrimSpace(string(stampBytes))
		headOut, _ := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD")
		head := strings.TrimSpace(headOut)
		if stamp != head {
			fmt.Println("  \u2717 Test stamp matches HEAD")
			fmt.Printf("    Stamp: %s\n", stamp)
			fmt.Printf("    HEAD:  %s\n", head)
			fmt.Println("    Fix: ./dev.sh test fast")
			allPassed = false
		} else {
			fmt.Println("  \u2713 Test stamp matches HEAD")
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

		// Create tag (will be signed if tag.gpgsign=true)
		_, err = upgrade.RunCommandOutput(projDir, "git", "tag", tagName)
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

		// Create tag (will be signed if tag.gpgsign=true)
		_, err = upgrade.RunCommandOutput(projDir, "git", "tag", tagName)
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
