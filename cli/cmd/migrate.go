package cmd

import (
	"fmt"
	"os"
	"strconv"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

var (
	migrateDescription string
	migrateExtension   string
	migrateTo          int64
	migrateUpTarget    string
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
	Long: `Apply pending migrations to the target database.

The --target flag selects which database to migrate:
  --target dev   (default) — POSTGRES_APP_DB (the working dev/runtime DB)
  --target seed             — POSTGRES_SEED_DB (the canonical fresh-from-
                              migrations DB; build-time only, never
                              worker-active). The seed sources the
                              published artifact via ./sb db seed create.

The --target flag overrides POSTGRES_APP_DB + PGDATABASE in the process
env for this invocation; existing in-process callers (install, upgrade)
that don't pass --target keep targeting POSTGRES_APP_DB exactly as
before.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runMigrateUp(migrateTo, true)
	},
}

var migrateUpOneCmd = &cobra.Command{
	Use:   "one",
	Short: "Apply only one pending migration",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runMigrateUp(migrateTo, false)
	},
}

// runMigrateUp resolves --target to a database name, overrides
// POSTGRES_APP_DB + PGDATABASE in the process env (reverted on
// defer so subsequent in-process commands aren't affected), and
// invokes migrate.Up. The env override is the same shape Redo uses
// and matches the existing dev.sh:998 pattern.
func runMigrateUp(migrateTo int64, all bool) error {
	projDir := config.ProjectDir()
	if migrateUpTarget == "" {
		migrateUpTarget = "dev"
	}
	dbName, err := migrate.ResolveTargetDB(projDir, migrateUpTarget)
	if err != nil {
		return err
	}

	prevApp, hadApp := os.LookupEnv("POSTGRES_APP_DB")
	prevPG, hadPG := os.LookupEnv("PGDATABASE")
	os.Setenv("POSTGRES_APP_DB", dbName)
	os.Setenv("PGDATABASE", dbName)
	defer func() {
		if hadApp {
			os.Setenv("POSTGRES_APP_DB", prevApp)
		} else {
			os.Unsetenv("POSTGRES_APP_DB")
		}
		if hadPG {
			os.Setenv("PGDATABASE", prevPG)
		} else {
			os.Unsetenv("PGDATABASE")
		}
	}()

	return migrate.Up(projDir, migrateTo, all, verbose)
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
	migrateUpCmd.Flags().StringVar(&migrateUpTarget, "target", "dev", "target DB: 'dev' (POSTGRES_APP_DB) or 'seed' (POSTGRES_SEED_DB)")
	migrateUpOneCmd.Flags().StringVar(&migrateUpTarget, "target", "dev", "target DB: 'dev' (POSTGRES_APP_DB) or 'seed' (POSTGRES_SEED_DB)")
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
