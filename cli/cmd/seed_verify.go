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
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/config"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
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

// redundantCastAliasRe matches a cast immediately followed by an explicit column
// alias — `::<type> AS <name>` — capturing (1) the whole cast incl. `::` and any
// schema qualification, (2) the type's UNQUALIFIED last component, and (3) the
// alias. PostgreSQL infers a cast expression's column name from the type's last
// component, so when <name> equals that component the `AS <name>` is REDUNDANT: it
// names the column EXACTLY what the cast already infers, hence collapsing it is
// behaviorally inert even on a set-operation's first branch. RE2 has no
// backreferences, so the alias==type-name test is done in the replace func, not
// the pattern. Type modifiers / spaced types (`character varying`) simply don't
// match and are preserved (collapse is opt-in, never speculative).
var redundantCastAliasRe = regexp.MustCompile(`(::(?:[a-zA-Z_][a-zA-Z0-9_]*\.)*([a-zA-Z_][a-zA-Z0-9_]*))\s+AS\s+([a-zA-Z_][a-zA-Z0-9_]*)`)

// collapseRedundantCastAliases drops `AS <name>` from `::<type> AS <name>` EXACTLY
// when <name> equals the cast type's own unqualified name. This is the one NAMED
// round-trip schema artifact (STATBUS-116 AC#4): pg_dump's pg_get_viewdef emits
// this redundant alias on a view that has been round-tripped through dump/restore
// (the INCREMENTAL seed) but omits it on a freshly-migrated view (the FULL seed) —
// observed on public.statistical_unit_def's UNION-branch `::public.
// statistical_unit_type AS statistical_unit_type` targets. Collapsing it makes the
// S1 text oracle agree with the proven SEMANTIC identity. Matching alias==type's
// own name is what guarantees a MEANINGFUL rename (alias ≠ type name) can NEVER be
// collapsed — proven by the differential tests in seed_verify_test.go.
func collapseRedundantCastAliases(s string) string {
	return redundantCastAliasRe.ReplaceAllStringFunc(s, func(m string) string {
		g := redundantCastAliasRe.FindStringSubmatch(m)
		// g[1]=cast incl `::`; g[2]=type's unqualified last component; g[3]=alias.
		if g[2] == g[3] {
			return g[1] // redundant alias → drop it (keep the cast verbatim)
		}
		return m // alias is a real rename → preserve untouched
	})
}

