package upgrade

import (
	"bytes"
	"context"
	"log"
	"os"
	"strings"
	"testing"
	"time"
)

// TestLiveExecObserved_ConstraintRejectionIsOnTheJournal proves the sweep's
// helper does what the pruner's swallowed Exec did not: a write the REAL schema
// refuses (here: rollback_finish_pending_at on an in_progress row, forbidden by
// chk_upgrade_rollback_finish_pending_requires_failed) produces a journal line
// naming the purpose, the arguments and the constraint, and a zero-row UPDATE
// says so rather than passing as success.
//
//	STATBUS_LIVE_DB=1 go test -count=1 -run TestLiveExecObserved -v ./internal/upgrade
func TestLiveExecObserved_ConstraintRejectionIsOnTheJournal(t *testing.T) {
	if os.Getenv("STATBUS_LIVE_DB") == "" {
		t.Skip("set STATBUS_LIVE_DB=1 to exercise the real database")
	}
	projDir := findProjDir(t)
	d := NewService(projDir, false, "test", "")
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	if err := d.loadConfig(); err != nil {
		t.Fatal(err)
	}
	if err := d.connect(ctx); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(d.Close)
	if _, err := d.queryConn.Exec(ctx, "BEGIN"); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = d.queryConn.Exec(context.Background(), "ROLLBACK") })

	const sha = "3470000000000000000000000000000000000081"
	var id int
	if err := d.queryConn.QueryRow(ctx, `
		INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state, scheduled_at, started_at)
		VALUES ($1, now(), '{}', 'commit', 'execObserved probe', 'in_progress', now(), now()) RETURNING id`, sha).Scan(&id); err != nil {
		t.Fatal(err)
	}

	var journal bytes.Buffer
	oldOut := log.Writer()
	log.SetOutput(&journal)
	t.Cleanup(func() { log.SetOutput(oldOut) })

	// 1. A write the schema refuses: the error is returned AND logged with purpose + args.
	if _, err := d.queryConn.Exec(ctx, "SAVEPOINT probe"); err != nil {
		t.Fatal(err)
	}
	err := d.execObserved(ctx, "probe: set pending on in_progress",
		"UPDATE public.upgrade SET rollback_finish_pending_at = now() WHERE id = $1", id)
	if err == nil {
		t.Fatal("execObserved returned nil for a write the CHECK constraint must refuse")
	}
	if !strings.Contains(err.Error(), "chk_upgrade_rollback_finish_pending_requires_failed") {
		t.Fatalf("returned error does not name the constraint: %v", err)
	}
	if _, err := d.queryConn.Exec(ctx, "ROLLBACK TO SAVEPOINT probe"); err != nil {
		t.Fatal(err)
	}
	line := journal.String()
	for _, want := range []string{"probe: set pending on in_progress", "write did not land", "chk_upgrade_rollback_finish_pending_requires_failed", "args=["} {
		if !strings.Contains(line, want) {
			t.Errorf("journal lacks %q:\n%s", want, line)
		}
	}

	// 2. A guarded UPDATE that matches nothing: success, but the miss is visible.
	journal.Reset()
	if err := d.execObserved(ctx, "probe: guarded no-op",
		"UPDATE public.upgrade SET docker_images_downloaded = true WHERE id = $1 AND state = 'completed'", id); err != nil {
		t.Fatalf("guarded no-op returned an error: %v", err)
	}
	if !strings.Contains(journal.String(), "probe: guarded no-op: UPDATE matched 0 rows") {
		t.Errorf("zero-row UPDATE was not reported:\n%s", journal.String())
	}

	// 3. A write that lands: silent.
	journal.Reset()
	if err := d.execObserved(ctx, "probe: landed",
		"UPDATE public.upgrade SET docker_images_downloaded = true WHERE id = $1", id); err != nil {
		t.Fatalf("landing write returned an error: %v", err)
	}
	if journal.Len() != 0 {
		t.Errorf("a landed write produced journal noise:\n%s", journal.String())
	}
}
