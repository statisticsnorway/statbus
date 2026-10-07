package upgrade

// Review round 2 of fix/rollback-db-recreate (tmp/review-rollback-db-recreate.md):
//
//	F1: convergeSourceDatabaseContainer closed the daemon's sessions and left them
//	    nil on every error exit. The park and PreSwap callers record their terminal
//	    through fresh connections and return nil, so the process continued into
//	    completeInProgressUpgrade / UpgradeParkedReason with a nil d.queryConn and
//	    panicked (pgx dereferences a nil *Conn receiver).
//	F2: the MayRun park path does not prove app/worker/rest are stopped, so the
//	    db recreate could meet live sessions (smart shutdown, SIGKILL after 10 s).
//	F3: the listenLoop goroutine was left reading the closed listen connection.
//	F4: the health wait did not advance progress under the PreSwap gated watchdog.
//
// These tests drive the REAL callers (parkServiceRecovery with the MayRun route,
// convergeUnchangedSourceServices) against a docker shim and a minimal
// PostgreSQL wire server, so connect/reconnect/terminalUpdate run their
// production code over a real socket.

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgproto3"
	"github.com/jackc/pgx/v5/pgtype"
)

// fakeUpgradePG is a minimal PostgreSQL backend: startup, simple Query, and the
// extended Parse/Describe/Bind/Execute/Sync flow pgx uses for parameterized and
// cached statements. It answers exactly the statements the source-recovery
// paths issue and records everything else as unexpected.
type fakeUpgradePG struct {
	t              *testing.T
	addr           string
	fromCommit     string
	queryErrorCode string

	mu            sync.Mutex
	connections   int
	advisoryLocks int
	narratives    []string
	alters        []string
	unexpected    []string
}

type fakeUpgradePGResult struct {
	oids   []uint32
	values []any // one row, or nil for no row
	tag    string
}

func startFakeUpgradePG(t *testing.T, fromCommit string) *fakeUpgradePG {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	s := &fakeUpgradePG{t: t, addr: ln.Addr().String(), fromCommit: fromCommit}
	var wg sync.WaitGroup
	t.Cleanup(func() {
		_ = ln.Close()
		wg.Wait()
	})
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			s.mu.Lock()
			s.connections++
			s.mu.Unlock()
			wg.Add(1)
			go func() {
				defer wg.Done()
				s.serve(conn)
			}()
		}
	}()
	return s
}

func (s *fakeUpgradePG) snapshot() (connections, locks int, narratives, alters, unexpected []string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.connections, s.advisoryLocks, append([]string(nil), s.narratives...), append([]string(nil), s.alters...), append([]string(nil), s.unexpected...)
}

var fakePGParamRef = regexp.MustCompile(`\$(\d+)`)

func fakePGParamCount(sql string) int {
	max := 0
	for _, m := range fakePGParamRef.FindAllStringSubmatch(sql, -1) {
		var n int
		_, _ = fmt.Sscanf(m[1], "%d", &n)
		if n > max {
			max = n
		}
	}
	return max
}

// respond models the statements. execute=false is a Describe: shape only, no
// side effects.
func (s *fakeUpgradePG) respond(sql string, params [][]byte, execute bool) fakeUpgradePGResult {
	text := strings.TrimSpace(sql)
	s.mu.Lock()
	defer s.mu.Unlock()
	switch {
	case strings.HasPrefix(text, "SET "):
		return fakeUpgradePGResult{tag: "SET"}
	case strings.HasPrefix(text, "LISTEN "):
		return fakeUpgradePGResult{tag: "LISTEN"}
	case strings.HasPrefix(text, "ALTER DATABASE"):
		if execute {
			s.alters = append(s.alters, text)
		}
		return fakeUpgradePGResult{tag: "ALTER DATABASE"}
	case strings.Contains(text, "pg_try_advisory_lock"):
		if execute {
			s.advisoryLocks++
		}
		return fakeUpgradePGResult{oids: []uint32{pgtype.BoolOID}, values: []any{true}, tag: "SELECT 1"}
	case strings.Contains(text, "current_database()"):
		return fakeUpgradePGResult{oids: []uint32{pgtype.TextOID}, values: []any{"statbus_fixture"}, tag: "SELECT 1"}
	case strings.Contains(text, "FROM db.migration"):
		return fakeUpgradePGResult{oids: []uint32{pgtype.TextOID}, values: []any{"0"}, tag: "SELECT 1"}
	case strings.Contains(text, "COALESCE(from_commit_version"):
		return fakeUpgradePGResult{oids: []uint32{pgtype.TextOID}, values: []any{s.fromCommit}, tag: "SELECT 1"}
	case strings.Contains(text, "SET recovery_parked_reason"):
		if execute && len(params) >= 2 {
			s.narratives = append(s.narratives, string(params[1]))
		}
		return fakeUpgradePGResult{oids: []uint32{pgtype.TextOID}, values: []any{`{"id":1,"state":"in_progress"}`}, tag: "UPDATE 1"}
	case strings.Contains(text, "SELECT recovery_parked_at, recovery_parked_reason"):
		return fakeUpgradePGResult{oids: []uint32{pgtype.TimestamptzOID, pgtype.TextOID}, values: []any{time.Date(2026, 9, 28, 20, 0, 0, 0, time.UTC), "fixture park"}, tag: "SELECT 1"}
	case strings.Contains(text, "FROM public.upgrade") && strings.Contains(text, "WHERE state = 'in_progress'"):
		// completeInProgressUpgrade's reconciliation read: no orphan row.
		return fakeUpgradePGResult{oids: []uint32{pgtype.Int4OID, pgtype.TextOID, pgtype.TextOID, pgtype.TextOID}, tag: "SELECT 0"}
	default:
		if execute {
			s.unexpected = append(s.unexpected, text)
		}
		return fakeUpgradePGResult{tag: "SELECT 0"}
	}
}