// normalizeSchemaDump strips the deterministic-but-volatile lines from a
// `pg_dump --schema-only` so that two dumps of the SAME schema normalize to
// identical text. Removed: blank lines; `--` comments (incl. the `-- Name:/Type:`
// decorations + the dump header); `SET ...` session lines; the
// `SELECT pg_catalog.set_config(...)` preamble; and psql backslash meta-commands
// (`\restrict`/`\unrestrict`/`\connect`/…). The `\restrict <token>` /
// `\unrestrict <token>` pair is the one NAMED schema non-determinism: PG18's
// pg_dump emits it with a fresh RANDOM token per invocation (a psql client
// directive, not schema), so without stripping it two dumps of an IDENTICAL
// schema digest differently — proven by the dump→restore round-trip whose ONLY
// schema diff was exactly those two lines. Each surviving line is then run through
// collapseRedundantCastAliases to erase the ONE NAMED round-trip artifact (a
// redundant `::type AS type` view-column alias). Everything else (the DDL) is kept
// verbatim; pg_dump emits DDL in an OID-independent, name+dependency order that
// is stable for identical schemas, so the surviving text is comparable.
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
		case strings.HasPrefix(t, `\`):
			continue // psql meta-command (\restrict/\unrestrict: random per-invocation token)
		}
		b.WriteString(collapseRedundantCastAliases(t))
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
		_, _ = io.WriteString(h, r) // hash.Hash.Write never returns an error
	}
	return hex.EncodeToString(h.Sum(nil))
}

// volatileDefaultPattern matches a column DEFAULT that is a build-volatile
// function — audit timestamps (now/clock_timestamp/statement_timestamp/
// current_timestamp) and random/uuid generators. STATBUS-116 AC#4: columns with
// such defaults receive the BUILD WALL-CLOCK time (or fresh randomness) when
// migration-inserted seed rows omit them, so they are build noise, NOT semantic
// seed content. Architect-blessed: business-temporal validity columns
// (x_from/x_to/valid_*) never carry a volatile DEFAULT, so this rule cannot
// touch them — it only excludes the audit-metadata columns.
const volatileDefaultPattern = `(now|clock_timestamp|statement_timestamp|current_timestamp|random|gen_random_uuid)`

// semanticColumnRe matches a column NAME that looks BUSINESS-TEMPORAL/semantic
// (validity periods, effective dates, business "on/from/to" dates) rather than
// audit metadata. The self-guard FAILS LOUD if such a column is about to be
// auto-excluded — see contentColumns.
var semanticColumnRe = regexp.MustCompile(`(?i)(valid|effective|period|range|_from$|_to$|_until$|_after$|_on$)`)

// contentColumns returns dbName.schema.table's DETERMINISTIC columns (ordinal
// order): all columns EXCEPT those whose DEFAULT matches volatileDefaultPattern.
// A column with no default, or a non-volatile default, is content.
//
// SELF-GUARD (architect refinement): the auto-exclusion is convenient but would
// SILENTLY HIDE REAL DRIFT if a future migration ever attached a volatile DEFAULT
// to a business-temporal/semantic column. So this aborts LOUD whenever an
// excluded column's NAME looks semantic (valid*/_from/_to/_until/_after/_on/
// period/range/effective) instead of audit. Verified 0 such columns today; the
// guard is what keeps the convenient rule safe as the schema evolves — it ships
// WITH the exclusion, not after.
func contentColumns(projDir, dbName, schema, table string) ([]string, error) {
	sql := fmt.Sprintf(`SELECT column_name, `+
		`(column_default IS NOT NULL AND column_default ~* '%s') AS volatile `+
		`FROM information_schema.columns `+
		`WHERE table_schema = %s AND table_name = %s ORDER BY ordinal_position`,
		volatileDefaultPattern, pgLiteral(schema), pgLiteral(table))
	out, err := migrate.QueryDB(projDir, dbName, sql, "-t", "-A", "-F", "|")
	if err != nil {
		return nil, fmt.Errorf("content columns %s.%s: %w", schema, table, err)
	}
	var cols []string
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		name, volatile, _ := strings.Cut(line, "|")
		if volatile == "t" {
			if semanticColumnRe.MatchString(name) {
				return nil, fmt.Errorf("SELF-GUARD TRIPPED: %s.%s.%s has a volatile DEFAULT but its name "+
					"looks business-temporal/semantic — auto-excluding it from the seed data digest could "+
					"silently HIDE real drift. A migration likely attached a volatile default to a semantic "+
					"column; investigate before trusting this proof (do not relax the guard blindly)",
					schema, table, name)
			}
			continue // benign audit column — excluded from the content digest
		}
		cols = append(cols, name)
	}
	return cols, nil
}

// perTableDataDigestSQL is the in-DB equivalent of dataDigestOfRows, restricted
// to the given CONTENT columns: md5 over the sorted text of ROW(content cols)
// only, so build-volatile audit columns (excluded by the caller) cannot enter
// the digest. With no content columns left (a table that is all audit metadata),
// it falls back to the row count so add/remove is still detected.
func perTableDataDigestSQL(schema, table string, contentCols []string) string {
	if len(contentCols) == 0 {
		return fmt.Sprintf(`SELECT 'rows:' || count(*) FROM %s.%s`, pgQuoteIdent(schema), pgQuoteIdent(table))
	}
	qualified := make([]string, len(contentCols))
	for i, c := range contentCols {
		qualified[i] = "t." + pgQuoteIdent(c)
	}
	rowExpr := "ROW(" + strings.Join(qualified, ", ") + ")::text"
	return fmt.Sprintf(`SELECT COALESCE(md5(string_agg(%s, '' ORDER BY %s)), '') FROM %s.%s AS t`,
		rowExpr, rowExpr, pgQuoteIdent(schema), pgQuoteIdent(table))
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

// pgLiteral single-quotes a SQL string literal (doubling embedded quotes).
func pgLiteral(s string) string { return `'` + strings.ReplaceAll(s, `'`, `''`) + `'` }

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

// excludedTables are whole tables whose DATA is excluded from the seed digest
// because it is OPERATIONAL/bookkeeping state, not semantic seed content:
//   - auth.secrets   — the shipped seed dumps it data-less.
//   - db.migration   — migration bookkeeping; its meaningful content is the
//     Ledger digest (version|filename). id/applied_at/duration_ms
//     are per-build volatile.
//   - worker.tasks   — the operational task QUEUE. Migrations spawn maintenance
//     tasks (collect_changes, *_cleanup) via worker.spawn() with
//     build-time-relative scheduled_at (now()/now()+interval), so
//     the rows carry build-wall-clock timestamps. Determined
//     MIGRATION-driven + deterministic (STATBUS-116 AC#4
//     diagnostic — NOT a worker-daemon run), so excluding the
//     queue verifies nothing semantic and avoids a hand-named
//     volatile-column list (which the self-guard discourages).
//     Architect-blessed disposition (a).
func isExcludedTable(qualifiedName string) bool {
	switch qualifiedName {
	case "auth.secrets", "db.migration", "worker.tasks":
		return true
	}
	return false
}

// computeSeedDigest fingerprints dbName: schema + per-table data + migration
// ledger. Two table data-sets are excluded as NON-SEED-CONTENT build noise:
//   - db.migration — bookkeeping, not seed data: its rows carry id (SERIAL),
//     applied_at (DEFAULT now()) and duration_ms, all per-build volatile. Its
//     MEANINGFUL content (which migrations are applied) is the Ledger digest
//     (version|filename) below, so the table itself is the NAMED data
//     non-determinism and is excluded from the data digest entirely.
//   - auth.secrets — the shipped seed dumps it data-less, so including it would
//     diverge full-vs-incremental spuriously.
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
		if isExcludedTable(qn) {
			perTable[qn] = "<data-excluded>"
			continue
		}
		parts := strings.SplitN(qn, ".", 2)
		if len(parts) != 2 {
			return seedDigest{}, fmt.Errorf("unexpected table name %q", qn)
		}
		cols, err := contentColumns(projDir, dbName, parts[0], parts[1])
		if err != nil {
			return seedDigest{}, err
		}
		d, err := migrate.QueryDB(projDir, dbName, perTableDataDigestSQL(parts[0], parts[1], cols), "-t", "-A")
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
		_ = os.Setenv(key, prev)
	} else {
		_ = os.Unsetenv(key)
	}
}

