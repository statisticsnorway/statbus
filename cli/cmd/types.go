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
		stampDecision := checkTypesStampGuard(projDir)
		switch stampDecision {
		case stampGuardSkip:
			return nil
		}
		// stampGuardRun and stampGuardRunNoStamp both proceed to generate; the
		// write below is gated on stampDecision so RUN_NO_STAMP withholds the stamp.

		sqlFile, err := os.Open(sqlPath)
		if err != nil {
			return fmt.Errorf("open type generator: %w", err)
		}
		defer func() { _ = sqlFile.Close() }()

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

		// Refuse if the seed DB's db.migration row set doesn't match the
		// on-disk migrations/ file set. Without this gate a stale seed
		// could yield database.types.ts reflecting an older schema —
		// stamp would still pass preflight (line 1 = HEAD SHA) but the
		// types would silently lag. assertDBAtHead returns the seed's
		// max migration version on success — we record it as line 2 of
		// the H1 two-line stamp so preflight catches the bypass case
		// where a future generator writes a stamp from a stale source.
		seedVersion, err := migrate.AssertDBAtHead(projDir, seedDB, "./sb types generate")
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
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

		// Write H1 two-line stamp for ./sb release preflight:
		//   line 1: HEAD SHA at generation time
		//   line 2: seed DB's migration_version at generation time
		// Preflight verifies BOTH lines so a stamp written from a stale
		// source DB (the bug class #123 hardens against) fails the gate
		// even when the SHA happens to be HEAD.
		// RUN_NO_STAMP: migrations/ was dirty at guard time — regenerate but
		// WITHHOLD the stamp (a dirty-tree stamp can't honestly point at a commit).
		// Loud, per "observe evidence + warn, never silently skip": say it was
		// withheld and that preflight needs a clean-tree re-run after the commit.
		if stampDecision == stampGuardRunNoStamp {
			fmt.Println("TypeScript types stamp WITHHELD — migrations/ was dirty at guard time.")
			fmt.Println("  Commit, then re-run './sb types generate' on a clean tree to write the")
			fmt.Println("  release stamp (preflight requires it).")
		} else if sha, err2 := upgrade.RunCommandOutput(projDir, "git", "rev-parse", "HEAD"); err2 == nil {
			stampPath := filepath.Join(projDir, "tmp", "types-passed-sha")
			_ = os.MkdirAll(filepath.Dir(stampPath), 0755)
			headSHA := strings.TrimSpace(sha)
			_ = os.WriteFile(stampPath, []byte(headSHA+"\n"+seedVersion+"\n"), 0644)
			fmt.Printf("TypeScript types stamp recorded: %s (seed version: %s)\n",
				headSHA, seedVersion)
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
	// stampGuardRunNoStamp: migrations/ is dirty (you're landing a migration).
	// RUN the generate, but DO NOT write the freshness stamp — a stamp from a
	// dirty tree can't honestly point at a commit. Release preflight re-derives
	// freshness, so a clean-tree re-run after the commit writes the honest stamp.
	stampGuardRunNoStamp
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
		// migrations/ is dirty — you're (almost certainly) landing a migration.
		// RUN the regen but WITHHOLD the freshness stamp (see stampGuardRunNoStamp).
		fmt.Println("RUNNING:", label, "— freshness stamp DEFERRED (migrations/ is dirty)")
		fmt.Println("Reason:  migrations/ has uncommitted changes — running the regen now, but NOT")
		fmt.Println("         writing the freshness stamp (a stamp from a dirty tree can't honestly")
		fmt.Println("         point at a commit). Release preflight re-derives freshness, so after you")
		fmt.Println("         commit, re-run this on a clean tree to write the stamp.")
		fmt.Println("If you're landing a migration, the full no-override flow is:")
		fmt.Println("  1. ./sb migrate up --target seed && ./dev.sh create-test-template   # seed->HEAD (non-destructive)")
		fmt.Println("  2. ./dev.sh generate-doc-db && ./sb types generate                  # regenerate")
		fmt.Println("  3. git add migrations/ doc/db/ app/src/lib/database.types.ts <your code>")
		fmt.Println("  4. git commit                                                       # pre-commit pairs migration+regen")
		fmt.Println("  5. after commit (clean tree) re-run step 2 once -> writes the release stamp")
		fmt.Println("Do NOT use FORCE=1 to land a migration — it writes a stamp from a dirty tree, the")
		fmt.Println("exact lie this guard prevents. FORCE=1 is only for regenerating against an")
		fmt.Println("already-committed schema (e.g. a generator change with no new migration).")
		fmt.Println("Evidence (uncommitted in migrations/):")
		for _, line := range strings.Split(strings.TrimRight(dirty, "\n"), "\n") {
			fmt.Println("  " + line)
		}
		return stampGuardRunNoStamp
	}

	data, err := os.ReadFile(stampPath)
	if err != nil {
		fmt.Println("RUNNING:", label)
		fmt.Printf("Reason:  no stamp at tmp/%s — no prior successful run to skip.\n", stampBasename)
		return stampGuardRun
	}
	// H1 two-line stamp (task #123): line 1 = HEAD SHA, line 2 = source
	// DB migration_version. Pre-task-#131 this used
	// `strings.TrimSpace(string(data))` which left the inner newline
	// intact — `stampSHA` became a two-line string that mangled git
	// operations (`git merge-base --is-ancestor` always failed because
	// the multi-line ref name is not a valid revision) and rendered as
	// a bled diagnostic across two terminal lines. parseTwoLineStamp
	// (release.go) extracts the two fields cleanly; legacy single-line
	// stamps return stampVersion="" and continue to work via the SHA
	// path below.
	stampSHA, stampVersion := parseTwoLineStamp(data)
	if stampSHA == "" {
		fmt.Println("RUNNING:", label)
		fmt.Printf("Reason:  stamp tmp/%s is empty.\n", stampBasename)
		return stampGuardRun
	}

	// Diagnostic helper: format the stamp identity for printing. Shows
	// just the SHA for legacy single-line stamps; SHA + labeled version
	// for H1 two-line stamps. Keeps the operator-visible output honest
	// about which stamp shape we're reading.
	stampDisplay := stampSHA
	if stampVersion != "" {
		stampDisplay = fmt.Sprintf("%s (source migration_version: %s)", stampSHA, stampVersion)
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
		fmt.Println("  stamp:   ", stampDisplay)
		fmt.Println("  HEAD SHA:", headSHA)
		fmt.Println("  files changed in scope (migrations): 0")
		fmt.Printf("Override: rm tmp/%s, or set FORCE=1.\n", stampBasename)
		return stampGuardSkip
	}

	fmt.Println("RUNNING:", label)
	fmt.Println("Reason:  in-scope content has drifted since stamp.")
	fmt.Println("Evidence:")
	fmt.Println("  stamp:   ", stampDisplay)
	fmt.Println("  HEAD SHA:", headSHA)
	fmt.Println("  files changed in scope (migrations):")
	for _, line := range strings.Split(changed, "\n") {
		fmt.Println("    " + line)
	}
	return stampGuardRun
}
