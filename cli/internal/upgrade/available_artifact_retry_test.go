//go:build livedb

package upgrade

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

// TestAvailableArtifactRetry exercises Run's idle-heartbeat helper and the real
// verifier against owned SQL and synthetic registry observations. It does not
// exercise Run startup, the timer, or publication in a real candidate guest.
func TestAvailableArtifactRetry(t *testing.T) {
	project := findProjDir(t)
	d := NewService(project, false, "test", "")
	dsn, err := d.recoveryDSN()
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := pgx.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	// Normal TestMain owns statbus_livedb_<pid>. The separately approved RC19
	// dual-override fixture must additionally match its exact private cluster.
	privateRC19 := cfg.Database == "statbus_rc19_artifact_retry_1007"
	if !privateRC19 && cfg.Database != fmt.Sprintf("statbus_livedb_%d", os.Getpid()) {
		t.Fatal("refusing mutation outside an owned live-test database")
	}
	if privateRC19 && (cfg.Host != "127.0.0.1" || cfg.Port != 33184 || cfg.User != "postgres") {
		t.Fatal("RC19 endpoint does not match explicit private runtime authorization")
	}
	if filepath.Clean(os.Getenv("HOME")) != filepath.Join(filepath.Dir(project), "home") {
		t.Fatal("fixture-private HOME required")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	conn, err := pgx.ConnectConfig(ctx, cfg)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.Close(context.Background()) })
	var database, systemID, version, ownerName string
	var rows int
	if err := conn.QueryRow(ctx, `SELECT current_database(), system_identifier::text, current_setting('server_version_num'), pg_get_userbyid(datdba) FROM pg_control_system(), pg_database WHERE datname=current_database()`).Scan(&database, &systemID, &version, &ownerName); err != nil {
		t.Fatal(err)
	}
	if database != cfg.Database || ownerName != cfg.User {
		t.Fatal("owned database identity mismatch")
	}
	if privateRC19 && (systemID != "7693664852495945767" || version != "180006") {
		t.Fatal("RC19 private cluster identity mismatch")
	}
	if err := conn.QueryRow(ctx, `SELECT count(*) FROM public.upgrade`).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 0 {
		t.Fatal("owned database has existing upgrade rows, refusing mutation")
	}
	for _, path := range []string{flagFilePath(project), filepath.Join(project, "sb.old"), filepath.Join(os.Getenv("HOME"), "statbus-maintenance")} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatalf("unsafe runtime sentinel %s: %v", path, err)
		}
	}
	d.queryConn = conn
	repo := t.TempDir()
	git := func(args ...string) string {
		t.Helper()
		cmd := exec.Command("git", testgit.Args(args...)...)
		cmd.Dir = repo
		cmd.Env = testgit.Env()
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
		return strings.TrimSpace(string(out))
	}
	git("init", "-q")
	git("commit", "--allow-empty", "-qm", "artifact retry fixture")
	sha := git("rev-parse", "HEAD")
	bin := t.TempDir()
	modePath, tracePath := filepath.Join(bin, "mode"), filepath.Join(bin, "probes")
	script := `#!/bin/sh
printf '%s\n' "$*" >> "$ARTIFACT_RETRY_TRACE"
[ "$1 $2" = 'manifest inspect' ] || exit 90
mode=$(cat "$ARTIFACT_RETRY_MODE")
[ "$mode" != error ] || exit 1
if [ "$mode" = missing ]; then
 case "$3" in *statbus-proxy:*) exit 1 ;; esac
fi
printf '{}\n'
`
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("ARTIFACT_RETRY_MODE", modePath)
	t.Setenv("ARTIFACT_RETRY_TRACE", tracePath)
	t.Setenv("NOTIFY_SOCKET", "")
	oldTransport := http.DefaultTransport
	transportMode := "error"
	httpProbes := 0
	// No network request can escape this transport, including the hard-coded
	// production GHCR fallback. Tests in this package must not run in parallel
	// while its default transport and subprocess environment are overridden.
	http.DefaultTransport = artifactRetryTransport(func(req *http.Request) (*http.Response, error) {
		httpProbes++
		if req.URL.Host != "ghcr.io" {
			return nil, fmt.Errorf("unexpected external host %s", req.URL.Host)
		}
		if transportMode == "error" {
			return nil, fmt.Errorf("fixture transport indeterminate")
		}
		body, status := `{"token":"fixture"}`, http.StatusOK
		if req.Method == http.MethodHead {
			body = ""
			if transportMode == "absent" {
				status = http.StatusNotFound
			}
		}
		return &http.Response{StatusCode: status, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(body)), Request: req}, nil
	})
	t.Cleanup(func() { http.DefaultTransport = oldTransport })
	setMode := func(mode string) {
		t.Helper()
		if err := os.WriteFile(modePath, []byte(mode), 0600); err != nil {
			t.Fatal(err)
		}
	}
	probes := func() []string {
		t.Helper()
		b, err := os.ReadFile(tracePath)
		if os.IsNotExist(err) {
			return nil
		}
		if err != nil {
			t.Fatal(err)
		}
		return strings.FieldsFunc(strings.TrimSpace(string(b)), func(r rune) bool { return r == '\n' })
	}
	for _, scenario := range []struct {
		name, mode, state                             string
		recover, terminal, pastGrace, fallbackPresent bool
	}{
		{name: "RecoversWithoutNotify", mode: "published", state: "available", recover: true},
		{name: "PersistentTransportPastGrace", mode: "error", state: "available", pastGrace: true},
		{name: "MissingImage", mode: "missing", state: "available"},
		{name: "FallbackPresentCannotAuthorizeReady", mode: "missing", state: "available", fallbackPresent: true},
		{name: "TerminalCompleted", mode: "published", state: "completed", terminal: true},
		{name: "TerminalRolledBack", mode: "published", state: "rolled_back", terminal: true},
		{name: "TerminalSkipped", mode: "published", state: "skipped", terminal: true},
		{name: "TerminalSuperseded", mode: "published", state: "superseded", terminal: true},
		{name: "TerminalDismissed", mode: "published", state: "dismissed", terminal: true},
		{name: "ScheduledSingleProbe", mode: "error", state: "scheduled"},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			var id int
			age := "0 seconds"
			if scenario.pastGrace {
				age = "21 minutes"
			}
			if err := conn.QueryRow(ctx, `INSERT INTO public.upgrade
    (commit_sha,committed_at,commit_tags,release_status,summary,state,docker_images_status,release_builds_status,discovered_at,
     scheduled_at,completed_at,rolled_back_at,skipped_at,superseded_at,dismissed_at,error,log_relative_file_path)
    VALUES ($1,now(),'{}','commit','artifact retry fixture',$2::public.upgrade_state,'building','ready',now()-$3::interval,
     CASE WHEN $2='scheduled' THEN now() ELSE NULL END,
     CASE WHEN $2='completed' THEN now() ELSE NULL END,
     CASE WHEN $2='rolled_back' THEN now() ELSE NULL END,
     CASE WHEN $2='skipped' THEN now() ELSE NULL END,
     CASE WHEN $2='superseded' THEN now() ELSE NULL END,
     CASE WHEN $2='dismissed' THEN now() ELSE NULL END,
     CASE WHEN $2 IN ('rolled_back','dismissed') THEN 'fixture failure' ELSE NULL END,
     CASE WHEN $2='completed' THEN 'fixture.log' ELSE NULL END) RETURNING id`, sha, scenario.state, age).Scan(&id); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() {
				cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 10*time.Second)
				defer cleanupCancel()
				if _, err := conn.Exec(cleanupCtx, `DELETE FROM public.upgrade_state_log WHERE upgrade_id=$1`, id); err != nil {
					t.Error(err)
				}
				if _, err := conn.Exec(cleanupCtx, `DELETE FROM public.upgrade WHERE id=$1`, id); err != nil {
					t.Error(err)
				}
			})
			snapshot := func() string {
				t.Helper()
				var value string
				if err := conn.QueryRow(ctx, `SELECT row_to_json(u)::text FROM public.upgrade AS u WHERE id=$1`, id).Scan(&value); err != nil {
					t.Fatal(err)
				}
				return value
			}
			original := snapshot()
			check := func(want string) {
				t.Helper()
				var state, status string
				var started *time.Time
				if err := conn.QueryRow(ctx, `SELECT state::text,docker_images_status::text,started_at FROM public.upgrade WHERE id=$1`, id).Scan(&state, &status, &started); err != nil {
					t.Fatal(err)
				}
				if state != scenario.state || status != want || started != nil {
					t.Fatalf("row state=%s images=%s started=%v, want %s/%s/no claim", state, status, started, scenario.state, want)
				}
				if scenario.terminal && snapshot() != original {
					t.Fatal("terminal row changed")
				}
			}
			setMode("error")
			transportMode = "error"
			before := len(probes())
			d.verifyArtifacts(ctx) // registration's initial verifier, indeterminate
			check("building")
			if scenario.terminal {
				if len(probes()) != before {
					t.Fatal("terminal candidate probed")
				}
			} else if len(probes()) != before+1 {
				t.Fatal("initial indeterminate observation missing")
			}
			setMode(scenario.mode)
			if scenario.mode == "missing" {
				transportMode = "absent"
				if scenario.fallbackPresent {
					transportMode = "present"
				}
			}
			before = len(probes())
			httpBefore := httpProbes
			d.idleHeartbeat(ctx) // real Run-wired helper, no NOTIFY or discover
			want := "building"
			if scenario.recover {
				want = "ready"
			}
			check(want)
			count := len(probes()) - before
			expected := 1
			if scenario.recover || scenario.mode == "missing" {
				expected = 4
			}
			if scenario.terminal {
				expected = 0
			}
			if count != expected {
				t.Fatalf("heartbeat docker probes=%d want=%d (duplicate or missing verification)", count, expected)
			}
			if !scenario.terminal && !scenario.recover && httpProbes == httpBefore {
				t.Fatal("fallback registry observation missing")
			}
			if scenario.recover {
				all := probes()
				for i, service := range []string{"db", "app", "worker", "proxy"} {
					wantRef := "manifest inspect ghcr.io/statisticsnorway/statbus-" + service + ":" + sha[:8]
					if all[before+i] != wantRef {
						t.Fatalf("probe=%q want=%q", all[before+i], wantRef)
					}
				}
			}
			before = len(probes())
			d.idleHeartbeat(ctx)
			check(want)
			if scenario.recover || scenario.terminal {
				if len(probes()) != before {
					t.Fatal("ready/terminal candidate re-probed")
				}
			} else if len(probes())-before != expected {
				t.Fatal("later heartbeat must retry once without another notification")
			}
			if scenario.state == "scheduled" {
				before = len(probes())
				d.executeScheduled(ctx) // independent startup/discovery/NOTIFY retry
				check("building")
				if len(probes())-before != 1 {
					t.Fatal("independent scheduled retry lost or duplicated")
				}
			}
			t.Logf("production heartbeat/verifier: state=%s images=%s probes=%d no claim", scenario.state, want, count)
		})
	}
}

type artifactRetryTransport func(*http.Request) (*http.Response, error)

func (f artifactRetryTransport) RoundTrip(req *http.Request) (*http.Response, error) { return f(req) }