// migrateNamedDb runs migrate.Up against dbName by overriding the resolved-DB env
// (the same shape runMigrateUp uses), reverted on return. migrateTo==0 → migrate
// ALL pending; migrateTo>0 → all pending up to that version inclusive.
func migrateNamedDb(projDir, dbName string, migrateTo int64) error {
	defer migrate.SetTargetDB(dbName)()

	prevMode, hadMode := os.LookupEnv("CADDY_DEPLOYMENT_MODE")
	// standalone dodges migrate.Up's dev-only maybeRebuildTestTemplate side-effect
	// (migrate.go) — the same dodge the hermetic seed-builder uses — so the verify
	// run never rebuilds the dev statbus_test_template.
	_ = os.Setenv("CADDY_DEPLOYMENT_MODE", "standalone")
	defer func() {
		restoreEnv("CADDY_DEPLOYMENT_MODE", prevMode, hadMode)
	}()
	// all=TRUE always: apply ALL pending migrations. The migrateTo>0 cap inside
	// runUp already bounds them to version <= migrateTo, so this means "all
	// pending up to V_prev". all=false would TRUNCATE to the first pending
	// migration (runUp's `if !all && len(pending) > 1`) — the bug that made the
	// manufactured prior a 1-migration stub.
	return migrate.Up(projDir, migrateTo, true, verbose)
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
	defer func() { _ = f.Close() }()
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
	defer func() { _ = f.Close() }()
	cmd := exec.Command("docker", "compose", "exec", "-T", "db",
		"pg_restore", "-U", "postgres",
		"--clean", "--if-exists", "--no-owner", "--disable-triggers",
		"--single-transaction", "-d", dbName)
	cmd.Dir = projDir
	cmd.Stdin = f
	return runPgRestoreAtomic(cmd, "seed-verify restore")
}

// keepVerifyDBs (set by --keep-dbs) preserves the verify databases on exit so a
// mismatch can be inspected live. Diff artifacts are written to tmp/ regardless.
var keepVerifyDBs bool

func dropVerifyDB(projDir, dbName string) {
	if keepVerifyDBs {
		return
	}
	if err := migrate.ExecOnDB(projDir, "postgres",
		fmt.Sprintf("DROP DATABASE IF EXISTS %s WITH (FORCE);", pgQuoteIdent(dbName))); err != nil {
		fmt.Printf("seed verify: warning: could not drop %s: %v\n", dbName, err)
	}
}

// captureSeedDumps writes the NORMALIZED schema dump + the per-table data digest
// lines of dbName to tmp/seed-verify-<label>-{schema,data}.txt, so two captures
// can be `diff`ed to LOCALIZE (name) exactly which DDL/object/table diverged.
func captureSeedDumps(projDir, dbName, label string) {
	schemaRaw, err := pgDumpSchemaOnly(projDir, dbName)
	if err != nil {
		fmt.Printf("seed verify: capture schema %s: %v\n", label, err)
		return
	}
	schemaPath := filepath.Join(projDir, "tmp", "seed-verify-"+label+"-schema.txt")
	_ = os.WriteFile(schemaPath, []byte(normalizeSchemaDump(schemaRaw)), 0644)

	var b strings.Builder
	if tables, err := userTables(projDir, dbName); err == nil {
		for _, qn := range tables {
			if isExcludedTable(qn) {
				b.WriteString(qn + "=<data-excluded>\n")
				continue
			}
			parts := strings.SplitN(qn, ".", 2)
			cols, _ := contentColumns(projDir, dbName, parts[0], parts[1])
			d, _ := migrate.QueryDB(projDir, dbName, perTableDataDigestSQL(parts[0], parts[1], cols), "-t", "-A")
			b.WriteString(qn + "=" + strings.TrimSpace(d) + "\n")
		}
	}
	dataPath := filepath.Join(projDir, "tmp", "seed-verify-"+label+"-data.txt")
	_ = os.WriteFile(dataPath, []byte(b.String()), 0644)
	fmt.Printf("  captured %s → %s + %s\n", label, schemaPath, dataPath)
}

