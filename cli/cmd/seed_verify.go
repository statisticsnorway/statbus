package cmd

import (
	"bytes"
	"crypto/md5"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// ─────────────────────────────────────────────────────────────────────────────
// STATBUS-116 AC#4 — seed identity-check PROOF (`sb db seed verify-identical`).
//
// Proves that an INCREMENTALLY-built seed (restore the prior seed dump, then
// apply only the delta migrations) is IDENTICAL to a FULL from-empty rebuild.
// This is the empirical backstop behind the static SeedBuildDecision gate: the
// live build must NOT switch to incremental until this passes.
//
// The only DANGEROUS failure of an identity proof is a FALSE "identical", so the
// digest design is chosen for that: it dumps EVERYTHING (schema digest = the
// whole `pg_dump --schema-only`), so its failure mode is false-MISMATCH (cry
// wolf → investigate), never a silent miss. (Schema-digest ruling S1.)
//
// Decision-agnostic: the harness MANUFACTURES its own prior (`migrate up --to
// V_prev`), so it needs no CI prior-seed selection (Fork A) to run.
//
// The pure cores below (normalizeSchemaDump / dataDigestOfRows /
// combineTableDigests) are Docker-free and DIFFERENTIALLY unit-tested
// (seed_verify_test.go) — proven to DETECT a planted difference, not merely to
// match identical input. The orchestration (computeSeedDigest + the 3-DB build)
// needs a live Postgres and is run on demand, never auto-run in CI.
// ─────────────────────────────────────────────────────────────────────────────

// ── pure cores (Docker-free; differentially unit-tested) ─────────────────────

func sha256hex(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

// normalizeSchemaDump strips the deterministic-but-volatile lines from a
// `pg_dump --schema-only` so that two dumps of the SAME schema normalize to
// identical text. Removed: blank lines, `--` comments (incl. the `-- Name:/Type:`
// decorations + the dump header), `SET ...` session lines, and the
// `SELECT pg_catalog.set_config(...)` preamble. Everything else (the DDL) is
// kept verbatim; pg_dump emits DDL in an OID-independent, name+dependency order
// that is stable for identical schemas, so the surviving text is comparable.
func normalizeSchemaDump(raw string) string {
	var b strings.Builder
	for _, line := range strings.Split(raw, "\n") {
		t := strings.TrimRight(line, " \t\r")
		switch {
		case t == "":
			continue
		case strings.HasPrefix(t, "--"):
			continue
		case strings.HasPrefix(t, "SET "):
			continue
		case strings.HasPrefix(t, "SELECT pg_catalog.set_config"):
			continue
		}
		b.WriteString(t)
		b.WriteByte('\n')
	}
	return b.String()
}

// schemaDigestFromDump is sha256 of the normalized schema dump.
func schemaDigestFromDump(raw string) string { return sha256hex(normalizeSchemaDump(raw)) }

// dataDigestOfRows is the Go SPEC for a single table's data digest. The
// production path computes the IDENTICAL value in Postgres via
// perTableDataDigestSQL (md5 over string_agg of t::text ordered by t::text); both
// compared seeds use that one SQL so the ordering collation is consistent. This
// Go mirror exists to DIFFERENTIALLY test the algorithm Docker-free: it sorts
// the row-texts (so physical/insertion order is irrelevant) and hashes them, so
// a one-row difference flips the digest while a pure reorder does not.
func dataDigestOfRows(rows []string) string {
	s := append([]string(nil), rows...)
	sort.Strings(s)
	h := md5.New()
	for _, r := range s {
		io.WriteString(h, r)
	}
	return hex.EncodeToString(h.Sum(nil))
}

// perTableDataDigestSQL is the in-DB equivalent of dataDigestOfRows: it returns
// the per-table digest as a single value (empty string for an empty table).
func perTableDataDigestSQL(schema, table string) string {
	return fmt.Sprintf(`SELECT COALESCE(md5(string_agg(t::text, '' ORDER BY t::text)), '') FROM %s.%s AS t`,
		pgQuoteIdent(schema), pgQuoteIdent(table))
}

// combineTableDigests folds the per-table digests (keyed "schema.table") into one
// overall data digest, ordered by qualified name so the result is independent of
// map/iteration order. A change to any one table's digest flips the whole.
func combineTableDigests(perTable map[string]string) string {
	names := make([]string, 0, len(perTable))
	for k := range perTable {
		names = append(names, k)
	}
	sort.Strings(names)
	var b strings.Builder
	for _, n := range names {
		b.WriteString(n)
		b.WriteByte('=')
		b.WriteString(perTable[n])
		b.WriteByte('\n')
	}
	return sha256hex(b.String())
}

// pgQuoteIdent double-quotes a SQL identifier (doubling embedded quotes).
func pgQuoteIdent(s string) string { return `"` + strings.ReplaceAll(s, `"`, `""`) + `"` }

// ── digest of a live DB (needs Postgres; not unit-tested) ────────────────────

// seedDigest is the full semantic fingerprint of one built seed DB.
type seedDigest struct {
	Schema string // sha256(normalized pg_dump --schema-only)
	Data   string // combineTableDigests over all user tables (auth.secrets data excluded, matching the shipped seed)
	Ledger string // sha256 of the db.migration version|filename rows (the cheap pre-check)
}

func (d seedDigest) equal(o seedDigest) bool {
	return d.Schema == o.Schema && d.Data == o.Data && d.Ledger == o.Ledger
}

// computeSeedDigest fingerprints dbName: schema + per-table data + migration
// ledger. auth.secrets DATA is excluded (the shipped seed dumps it data-less, so
// including it would diverge full-vs-incremental spuriously).
func computeSeedDigest(projDir, dbName string) (seedDigest, error) {
	schemaRaw, err := pgDumpSchemaOnly(projDir, dbName)
	if err != nil {
		return seedDigest{}, err
	}

	tables, err := userTables(projDir, dbName)
	if err != nil {
		return seedDigest{}, err
	}
	perTable := make(map[string]string, len(tables))
	for _, qn := range tables {
		if qn == "auth.secrets" {
			perTable[qn] = "<data-excluded>"
			continue
		}
		parts := strings.SplitN(qn, ".", 2)
		if len(parts) != 2 {
			return seedDigest{}, fmt.Errorf("unexpected table name %q", qn)
		}
		d, err := migrate.QueryDB(projDir, dbName, perTableDataDigestSQL(parts[0], parts[1]), "-t", "-A")
		if err != nil {
			return seedDigest{}, fmt.Errorf("data digest %s: %w", qn, err)
		}
		perTable[qn] = strings.TrimSpace(d)
	}

	ledger, err := migrate.QueryDB(projDir, dbName,
		"SELECT version || '|' || filename FROM db.migration ORDER BY version", "-t", "-A")
	if err != nil {
		return seedDigest{}, fmt.Errorf("ledger digest: %w", err)
	}

	return seedDigest{
		Schema: schemaDigestFromDump(schemaRaw),
		Data:   combineTableDigests(perTable),
		Ledger: sha256hex(strings.TrimSpace(ledger)),
	}, nil
}

// userTables lists "schema.table" for every non-system table in dbName.
func userTables(projDir, dbName string) ([]string, error) {
	out, err := migrate.QueryDB(projDir, dbName,
		"SELECT schemaname || '.' || tablename FROM pg_tables "+
			"WHERE schemaname NOT IN ('pg_catalog','information_schema') ORDER BY 1", "-t", "-A")
	if err != nil {
		return nil, fmt.Errorf("list user tables: %w", err)
	}
	var tables []string
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		if t := strings.TrimSpace(line); t != "" {
			tables = append(tables, t)
		}
	}
	return tables, nil
}

// pgDumpSchemaOnly returns the schema-only dump text of dbName (DOCKER_PSQL-aware
// via PgDumpCommand, the same resolution DumpSeed uses).
func pgDumpSchemaOnly(projDir, dbName string) (string, error) {
	pgDumpPath, prefix, env, err := migrate.PgDumpCommand(projDir)
	if err != nil {
		return "", fmt.Errorf("resolve pg_dump: %w", err)
	}
	args := append(append([]string{}, prefix...), "-U", "postgres", "--schema-only", "--no-owner", dbName)
	cmd := exec.Command(pgDumpPath, args...)
	cmd.Dir = projDir
	cmd.Env = env
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("pg_dump --schema-only %s: %w", dbName, err)
	}
	return out.String(), nil
}

