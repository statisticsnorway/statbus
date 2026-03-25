package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

var typesCmd = &cobra.Command{
	Use:   "types",
	Short: "TypeScript type generation",
}

var typesGenerateCmd = &cobra.Command{
	Use:   "generate",
	Short: "Generate TypeScript types from database schema",
	Long: `Runs the SQL type generator against the database and writes
TypeScript type definitions to app/src/lib/database.types.ts.

Requires the database to be running.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		projDir := config.ProjectDir()
		sqlPath := filepath.Join(projDir, "devops", "generate_database_types.sql")

		sqlFile, err := os.Open(sqlPath)
		if err != nil {
			return fmt.Errorf("open type generator: %w", err)
		}
		defer sqlFile.Close()

		psqlPath, prefix, env, err := migrate.PsqlCommand(projDir)
		if err != nil {
			return err
		}

		c := exec.Command(psqlPath, prefix...)
		c.Dir = projDir
		c.Env = env
		c.Stdin = sqlFile
		c.Stdout = os.Stdout
		c.Stderr = os.Stderr
		if err := c.Run(); err != nil {
			return err
		}

		fmt.Println("TypeScript types generated in app/src/lib/database.types.ts")
		return nil
	},
}

func init() {
	typesCmd.AddCommand(typesGenerateCmd)
	rootCmd.AddCommand(typesCmd)
}