// buildFullSeed recreates dbName and migrates ALL → a fresh full seed; returns
// its digest.
func buildFullSeed(projDir, dbName string) (seedDigest, error) {
	if err := recreateVerifyDb(projDir, dbName); err != nil {
		return seedDigest{}, err
	}
	if err := migrateNamedDb(projDir, dbName, 0); err != nil {
		return seedDigest{}, fmt.Errorf("full migrate %s: %w", dbName, err)
	}
	return computeSeedDigest(projDir, dbName)
}

// priorSource abstracts HOW the "prior seed" the incremental path restores is
// obtained, so one shared verify body serves two proofs:
//   - MANUFACTURED (AC#4, `verify-identical`): build the prior from empty via
//     `migrate --to V_prev` → a SINGLE last-migration delta, and (crucially) the
//     SAME physical layout as the FULL build (both from empty). Cheap, self-
//     contained, decision-agnostic — but blind to physical-state-dependent
//     migrations, which are consistently-wrong in both from-empty builds.
//   - REAL IMAGE (AC#6, `verify-multidelta`): restore a REAL published prior-
//     RELEASE seed image (its OID/row order frozen by a PAST CI build) and apply
//     that release's FULL, MANY-migration delta. The only proof that exercises
//     physical-state-independence across a real restored-base boundary.
//
// prepare produces the prior dump (returning its path), the prior's migration
// version V_prior, and — when the prior is a real recorded seed — its seedMeta
// (nil for the manufactured prior). fullDb is the intact FULL build (dbA) it may
// read version info from; scratchDb (dbB) is a disposable it may rebuild.
type priorSource struct {
	label             string
	requireMultiDelta bool // AC#6: fail loud if the delta is <= 1 migration
	prepare           func(projDir, fullDb, scratchDb string) (dumpPath string, vPrior int64, meta *seedMeta, err error)
}

// manufacturedPriorSource is the AC#4 single-delta prior: rebuild scratchDb to
// V_prev (the second-highest applied version) from empty and dump it. meta=nil
// (no recorded fingerprint to eligibility-check); requireMultiDelta=false (a
// single last-migration delta is the whole point).
func manufacturedPriorSource() priorSource {
	return priorSource{
		label: "manufactured single-delta prior (migrate --to V_prev from empty)",
		prepare: func(projDir, fullDb, scratchDb string) (string, int64, *seedMeta, error) {
			vPrev, err := secondHighestVersion(projDir, fullDb)
			if err != nil {
				return "", 0, nil, err
			}
			priorDump := filepath.Join(projDir, "tmp", "seed-verify-prior.pg_dump")
			fmt.Printf("seed verify: building PRIOR seed (--to %d) and dumping it...\n", vPrev)
			if err := recreateVerifyDb(projDir, scratchDb); err != nil {
				return "", 0, nil, err
			}
			if err := migrateNamedDb(projDir, scratchDb, vPrev); err != nil {
				return "", 0, nil, fmt.Errorf("prior migrate --to %d: %w", vPrev, err)
			}
			if err := dumpVerifyDB(projDir, scratchDb, priorDump); err != nil {
				return "", 0, nil, err
			}
			return priorDump, vPrev, nil, nil
		},
	}
}

// imagePriorSource is the AC#6 real prior-RELEASE prior: extract seed.pg_dump +
// seed.json from a published statbus-seed image (extractSeedFromImage → the same
// docker create + cp used by `seed fetch`), parse V_release from its recorded
// meta. requireMultiDelta=true (the run must exercise a real many-migration
// delta); meta!=nil so the shared body runs the AC#2 fingerprint eligibility gate.
func imagePriorSource(imageRef string) priorSource {
	return priorSource{
		label:             "real prior-RELEASE image " + imageRef,
		requireMultiDelta: true,
		prepare: func(projDir, fullDb, scratchDb string) (string, int64, *seedMeta, error) {
			if strings.TrimSpace(imageRef) == "" {
				return "", 0, nil, fmt.Errorf("--prior-image is required (a published statbus-seed:<release-commit-short> ref)")
			}
			dir := filepath.Join(projDir, "tmp", "seed-verify-prior-image")
			if err := os.RemoveAll(dir); err != nil {
				return "", 0, nil, fmt.Errorf("clear %s: %w", dir, err)
			}
			if err := os.MkdirAll(dir, 0755); err != nil {
				return "", 0, nil, err
			}
			fmt.Printf("seed verify: extracting prior-RELEASE seed from %s ...\n", imageRef)
			if err := extractSeedFromImage(projDir, imageRef, dir); err != nil {
				return "", 0, nil, fmt.Errorf("extract prior seed image %s: %w", imageRef, err)
			}
			meta, err := loadSeedMetaFrom(filepath.Join(dir, "seed.json"))
			if err != nil {
				return "", 0, nil, fmt.Errorf("load prior seed.json: %w", err)
			}
			vRelease, err := parseSeedMetaVersion(meta)
			if err != nil {
				return "", 0, nil, err
			}
			return filepath.Join(dir, "seed.pg_dump"), vRelease, meta, nil
		},
	}
}

