package upgrade

import (
	"context"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"
)

// TestLiveMaintenanceFile_ExtractorCommandRunsAgainstTheRealRow closes the
// STATBUS-347 style rule 9 loop on the real path: the maintenance file is
// produced from a REAL claim snapshot (the to_json text PostgreSQL itself
// returned from the claim UPDATE), written through the REAL setMaintenance
// writer to the real ~/statbus-maintenance/active location, and then line 3
// (the psql extractor command an operator would paste) is EXECUTED with the
// real ./sb psql against the real row and must return that row's live state.
//
// A file that names a command nobody ran is exactly the "file can never lie"
// promise unkept; this runs it.
//
//	STATBUS_LIVE_DB=1 go test -count=1 -run TestLiveMaintenanceFile -v ./internal/upgrade
func TestLiveMaintenanceFile_ExtractorCommandRunsAgainstTheRealRow(t *testing.T) {
	if os.Getenv("STATBUS_LIVE_DB") == "" {
		t.Skip("set STATBUS_LIVE_DB=1 to exercise the real database")
	}
	projDir := findProjDir(t)
	if _, err := os.Stat(maintenanceFlagHostPath()); err == nil {
		t.Fatalf("a real maintenance flag exists at %s; refusing to run beside a live upgrade", maintenanceFlagHostPath())
	}
	d := NewService(projDir, false, "test", "")
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	if err := d.LoadConfigAndConnect(ctx); err != nil {
		t.Fatalf("LoadConfigAndConnect: %v", err)
	}
	t.Cleanup(d.Close)

	// A real scheduled row, claimed by the real claim path so the snapshot's
	// ImmutableJSON is the database's own to_json text.
	const sha = "3470000000000000000000000000000000000041"
	var id int
	if err := d.queryConn.QueryRow(ctx, `
		INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary, state, scheduled_at, commit_version, docker_images_status)
		VALUES ($1, now() - interval '1 day', '{v2099.01.0-rc.01}', 'prerelease', 'live maintenance-file probe', 'scheduled', now(), 'v2099.01.0-rc.01', 'ready')
		RETURNING id`, sha).Scan(&id); err != nil {
		t.Fatalf("insert scheduled row: %v", err)
	}
	t.Cleanup(func() {
		cctx, ccancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer ccancel()
		if _, err := d.queryConn.Exec(cctx, "DELETE FROM public.upgrade_state_log WHERE upgrade_id = $1", id); err != nil {
			t.Errorf("cleanup state log: %v", err)
		}
		if _, err := d.queryConn.Exec(cctx, "DELETE FROM public.upgrade WHERE id = $1", id); err != nil {
			t.Errorf("cleanup row: %v", err)
		}
		_ = os.Remove(maintenanceFlagHostPath())
	})

	claim, err := d.claimScheduledUpgrade(ctx, id)
	if err != nil {
		t.Fatalf("claim: %v", err)
	}
	content, err := maintenanceFlagContent(claim.Snapshot)
	if err != nil {
		t.Fatalf("maintenanceFlagContent: %v", err)
	}
	if err := d.setMaintenance(true, content); err != nil {
		t.Fatalf("setMaintenance(true): %v", err)
	}

	written, err := os.ReadFile(maintenanceFlagHostPath())
	if err != nil {
		t.Fatalf("read the written flag: %v", err)
	}
	lines := strings.Split(strings.TrimRight(string(written), "\n"), "\n")
	if len(lines) != 3 {
		t.Fatalf("maintenance file has %d lines, want 3:\n%s", len(lines), written)
	}
	if lines[0] != "upgrade "+itoa(id)+" to v2099.01.0-rc.01" {
		t.Errorf("headline = %q", lines[0])
	}
	for _, key := range []string{`"id":` + itoa(id), `"commit_version":"v2099.01.0-rc.01"`, `"commit_sha":"` + sha + `"`, `"started_at":"`} {
		if !strings.Contains(lines[1], key) {
			t.Errorf("immutable JSON line lacks %s: %s", key, lines[1])
		}
	}
	// Ordered as SELECTed (to_json, not jsonb): id, commit_version, commit_sha, from_commit_version, started_at.
	last := -1
	for _, key := range []string{`"id"`, `"commit_version"`, `"commit_sha"`, `"from_commit_version"`, `"started_at"`} {
		idx := strings.Index(lines[1], key)
		if idx <= last {
			t.Errorf("immutable JSON key %s is out of SELECT order: %s", key, lines[1])
		}
		last = idx
	}

	// Line 3 is a shell command. RUN IT, as the operator would, from projDir.
	cmd := exec.CommandContext(ctx, "sh", "-c", lines[2])
	cmd.Dir = projDir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("the extractor command from the maintenance file failed: %v\ncommand: %s\noutput: %s", err, lines[2], out)
	}
	// ./sb may print a stale-binary WARN banner to stderr; the JSON is the last non-empty line.
	var jsonLine string
	for _, l := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if strings.HasPrefix(strings.TrimSpace(l), "{") {
			jsonLine = strings.TrimSpace(l)
		}
	}
	if jsonLine == "" {
		t.Fatalf("extractor command printed no JSON row:\n%s", out)
	}
	for _, want := range []string{`"id":` + itoa(id), `"state":"in_progress"`, `"completed_at":null`, `"rolled_back_at":null`} {
		if !strings.Contains(jsonLine, want) {
			t.Errorf("live-state JSON lacks %s: %s", want, jsonLine)
		}
	}
	t.Logf("maintenance file:\n%s\nextractor returned: %s", written, jsonLine)

	// And the symmetric writer removes exactly this file.
	if err := d.setMaintenance(false, ""); err != nil {
		t.Fatalf("setMaintenance(false): %v", err)
	}
	if _, err := os.Stat(maintenanceFlagHostPath()); !os.IsNotExist(err) {
		t.Errorf("maintenance flag still present after setMaintenance(false): %v", err)
	}
}

func itoa(n int) string { return strconv.Itoa(n) }