func fakePGFields(oids []uint32, formats []int16) []pgproto3.FieldDescription {
	fields := make([]pgproto3.FieldDescription, len(oids))
	for i, oid := range oids {
		fields[i] = pgproto3.FieldDescription{Name: []byte(fmt.Sprintf("col%d", i)), DataTypeOID: oid, DataTypeSize: -1, TypeModifier: -1, Format: fakePGFormat(formats, i)}
	}
	return fields
}

func fakePGFormat(formats []int16, i int) int16 {
	switch len(formats) {
	case 0:
		return pgtype.TextFormatCode
	case 1:
		return formats[0]
	default:
		return formats[i]
	}
}

func (s *fakeUpgradePG) serve(conn net.Conn) {
	defer func() { _ = conn.Close() }()
	b := pgproto3.NewBackend(conn, conn)
	if _, err := b.ReceiveStartupMessage(); err != nil {
		return
	}
	b.Send(&pgproto3.AuthenticationOk{})
	b.Send(&pgproto3.ParameterStatus{Name: "server_version", Value: "18.0"})
	b.Send(&pgproto3.ParameterStatus{Name: "client_encoding", Value: "UTF8"})
	b.Send(&pgproto3.ParameterStatus{Name: "standard_conforming_strings", Value: "on"})
	b.Send(&pgproto3.ReadyForQuery{TxStatus: 'I'})
	if b.Flush() != nil {
		return
	}
	typeMap := pgtype.NewMap()
	encodeRow := func(result fakeUpgradePGResult, formats []int16) *pgproto3.DataRow {
		values := make([][]byte, len(result.values))
		for i, v := range result.values {
			encoded, err := typeMap.Encode(result.oids[i], fakePGFormat(formats, i), v, nil)
			if err != nil {
				s.t.Errorf("fake PG encode %v as OID %d: %v", v, result.oids[i], err)
			}
			values[i] = encoded
		}
		return &pgproto3.DataRow{Values: values}
	}
	statements := map[string]string{}
	type portal struct {
		sql     string
		params  [][]byte
		formats []int16
	}
	var current portal
	for {
		msg, err := b.Receive()
		if err != nil {
			return
		}
		switch m := msg.(type) {
		case *pgproto3.Terminate:
			return
		case *pgproto3.Query:
			result := s.respond(m.String, nil, true)
			if len(result.oids) > 0 {
				b.Send(&pgproto3.RowDescription{Fields: fakePGFields(result.oids, nil)})
				if result.values != nil {
					b.Send(encodeRow(result, nil))
				}
			}
			b.Send(&pgproto3.CommandComplete{CommandTag: []byte(result.tag)})
			b.Send(&pgproto3.ReadyForQuery{TxStatus: 'I'})
			if b.Flush() != nil {
				return
			}
		case *pgproto3.Parse:
			statements[m.Name] = m.Query
			b.Send(&pgproto3.ParseComplete{})
		case *pgproto3.Describe:
			sql := statements[m.Name]
			if m.ObjectType == 'P' {
				sql = current.sql
			} else {
				b.Send(&pgproto3.ParameterDescription{ParameterOIDs: make([]uint32, fakePGParamCount(sql))})
			}
			result := s.respond(sql, nil, false)
			if len(result.oids) > 0 {
				b.Send(&pgproto3.RowDescription{Fields: fakePGFields(result.oids, nil)})
			} else {
				b.Send(&pgproto3.NoData{})
			}
		case *pgproto3.Bind:
			current = portal{sql: statements[m.PreparedStatement], params: append([][]byte(nil), m.Parameters...), formats: append([]int16(nil), m.ResultFormatCodes...)}
			b.Send(&pgproto3.BindComplete{})
		case *pgproto3.Execute:
			if s.queryErrorCode != "" && strings.Contains(current.sql, "WHERE state = 'in_progress'") {
				b.Send(&pgproto3.ErrorResponse{Severity: "ERROR", Code: s.queryErrorCode, Message: "fixture missing upgrade schema"})
				continue
			}
			result := s.respond(current.sql, current.params, true)
			if result.values != nil {
				b.Send(encodeRow(result, current.formats))
			}
			b.Send(&pgproto3.CommandComplete{CommandTag: []byte(result.tag)})
		case *pgproto3.Close:
			b.Send(&pgproto3.CloseComplete{})
		case *pgproto3.Sync:
			b.Send(&pgproto3.ReadyForQuery{TxStatus: 'I'})
			if b.Flush() != nil {
				return
			}
		case *pgproto3.Flush:
			if b.Flush() != nil {
				return
			}
		default:
			s.t.Errorf("fake PG: unexpected message %T", m)
			return
		}
	}
}

