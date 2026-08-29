package cmd

import (
	"fmt"

	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// normalizeAllSequences resets every column-owned sequence in dbName to a
// position derived from the data actually present, discarding whatever burn
// history a restored artifact (or a rolled-back test) carried in. See
// public.normalize_all_sequences() (migration 20260829114700) for the full
// rationale and the query itself -- this Go function is a thin wrapper, not
// a second copy of the SQL: the procedure is the single source every
// caller shares (Go restore paths AND test/setup.sql), so the logic cannot
// drift between an embedded-in-Go copy and a test-file copy.
//
// STATBUS-316: called once, at the genuine completion point of every
// restore path -- never mid-multi-phase-restore (a multi-phase restore
// like restoreLocal's must normalize only after its LAST phase), and never
// inside runPgRestoreAtomic itself, which operates on an arbitrary
// *exec.Cmd with no database name and no notion of "the restore, as a
// whole, is done."
//
// Uses QueryDB (not ExecOnDB) deliberately: the procedure's RAISE NOTICE
// for skipped (unowned) sequences must be VISIBLE, not silently discarded
// -- ExecOnDB's own doc comment says it "discards stdout and returns only
// an error", which would swallow exactly the skip-with-reason signal this
// ticket requires.
func normalizeAllSequences(projDir, dbName string) error {
	out, err := migrate.QueryDB(projDir, dbName, "CALL public.normalize_all_sequences();")
	if err != nil {
		return fmt.Errorf("normalize sequences in %s: %w", dbName, err)
	}
	if out != "" {
		fmt.Println(out)
	}
	return nil
}
