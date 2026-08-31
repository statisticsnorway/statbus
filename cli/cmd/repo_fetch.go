package cmd

import (
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// repoFetchCmd is install.sh's delegation target for `git fetch` (STATBUS-330).
//
// WHY IT EXISTS. STATBUS-324's translator makes a refused fetch say what
// actually happened — the repository is public, so a credential demand is never
// an auth failure — but it lives in the Go exec path. The failure that started
// all of this happened in install.sh's OWN fetch, which hands git's raw text to
// the operator. Delegating that fetch here means ONE implementation of
// fetch-with-good-errors serves both, which is the whole point: a bash copy of
// the same reasoning would be the second translator the ruling forbids, and it
// would drift the first time either side changed.
//
// WHY A VERB AND NOT A FILTER. The architect rejected an `explain-git-failure`
// pipe as "a public surface whose only job is reinterpreting another command's
// output". This is a different thing: it DOES the fetch, and the error quality
// comes along because the product's exec path is what performed it. Nothing here
// reinterprets anything after the fact.
//
// HIDDEN, deliberately. It is an internal delegation target, not a command
// anyone should discover in --help and reach for; `git fetch` remains the thing
// a human runs. Hiding it keeps the surface the ruling was protecting.
//
// READ-ONLY, and registered as such in readOnlyCommandPaths. That registration
// is load-bearing rather than tidy: isMutatingCommand treats an unregistered
// command as mutating, and the staleness guard HARD-FAILS mutating commands when
// the binary's commit disagrees with the worktree. That disagreement is the
// normal mid-rescue state — install.sh places the new binary and only then
// checks the tree out to match — so without the registration this command would
// refuse at precisely the moment install.sh calls it, and the delegation would
// break the install it was added to improve. A fetch writes git objects and
// refs; it does not touch the working tree or any product state. Same reasoning
// as `sb db seed fetch`, which is registered for the same kind of reason.
var repoFetchCmd = &cobra.Command{
	Use:    "repo-fetch [git fetch arguments...]",
	Short:  "Fetch from origin, reporting failures in the product's own words (internal)",
	Hidden: true,
	RunE: func(cmd *cobra.Command, args []string) error {
		gitArgs := append([]string{"fetch"}, args...)
		out, err := upgrade.RunCommandOutput(config.ProjectDir(), "git", gitArgs...)
		// git writes progress to stderr and RunCommandOutput captures both, so
		// this is the whole of what the operator would have seen. Print it either
		// way — on success it is the ordinary fetch output they expect, and on
		// failure the translated error below refers to it.
		if s := strings.TrimSpace(out); s != "" {
			fmt.Fprintln(os.Stderr, s)
		}
		// Already translated: explainGitFailure has turned a credential demand
		// into an unreachable-or-refused remote, with git's raw text preserved
		// inside it. Returned unwrapped so cobra prints it and the exit code
		// reaches install.sh's `set -e`.
		return err
	},
}

func init() {
	rootCmd.AddCommand(repoFetchCmd)
}