// verifyPriorEligible establishes that the migrations baked into the prior seed
// (version <= vPrior) are byte-unchanged in the current tree — the precondition
// for a meaningful INCR-vs-FULL comparison.
//
//   - Fingerprint RECORDED (post-STATBUS-116 seed): SeedBuildDecision is
//     authoritative (recompute the fingerprint over the current migrations <=
//     vPrior and compare). A mismatch hard-fails exactly as production would fall
//     back to full — an off-path base proves nothing.
//   - Fingerprint ABSENT (pre-fingerprint seed): production can't verify it and
//     falls back to full, but for the VERIFICATION we DERIVE eligibility from git —
//     the prior's seed.json records the commit it was built from, so a git diff of
//     the baked migrations between that commit and HEAD answers the same question
//     the fingerprint would. This is what lets AC#6 run against a real pre-116
//     release (its frozen physical layout is a valid physical-state substrate; the
//     fingerprint guards a DIFFERENT, content-drift axis).
func verifyPriorEligible(projDir string, priorMeta *seedMeta, vPrior int64) error {
	if priorMeta.MigrationsFingerprint != "" {
		if ok, reason := SeedBuildDecision(priorMeta, projDir); !ok {
			return fmt.Errorf("✗ chosen prior is NOT incremental-eligible: %s\n"+
				"  Pick a prior RELEASE whose migrations <= its version are unchanged in this tree "+
				"(a retro-edited base would fall back to a full rebuild in production, so this run would prove nothing)", reason)
		}
		return nil
	}
	return deriveEligibilityFromGit(projDir, priorMeta, vPrior)
}

// deriveEligibilityFromGit answers "are the migrations <= vPrior baked into the
// prior seed byte-unchanged in the current tree?" for a pre-fingerprint seed, by
// diffing them between the prior's build commit (recorded in seed.json) and HEAD.
// --no-renames so a renamed/deleted <=vPrior migration always surfaces as a
// change (rename → delete-old + add-new, both listed). Empty changed set →
// eligible (loud, named derivation); non-empty → fail loud like a fingerprint
// mismatch. Fails loud if the commit is missing/unresolvable (no silent pass).
func deriveEligibilityFromGit(projDir string, priorMeta *seedMeta, vPrior int64) error {
	commit := strings.TrimSpace(priorMeta.CommitSHA)
	if commit == "" {
		return fmt.Errorf("✗ prior seed.json records no commit_sha and no migrations_fingerprint — cannot establish " +
			"eligibility for this pre-fingerprint seed; pick a prior with a recorded fingerprint or commit")
	}
	if !gitHasCommit(projDir, commit) {
		// Best-effort fetch, then re-check — the prior's commit must be a real
		// object in this clone to diff against.
		_, _ = upgrade.RunCommandOutput(projDir, "git", "fetch", "--quiet")
		if !gitHasCommit(projDir, commit) {
			return fmt.Errorf("✗ prior seed commit %s is not in the local clone (even after a fetch) — cannot derive "+
				"eligibility from git; fetch it or pick a different prior", shortCommit(commit))
		}
	}
	out, err := upgrade.RunCommandOutput(projDir, "git", "diff", "--name-only", "--no-renames", commit+"..HEAD", "--", "migrations")
	if err != nil {
		return fmt.Errorf("git diff for eligibility (%s..HEAD): %w\n  %s", shortCommit(commit), err, strings.TrimSpace(out))
	}
	changed := changedBakedMigrations(strings.Split(out, "\n"), vPrior)
	if len(changed) > 0 {
		return fmt.Errorf("✗ chosen prior is NOT incremental-eligible: %d baked migration(s) <= V_prior=%d changed "+
			"between the prior seed's commit %s and HEAD (same drift hazard as a fingerprint mismatch — a changed/"+
			"renamed/deleted <=V_prior migration makes INCR differ from FULL for a CONTENT reason):\n    %s",
			len(changed), vPrior, shortCommit(commit), strings.Join(changed, "\n    "))
	}
	fmt.Printf("seed verify: fingerprint absent (pre-fingerprint seed); eligibility DERIVED from git — "+
		"0 changed migrations <= V_prior=%d between %s and HEAD → eligible\n", vPrior, shortCommit(commit))
	return nil
}

