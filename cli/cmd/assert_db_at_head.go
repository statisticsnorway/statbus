package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// `./sb assert-db-at-head <db_name> <caller>`
//
// Cobra subcommand exposing migrate.AssertDBAtHead at the CLI surface.
// Lets dev.sh callsites (test fast, generate-doc-db) drop
// the bash `assert_db_at_head` function and call into the Go
// implementation instead. Single source of truth for the
// "is this DB's db.migration set equal to HEAD's on-disk migrations"
// invariant, including:
//
//   - Template-DB refusal (datistemplate=true → caller should target
//     the seed, not the test_template).
//   - Symmetric behind/ahead detection (operator on stale branch
//     catches).
//   - Shared advisory lock on hashtext('statbus_seed_mutate') so
//     parallel `./sb db with-seed-lock --exclusive` blocks this
//     query during the mutation window.
//
// On success: echoes the source-DB's max migration version on stdout.
// Callers in dev.sh capture this for H1 two-line stamp writes.
// On failure: actionable error on stderr, exit 1.

var assertDBAtHeadCmd = &cobra.Command{
	Use:   "assert-db-at-head <db_name> <caller>",
	Short: "Refuse if <db_name>'s db.migration row set doesn't match HEAD's on-disk migrations",
	Long: `Verify that <db_name>'s db.migration table contains exactly the
set of migration versions present on disk in migrations/*.up.{sql,psql}.

Symmetric — refuses with the appropriate diagnostic on both:
  - behind (DB is missing migrations that exist on disk)
  - ahead  (DB has migrations the working tree doesn't ship — feature
            branch contamination)

PG template DBs (datistemplate=true) are refused regardless of state —
they're not directly queryable. Callers should target the SEED (the
canonical source-of-truth: ${POSTGRES_SEED_DB:-statbus_seed}).

Acquires a SHARED advisory lock on the postgres system DB so that
concurrent recreate-seed (which holds the EXCLUSIVE variant via
./sb db with-seed-lock --exclusive) blocks this query during its DROP
window — without the lock, the seed's intermittent absence mid-rebuild
would cause spurious "BEHIND by N" diagnostics.

On success: echoes the source-DB's max migration version on stdout
(callers capture this for H1 two-line stamp writes).

Exits 0 on PASS, 1 on REFUSE.`,
	Args: cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		dbName := args[0]
		caller := args[1]

		version, err := migrate.AssertDBAtHead(config.ProjectDir(), dbName, caller)
		if err != nil {
			// migrate.AssertDBAtHead's error is already shaped for
			// terminal display (REFUSED: ... / Reason: ... / Fix: ...).
			// Print verbatim and exit 1.
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		// Stamp writers capture stdout for the H1 two-line stamp's line 2.
		fmt.Println(version)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(assertDBAtHeadCmd)
}
