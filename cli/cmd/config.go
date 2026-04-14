package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

var (
	configShowPostgres bool
)

var configCmd = &cobra.Command{
	Use:   "config",
	Short: "Manage StatBus configuration",
}

var configGenerateCmd = &cobra.Command{
	Use:   "generate",
	Short: "Generate .env and Caddyfiles from .env.config and .env.credentials",
	Long: `Reads .env.config and .env.credentials (generating defaults if missing),
derives all computed values (ports, memory tuning, URLs), writes .env,
and renders Caddyfile templates from caddy/templates/*.caddyfile.tmpl
into caddy/config/.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return config.Generate(verbose)
	},
}

var configShowCmd = &cobra.Command{
	Use:   "show",
	Short: "Show current configuration values",
	Long: `Show current configuration values from .env (read-only).

Reads and prints the generated .env. Does NOT regenerate. If
.env.config has been edited since .env was last generated, prints a
"stale" warning on stderr suggesting ./sb config generate.

With --postgres, outputs PostgreSQL connection variables in shell-evaluable
format. Use with eval to set variables in your current shell:

    eval $(./sb config show --postgres)

Set TLS=1 to get TLS connection settings:

    eval $(TLS=1 ./sb config show --postgres)`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if configShowPostgres {
			return showPostgresVars()
		}
		return showConfig()
	},
}

// showConfig dumps .env to stdout (read-only) and warns on stderr if
// .env.config is newer than .env (the typical staleness signal). It
// never regenerates — that would surprise an operator who ran a "show"
// command and silently mutated their tree. The matching mutation
// command is `./sb config generate`, suggested in both the missing-file
// error and the staleness warning.
func showConfig() error {
	projDir := config.ProjectDir()
	envPath := filepath.Join(projDir, ".env")
	cfgPath := filepath.Join(projDir, ".env.config")

	envContent, err := os.ReadFile(envPath)
	if err != nil {
		if os.IsNotExist(err) {
			return fmt.Errorf(".env not found at %s\n\n  Generate it from .env.config + .env.credentials:\n    ./sb config generate", envPath)
		}
		return fmt.Errorf("read .env: %w", err)
	}

	envInfo, envStatErr := os.Stat(envPath)
	cfgInfo, cfgStatErr := os.Stat(cfgPath)
	if envStatErr == nil && cfgStatErr == nil && cfgInfo.ModTime().After(envInfo.ModTime()) {
		fmt.Fprintf(os.Stderr,
			"WARNING: .env.config (modified %s) is newer than .env (modified %s).\n"+
				"  .env may not reflect recent .env.config edits. Regenerate with:\n"+
				"    ./sb config generate\n\n",
			cfgInfo.ModTime().Format(time.RFC3339),
			envInfo.ModTime().Format(time.RFC3339))
	}

	fmt.Print(string(envContent))
	return nil
}

func showPostgresVars() error {
	f, err := dotenv.Load(".env")
	if err != nil {
		return fmt.Errorf("loading .env: %w", err)
	}

	getOrDefault := func(key, fallback string) string {
		if v, ok := f.Get(key); ok {
			return v
		}
		return fallback
	}

	getOrFail := func(key string) (string, error) {
		if v, ok := f.Get(key); ok {
			return v, nil
		}
		return "", fmt.Errorf("required key %s not found in .env", key)
	}

	pgHost := getOrDefault("SITE_DOMAIN", "local.statbus.org")
	pgDatabase, err := getOrFail("POSTGRES_APP_DB")
	if err != nil {
		return err
	}

	// Allow PGUSER from environment to override .env value
	pgUser := os.Getenv("PGUSER")
	if pgUser == "" {
		pgUser, err = getOrFail("POSTGRES_ADMIN_USER")
		if err != nil {
			return err
		}
	}

	pgPassword, err := getOrFail("POSTGRES_ADMIN_PASSWORD")
	if err != nil {
		return err
	}

	testDB := getOrDefault("POSTGRES_TEST_DB", "statbus_test_template")

	tls := os.Getenv("TLS")
	if tls == "1" || tls == "true" {
		pgPort, err := getOrFail("CADDY_DB_TLS_PORT")
		if err != nil {
			return err
		}
		fmt.Printf("export PGHOST=%s PGPORT=%s PGDATABASE=%s PGUSER=%s PGPASSWORD=%s PGSSLMODE=require PGSSLNEGOTIATION=direct PGSSLSNI=1 POSTGRES_TEST_DB=%s\n",
			pgHost, pgPort, pgDatabase, pgUser, pgPassword, testDB)
	} else {
		pgPort, err := getOrFail("CADDY_DB_PORT")
		if err != nil {
			return err
		}
		fmt.Printf("export PGHOST=%s PGPORT=%s PGDATABASE=%s PGUSER=%s PGPASSWORD=%s PGSSLMODE=disable POSTGRES_TEST_DB=%s\n",
			pgHost, pgPort, pgDatabase, pgUser, pgPassword, testDB)
	}

	return nil
}

func init() {
	configShowCmd.Flags().BoolVar(&configShowPostgres, "postgres", false, "output PostgreSQL connection variables in shell-evaluable format")
	configCmd.AddCommand(configGenerateCmd)
	configCmd.AddCommand(configShowCmd)
	rootCmd.AddCommand(configCmd)
}
