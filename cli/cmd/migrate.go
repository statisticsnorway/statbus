package cmd

import (
	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

var (
	migrateDescription string
	migrateExtension   string
	migrateTo          int64
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
	Use:   "redo",
	Short: "Roll back and re-apply the last migration",
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		if err := migrate.Down(projDir, 0, false, verbose); err != nil {
			return err
		}
		return migrate.Up(projDir, 0, false, verbose)
	},
}

func init() {
	migrateUpCmd.Flags().Int64Var(&migrateTo, "to", 0, "migrate up to this version (inclusive)")
	migrateUpCmd.AddCommand(migrateUpOneCmd)

	migrateDownCmd.Flags().Int64Var(&migrateTo, "to", 0, "roll back to this version (inclusive)")
	migrateDownCmd.AddCommand(migrateDownAllCmd)

	migrateNewCmd.Flags().StringVarP(&migrateDescription, "description", "d", "", "migration description (required)")
	migrateNewCmd.Flags().StringVarP(&migrateExtension, "extension", "e", "sql", "file extension (sql or psql)")

	migrateCmd.AddCommand(migrateUpCmd)
	migrateCmd.AddCommand(migrateDownCmd)
	migrateCmd.AddCommand(migrateNewCmd)
	migrateCmd.AddCommand(migrateRedoCmd)
	rootCmd.AddCommand(migrateCmd)
}
