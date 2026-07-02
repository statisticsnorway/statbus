package cmd

import (
	"strings"
	"testing"
)

// The only DANGEROUS failure of the AC#4 identity proof is a FALSE "identical".
// These differential tests prove the pure cores DETECT a planted difference (and
// do NOT cry wolf on volatile noise) — they are the proof that the proof works.

// ── schema digest (S1: normalized pg_dump --schema-only) ─────────────────────

func TestSchemaDigest_DetectsOneObjectDifference(t *testing.T) {
	withIndex := `--
-- PostgreSQL database dump
--
SET statement_timeout = 0;
CREATE TABLE public.foo (id integer NOT NULL);
CREATE INDEX foo_id_idx ON public.foo (id);
`
	withoutIndex := `--
-- PostgreSQL database dump
--
SET statement_timeout = 0;
CREATE TABLE public.foo (id integer NOT NULL);
`
	if schemaDigestFromDump(withIndex) == schemaDigestFromDump(withoutIndex) {
		t.Error("schema digest MUST differ when one object (an index) is removed — a false 'identical' is the dangerous failure")
	}
}

func TestIsExcludedTable(t *testing.T) {
	for _, ex := range []string{"auth.secrets", "db.migration", "worker.tasks"} {
		if !isExcludedTable(ex) {
			t.Errorf("%s must be excluded (operational/bookkeeping, not semantic seed content)", ex)
		}
	}
	for _, keep := range []string{"public.country", "public.activity_category", "worker.command_registry"} {
		if isExcludedTable(keep) {
			t.Errorf("%s is semantic seed content and must NOT be excluded", keep)
		}
	}
}

// The self-guard: an EXCLUDED (volatile-default) column whose NAME looks
// business-temporal must trip the guard; benign audit column names must not.
func TestSemanticColumnGuard(t *testing.T) {
	for _, audit := range []string{"created_at", "updated_at", "edit_at", "discovered_at", "uploaded_at", "last_used_at"} {
		if semanticColumnRe.MatchString(audit) {
			t.Errorf("audit column %q must NOT trip the self-guard (it's benign to exclude)", audit)
		}
	}
	for _, semantic := range []string{"valid_from", "valid_to", "valid_until", "born_on", "effective_date", "active_period", "valid_after", "date_range"} {
		if !semanticColumnRe.MatchString(semantic) {
			t.Errorf("business-temporal column %q MUST trip the self-guard (auto-excluding it could hide drift)", semantic)
		}
	}
}

// The NAMED schema non-determinism: PG18 pg_dump wraps the dump in
// `\restrict <random>` / `\unrestrict <random>` psql meta-commands with a fresh
// random token per invocation. Two dumps of an IDENTICAL schema must normalize
// to the SAME digest despite differing tokens.
func TestSchemaDigest_IgnoresRestrictRandomToken(t *testing.T) {
	a := `\restrict AAAAAAAAAAAAAAAAAAAAAAAAAAAA
CREATE TABLE public.foo (id integer NOT NULL);
\unrestrict AAAAAAAAAAAAAAAAAAAAAAAAAAAA
`
	b := `\restrict ZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
CREATE TABLE public.foo (id integer NOT NULL);
\unrestrict ZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
`
	if schemaDigestFromDump(a) != schemaDigestFromDump(b) {
		t.Error("schema digest MUST ignore the random \\restrict/\\unrestrict token (else it's non-deterministic per pg_dump invocation)")
	}
	// ...but a real DDL change alongside the token must still be detected.
	c := `\restrict ZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
CREATE TABLE public.foo (id integer NOT NULL, extra text);
\unrestrict ZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
`
	if schemaDigestFromDump(a) == schemaDigestFromDump(c) {
		t.Error("stripping \\restrict must NOT mask a real DDL difference")
	}
}

