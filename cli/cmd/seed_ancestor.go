package cmd

import (
	"fmt"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// ─────────────────────────────────────────────────────────────────────────────
// STATBUS-116 AC#1 Step 2 — Fork-A ancestor-walk (HOST side).
//
// Runs on the CI runner / dev host (has git + a docker registry), NOT inside the
// hermetic seed-builder STAGE (which has neither a .git nor a docker daemon, so it
// cannot pull). It finds the closest ancestor of the build commit that already has
// a PUBLISHED statbus-seed image; images.yaml injects that image into the build as
// the `prior-seed` build-context (mirroring how statbus-sb is injected today).
//
// This is BUILD-time only (the CI seed build) — NOT upgrade/executeUpgrade-time.
// ─────────────────────────────────────────────────────────────────────────────

const seedImageRepo = "ghcr.io/statisticsnorway/statbus-seed"

// defaultSeedAncestorWalk bounds the walk. Published seeds exist for master-push
// commits, so the closest is normally the immediate first-parent; a generous cap
// bounds the registry probes without risking correctness (a miss → full rebuild).
const defaultSeedAncestorWalk = 40

// firstPublishedAncestor is the PURE walk core: given ancestor commit_shorts
// (closest first) and an image-existence probe, return the first published one's
// image ref. capHit reports the walk exhausted maxWalk with no hit (caller LOGs a
// loud no-silent-cap warning). No git / registry here → unit-testable.
func firstPublishedAncestor(ancestors []string, seedImageExists func(short string) bool, maxWalk int) (tag string, found bool, capHit bool) {
	n := 0
	for _, short := range ancestors {
		if n >= maxWalk {
			return "", false, true
		}
		n++
		if seedImageExists(short) {
			return seedImageRepo + ":" + short, true, false
		}
	}
	return "", false, false
}

// SelectPriorSeed walks the git first-parent ancestry of the build commit for the
// closest ancestor with a PUBLISHED statbus-seed image and returns its full image
// ref. found=false → full rebuild. maxWalk<=0 → default; a cap-hit is logged
// loudly (no silent cap).
func SelectPriorSeed(projDir string, maxWalk int) (tag string, found bool, err error) {
	if maxWalk <= 0 {
		maxWalk = defaultSeedAncestorWalk
	}
	ancestors, err := gitFirstParentAncestors(projDir, maxWalk)
	if err != nil {
		return "", false, err
	}
	tag, found, capHit := firstPublishedAncestor(ancestors,
		func(short string) bool { return seedImagePublished(projDir, short) }, maxWalk)
	if capHit {
		fmt.Printf("seed select-prior: walked the %d-ancestor cap with no published seed — full rebuild\n", maxWalk)
	}
	return tag, found, nil
}

// gitFirstParentAncestors returns up to maxWalk 8-char commit_shorts along the
// first-parent line, closest first, EXCLUDING the build commit (HEAD) itself.
// Matches the commit_short images.yaml tags seeds with (git rev-parse --short=8).
func gitFirstParentAncestors(projDir string, maxWalk int) ([]string, error) {
	out, err := upgrade.RunCommandOutput(projDir, "git", "rev-list", "--first-parent",
		fmt.Sprintf("-n%d", maxWalk+1), "HEAD")
	if err != nil {
		return nil, fmt.Errorf("git rev-list first-parent: %w", err)
	}
	var shorts []string
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		sha := strings.TrimSpace(line)
		if len(sha) >= 8 {
			shorts = append(shorts, sha[:8])
		}
	}
	if len(shorts) <= 1 {
		return nil, nil // only HEAD (or nothing) — no ancestor to build on
	}
	return shorts[1:], nil // drop HEAD; closest ancestor first
}

// seedImagePublished reports whether statbus-seed:<short> exists in the registry
// via `docker manifest inspect` (a remote HEAD — no pull), the image-existence
// pattern the CI harnesses already use.
func seedImagePublished(projDir, short string) bool {
	_, err := upgrade.RunCommandOutput(projDir, "docker", "manifest", "inspect", seedImageRepo+":"+short)
	return err == nil
}

// seedSelectPriorCmd prints the chosen prior seed image ref (or nothing) for the
// images.yaml gated `prior` step to consume. Read-only.
var seedSelectPriorCmd = &cobra.Command{
	Use:   "select-prior",
	Short: "Print the closest published ancestor seed image (Fork-A ancestor-walk), or empty",
	RunE: func(cmd *cobra.Command, args []string) error {
		tag, found, err := SelectPriorSeed(config.ProjectDir(), 0)
		if err != nil {
			return err
		}
		if found {
			fmt.Println(tag)
		}
		return nil
	},
}

func init() {
	seedCmd.AddCommand(seedSelectPriorCmd)
}