type sourceDBConvergeFixture struct {
	git       *gitRepoFixture
	sourceTag string
	pg        *fakeUpgradePG
	logPath   string
	shimDir   string
	svc       *Service
}

// newSourceDBConvergeFixture builds a box whose serving containers are the
// verified source era, whose db route and ./sb config generate succeed, and
// whose database convergence behaves per dbUp: "ok", "fail" (compose up
// errors before touching the old container), or "unhealthy" (the converged
// container never becomes ready). clientState is app/worker/rest's state until
// a `compose stop app worker rest` is issued.
func newSourceDBConvergeFixture(t *testing.T, dbUp, clientState string) *sourceDBConvergeFixture {
	t.Helper()
	setSourceStackImageIdentityEnv(t)
	git := newGitRepoFixture(t)
	sourceTag := git.newSHA[:8]
	writeSourceStackRecoveryFlag(t, git.dir, sourceTag, nil)
	pg := startFakeUpgradePG(t, git.newSHA)
	host, port, err := net.SplitHostPort(pg.addr)
	if err != nil {
		t.Fatal(err)
	}
	env := fmt.Sprintf("CADDY_DB_BIND_ADDRESS=%s\nCADDY_DB_PORT=%s\nPOSTGRES_APP_DB=statbus_fixture\nPOSTGRES_ADMIN_USER=postgres\nPOSTGRES_ADMIN_PASSWORD=fixture\n", host, port)
	if err := os.WriteFile(filepath.Join(git.dir, ".env"), []byte(env), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(git.dir, "sb"), []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	shimDir := t.TempDir()
	logPath := filepath.Join(shimDir, "docker.log")
	shim := `#!/bin/sh
printf '%s\n' "$*" >> "$STATBUS_TEST_DOCKER_LOG"
case "$*" in
	` + sourceStackImageInspectCases + `
	"compose --profile all config --format json")
		printf '%s\n' '{"services":{"app":{"image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'"},"worker":{"image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'"},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'"}}}'
		;;
	"compose ps -a --format json")
		state="$STATBUS_TEST_CLIENT_STATE"
		if [ -f "$STATBUS_TEST_SHIM_DIR/clients-stopped" ]; then state=exited; fi
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_APP_SOURCE_ID"'","Service":"app","State":"'"$state"'","Image":"ghcr.io/statisticsnorway/statbus-app:'"$STATBUS_TEST_SOURCE_TAG"'","ImageID":"'"$STATBUS_TEST_APP_SOURCE_ID"'"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_WORKER_SOURCE_ID"'","Service":"worker","State":"'"$state"'","Image":"ghcr.io/statisticsnorway/statbus-worker:'"$STATBUS_TEST_SOURCE_TAG"'","ImageID":"'"$STATBUS_TEST_WORKER_SOURCE_ID"'"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_REST_SOURCE_ID"'","Service":"rest","State":"'"$state"'","Image":"postgrest/postgrest:v12.2.8","ImageID":"'"$STATBUS_TEST_REST_SOURCE_ID"'"}'
		printf '%s\n' '{"ID":"'"$STATBUS_TEST_PROXY_SOURCE_ID"'","Service":"proxy","State":"running","Image":"ghcr.io/statisticsnorway/statbus-proxy:'"$STATBUS_TEST_SOURCE_TAG"'","ImageID":"'"$STATBUS_TEST_PROXY_SOURCE_ID"'"}'
		;;
	"compose ps -a -q proxy") printf 'proxy-container\n' ;;
	"compose stop app worker rest") touch "$STATBUS_TEST_SHIM_DIR/clients-stopped" ;;
	"compose up -d --no-build --no-deps db")
		# F4 seam: an optional gate holds the convergence until the test releases it.
		if [ -n "${STATBUS_TEST_DB_UP_GATE:-}" ]; then
			touch "$STATBUS_TEST_SHIM_DIR/db-up-entered"
			while [ ! -f "$STATBUS_TEST_DB_UP_GATE" ]; do sleep 0.05; done
		fi
		if [ "$STATBUS_TEST_DB_UP" = fail ]; then
			echo 'Error response from daemon: simulated compose up failure' >&2
			exit 1
		fi
		touch "$STATBUS_TEST_SHIM_DIR/db-converged"
		;;
	"compose exec db pg_isready -U postgres")
		if [ -f "$STATBUS_TEST_SHIM_DIR/db-converged" ]; then
			n=$(cat "$STATBUS_TEST_SHIM_DIR/post-converge-probes" 2>/dev/null || echo 0)
			n=$((n + 1))
			printf '%s\n' "$n" > "$STATBUS_TEST_SHIM_DIR/post-converge-probes"
			if [ "$STATBUS_TEST_DB_UP" = unhealthy ]; then exit 2; fi
			if [ -n "${STATBUS_TEST_HEALTH_GATE:-}" ] && [ "$n" -ge 2 ]; then
				while [ ! -f "$STATBUS_TEST_HEALTH_GATE" ]; do sleep 0.05; done
				exit 0
			fi
			if [ "$n" -lt "${STATBUS_TEST_UNREADY_PROBES:-0}" ]; then exit 2; fi
		fi
		;;
esac
exit 0
`
	if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STATBUS_TEST_DOCKER_LOG", logPath)
	t.Setenv("STATBUS_TEST_SHIM_DIR", shimDir)
	t.Setenv("STATBUS_TEST_SOURCE_TAG", sourceTag)
	t.Setenv("STATBUS_TEST_CLIENT_STATE", clientState)
	t.Setenv("STATBUS_TEST_DB_UP", dbUp)
	t.Setenv("HOME", t.TempDir()) // setMaintenance(false) removes $HOME/statbus-maintenance/active

	oldHealth := sourceDatabaseConvergeHealthTimeout
	sourceDatabaseConvergeHealthTimeout = 3 * time.Second
	t.Cleanup(func() { sourceDatabaseConvergeHealthTimeout = oldHealth })

	srv, _ := sourceStackHealthServer(t)
	d := &Service{projDir: git.dir, cachedURL: srv.URL + "/rpc/auth_status", cachedReadyURL: srv.URL + "/ready"}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := d.connect(ctx); err != nil {
		t.Fatalf("connect the daemon's sessions to the fixture database: %v", err)
	}
	t.Cleanup(d.Close)
	return &sourceDBConvergeFixture{git: git, sourceTag: sourceTag, pg: pg, logPath: logPath, shimDir: shimDir, svc: d}
}

func (f *sourceDBConvergeFixture) dockerLog(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(f.logPath)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// assertDaemonSessionsUsable is the F1 invariant: the service that entered the
// source gate connected leaves it connected, and the readers that run next in
// the real process (Run's completeInProgressUpgrade, runCrashRecovery's
// UpgradeParkedReason) work instead of panicking on a nil *pgx.Conn.
func assertDaemonSessionsUsable(t *testing.T, f *sourceDBConvergeFixture, connectionsBefore, locksBefore int) {
	t.Helper()
	d := f.svc
	if d.queryConn == nil || d.listenConn == nil {
		t.Fatalf("a failed database convergence left the daemon disconnected (queryConn nil=%t, listenConn nil=%t); the caller continues into completeInProgressUpgrade/UpgradeParkedReason and panics", d.queryConn == nil, d.listenConn == nil)
	}
	connections, locks, _, _, _ := f.pg.snapshot()
	if connections <= connectionsBefore || locks <= locksBefore {
		t.Fatalf("the daemon's sessions were not re-established through reconnect (connections %d -> %d, advisory locks %d -> %d)", connectionsBefore, connections, locksBefore, locks)
	}
	ctx := context.Background()
	parked, reason, err := d.UpgradeParkedReason(ctx, 1)
	if err != nil || !parked || reason != "fixture park" {
		t.Fatalf("UpgradeParkedReason after the failed convergence = (%t, %q, %v), want (true, fixture park, nil)", parked, reason, err)
	}
	if err := d.completeInProgressUpgrade(ctx); err != nil {
		t.Fatalf("completeInProgressUpgrade after the failed convergence: %v", err)
	}
}

func startupRecoveryServiceFixture(t *testing.T, dir, addr string) *Service {
	t.Helper()
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		t.Fatal(err)
	}
	env := fmt.Sprintf("CADDY_DB_BIND_ADDRESS=%s\nCADDY_DB_PORT=%s\nPOSTGRES_APP_DB=statbus_fixture\nPOSTGRES_ADMIN_USER=postgres\nPOSTGRES_ADMIN_PASSWORD=fixture\n", host, port)
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0o600); err != nil {
		t.Fatal(err)
	}
	d := &Service{projDir: dir}
	t.Cleanup(d.Close)
	return d
}

