package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
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
		sqlPath := filepath.Join(projDir, "cli", "sql", "generate_database_types.sql")

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

		// Write stamp for ./sb release preflight (check: types cover latest migrations)
		if sha, err2 := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD"); err2 == nil {
			stampPath := filepath.Join(projDir, "tmp", "types-passed-sha")
			_ = os.MkdirAll(filepath.Dir(stampPath), 0755)
			_ = os.WriteFile(stampPath, []byte(strings.TrimSpace(sha)+"\n"), 0644)
			fmt.Println("TypeScript types stamp recorded:", strings.TrimSpace(sha))
		}
		return nil
	},
}

func init() {
	typesCmd.AddCommand(typesGenerateCmd)
	rootCmd.AddCommand(typesCmd)
}
