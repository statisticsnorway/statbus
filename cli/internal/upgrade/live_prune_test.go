//go:build livedb

package upgrade

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/livedbtest"
)

// TestPruneDeletedTagsRecordsAllPrunedRow runs the REAL pruneDeletedTags
// against the REAL local database (the same connect path the daemon uses),
// with a row shaped exactly like the 25 rows that wedged on dev: every tag
// moved elsewhere in git. Before 40baf42fe the reconcile UPDATE was rejected
// (NULL into NOT NULL commit_tags) and the error discarded, so the row kept
// its tags forever and the journal repeated the prune line every tick.
//
// Everything runs inside one transaction that is rolled back, so the local
// database is untouched. Opt-in: needs the local db up.
//
// go test -tags livedb -count=1 ./internal/upgrade ./internal/install
func TestPruneDeletedTagsRecordsAllPrunedRow(t *testing.T) {
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
	defer func() {
		if _, err := d.queryConn.Exec(context.Background(), "ROLLBACK"); err != nil {
			t.Errorf("cleanup ROLLBACK: %v", err)
		}
	}()

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

func TestPinnedSBIgnoresProjectBinaryReplacement(t *testing.T) {
	projDir := findProjDir(t)
	projectSB := filepath.Join(projDir, "sb")
	original, err := os.ReadFile(projectSB)
	if err != nil {
		t.Fatalf("read fixture project sb: %v", err)
	}
	info, err := os.Stat(projectSB)
	if err != nil {
		t.Fatalf("stat fixture project sb: %v", err)
	}
	if err := os.WriteFile(projectSB, []byte("#!/bin/sh\nexit 99\n"), 0o755); err != nil {
		t.Fatalf("replace fixture project sb: %v", err)
	}
	t.Cleanup(func() {
		if err := os.WriteFile(projectSB, original, info.Mode().Perm()); err != nil {
			t.Errorf("restore fixture project sb: %v", err)
		}
	})

	cmd := exec.Command(liveSBPath(t), "--version")
	cmd.Dir = projDir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("pinned sb changed after project ./sb replacement: %v\n%s", err, out)
	}
}

func findProjDir(t *testing.T) string {
	t.Helper()
	if dir := livedbtest.ProjectDir(); dir != "" {
		return dir
	}
	t.Fatal("live-database fixture project dir is unset")
	return ""
}

func liveSBPath(t *testing.T) string {
	t.Helper()
	if path := livedbtest.PinnedSB(); path != "" {
		return path
	}
	t.Fatal("live-database pinned sb path is unset")
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