// ── 3-seed orchestration (needs Postgres + docker; runnable on demand, NEVER
//    auto-run — the foreman sequences the run) ─────────────────────────────────

const seedVerifyDBName = "statbus_seed_verify" // dedicated; never the real POSTGRES_SEED_DB

func restoreEnv(key, prev string, had bool) {
	if had {
		os.Setenv(key, prev)
	} else {
		os.Unsetenv(key)
	}
}

// migrateNamedDb runs migrate.Up against dbName by overriding the resolved-DB env
// (the same shape runMigrateUp uses), reverted on return. migrateTo==0 → migrate
// ALL pending; migrateTo>0 → up to that version inclusive.
func migrateNamedDb(projDir, dbName string, migrateTo int64) error {
	prevApp, hadApp := os.LookupEnv("POSTGRES_APP_DB")
	prevPG, hadPG := os.LookupEnv("PGDATABASE")
	os.Setenv("POSTGRES_APP_DB", dbName)
	os.Setenv("PGDATABASE", dbName)
	defer func() {
		restoreEnv("POSTGRES_APP_DB", prevApp, hadApp)
		restoreEnv("PGDATABASE", prevPG, hadPG)
	}()
	return migrate.Up(projDir, migrateTo, migrateTo == 0, verbose)
}

// recreateVerifyDb drops (force) and recreates dbName from template_statbus +
// the per-DB auth grants — the same shape as CreateSeedDb, but for an arbitrary
// (dedicated, disposable) name.
func recreateVerifyDb(projDir, dbName string) error {
	if err := migrate.ExecOnDB(projDir, "postgres",
		fmt.Sprintf("DROP DATABASE IF EXISTS %s WITH (FORCE);", pgQuoteIdent(dbName))); err != nil {
		return fmt.Errorf("drop %s: %w", dbName, err)
	}
	if err := migrate.ExecOnDB(projDir, "postgres",
		fmt.Sprintf("CREATE DATABASE %s WITH TEMPLATE template_statbus OWNER postgres;", pgQuoteIdent(dbName))); err != nil {
		return fmt.Errorf("create %s from template_statbus: %w", dbName, err)
	}
	if err := migrate.ExecOnDB(projDir, dbName,
		"CREATE SCHEMA IF NOT EXISTS auth;\n"+
			"GRANT USAGE ON SCHEMA auth TO authenticated;\n"+
			"GRANT USAGE ON SCHEMA auth TO anon;\n"+
			"GRANT USAGE ON SCHEMA public TO notify_reader;\n"); err != nil {
		return fmt.Errorf("auth grants on %s: %w", dbName, err)
	}
	return nil
}