// These controls exercise the actual startup recovery helper and production
// sessions over the existing wire fixture, not a whole service or guest boot.
func TestStartupFlagRecoveryReconnectsAndReplays(t *testing.T) {
	refusingDir := t.TempDir()
	for _, command := range []string{"docker", "sb", "systemctl", "ssh", "git"} {
		if err := os.WriteFile(filepath.Join(refusingDir, command), []byte("#!/bin/sh\necho REFUSED >&2\nexit 97\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", refusingDir)
	t.Run("unavailable-then-return", func(t *testing.T) {
		pg := startFakeUpgradePG(t, "fixture")
		ln, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = ln.Close() })
		var refused atomic.Int32
		go func() {
			for {
				c, e := ln.Accept()
				if e != nil {
					return
				}
				if refused.Load() < 2 {
					refused.Add(1)
					_ = c.Close()
					continue
				}
				go func() {
					defer func() { _ = c.Close() }()
					upstream, e := net.Dial("tcp", pg.addr)
					if e != nil {
						return
					}
					defer func() { _ = upstream.Close() }()
					go func() { _, _ = io.Copy(upstream, c) }()
					_, _ = io.Copy(c, upstream)
				}()
			}
		}()
		oldAfter := connectRetryAfter
		connectRetryAfter = func(time.Duration) <-chan time.Time { ch := make(chan time.Time, 1); ch <- time.Now(); return ch }
		t.Cleanup(func() { connectRetryAfter = oldAfter })
		d := startupRecoveryServiceFixture(t, t.TempDir(), ln.Addr().String())
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		if err := d.recoverStartupFlag(ctx); err != nil {
			t.Fatal(err)
		}
		if refused.Load() != 2 {
			t.Fatalf("refused attempts=%d", refused.Load())
		}
		if err := d.completeInProgressUpgrade(ctx); err != nil {
			t.Fatal(err)
		}
	})
	t.Run("cancel-while-unavailable", func(t *testing.T) {
		ln, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = ln.Close() })
		go func() {
			for {
				c, e := ln.Accept()
				if e != nil {
					return
				}
				_ = c.Close()
			}
		}()
		flag := UpgradeFlag{ID: 0, Holder: HolderService, Phase: PhaseNewSbUpgrading, Step: StepRollback}
		dir, lock := heldRecoveryFixture(t, flag)
		lock.Close()
		before, err := os.ReadFile(flagFilePath(dir))
		if err != nil {
			t.Fatal(err)
		}
		d := startupRecoveryServiceFixture(t, dir, ln.Addr().String())
		d.rollbackFinishPendingForTest = func(context.Context, int) (bool, error) { return false, nil }
		d.servingTreeObligationForTest = func(context.Context, int) (bool, string, error) { return false, "", nil }
		ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
		defer cancel()
		start := time.Now()
		if err := d.recoverStartupFlag(ctx); err == nil {
			t.Fatal("down startup succeeded")
		}
		if time.Since(start) > time.Second {
			t.Fatal("cancel not prompt")
		}
		if d.queryConn != nil && !d.queryConn.IsClosed() {
			t.Fatal("down startup created usable query session")
		}
		after, err := os.ReadFile(flagFilePath(dir))
		if err != nil || string(before) != string(after) || IsFlockHeld(dir) {
			t.Fatalf("canceled unavailable recovery changed marker or retained flock: %v", err)
		}
	})
	t.Run("retained-service-marker-replayed", func(t *testing.T) {
		flag := UpgradeFlag{ID: 0, Holder: HolderService, Phase: PhaseNewSbUpgrading, Step: StepRollback}
		dir, lock := heldRecoveryFixture(t, flag)
		lock.Close()
		before, err := os.ReadFile(flagFilePath(dir))
		if err != nil {
			t.Fatal(err)
		}
		pg := startFakeUpgradePG(t, "fixture")
		d := startupRecoveryServiceFixture(t, dir, pg.addr)
		var reads int
		d.rollbackFinishPendingForTest = func(context.Context, int) (bool, error) { reads++; return false, nil }
		d.servingTreeObligationForTest = func(context.Context, int) (bool, string, error) { return false, "", nil }
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		if err := d.connect(ctx); err != nil {
			t.Fatal(err)
		}
		if err := d.queryConn.Close(ctx); err != nil {
			t.Fatal(err)
		}
		if err := d.recoverStartupFlag(ctx); err != nil {
			t.Fatal(err)
		}
		if reads != 2 {
			t.Fatalf("actual flag recovery passes=%d want2", reads)
		}
		after, err := os.ReadFile(flagFilePath(dir))
		if err != nil || string(before) != string(after) {
			t.Fatalf("marker changed: %v", err)
		}
		if IsFlockHeld(dir) {
			t.Fatal("parked marker retained live flock")
		}
		_, _, narratives, alters, unexpected := pg.snapshot()
		if len(narratives)+len(alters)+len(unexpected) != 0 {
			t.Fatalf("unexpected writes/queries: %v %v %v", narratives, alters, unexpected)
		}
	})
	t.Run("phase-drift-remains-fatal", func(t *testing.T) {
		flag := UpgradeFlag{ID: 0, Holder: HolderService, Phase: "unrecognized-probe-phase"}
		dir, lock := heldRecoveryFixture(t, flag)
		lock.Close()
		before, err := os.ReadFile(flagFilePath(dir))
		if err != nil {
			t.Fatal(err)
		}
		pg := startFakeUpgradePG(t, "fixture")
		d := startupRecoveryServiceFixture(t, dir, pg.addr)
		d.rollbackFinishPendingForTest = func(context.Context, int) (bool, error) { return false, nil }
		d.servingTreeObligationForTest = func(context.Context, int) (bool, string, error) { return false, "", nil }
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		if err := d.connect(ctx); err != nil {
			t.Fatal(err)
		}
		if err := d.recoverStartupFlag(ctx); err == nil {
			t.Fatal("unknown recovery phase swallowed")
		}
		after, err := os.ReadFile(flagFilePath(dir))
		if err != nil || string(after) != string(before) {
			t.Fatalf("divergence mutated marker: %v", err)
		}
		connections, locks, _, _, _ := pg.snapshot()
		if connections != 2 || locks != 0 {
			t.Fatalf("divergence retried connection: connections=%d locks=%d", connections, locks)
		}
	})
	t.Run("actual-wire-schema-error-remains-fatal", func(t *testing.T) {
		pg := startFakeUpgradePG(t, "fixture")
		pg.queryErrorCode = "42P01"
		d := startupRecoveryServiceFixture(t, t.TempDir(), pg.addr)
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		if err := d.recoverStartupFlag(ctx); err != nil {
			t.Fatal(err)
		}
		err := d.completeInProgressUpgrade(ctx)
		var sqlErr *pgconn.PgError
		if !errors.As(err, &sqlErr) || sqlErr.Code != "42P01" {
			t.Fatalf("actual reader error=%v", err)
		}
		if isConnError(err) {
			t.Fatal("schema error misclassified as reconnectable")
		}
	})
}

