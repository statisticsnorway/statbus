package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
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

		// Tier-1 stamp guard — parallels check_stamp_guard() in dev.sh.
		// Refuse dirty migrations (stamp would lie), skip when stamp still
		// represents HEAD's migrations/ content. Mirror the bash output
		// format so the three Tier-1 commands behave identically. On refuse,
		// exit 1 directly — the banner already carries the diagnostic, we
		// don't want cobra to append a second "Error: ..." line after it.
		switch checkTypesStampGuard(projDir) {
		case stampGuardRefuse:
			os.Exit(1)
		case stampGuardSkip:
			return nil
		}

		sqlFile, err := os.Open(sqlPath)
		if err != nil {
			return fmt.Errorf("open type generator: %w", err)
		}
		defer sqlFile.Close()

		psqlPath, prefix, env, err := migrate.PsqlCommand(projDir)
		if err != nil {
			return err
		}

		// Override PGDATABASE to the seed DB. Types are derived from
		// canonical schema; the seed DB has migrations applied but no
		// per-job tables (import_job_<N>_data). The app DB is whatever
		// the operator's dev environment is using, which on a working
		// dev box has live import jobs whose dynamically-created tables
		// would otherwise pollute database.types.ts.
		seedDB := "statbus_seed"
		if envFile, derr := dotenv.Load(filepath.Join(projDir, ".env")); derr == nil {
			if v, ok := envFile.Get("POSTGRES_SEED_DB"); ok && v != "" {
				seedDB = v
			}
		}
		for i, e := range env {
			if strings.HasPrefix(e, "PGDATABASE=") {
				env[i] = "PGDATABASE=" + seedDB
				break
			}
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

type stampGuardDecision int

const (
	stampGuardRun stampGuardDecision = iota
	stampGuardSkip
	stampGuardRefuse
)

// checkTypesStampGuard mirrors check_stamp_guard() in dev.sh for
// `./sb types generate`. Stamp basename: types-passed-sha. SKIP scope:
// migrations/ only (types derive from schema, not from tests or app code).
// REFUSE scope: migrations/ (stamping precondition).
//
// Output format matches the bash helper so operators see the same banner
// regardless of which Tier-1 command they invoked. FORCE=1 bypasses.
func checkTypesStampGuard(projDir string) stampGuardDecision {
	const label = "./sb types generate"
	const stampBasename = "types-passed-sha"
	stampPath := filepath.Join(projDir, "tmp", stampBasename)

	if force := os.Getenv("FORCE"); force == "1" || force == "true" {
		fmt.Println("RUNNING:", label)
		fmt.Println("Reason:  FORCE=1 — guard bypassed.")
		return stampGuardRun
	}

	dirty, _ := upgrade.RunCommandOutput(projDir, "git", "status", "--porcelain", "--", "migrations/")
	if strings.TrimSpace(dirty) != "" {
		fmt.Println("REFUSED:", label)
		fmt.Println("Reason:  migrations/ has uncommitted changes — stamping would not")
		fmt.Println("         honestly reflect HEAD.")
		fmt.Println("Evidence:")
		for _, line := range strings.Split(strings.TrimRight(dirty, "\n"), "\n") {
			fmt.Println("  " + line)
		}
		fmt.Println("Override: commit or stash migrations/ changes, or set FORCE=1 to bypass.")
		return stampGuardRefuse
	}

	data, err := os.ReadFile(stampPath)
	if err != nil {
		fmt.Println("RUNNING:", label)
		fmt.Printf("Reason:  no stamp at tmp/%s — no prior successful run to skip.\n", stampBasename)
		return stampGuardRun
	}
	stampSHA := strings.TrimSpace(string(data))
	if stampSHA == "" {
		fmt.Println("RUNNING:", label)
		fmt.Printf("Reason:  stamp tmp/%s is empty.\n", stampBasename)
		return stampGuardRun
	}

	if _, err := upgrade.RunCommandOutput(projDir, "git", "merge-base", "--is-ancestor", stampSHA, "HEAD"); err != nil {
		fmt.Println("RUNNING:", label)
		fmt.Printf("Reason:  stamp SHA %s is not an ancestor of HEAD (branch switch, rebase, or unknown commit).\n", stampSHA)
		return stampGuardRun
	}

	headOut, _ := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD")
	headSHA := strings.TrimSpace(headOut)

	changed, _ := upgrade.RunCommandOutput(projDir, "git", "diff", "--name-only", stampSHA, "HEAD", "--", "migrations/")
	changed = strings.TrimSpace(changed)
	if changed == "" {
		fmt.Println("SKIPPED:", label)
		fmt.Printf("Reason:  stamp tmp/%s points to a commit whose migrations content matches HEAD — re-running would produce an identical result.\n", stampBasename)
		fmt.Println("Evidence:")
		fmt.Println("  stamp SHA:", stampSHA)
		fmt.Println("  HEAD SHA: ", headSHA)
		fmt.Println("  files changed in scope (migrations): 0")
		fmt.Printf("Override: rm tmp/%s, or set FORCE=1.\n", stampBasename)
		return stampGuardSkip
	}

	fmt.Println("RUNNING:", label)
	fmt.Println("Reason:  in-scope content has drifted since stamp.")
	fmt.Println("Evidence:")
	fmt.Println("  stamp SHA:", stampSHA)
	fmt.Println("  HEAD SHA: ", headSHA)
	fmt.Println("  files changed in scope (migrations):")
	for _, line := range strings.Split(changed, "\n") {
		fmt.Println("    " + line)
	}
	return stampGuardRun
}
