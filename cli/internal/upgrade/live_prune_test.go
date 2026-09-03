package upgrade

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"
)

// TestLivePruneDeletedTags_AllPrunedRowLands runs the REAL pruneDeletedTags
// against the REAL local database (the same connect path the daemon uses),
// with a row shaped exactly like the 25 rows that wedged on dev: every tag
// moved elsewhere in git. Before 40baf42fe the reconcile UPDATE was rejected
// (NULL into NOT NULL commit_tags) and the error discarded, so the row kept
// its tags forever and the journal repeated the prune line every tick.
//
// Everything runs inside one transaction that is rolled back, so the local
// database is untouched. Opt-in: needs the local db up.
//
//	STATBUS_LIVE_DB=1 go test -count=1 -run TestLivePruneDeletedTags -v ./internal/upgrade
func TestLivePruneDeletedTags_AllPrunedRowLands(t *testing.T) {
	if os.Getenv("STATBUS_LIVE_DB") == "" {
		t.Skip("set STATBUS_LIVE_DB=1 to exercise the real database")
	}
	projDir := findProjDir(t)
	d := NewService(projDir, false, "test", "")
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	if err := d.loadConfig(); err != nil {
		t.Fatalf("loadConfig: %v", err)
	}
	if err := d.connect(ctx); err != nil {
		t.Fatalf("connect: %v", err)
	}
	defer d.Close()

	// Wrap the whole exercise in a transaction on the daemon's own connection:
	// pruneDeletedTags uses d.queryConn, so its SELECT and UPDATE run inside it.
	if _, err := d.queryConn.Exec(ctx, "BEGIN"); err != nil {
		t.Fatal(err)
	}
	defer func() { _, _ = d.queryConn.Exec(context.Background(), "ROLLBACK") }()

	const rowSHA = "8547d74fb8063c7084f98010c179c57f3dd52d95" // dev row 324308's commit
	const movedTo = "51670d9e10000000000000000000000000000000"
	const tag = "v2026.05.6-rc.01"
	var id int
	if err := d.queryConn.QueryRow(ctx, `
		INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state, superseded_at)
		VALUES ($1, now() - interval '100 days', ARRAY[$2]::text[], 'prerelease', 'live prune probe', 'superseded', now())
		RETURNING id`, rowSHA, tag).Scan(&id); err != nil {
		t.Fatalf("insert probe row: %v", err)
	}

	// Git says the tag exists but points elsewhere: MOVED, so every tag drops.
	d.pruneDeletedTags(ctx, []GitTag{{TagName: tag, CommitSHA: movedTo}})

	var tags []string
	var status string
	if err := d.queryConn.QueryRow(ctx,
		"SELECT commit_tags, release_status::text FROM public.upgrade WHERE id = $1", id).Scan(&tags, &status); err != nil {
		t.Fatalf("read back: %v", err)
	}
	if len(tags) != 0 {
		t.Errorf("all-pruned row still carries %v; the reconcile UPDATE did not land", tags)
	}
	if status != "commit" {
		t.Errorf("release_status = %q, want commit after every tag was pruned", status)
	}

	// Idempotence: a second tick finds nothing to prune and prints nothing.
	out := captureStdoutUpgrade(t, func() { d.pruneDeletedTags(ctx, []GitTag{{TagName: tag, CommitSHA: movedTo}}) })
	if strings.Contains(out, "Pruned") {
		t.Errorf("second tick re-pruned an already-reconciled row (the dev wedge shape):\n%s", out)
	}
}

func findProjDir(t *testing.T) string {
	t.Helper()
	dir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 6; i++ {
		if _, err := os.Stat(dir + "/.env"); err == nil {
			if _, err := os.Stat(dir + "/dev.sh"); err == nil {
				return dir
			}
		}
		dir += "/.."
	}
	t.Fatal("project dir (with .env and dev.sh) not found above the test cwd")
	return ""
}

func captureStdoutUpgrade(t *testing.T, fn func()) string {
	t.Helper()
	old := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stdout = w
	fn()
	_ = w.Close()
	os.Stdout = old
	buf := make([]byte, 64*1024)
	n, _ := r.Read(buf)
	return string(buf[:n])
}