func TestSourceDatabaseConvergenceFailureRestoresDaemonSessions(t *testing.T) {
	for _, caller := range []string{"park-mayrun", "preswap"} {
		for _, dbUp := range []string{"fail", "unhealthy"} {
			t.Run(caller+"/"+dbUp, func(t *testing.T) {
				f := newSourceDBConvergeFixture(t, dbUp, "exited")
				connectionsBefore, locksBefore, _, _, _ := f.pg.snapshot()
				progress, progressPath := sourceStackTestProgress(t, f.git.dir)
				ctx := context.Background()
				wantErr := "converge database container to restored source configuration"
				if dbUp == "unhealthy" {
					wantErr = "database not healthy after converging to restored source configuration"
				}

				switch caller {
				case "park-mayrun":
					// The deterministic park with an Unreadable position (service.go
					// parkForDeterministicFailure): era verdict through the MayRun route,
					// then restoreSourceServices -> startSourceApplicationStack.
					if err := f.svc.parkServiceRecovery(ctx, 1, f.git.newSHA, progress, f.svc.StartDatabaseRouteServingMayRun, true); err != nil {
						t.Fatalf("parkServiceRecovery returned %v; a failed restore is narrative-only", err)
					}
					_, _, narratives, _, _ := f.pg.snapshot()
					if len(narratives) != 1 || !strings.Contains(narratives[0], wantErr) {
						t.Fatalf("park narrative = %q, want one note carrying %q", narratives, wantErr)
					}
				case "preswap":
					// The PreSwap pair terminal's convergence (recoveryRollback writes
					// STOPPED-DEGRADED through terminalUpdate and returns nil).
					err := f.svc.convergeUnchangedSourceServices(ctx, progress)
					if err == nil || !strings.Contains(err.Error(), wantErr) {
						t.Fatalf("convergeUnchangedSourceServices error = %v, want %q", err, wantErr)
					}
				}

				log := f.dockerLog(t)
				if !strings.Contains(log, "compose up -d --no-build --no-deps db\n") {
					t.Fatalf("the database convergence was not attempted:\n%s", log)
				}
				if strings.Contains(log, "compose start app worker rest proxy\n") {
					t.Fatalf("the serving tier started after a failed database convergence:\n%s", log)
				}
				assertDaemonSessionsUsable(t, f, connectionsBefore, locksBefore)
				progressBytes, err := os.ReadFile(progressPath)
				if err != nil {
					t.Fatal(err)
				}
				if !strings.Contains(string(progressBytes), "Reconnecting after the failed database convergence ... ok") {
					t.Fatalf("the restored sessions were not narrated:\n%s", progressBytes)
				}
			})
		}
	}
}