// gitHasCommit reports whether commit resolves to a commit object in projDir's
// clone (git cat-file -e <commit>^{commit}).
func gitHasCommit(projDir, commit string) bool {
	_, err := upgrade.RunCommandOutput(projDir, "git", "cat-file", "-e", commit+"^{commit}")
	return err == nil
}

// bakedMigrationRe extracts the 14-digit version from an UP-migration path
// (.up.sql / .up.psql) — the files a seed bakes, matching what
// UpMigrationsFingerprintUpTo digests. Down files / post_restore.sql / non-
// migration paths don't match and are ignored.
var bakedMigrationRe = regexp.MustCompile(`(?:^|/)(\d{14})_[^/]*\.up\.(?:sql|psql)$`)

// changedBakedMigrations filters git-diff --name-only lines to the UP migrations
// with version <= vPrior — i.e. the migrations baked into the prior seed that
// have changed. Non-empty ⇒ the prior's baked set diverged from the current tree
// (INCR would drift from FULL). Pure — differentially unit-tested.
func changedBakedMigrations(changedFiles []string, vPrior int64) []string {
	var hits []string
	for _, f := range changedFiles {
		f = strings.TrimSpace(f)
		if f == "" {
			continue
		}
		m := bakedMigrationRe.FindStringSubmatch(f)
		if m == nil {
			continue // not an up-migration (down file / post_restore.sql / non-migration)
		}
		v, err := strconv.ParseInt(m[1], 10, 64)
		if err != nil {
			continue
		}
		if v <= vPrior {
			hits = append(hits, f)
		}
	}
	return hits
}

// parseSeedMetaVersion parses a prior seed's recorded migration_version into the
// int64 V_prior the delta count + eligibility gate need. Pure — unit-testable.
func parseSeedMetaVersion(meta *seedMeta) (int64, error) {
	v, err := strconv.ParseInt(strings.TrimSpace(meta.MigrationVersion), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse prior seed migration version %q: %w", meta.MigrationVersion, err)
	}
	return v, nil
}

// deltaIsMultiMigration is the AC#6 multi-delta predicate: the delta applied on
// the restored prior must be more than one migration to exercise physical-state-
// independence across the restored-base boundary. Pure — unit-testable.
func deltaIsMultiMigration(delta int) bool { return delta > 1 }

// deltaMigrationCount is the number of migrations the delta will apply on top of
// the restored prior: the applied migrations in the FULL build with version >
// vPrior (identical to the on-disk migrations > vPrior, since FULL applied them
// all). The AC#6 multi-delta guard rejects <= 1.
func deltaMigrationCount(projDir, fullDb string, vPrior int64) (int, error) {
	out, err := migrate.QueryDB(projDir, fullDb,
		fmt.Sprintf("SELECT count(*) FROM db.migration WHERE version > %d", vPrior), "-t", "-A")
	if err != nil {
		return 0, fmt.Errorf("count delta migrations > %d: %w", vPrior, err)
	}
	n, err := strconv.Atoi(strings.TrimSpace(out))
	if err != nil {
		return 0, fmt.Errorf("parse delta count %q: %w", out, err)
	}
	return n, nil
}

// verifySeedIdentical is the AC#4 proof: incremental == full for a MANUFACTURED
// single-delta prior. Thin wrapper over the shared verify body.
func verifySeedIdentical(projDir string) error {
	return verifySeedAgainstPrior(projDir, manufacturedPriorSource())
}

// verifySeedMultiDelta is the AC#6 pre-enable proof: incremental == full for a
// REAL prior-RELEASE seed image + that release's full multi-migration delta.
func verifySeedMultiDelta(projDir, imageRef string) error {
	return verifySeedAgainstPrior(projDir, imagePriorSource(imageRef))
}

