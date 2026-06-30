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

func TestPerTableDataDigestSQL_Shape(t *testing.T) {
	sql := perTableDataDigestSQL("auth", "user")
	for _, want := range []string{`md5(string_agg(t::text, '' ORDER BY t::text))`, `"auth"."user"`} {
		if !strings.Contains(sql, want) {
			t.Errorf("perTableDataDigestSQL missing %q; got: %s", want, sql)
		}
	}
}