// TestNilQueryConnReadersReturnErrorsNotPanics pins the readers the review
// found reachable with a nil d.queryConn (a failed convergence whose
// best-effort reconnect also failed, and master's pre-reconnect park window).
func TestNilQueryConnReadersReturnErrorsNotPanics(t *testing.T) {
	ctx := context.Background()
	t.Run("completeInProgressUpgrade", func(t *testing.T) {
		err := (&Service{projDir: t.TempDir()}).completeInProgressUpgrade(ctx)
		if err == nil || !strings.Contains(err.Error(), "query connection is not available") {
			t.Fatalf("completeInProgressUpgrade with nil queryConn = %v, want a named query-connection error", err)
		}
	})
	t.Run("UpgradeParkedReason", func(t *testing.T) {
		parked, _, err := (&Service{projDir: t.TempDir()}).UpgradeParkedReason(ctx, 42)
		if err == nil || !strings.Contains(err.Error(), "query connection is not available") {
			t.Fatalf("UpgradeParkedReason with nil queryConn = %v, want a named query-connection error", err)
		}
		if parked {
			t.Fatal("an unreadable park state must not read as parked")
		}
		// Not a 42703: the park state is UNKNOWN, so every caller fails safe.
		if !parkStateUnknown(err) {
			t.Fatalf("nil-conn park read must classify as UNKNOWN: %v", err)
		}
	})
}