// The NAMED round-trip schema artifact (STATBUS-116 AC#4): pg_dump's
// pg_get_viewdef emits a redundant `::type AS type` column alias on a view that
// has been dump/restore round-tripped (the INCREMENTAL seed) but omits it on a
// freshly-migrated view (the FULL seed). collapseRedundantCastAliases erases ONLY
// that provably-redundant form. These cases prove it collapses noise (alias ==
// type's own name) and NEVER signal (a real rename, or a non-cast alias) — the
// proof that the normalize can't hide a real schema diff.
func TestSchemaDigest_CollapsesOnlyRedundantCastAlias(t *testing.T) {
	// (i) redundant alias (alias == type's own name) → collapsed to the bare cast.
	if got := collapseRedundantCastAliases(`'x'::statistical_unit_type AS statistical_unit_type`); got != `'x'::statistical_unit_type` {
		t.Errorf("(i) redundant `::type AS type` must collapse; got %q", got)
	}
	// (ii) a MEANINGFUL rename (alias != type name) MUST survive untouched — this is
	// the case that proves the regex can never mask a real column-name difference.
	const rename = `'x'::statistical_unit_type AS something_else`
	if got := collapseRedundantCastAliases(rename); got != rename {
		t.Errorf("(ii) a real rename must be PRESERVED; got %q", got)
	}
	// (iii) an alias with NO cast must survive — only the `::type AS type` form collapses.
	const noCast = `expr AS statistical_unit_type`
	if got := collapseRedundantCastAliases(noCast); got != noCast {
		t.Errorf("(iii) a non-cast alias must be PRESERVED; got %q", got)
	}
	// (iv) qualified type, alias == the type's UNQUALIFIED last component → collapsed.
	if got := collapseRedundantCastAliases(`'legal_unit'::public.statistical_unit_type AS statistical_unit_type,`); got != `'legal_unit'::public.statistical_unit_type,` {
		t.Errorf("(iv) qualified `::schema.type AS type` (alias = last component) must collapse; got %q", got)
	}
	// End-to-end at the digest level: the exact round-trip artifact (FULL omits the
	// alias, INCR emits it) must now normalize to the SAME digest...
	full := `CREATE VIEW v AS
                 SELECT 'legal_unit'::public.statistical_unit_type,
                 'a'::text;`
	incr := `CREATE VIEW v AS
                 SELECT 'legal_unit'::public.statistical_unit_type AS statistical_unit_type,
                 'a'::text;`
	if schemaDigestFromDump(full) != schemaDigestFromDump(incr) {
		t.Error("the redundant view-alias round-trip artifact must normalize to an IDENTICAL schema digest")
	}
	// ...but a genuine rename in the same position must STILL flip the digest.
	renamed := `CREATE VIEW v AS
                 SELECT 'legal_unit'::public.statistical_unit_type AS unit_kind,
                 'a'::text;`
	if schemaDigestFromDump(full) == schemaDigestFromDump(renamed) {
		t.Error("collapsing the redundant alias must NOT mask a real column rename")
	}
}

func TestSchemaDigest_IgnoresVolatileOnlyDifferences(t *testing.T) {
	a := `--
-- Dumped from database version 18.0
--
SET statement_timeout = 0;
SET lock_timeout = 0;
SELECT pg_catalog.set_config('search_path', '', false);

CREATE TABLE public.foo (id integer NOT NULL);
`
	// Identical DDL; only the header comment, SET lines, set_config, and blank
	// lines differ — all volatile noise pg_dump emits.
	b := `--
-- Dumped from database version 18.1 (different build)
--
SET statement_timeout = 99;


SELECT pg_catalog.set_config('search_path', 'x', false);
CREATE TABLE public.foo (id integer NOT NULL);

`
	if schemaDigestFromDump(a) != schemaDigestFromDump(b) {
		t.Error("schema digest MUST be identical when only volatile lines differ — else the proof cries wolf on noise")
	}
}

// ── data digest (per-table + combine) ────────────────────────────────────────

func TestDataDigestOfRows_DetectsOneRowDifference(t *testing.T) {
	a := []string{"(1,alpha)", "(2,beta)", "(3,gamma)"}
	b := []string{"(1,alpha)", "(2,beta)", "(3,GAMMA)"} // exactly one row differs
	if dataDigestOfRows(a) == dataDigestOfRows(b) {
		t.Error("data digest MUST differ when one row differs")
	}
}

func TestDataDigestOfRows_OrderIndependent(t *testing.T) {
	a := []string{"(1,alpha)", "(2,beta)", "(3,gamma)"}
	b := []string{"(3,gamma)", "(1,alpha)", "(2,beta)"} // same rows, physical order differs
	if dataDigestOfRows(a) != dataDigestOfRows(b) {
		t.Error("data digest MUST match identical rows in a different order (physical/insertion order is irrelevant)")
	}
}

func TestCombineTableDigests_DetectsChangeAndIgnoresMapOrder(t *testing.T) {
	base := map[string]string{"public.foo": "d1", "public.bar": "d2", "auth.user": "d3"}
	reordered := map[string]string{"auth.user": "d3", "public.bar": "d2", "public.foo": "d1"}
	if combineTableDigests(base) != combineTableDigests(reordered) {
		t.Error("combine MUST be independent of Go map iteration order")
	}
	oneTableChanged := map[string]string{"public.foo": "d1", "public.bar": "d2-CHANGED", "auth.user": "d3"}
	if combineTableDigests(base) == combineTableDigests(oneTableChanged) {
		t.Error("combine MUST differ when any single table's digest changes")
	}
	tableAddedOrRemoved := map[string]string{"public.foo": "d1", "public.bar": "d2"}
	if combineTableDigests(base) == combineTableDigests(tableAddedOrRemoved) {
		t.Error("combine MUST differ when a table is added/removed")
	}
}

