package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// `./sb assert-db-content-hash <db_name> <caller>`
//
// STATBUS-292: generate-doc-db dumps its documentation database from a clone
// of the seed without ever asking the question `./sb migrate up` already asks
// on every run — does each APPLIED migration's stored db.migration.content_hash
// still match the file on disk? Without this gate, amending an already-applied
// migration after the seed was built produces doc/db/*.md describing a
// definition that no longer exists anywhere: not the file, not any database.
//
// This is a DETECT-only gate (architect ruling on STATBUS-292, comment #1):
// it reuses the exact comparator DumpSeed's publish gate already uses
// (migrate.LedgerContentHashMismatches — sha256 of on-disk file bytes vs the
// hash stamped at apply time), read-only. It does NOT invoke `./sb migrate
// up`, `redo`, or anything that mutates state — a hash mismatch has two
// possible causes (deliberate WIP edit vs. an immutability violation on an
// already-released migration) and only a human can tell them apart, so this
// command refuses and names BOTH remedies rather than guessing or silently
// absorbing.
//
// Distinct from `./sb assert-db-at-head`, which only compares the VERSION
// SET (behind/ahead) — that catches "on-disk migrations the seed doesn't
// have yet" but is blind to "same version, edited bytes", which is the gap
// this command closes.
//
// Exits 0 (silent) when every version's stored hash matches its on-disk
// file. Exits 1 with the full REFUSING diagnostic on any mismatch.

var assertDBContentHashCmd = &cobra.Command{
	Use:   "assert-db-content-hash <db_name> <caller>",
	Short: "Refuse if <db_name>'s db.migration content_hash disagrees with the on-disk migration files",
	Long: `Compare every db.migration.content_hash row in <db_name> against the
sha256 of the corresponding on-disk migrations/*.up.{sql,psql} file.

Read-only: runs one SELECT against <db_name> and hashes on-disk files. Never
invokes migrate up/redo or any command that applies or amends a migration.

A version whose on-disk file is missing (deleted at HEAD) is a harmless
orphan and is skipped, matching the migrate runner's own eager check.

On any mismatch, refuses and names both possible remedies — a mismatch on a
not-yet-released migration is fixed with ` + "`./sb migrate redo <version>`" + `;
a mismatch on an already-released migration is an immutability violation
whose only remedy is a forward repair migration (AGENTS.md, STATBUS-172).
Only a human can tell which applies, so both are named.

caller is the human-readable command name printed in the diagnostic and used
to build the "re-run" hint (e.g. "./dev.sh generate-doc-db").

Exits 0 on PASS (silent), 1 on REFUSE.`,
	Args: cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		dbName := args[0]
		caller := args[1]

		mismatches, err := migrate.LedgerContentHashMismatches(config.ProjectDir(), dbName)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s: check %s content hashes: %v\n", caller, dbName, err)
			os.Exit(1)
		}
		if len(mismatches) > 0 {
			fmt.Fprintln(os.Stderr, migrate.FormatContentHashRefusal(caller, mismatches))
			os.Exit(1)
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(assertDBContentHashCmd)
}