// TestSourceDatabaseConvergenceStopsLiveClientsFirst is F2 plus F3: on the
// MayRun park path app/worker/rest may still be running target sessions. They
// must be stopped and verified before the database can be recreated, and the
// listenLoop must be stopped before its connection is closed, as executeUpgrade
// does. The success path then serves normally.
func TestSourceDatabaseConvergenceStopsLiveClientsFirst(t *testing.T) {
	f := newSourceDBConvergeFixture(t, "ok", "running")
	d := f.svc
	ctx := context.Background()
	// A stand-in for the live listenLoop goroutine: it owns the listener guard
	// exactly as startListenLoop sets it and exits when its context is cancelled.
	// (The real loop reads the pgx session concurrently; that close-while-reading
	// is stopListenLoop's own documented design and is not what F3 is about.)
	listenCtx, listenCancel := context.WithCancel(ctx)
	oldListenDone := make(chan struct{})
	go func() {
		defer close(oldListenDone)
		<-listenCtx.Done()
	}()
	d.listenCancel = listenCancel
	d.listenDone = oldListenDone
	t.Cleanup(listenCancel)
	progress, _ := sourceStackTestProgress(t, f.git.dir)

	if err := d.parkServiceRecovery(ctx, 1, f.git.newSHA, progress, d.StartDatabaseRouteServingMayRun, true); err != nil {
		t.Fatalf("parkServiceRecovery: %v", err)
	}
	_, _, narratives, alters, unexpected := f.pg.snapshot()
	if len(narratives) != 0 {
		t.Fatalf("successful source restore wrote park narrative(s): %q", narratives)
	}
	if len(alters) != 1 || !strings.Contains(alters[0], "default_transaction_read_only = off") {
		t.Fatalf("serve-proven restore did not lift the read-only window: %q", alters)
	}
	if len(unexpected) != 0 {
		t.Fatalf("unexpected SQL reached the fixture database: %q", unexpected)
	}

	log := f.dockerLog(t)
	stopIdx := strings.Index(log, "compose stop app worker rest\n")
	convergeIdx := strings.Index(log, "compose up -d --no-build --no-deps db\n")
	startIdx := strings.Index(log, "compose start app worker rest proxy\n")
	if stopIdx < 0 || convergeIdx < 0 || stopIdx > convergeIdx {
		t.Fatalf("live app/worker/rest must be stopped before the database convergence (smart shutdown would wait on their sessions and be SIGKILLed): stop=%d converge=%d\n%s", stopIdx, convergeIdx, log)
	}
	verifyAfterStop := strings.Index(log[stopIdx:], "compose ps -a --format json\n")
	if verifyAfterStop < 0 || stopIdx+verifyAfterStop > convergeIdx {
		t.Fatalf("the stop must be positively verified before the database convergence:\n%s", log)
	}
	if startIdx < convergeIdx {
		t.Fatalf("the serving tier must start after the database convergence: converge=%d start=%d\n%s", convergeIdx, startIdx, log)
	}

	// F3: the listener reading the replaced session was stopped (not left to
	// error on the closed socket and trigger the main loop's errCh reconnect,
	// which would close the sessions the convergence just reopened), and the
	// guard is clear, so the main loop's `if d.listenCancel == nil` restarts the
	// listener on the NEW session.
	select {
	case <-oldListenDone:
	case <-time.After(time.Second):
		t.Fatal("the listenLoop reading the replaced listen session is still running; it was not stopped before its connection was closed")
	}
	if d.listenCancel != nil || d.listenDone != nil {
		t.Fatal("the listenLoop guard still looks live after its connection was replaced; the main loop would not restart the listener on the new session")
	}
	if d.queryConn == nil || d.listenConn == nil {
		t.Fatal("successful convergence must leave the daemon connected")
	}
}