// perTableDataDigestSQL digests ONLY the content columns it is given, so an
// excluded (build-volatile audit) column cannot enter the digest by
// construction: the SQL never references it. This is the structural form of the
// differential requirement — a content-column change can flip the digest; an
// audit-column change cannot, because the audit column is absent from the
// expression.
func TestPerTableDataDigestSQL_DigestsOnlyContentColumns(t *testing.T) {
	// content cols = iso_2,name; created_at/updated_at were excluded by the caller.
	sql := perTableDataDigestSQL("public", "country", []string{"iso_2", "name"})
	for _, want := range []string{`md5(string_agg(`, `ROW(t."iso_2", t."name")::text`, `"public"."country"`} {
		if !strings.Contains(sql, want) {
			t.Errorf("digest SQL missing %q; got: %s", want, sql)
		}
	}
	for _, excluded := range []string{"created_at", "updated_at"} {
		if strings.Contains(sql, excluded) {
			t.Errorf("digest SQL must NOT reference excluded audit column %q (it cannot affect the digest); got: %s", excluded, sql)
		}
	}
	// degenerate: a table with no content columns left → row count (still detects add/remove).
	if deg := perTableDataDigestSQL("public", "x", nil); !strings.Contains(deg, "count(*)") {
		t.Errorf("no-content-columns case must fall back to row count; got: %s", deg)
	}
}

// ── AC#6 (verify-multidelta) guards — pure, Docker-free ───────────────────────

// The multi-delta guard is what makes AC#6 ≠ AC#4: a <=1-migration delta
// degenerates to the single-delta case and cannot exercise physical-state-
// independence across the restored-base boundary, so it MUST be rejected.
func TestDeltaIsMultiMigration(t *testing.T) {
	for _, n := range []int{-1, 0, 1} {
		if deltaIsMultiMigration(n) {
			t.Errorf("delta=%d must be rejected (not multi-migration) — it degenerates to AC#4's single-delta case", n)
		}
	}
	for _, n := range []int{2, 3, 50} {
		if !deltaIsMultiMigration(n) {
			t.Errorf("delta=%d must be accepted as a genuine multi-migration delta", n)
		}
	}
}

// changedBakedMigrations is the git-derived eligibility core (fingerprint-absent
// prior): from `git diff --name-only` lines it must flag exactly the UP migrations
// baked into the prior (version <= V_prior) that changed — the same drift hazard a
// fingerprint mismatch catches. A change ABOVE V_prior is part of the delta (not a
// baked migration) and must be ignored; down files / non-migration paths never count.
func TestChangedBakedMigrations(t *testing.T) {
	const vPrior = int64(20260603093525)
	lines := []string{
		"migrations/20260601000000_early.up.sql",        // <= V_prior, up → HIT
		"migrations/20260603093525_boundary.up.psql",    // == V_prior, up → HIT (inclusive)
		"migrations/20260616104500_in_the_delta.up.sql", // > V_prior → ignore (it IS the delta)
		"migrations/20260601000000_early.down.sql",      // down file → ignore (not baked/digested)
		"migrations/post_restore.sql",                   // not a versioned migration → ignore
		"cli/cmd/seed.go",                               // non-migration path → ignore
		"",                                              // blank → ignore
	}
	got := changedBakedMigrations(lines, vPrior)
	want := []string{
		"migrations/20260601000000_early.up.sql",
		"migrations/20260603093525_boundary.up.psql",
	}
	if len(got) != len(want) {
		t.Fatalf("changedBakedMigrations = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("hit[%d] = %q, want %q", i, got[i], want[i])
		}
	}

	// A renamed <=V_prior migration surfaces (with --no-renames) as delete-old +
	// add-new; the OLD path (<=V_prior) must be flagged → not silently eligible.
	renamed := changedBakedMigrations([]string{"migrations/20260602000000_old_name.up.sql"}, vPrior)
	if len(renamed) != 1 {
		t.Errorf("a renamed/deleted <=V_prior migration must be flagged; got %v", renamed)
	}

	// All-above-V_prior (a clean delta, no baked-migration edits) → eligible (empty).
	clean := changedBakedMigrations([]string{"migrations/20260616104500_in_the_delta.up.sql"}, vPrior)
	if len(clean) != 0 {
		t.Errorf("changes confined to the delta (> V_prior) must NOT block eligibility; got %v", clean)
	}
}

// parseSeedMetaVersion must turn a real recorded migration_version into V_prior
// (tolerating surrounding whitespace) and FAIL LOUD on a missing/garbage version
// rather than silently defaulting to 0 (which would mis-scope the delta count).
func TestParseSeedMetaVersion(t *testing.T) {
	v, err := parseSeedMetaVersion(&seedMeta{MigrationVersion: "  20260616104500 "})
	if err != nil || v != 20260616104500 {
		t.Errorf("valid version must parse (with whitespace trimmed); got v=%d err=%v", v, err)
	}
	for _, bad := range []string{"", "not-a-number", "2026-06-16"} {
		if _, err := parseSeedMetaVersion(&seedMeta{MigrationVersion: bad}); err == nil {
			t.Errorf("migration_version %q must fail loud, not default to 0", bad)
		}
	}
}
