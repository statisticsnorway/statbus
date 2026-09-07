package upgrade

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestLivePreswapFetchReturnedErrorRealSite_STATBUS339 drives executeUpgrade to
// the actual inject.ErrorHere call immediately before ensureUpgradeCommitObjects.
func TestLivePreswapFetchReturnedErrorRealSite_STATBUS339(t *testing.T) {
	if os.Getenv("STATBUS_LIVE_DB") == "" {
		t.Skip("set STATBUS_LIVE_DB=1 to exercise the real database")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	realProjDir := findProjDir(t)

	shimDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(shimDir, "git"), []byte(`#!/bin/sh
case "$*" in
  *"cat-file -e"*) exit 1 ;;
  *) exit 0 ;;
esac
`), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))

	for _, tc := range []struct {
		name        string
		inject      bool
		wantFetches int
	}{
		{name: "injected error bypasses fetch seam", inject: true, wantFetches: 0},
		{name: "production no-op reaches fetch seam", inject: false, wantFetches: 3},
	} {
		t.Run(tc.name, func(t *testing.T) {
			projDir := t.TempDir()
			if err := os.Symlink(filepath.Join(realProjDir, ".env"), filepath.Join(projDir, ".env")); err != nil {
				t.Fatal(err)
			}
			d := NewService(realProjDir, false, "dev", "")
			if err := d.LoadConfigAndConnect(ctx); err != nil {
				t.Fatalf("LoadConfigAndConnect: %v", err)
			}
			defer d.Close()
			d.projDir = projDir
			d.allowedSignersPath = filepath.Join(projDir, "allowed-signers")
			if err := os.WriteFile(d.allowedSignersPath, []byte("test ssh-ed25519 AAAA\n"), 0o644); err != nil {
				t.Fatal(err)
			}

			fetchCalls := 0
			fetchSentinel := errors.New("STATBUS-339 fetch seam reached")
			d.fetchCommitObjects = func(context.Context, io.Writer, string) error {
				fetchCalls++
				return fetchSentinel
			}
			d.fetchRetryWait = func(context.Context, time.Duration) error { return nil }
			if tc.inject {
				t.Setenv("STATBUS_INJECT_AT", "preswap-fetch-returns-error")
			} else {
				t.Setenv("STATBUS_INJECT_AT", "")
			}

			sha := fmt.Sprintf("%040x", time.Now().UnixNano())
			var id int
			if err := d.queryConn.QueryRow(ctx, `
				INSERT INTO public.upgrade (commit_sha, committed_at, commit_tags, release_status, summary,
				                            state, scheduled_at, started_at, from_commit_version)
				VALUES ($1, now(), '{}', 'commit', 'STATBUS-339 real preswap site',
				        'in_progress', now(), now(), 'dev') RETURNING id`, sha).Scan(&id); err != nil {
				t.Fatalf("insert upgrade row: %v", err)
			}
			t.Cleanup(func() {
				_ = d.removeUpgradeFlag()
				_, _ = d.queryConn.Exec(context.Background(), "DELETE FROM public.upgrade_state_log WHERE upgrade_id = $1", id)
				_, _ = d.queryConn.Exec(context.Background(), "DELETE FROM public.upgrade WHERE id = $1", id)
			})

			err := d.executeUpgrade(ctx, upgradeClaimSnapshot{
				ID: id, CommitVersion: ShortForDisplay(sha), CommitSHA: sha,
				FromCommitVersion: "dev", StartedAt: time.Now(),
			}, ShortForDisplay(sha), nil, "test", string(TriggerService), false)
			if err == nil {
				t.Fatal("executeUpgrade unexpectedly succeeded")
			}
			if fetchCalls != tc.wantFetches {
				t.Fatalf("fetchCommitObjects calls = %d, want %d", fetchCalls, tc.wantFetches)
			}
			if tc.inject && !strings.Contains(err.Error(), "injected failure: preswap-fetch-returns-error") {
				t.Fatalf("real injection error not returned: %v", err)
			}
			if !tc.inject && !strings.Contains(err.Error(), fetchSentinel.Error()) {
				t.Fatalf("production no-op did not return fetch seam error: %v", err)
			}

			var state string
			var failureCode *string
			if err := d.queryConn.QueryRow(ctx,
				"SELECT state::text, failure_code::text FROM public.upgrade WHERE id = $1", id,
			).Scan(&state, &failureCode); err != nil {
				t.Fatalf("read terminal row: %v", err)
			}
			if state != "failed" || failureCode == nil || *failureCode != string(ErrGitFetchRetryable) {
				t.Fatalf("terminal row = state %q failure_code %v, want failed/%s", state, failureCode, ErrGitFetchRetryable)
			}
		})
	}
}
