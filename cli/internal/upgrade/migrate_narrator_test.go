package upgrade

import (
	"fmt"
	"reflect"
	"testing"
	"time"
)

// TestMigrateNarrator_RealisticSequence drives the narrator with the stdout a
// real `./sb migrate up --verbose` child prints (Norway rc.02 shape: a slow
// extension update, then a pending count, a fast migration and one that runs
// for minutes) and asserts the M lines the progress page shows, in order.
func TestMigrateNarrator_RealisticSequence(t *testing.T) {
	var got []string
	base := time.Date(2026, 11, 28, 10, 24, 0, 0, time.UTC)
	now := base
	n := newMigrateNarrator(func(format string, args ...interface{}) {
		got = append(got, fmt.Sprintf(format, args...))
	}, func() time.Time { return now })

	at := func(sec int) { now = base.Add(time.Duration(sec) * time.Second) }

	at(0)
	n.Line("[migrate] Extension sql_saga: 1.14 -> 1.15 (direct update to image default) ...")
	at(30)
	n.Tick()
	at(60)
	n.Tick()
	at(70)
	n.Line("[migrate] Extension sql_saga: 1.14 -> 1.15 (direct update to image default) ... ok (1m10s)")
	at(71)
	n.Line("STATBUS_MIGRATE_PENDING_COUNT=2")
	n.Line("[migrate] Applying 20261127100000_small.up.sql ...")
	n.Line("Migration 20261127100000 (small)")
	at(72)
	n.Tick() // fast migration: no still-running line
	n.Line("[migrate] Applying 20261127100000_small.up.sql ... ok (812ms)")
	n.Line("[applied] (812ms)")
	n.Line("[migrate] Applying 20261127162620_statistical_unit.up.sql ...")
	at(102)
	n.Tick()
	at(132)
	n.Tick()
	at(140)
	n.Line("[migrate] Applying 20261127162620_statistical_unit.up.sql ... ok (1m8s)")
	at(170)
	n.Tick() // nothing running: silent

	want := []string{
		"Extension sql_saga: 1.14 -> 1.15 (direct update to image default) ...",
		"Still applying extension sql_saga (30s) ...",
		"Still applying extension sql_saga (1m0s) ...",
		"Extension sql_saga: 1.14 -> 1.15 (direct update to image default) ... ok (1m10s)",
		"Applying database migrations: 2 pending ...",
		"Applying migration 20261127100000_small.up.sql ...",
		"Applying migration 20261127100000_small.up.sql ... ok (812ms)",
		"Applying migration 20261127162620_statistical_unit.up.sql ...",
		"Still applying 20261127162620_statistical_unit.up.sql (30s) ...",
		"Still applying 20261127162620_statistical_unit.up.sql (1m0s) ...",
		"Applying migration 20261127162620_statistical_unit.up.sql ... ok (1m8s)",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("M lines mismatch\n got: %q\nwant: %q", got, want)
	}
}

// TestMigrateNarrator_Failure names the migration that failed and stops the
// still-running lines.
func TestMigrateNarrator_Failure(t *testing.T) {
	var got []string
	now := time.Date(2026, 11, 28, 0, 0, 0, 0, time.UTC)
	n := newMigrateNarrator(func(format string, args ...interface{}) {
		got = append(got, fmt.Sprintf(format, args...))
	}, func() time.Time { return now })
	n.Line("[migrate] Applying 1_x.up.sql ...")
	now = now.Add(5 * time.Second)
	n.Line("[migrate] Applying 1_x.up.sql ... failed after 5s")
	now = now.Add(time.Minute)
	n.Tick()
	want := []string{"Applying migration 1_x.up.sql ...", "Applying migration 1_x.up.sql ... failed after 5s"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %q want %q", got, want)
	}
}
