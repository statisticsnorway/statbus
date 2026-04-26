package cmd

import (
	"fmt"
	"strconv"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

var (
	migrateDescription string
	migrateExtension   string
	migrateTo          int64
	migrateRedoTarget  string
	migrateRedoConfirm bool
)

var migrateCmd = &cobra.Command{
	Use:   "migrate",
	Short: "Manage database migrations",
}

var migrateUpCmd = &cobra.Command{
	Use:   "up",
	Short: "Apply pending migrations",
	RunE: func(cmd *cobra.Command, args []string) error {
		return migrate.Up(config.ProjectDir(), migrateTo, true, verbose)
	},
}

var migrateUpOneCmd = &cobra.Command{
	Use:   "one",
	Short: "Apply only one pending migration",
	RunE: func(cmd *cobra.Command, args []string) error {
		return migrate.Up(config.ProjectDir(), migrateTo, false, verbose)
	},
}

var migrateDownCmd = &cobra.Command{
	Use:   "down",
	Short: "Roll back the last migration",
	RunE: func(cmd *cobra.Command, args []string) error {
		return migrate.Down(config.ProjectDir(), migrateTo, false, verbose)
	},
}

var migrateDownAllCmd = &cobra.Command{
	Use:   "all",
	Short: "Roll back all migrations",
	RunE: func(cmd *cobra.Command, args []string) error {
		return migrate.Down(config.ProjectDir(), migrateTo, true, verbose)
	},
}

var migrateNewCmd = &cobra.Command{
	Use:   "new",
	Short: "Create a new migration file pair",
	RunE: func(cmd *cobra.Command, args []string) error {
		return migrate.New(config.ProjectDir(), migrateDescription, migrateExtension)
	},
}

var migrateRedoCmd = &cobra.Command{
	Use:   "redo <version>",
	Short: "Re-run a migration's down + up cycle and re-stamp content_hash",
	Long: `Re-run the migration's down.sql + up.sql for <version>, deleting
the tracking row in between, and re-inserting (so content_hash refreshes).

Use case: an already-applied migration's up.sql was edited (WIP), and the
next ` + "`./sb migrate up`" + ` errored with a content_hash mismatch and pointed
at this command. Redo recovers the schema without going through manual psql.

Constraints (enforced):
  --target {dev,seed}  default 'seed' (build-time DB; safe, disposable).
                       'dev' requires --confirm — destructive on a dev DB
                       with custom data because down.sql may drop tables.
  --target seed        requires POSTGRES_SEED_DB configured. The seed DB
                       is introduced in commit 3 of the seed feature; until
                       then this branch errors with guidance.
  Restricted to LATEST applied version. Intermediate redos leave
  dependent migrations' effects orphaned over a reverted base.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		version, err := strconv.ParseInt(args[0], 10, 64)
		if err != nil {
			return fmt.Errorf("invalid version %q: must be a 14-digit YYYYMMDDHHMMSS timestamp", args[0])
		}
		return migrate.Redo(config.ProjectDir(), version, migrateRedoTarget, migrateRedoConfirm, verbose)
	},
}

func init() {
	migrateUpCmd.Flags().Int64Var(&migrateTo, "to", 0, "migrate up to this version (inclusive)")
	migrateUpCmd.AddCommand(migrateUpOneCmd)

	migrateDownCmd.Flags().Int64Var(&migrateTo, "to", 0, "roll back to this version (inclusive)")
	migrateDownCmd.AddCommand(migrateDownAllCmd)

	migrateNewCmd.Flags().StringVarP(&migrateDescription, "description", "d", "", "migration description (required)")
	migrateNewCmd.Flags().StringVarP(&migrateExtension, "extension", "e", "sql", "file extension (sql or psql)")

	migrateRedoCmd.Flags().StringVar(&migrateRedoTarget, "target", "seed", "target DB: 'dev' (POSTGRES_APP_DB) or 'seed' (POSTGRES_SEED_DB)")
	migrateRedoCmd.Flags().BoolVar(&migrateRedoConfirm, "confirm", false, "required for --target dev (down.sql may be destructive on a dev DB with custom data)")

	migrateCmd.AddCommand(migrateUpCmd)
	migrateCmd.AddCommand(migrateDownCmd)
	migrateCmd.AddCommand(migrateNewCmd)
	migrateCmd.AddCommand(migrateRedoCmd)
	rootCmd.AddCommand(migrateCmd)
}
