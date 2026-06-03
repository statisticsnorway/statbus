package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/freshness"
)

// committedDriftCmd is a hidden, guard-exempt probe for dev.sh's rebuild
// decision. It reports the committed-drift axis — the binary's build commit
// differs from HEAD with cli/ changes between them — that a file-mtime check
// misses, because `git commit`/`checkout`/`pull` move HEAD without touching
// working-tree mtimes. dev.sh rebuilds ./sb when this exits non-zero.
//
// Exit codes:
//
//	0  no committed drift — ./sb is at HEAD (or there is no cli/ delta).
//	1  committed drift — rebuild to HEAD.
//	2  probe could not run (no identity / not a git tree / git error) — dev.sh
//	   rebuilds anyway, since it cannot confirm freshness.
//
// Annotated freshness_probe so stalenessGuard skips it: this command IS the
// staleness check dev.sh calls, so running the guard on it would be circular
// (and would leak a WARN into the output dev.sh parses).
//
// It deliberately does NOT report uncommitted/WIP drift: a dirty tree can never
// be cleared by a rebuild, so triggering a rebuild on it would loop. The
// hot-edit axis is dev.sh's `find cli -newer ./sb` mtime check, which
// self-clears on rebuild.
var committedDriftCmd = &cobra.Command{
	Use:         "committed-drift",
	Short:       "Exit non-zero if ./sb's build commit differs from HEAD (for dev.sh's rebuild decision)",
	Hidden:      true,
	Args:        cobra.NoArgs,
	Annotations: map[string]string{"freshness_probe": "true"},
	Run: func(_ *cobra.Command, _ []string) {
		drift, err := freshness.CommittedDrift(config.ProjectDir(), string(commitSHA))
		if err != nil {
			fmt.Fprintf(os.Stderr, "committed-drift: %v — rebuild recommended\n", err)
			os.Exit(2)
		}
		if drift {
			os.Exit(1)
		}
		os.Exit(0)
	},
}

func init() {
	rootCmd.AddCommand(committedDriftCmd)
}