// TestSourceDatabaseConvergenceHealthWaitAdvancesProgress is F4. The PreSwap
// caller runs under the gated watchdog ticker (3 min stall threshold); a
// recreated container's readiness wait may take minutes, and each completed
// probe is real progress.
func TestSourceDatabaseConvergenceHealthWaitAdvancesProgress(t *testing.T) {
	f := newSourceDBConvergeFixture(t, "ok", "exited")
	upGate := filepath.Join(f.shimDir, "release-db-up")
	healthGate := filepath.Join(f.shimDir, "release-health")
	t.Setenv("STATBUS_TEST_DB_UP_GATE", upGate)
	t.Setenv("STATBUS_TEST_HEALTH_GATE", healthGate)
	t.Setenv("STATBUS_TEST_UNREADY_PROBES", "2") // probe 1 fails, probe 2 blocks on the gate
	sourceDatabaseConvergeHealthTimeout = time.Minute
	progress, _ := sourceStackTestProgress(t, f.git.dir)

	done := make(chan error, 1)
	go func() { done <- f.svc.convergeSourceDatabaseContainer(context.Background(), progress) }()
	waitForFile := func(path string) {
		t.Helper()
		deadline := time.Now().Add(20 * time.Second)
		for time.Now().Before(deadline) {
			if _, err := os.Stat(path); err == nil {
				return
			}
			select {
			case err := <-done:
				t.Fatalf("convergence returned early (%v) before %s", err, filepath.Base(path))
			case <-time.After(20 * time.Millisecond):
			}
		}
		t.Fatalf("timed out waiting for %s", path)
	}
	waitForFile(filepath.Join(f.shimDir, "db-up-entered"))
	// Everything before the wait (client verification, the compose up) has
	// advanced progress already. Age it, then let the health wait run.
	progress.setLastAdvanceForTest(time.Now().Add(-time.Hour))
	if err := os.WriteFile(upGate, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	// Probe 2 is entered only after probe 1 completed (and the 2 s pacing).
	deadline := time.Now().Add(20 * time.Second)
	for {
		data, _ := os.ReadFile(filepath.Join(f.shimDir, "post-converge-probes"))
		if strings.TrimSpace(string(data)) == "2" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("timed out waiting for the second readiness probe")
		}
		time.Sleep(20 * time.Millisecond)
	}
	stale := progress.sinceLastAdvance()
	if err := os.WriteFile(healthGate, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := <-done; err != nil {
		t.Fatalf("convergeSourceDatabaseContainer: %v", err)
	}
	if stale > time.Minute {
		t.Fatalf("progress was last advanced %s ago during the readiness wait; the gated watchdog (stall threshold %s) would stop pinging a wait that is advancing", stale.Round(time.Second), applyNewSbUpgradingStallThreshold)
	}
}