// secondHighestVersion returns the second-largest applied db.migration version in
// dbName — used as V_prev so the manufactured incremental applies a non-empty
// delta (the final migration) over the restored prior.
func secondHighestVersion(projDir, dbName string) (int64, error) {
	out, err := migrate.QueryDB(projDir, dbName,
		"SELECT version FROM db.migration ORDER BY version DESC OFFSET 1 LIMIT 1", "-t", "-A")
	if err != nil {
		return 0, fmt.Errorf("query V_prev: %w", err)
	}
	v, err := strconv.ParseInt(strings.TrimSpace(out), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse V_prev %q: %w", out, err)
	}
	return v, nil
}

// dumpVerifyDB writes a -Fc dump of dbName to outPath, matching the shipped
// seed's flags (--no-owner --exclude-table-data=auth.secrets).
func dumpVerifyDB(projDir, dbName, outPath string) error {
	pgDumpPath, prefix, env, err := migrate.PgDumpCommand(projDir)
	if err != nil {
		return fmt.Errorf("resolve pg_dump: %w", err)
	}
	f, err := os.Create(outPath)
	if err != nil {
		return fmt.Errorf("create %s: %w", outPath, err)
	}
	defer f.Close()
	args := append(append([]string{}, prefix...),
		"-U", "postgres", "-Fc", "--no-owner", "--exclude-table-data=auth.secrets", dbName)
	cmd := exec.Command(pgDumpPath, args...)
	cmd.Dir = projDir
	cmd.Env = env
	cmd.Stdout = f
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("pg_dump -Fc %s: %w", dbName, err)
	}
	return nil
}

// restoreVerifyDB pg_restores dumpPath into dbName via docker compose exec (the
// same atomic contract seedRestoreCmd uses — runPgRestoreAtomic fails loud on any
// error with --single-transaction).
func restoreVerifyDB(projDir, dbName, dumpPath string) error {
	f, err := os.Open(dumpPath)
	if err != nil {
		return fmt.Errorf("open %s: %w", dumpPath, err)
	}
	defer f.Close()
	cmd := exec.Command("docker", "compose", "exec", "-T", "db",
		"pg_restore", "-U", "postgres",
		"--clean", "--if-exists", "--no-owner", "--disable-triggers",
		"--single-transaction", "-d", dbName)
	cmd.Dir = projDir
	cmd.Stdin = f
	return runPgRestoreAtomic(cmd, "seed-verify restore")
}

