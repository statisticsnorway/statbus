package cmd

import (
	"fmt"
	"strings"

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
//
// ABSENCE TOLERANCE (found by CI, run 33275592180): a restored artifact can
// predate migration 20260829114700 -- CI's restore path (and install.sh's
// seed-restore on a real box taking a pre-316 artifact) restores an OLDER
// dump, then this completion-point CALL fires before `migrate up` has ever
// run against that database, so the procedure genuinely does not exist yet.
// Checking existence first and skipping LOUDLY on absence is the fix -- NOT
// moving the call after migrate up (the completion-point placement is
// ruled) and NOT a blanket error-swallow (that would also hide a REAL
// failure inside the procedure itself as a false "predates the
// normalizer"). to_regprocedure returns NULL for a name that resolves to
// nothing, rather than raising -- the one query that can ask "does this
// exist" without risking the exact error we are trying to distinguish from.
func normalizeAllSequences(projDir, dbName string) error {
	exists, err := migrate.QueryDB(projDir, dbName,
		"SELECT to_regprocedure('public.normalize_all_sequences()') IS NOT NULL", "-t", "-A")
	if err != nil {
		return fmt.Errorf("normalize sequences in %s: check procedure exists: %w", dbName, err)
	}
	if strings.TrimSpace(exists) != "t" {
		fmt.Printf("normalizeAllSequences(%s): artifact predates the sequence normalizer (public.normalize_all_sequences does not exist yet) -- skipping; sequences keep the artifact's positions until the next restore of a post-normalizer artifact\n", dbName)
		return nil
	}

	out, err := migrate.QueryDB(projDir, dbName, "CALL public.normalize_all_sequences();")
	if err != nil {
		return fmt.Errorf("normalize sequences in %s: %w", dbName, err)
	}
	if out != "" {
		fmt.Println(out)
	}
	return nil
}