// verifySeedAgainstPrior first runs the INSTRUMENT CONTROL (build FULL twice → the
// digests MUST match, proving the digest is build-deterministic), then the real
// measurement (INCREMENTAL vs FULL) using src to obtain the prior. A non-
// deterministic control means the instrument is broken — reported as such, BEFORE
// any incremental verdict can mean anything. Destructive only to the dedicated
// seedVerify* databases; never the real seed DB. Heavy (4 migrate passes + a
// restore) — run on demand.
func verifySeedAgainstPrior(projDir string, src priorSource) error {
	if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0755); err != nil {
		return err
	}
	dbA := seedVerifyDBName + "_a"
	dbB := seedVerifyDBName + "_b"

	// CONTROL: build FULL twice; the digests MUST be identical (deterministic
	// instrument) before INCR-vs-FULL can be trusted.
	fmt.Println("seed verify [CONTROL]: building FULL seed #1 (all migrations from empty)...")
	full1, err := buildFullSeed(projDir, dbA)
	if err != nil {
		return err
	}
	fmt.Println("seed verify [CONTROL]: building FULL seed #2 (the determinism control)...")
	full2, err := buildFullSeed(projDir, dbB)
	if err != nil {
		return err
	}
	if !full1.equal(full2) {
		captureSeedDumps(projDir, dbA, "control-full-1")
		captureSeedDumps(projDir, dbB, "control-full-2")
		dropVerifyDB(projDir, dbA)
		dropVerifyDB(projDir, dbB)
		return fmt.Errorf("✗ INSTRUMENT NON-DETERMINISTIC — two from-empty FULL builds digest differently; "+
			"the proof is INVALID until this is fixed (diff the captured tmp/seed-verify-control-full-*.txt to name it):\n"+
			"  schema: %s vs %s%s\n  data:   %s vs %s%s\n  ledger: %s vs %s%s",
			full1.Schema[:12], full2.Schema[:12], mark(full1.Schema == full2.Schema),
			full1.Data[:12], full2.Data[:12], mark(full1.Data == full2.Data),
			full1.Ledger[:12], full2.Ledger[:12], mark(full1.Ledger == full2.Ledger))
	}
	fmt.Printf("✓ CONTROL passed: FULL==FULL deterministic (schema=%s data=%s ledger=%s) — instrument valid.\n",
		full1.Schema[:12], full1.Data[:12], full1.Ledger[:12])

	// PRIOR: obtain it via the source. Keep dbA as the canonical FULL; scratchDb
	// (dbB) is reused for the prior build (manufactured) and then the INCR build.
	fmt.Printf("seed verify: preparing prior — %s\n", src.label)
	priorDump, vPrior, priorMeta, err := src.prepare(projDir, dbA, dbB)
	if err != nil {
		dropVerifyDB(projDir, dbA)
		dropVerifyDB(projDir, dbB)
		return err
	}

	// ELIGIBILITY GATE (real prior only): a real prior-release seed is a valid
	// substrate ONLY if the migrations <= V_release baked into it are byte-unchanged
	// in the current tree — otherwise INCR (restored old effect) would drift from
	// FULL (current disk migration) for a CONTENT reason, masquerading as a physical-
	// state finding.
	if priorMeta != nil {
		if err := verifyPriorEligible(projDir, priorMeta, vPrior); err != nil {
			dropVerifyDB(projDir, dbA)
			dropVerifyDB(projDir, dbB)
			return err
		}
	}

	// AC#6 MULTI-DELTA GUARD: the whole point is a prod-shaped MANY-migration delta
	// applied on a real restored base. A <=1-migration delta degenerates to AC#4's
	// single-delta case and cannot exercise physical-state-independence across the
	// restored-base boundary — refuse loud rather than pass a hollow "multi-delta".
	if src.requireMultiDelta {
		delta, err := deltaMigrationCount(projDir, dbA, vPrior)
		if err != nil {
			dropVerifyDB(projDir, dbA)
			dropVerifyDB(projDir, dbB)
			return err
		}
		if !deltaIsMultiMigration(delta) {
			dropVerifyDB(projDir, dbA)
			dropVerifyDB(projDir, dbB)
			return fmt.Errorf("✗ delta is %d migration(s) above V_prior=%d — AC#6 requires a MULTI-migration "+
				"delta to exercise physical-state-independence across the restored-base boundary; pick an EARLIER "+
				"prior RELEASE (this is just AC#4's single-delta case otherwise)", delta, vPrior)
		}
		fmt.Printf("seed verify: delta = %d migrations above V_prior=%d (multi-delta ✓)\n", delta, vPrior)
	}

	// INCREMENTAL: recreate dbB, restore the prior, apply only the delta, digest.
	fmt.Println("seed verify: building INCREMENTAL seed (restore prior + delta-migrate)...")
	if err := recreateVerifyDb(projDir, dbB); err != nil {
		return err
	}
	if err := restoreVerifyDB(projDir, dbB, priorDump); err != nil {
		return err
	}
	if err := migrateNamedDb(projDir, dbB, 0); err != nil {
		return fmt.Errorf("delta migrate: %w", err)
	}
	incr, err := computeSeedDigest(projDir, dbB)
	if err != nil {
		return err
	}

	if full1.equal(incr) {
		dropVerifyDB(projDir, dbA)
		dropVerifyDB(projDir, dbB)
		fmt.Printf("✓ seed identity PROVEN: incremental == full (schema=%s data=%s ledger=%s; V_prior=%d; prior: %s)\n",
			full1.Schema[:12], full1.Data[:12], full1.Ledger[:12], vPrior, src.label)
		return nil
	}
	// Real drift (instrument already proven deterministic). Capture both for naming.
	captureSeedDumps(projDir, dbA, "full")
	captureSeedDumps(projDir, dbB, "incr")
	dropVerifyDB(projDir, dbA)
	dropVerifyDB(projDir, dbB)
	return fmt.Errorf("✗ seed identity FAILED — incremental differs from full (instrument is deterministic, so this is REAL drift; "+
		"diff tmp/seed-verify-{full,incr}-*.txt to name it):\n"+
		"  schema: full=%s incr=%s%s\n  data:   full=%s incr=%s%s\n  ledger: full=%s incr=%s%s\n"+
		"  prior: %s (V_prior=%d)\n"+
		"  (do NOT enable incremental)",
		full1.Schema[:12], incr.Schema[:12], mark(full1.Schema == incr.Schema),
		full1.Data[:12], incr.Data[:12], mark(full1.Data == incr.Data),
		full1.Ledger[:12], incr.Ledger[:12], mark(full1.Ledger == incr.Ledger),
		src.label, vPrior)
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
	Long: `First a CONTROL — build a FULL seed twice and require identical digests
(proving the digest instrument is build-deterministic) — then the measurement:
build an INCREMENTAL seed (restore a manufactured prior + apply only the delta
migrations) and prove it equals a FULL rebuild on schema + data + migration
ledger. The empirical backstop behind the seed-incremental gate.

On any mismatch the normalized schema dump + per-table data digests of both
sides are written to tmp/seed-verify-*.txt so the diverging construct/table can
be named by diffing them; --keep-dbs additionally preserves the live databases.

Heavy (4 migrate passes + a restore against a live database) and DESTRUCTIVE to
the dedicated ` + seedVerifyDBName + `_a/_b databases (never the real seed DB). Run
on demand — not part of per-build CI. Requires 'sb start all' (template_statbus).`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return verifySeedIdentical(config.ProjectDir())
	},
}