// verifySeedIdentical builds a FULL seed and an INCREMENTAL seed (manufacturing
// its own prior) and proves their digests match. Destructive only to the
// dedicated seedVerifyDBName; never touches the real seed DB. Heavy (3 migrate
// passes + a restore) — run on demand, not in per-build CI.
func verifySeedIdentical(projDir string) error {
	tmpDir := filepath.Join(projDir, "tmp")
	if err := os.MkdirAll(tmpDir, 0755); err != nil {
		return err
	}
	priorDump := filepath.Join(tmpDir, "seed-verify-prior.pg_dump")

	// 1. FULL: build the whole seed, digest it, and learn V_prev (second-highest).
	fmt.Println("seed verify: building FULL seed (all migrations from empty)...")
	if err := recreateVerifyDb(projDir, seedVerifyDBName); err != nil {
		return err
	}
	if err := migrateNamedDb(projDir, seedVerifyDBName, 0); err != nil {
		return fmt.Errorf("full migrate: %w", err)
	}
	full, err := computeSeedDigest(projDir, seedVerifyDBName)
	if err != nil {
		return err
	}
	vPrev, err := secondHighestVersion(projDir, seedVerifyDBName)
	if err != nil {
		return err
	}

	// 2. PRIOR: rebuild only up to V_prev and dump it (the manufactured prior seed).
	fmt.Printf("seed verify: building PRIOR seed (--to %d) and dumping it...\n", vPrev)
	if err := recreateVerifyDb(projDir, seedVerifyDBName); err != nil {
		return err
	}
	if err := migrateNamedDb(projDir, seedVerifyDBName, vPrev); err != nil {
		return fmt.Errorf("prior migrate --to %d: %w", vPrev, err)
	}
	if err := dumpVerifyDB(projDir, seedVerifyDBName, priorDump); err != nil {
		return err
	}

	// 3. INCREMENTAL: restore the prior, apply only the delta, digest it.
	fmt.Println("seed verify: building INCREMENTAL seed (restore prior + delta-migrate)...")
	if err := recreateVerifyDb(projDir, seedVerifyDBName); err != nil {
		return err
	}
	if err := restoreVerifyDB(projDir, seedVerifyDBName, priorDump); err != nil {
		return err
	}
	if err := migrateNamedDb(projDir, seedVerifyDBName, 0); err != nil {
		return fmt.Errorf("delta migrate: %w", err)
	}
	incr, err := computeSeedDigest(projDir, seedVerifyDBName)
	if err != nil {
		return err
	}

	// 4. Compare + clean up the disposable DB.
	if dropErr := migrate.ExecOnDB(projDir, "postgres",
		fmt.Sprintf("DROP DATABASE IF EXISTS %s WITH (FORCE);", pgQuoteIdent(seedVerifyDBName))); dropErr != nil {
		fmt.Printf("seed verify: warning: could not drop %s: %v\n", seedVerifyDBName, dropErr)
	}

	if full.equal(incr) {
		fmt.Printf("✓ seed identity PROVEN: incremental == full (schema=%s data=%s ledger=%s; V_prev=%d)\n",
			full.Schema[:12], full.Data[:12], full.Ledger[:12], vPrev)
		return nil
	}
	return fmt.Errorf("✗ seed identity FAILED — incremental seed differs from a full rebuild:\n"+
		"  schema: full=%s incr=%s%s\n"+
		"  data:   full=%s incr=%s%s\n"+
		"  ledger: full=%s incr=%s%s\n"+
		"  (a true mismatch means the incremental shortcut is UNSAFE — do NOT enable it)",
		full.Schema[:12], incr.Schema[:12], mark(full.Schema == incr.Schema),
		full.Data[:12], incr.Data[:12], mark(full.Data == incr.Data),
		full.Ledger[:12], incr.Ledger[:12], mark(full.Ledger == incr.Ledger))
}

func mark(ok bool) string {
	if ok {
		return " ✓"
	}
	return " ✗ DIFFERS"
}

var seedVerifyIdenticalCmd = &cobra.Command{
	Use:   "verify-identical",
	Short: "Prove an incrementally-built seed is identical to a full rebuild (STATBUS-116 AC#4)",
	Long: `Build a FULL seed and an INCREMENTAL seed (restore a manufactured prior +
apply only the delta migrations) and prove their schema + data + migration-ledger
digests match. The empirical backstop behind the seed-incremental gate.

Heavy (3 migrate passes + a restore against a live database) and DESTRUCTIVE to
the dedicated ` + seedVerifyDBName + ` database (never the real seed DB). Run on
demand — not part of per-build CI. Requires 'sb start all' (template_statbus).`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return verifySeedIdentical(config.ProjectDir())
	},
}

func init() {
	seedCmd.AddCommand(seedVerifyIdenticalCmd)
}