// priorImageRef is the --prior-image ref for `verify-multidelta` (a published
// statbus-seed:<release-commit-short> the AC#6 run restores as the real prior base).
var priorImageRef string

var seedVerifyMultiDeltaCmd = &cobra.Command{
	Use:   "verify-multidelta",
	Short: "Prove incremental == full against a REAL prior-RELEASE seed + its full delta (STATBUS-116 AC#6)",
	Long: `The pre-enable safety check for seed-incremental (STATBUS-116 AC#6).

Unlike verify-identical (which manufactures a single-migration prior FROM EMPTY,
so both sides share a physical layout), this restores a REAL published prior-
RELEASE seed image — its OID/row order frozen by a past CI build — and applies
that release's FULL, MANY-migration delta. It is the ONLY proof that exercises
physical-state-independence across a real restored-base boundary (a migration
whose semantic output depends on physical row order would diverge here but stay
invisible to a from-empty FULL-vs-FULL).

Same CONTROL (FULL==FULL determinism) + schema+data+ledger digest + verdict as
verify-identical. Two loud guards refuse a meaningless run: the prior must be
incremental-ELIGIBLE (AC#2 fingerprint gate — migrations <= its version unchanged
in this tree) and the delta must be MULTI-migration (> 1).

Requires 'sb start all' (template_statbus + a live db container) and registry
read access (the image is auto-pulled). DESTRUCTIVE to the dedicated ` + seedVerifyDBName + `_a/_b
databases only (never the real seed DB). Run on demand — not part of CI.

  ./sb db seed verify-multidelta --prior-image ghcr.io/statisticsnorway/statbus-seed:<release-commit-short>`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return verifySeedMultiDelta(config.ProjectDir(), priorImageRef)
	},
}

func init() {
	seedVerifyIdenticalCmd.Flags().BoolVar(&keepVerifyDBs, "keep-dbs", false,
		"preserve the seed-verify databases on exit (for live inspection of a mismatch)")
	seedCmd.AddCommand(seedVerifyIdenticalCmd)

	seedVerifyMultiDeltaCmd.Flags().StringVar(&priorImageRef, "prior-image", "",
		"published statbus-seed:<release-commit-short> image to restore as the real prior base (required)")
	seedVerifyMultiDeltaCmd.Flags().BoolVar(&keepVerifyDBs, "keep-dbs", false,
		"preserve the seed-verify databases on exit (for live inspection of a mismatch)")
	_ = seedVerifyMultiDeltaCmd.MarkFlagRequired("prior-image")
	seedCmd.AddCommand(seedVerifyMultiDeltaCmd)
}
