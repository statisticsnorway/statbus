package upgrade

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgproto3"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
	"github.com/statisticsnorway/statbus/cli/internal/selfupdate"
)

// Protocol boundary only: production claim/execute/terminal methods are unmodified.
// No real database, Docker daemon, GitHub requests or operator state are touched.
type astraClaimDB struct {
	mu                       sync.Mutex
	parked                   bool
	displacedPending         bool
	convergenceRequired      bool
	otherConvergenceRequired bool
	preColumn                bool
	// Modeled migrate_up advisory key. The claim takes its transaction-scoped
	// form; a modeled migration session takes its session-scoped form. Either
	// holder blocks the other until release: the claim releases on commit AND
	// rollback (PostgreSQL semantics), the migration on its commit.
	claimHoldsMigrateLock     bool
	claimMigrateLockReleased  chan struct{}
	migrationHoldsMigrateLock bool
	migrationLockReleased     chan struct{}
	migrationReady            chan struct{}
	migrationCommitted        chan struct{}
	// floorAppliedPath models the daemon-floor migrate subprocess landing the
	// column: the ./sb shim writes this file, and the catalog probe treats its
	// presence as the column existing.
	floorAppliedPath                 string
	state, target, from, lastFailure string
	queries                          []string
}

func (s *astraClaimDB) snapshot() (bool, bool, string, string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.parked, s.convergenceRequired || s.otherConvergenceRequired, s.state, s.lastFailure
}

func (s *astraClaimDB) scheduleReplacement(target string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	// Model public.upgrade_schedule(D): C is superseded but retains its true bit,
	// while the new scheduled D row begins with the migration default false.
	s.otherConvergenceRequired = s.convergenceRequired
	s.convergenceRequired = false
	s.state = "scheduled"
	s.target = target
}

// migrateTreeConvergenceColumn models the migration subsystem's independent
// session: it must acquire the same advisory key as the claim before the new
// column can commit. The channels make the interleaving deterministic rather
// than timing-dependent: migrationReady closes once the migration is either
// blocked on the claim's key or free to run, migrationCommitted once the column
// has landed.
func (s *astraClaimDB) migrateTreeConvergenceColumn() {
	s.mu.Lock()
	blocked := s.claimHoldsMigrateLock
	released := s.claimMigrateLockReleased
	ready := s.migrationReady
	committed := s.migrationCommitted
	s.mu.Unlock()

	if blocked {
		close(ready)
		<-released
		s.mu.Lock()
		s.preColumn = false
		s.mu.Unlock()
		close(committed)
		return
	}

	// This is the old two-lock shape: migrate_up does not conflict with the
	// claim's upgrade_daemon lock, so the column lands while the paused claim
	// remains committed to legacy SQL.
	s.mu.Lock()
	s.preColumn = false
	s.mu.Unlock()
	close(committed)
	close(ready)
}

// holdMigrationLock models a migration session that already owns the
// session-scoped migrate_up key before the claim begins. The claim's
// transaction-scoped acquisition must block until commitHeldMigration.
func (s *astraClaimDB) holdMigrationLock() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.migrationHoldsMigrateLock = true
	s.migrationLockReleased = make(chan struct{})
}

// commitHeldMigration lands the column and releases the session key taken by
// holdMigrationLock, waking any claim blocked on it.
func (s *astraClaimDB) commitHeldMigration() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.preColumn = false
	s.migrationHoldsMigrateLock = false
	close(s.migrationLockReleased)
}

// releaseClaimMigrateLockLocked is the modeled auto-release of the claim's
// transaction-scoped key. Called with s.mu held, on commit and on rollback.
func (s *astraClaimDB) releaseClaimMigrateLockLocked() {
	if !s.claimHoldsMigrateLock {
		return
	}
	s.claimHoldsMigrateLock = false
	if s.claimMigrateLockReleased != nil {
		close(s.claimMigrateLockReleased)
		s.claimMigrateLockReleased = nil
	}
}

// hasTreeConvergenceColumnLocked is the modeled pg_attribute observation. The
// column exists once the modeled migration committed OR the daemon-floor
// migrate subprocess (the ./sb shim) landed it.
func (s *astraClaimDB) hasTreeConvergenceColumnLocked() bool {
	if s.preColumn && s.floorAppliedPath != "" {
		if _, err := os.Stat(s.floorAppliedPath); err == nil {
			s.preColumn = false
		}
	}
	return !s.preColumn
}

// claimFloorMigrateShim is the ./sb the claim's floor-apply step launches in
// projDir. It records its exact arguments, models the session-scoped migrate_up
// wait when a modeled migration is in flight (STATBUS_TEST_MODELED_MIGRATION_*
// files), and lands the column by writing the floor-applied marker. A
// deterministic-failure file makes it exit with migrate.ExitDeterministic
// without landing anything, exactly like a broken floor migration.
const claimFloorMigrateShim = `#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$STATBUS_TEST_FLOOR_SHIM_LOG"
if [ -f "$STATBUS_TEST_FLOOR_FAIL_DETERMINISTIC" ]; then
  echo 'shim: floor migration SQL failed deterministically' >&2
  exit 20
fi
if [ -f "$STATBUS_TEST_MODELED_MIGRATION_PENDING" ]; then
  i=0
  until [ -f "$STATBUS_TEST_MODELED_MIGRATION_COMMITTED" ]; do
    i=$((i+1)); if [ "$i" -gt 500 ]; then echo 'shim: modeled migration never committed' >&2; exit 1; fi
    sleep 0.01
  done
fi
touch "$STATBUS_TEST_FLOOR_APPLIED"
`

type claimFloorShimPaths struct {
	log, applied, failDeterministic, migrationPending, migrationCommitted string
}

// installClaimFloorMigrateShim places the ./sb shim and this binary's floor
// migration file into projDir so the production floor-apply step (DiskVersions
// check + `./sb migrate up --to floor`) runs against a modeled boundary.
func installClaimFloorMigrateShim(t *testing.T, projDir string, withFloorMigrationOnDisk bool) claimFloorShimPaths {
	t.Helper()
	tmp := filepath.Join(projDir, "tmp")
	if err := os.MkdirAll(tmp, 0o755); err != nil {
		t.Fatal(err)
	}
	paths := claimFloorShimPaths{
		log:                filepath.Join(tmp, "floor-shim.log"),
		applied:            filepath.Join(tmp, "floor-applied"),
		failDeterministic:  filepath.Join(tmp, "floor-fail-deterministic"),
		migrationPending:   filepath.Join(tmp, "modeled-migration-pending"),
		migrationCommitted: filepath.Join(tmp, "modeled-migration-committed"),
	}
	t.Setenv("STATBUS_TEST_FLOOR_SHIM_LOG", paths.log)
	t.Setenv("STATBUS_TEST_FLOOR_APPLIED", paths.applied)
	t.Setenv("STATBUS_TEST_FLOOR_FAIL_DETERMINISTIC", paths.failDeterministic)
	t.Setenv("STATBUS_TEST_MODELED_MIGRATION_PENDING", paths.migrationPending)
	t.Setenv("STATBUS_TEST_MODELED_MIGRATION_COMMITTED", paths.migrationCommitted)
	if err := os.WriteFile(filepath.Join(projDir, "sb"), []byte(claimFloorMigrateShim), 0o755); err != nil {
		t.Fatal(err)
	}
	if withFloorMigrationOnDisk {
		if err := os.MkdirAll(filepath.Join(projDir, "migrations"), 0o755); err != nil {
			t.Fatal(err)
		}
		name := fmt.Sprintf("%d_persist_serving_tree_convergence_obligation.up.sql", migrate.DaemonSchemaFloor)
		if err := os.WriteFile(filepath.Join(projDir, "migrations", name), []byte("-- fixture copy of the floor migration\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return paths
}

func readClaimFloorShimLog(t *testing.T, paths claimFloorShimPaths) string {
	t.Helper()
	data, err := os.ReadFile(paths.log)
	if os.IsNotExist(err) {
		return ""
	}
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func astraClaimConnection(t *testing.T, s *astraClaimDB) *pgx.Conn {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = ln.Close() })
	go func() {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		defer func() { _ = conn.Close() }()
		b := pgproto3.NewBackend(conn, conn)
		if _, err = b.ReceiveStartupMessage(); err != nil {
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
		for {
			m, err := b.Receive()
			if err != nil {
				return
			}
			if _, ok := m.(*pgproto3.Terminate); ok {
				return
			}
			q, ok := m.(*pgproto3.Query)
			if !ok {
				t.Errorf("unexpected PG message %T", m)
				return
			}
			s.mu.Lock()
			s.queries = append(s.queries, q.String)
			text := strings.TrimSpace(q.String)
			tag := "SELECT 0"
			var row []string
			var oids []uint32
			var pgErrorCode string
			switch {
			case text == "begin":
				tag = "BEGIN"
			case text == "commit":
				s.releaseClaimMigrateLockLocked()
				tag = "COMMIT"
			case text == "rollback":
				s.releaseClaimMigrateLockLocked()
				tag = "ROLLBACK"
			case strings.Contains(text, "SELECT pg_try_advisory_xact_lock"):
				row = []string{"t"}
				oids = []uint32{16}
				tag = "SELECT 1"
			case strings.Contains(text, "SELECT pg_advisory_xact_lock(hashtext('migrate_up'))"):
				// A migration session owning the key blocks the claim until its
				// commit; the wait happens without the fixture mutex so the
				// migration's commit can proceed.
				if s.migrationHoldsMigrateLock {
					wait := s.migrationLockReleased
					s.mu.Unlock()
					<-wait
					s.mu.Lock()
				}
				s.claimHoldsMigrateLock = true
				row = []string{""}
				oids = []uint32{2278}
				tag = "SELECT 1"
			case strings.Contains(text, "FROM pg_catalog.pg_attribute") && strings.Contains(text, "tree_convergence_required"):
				row = []string{map[bool]string{false: "f", true: "t"}[s.hasTreeConvergenceColumnLocked()]}
				oids = []uint32{16}
				tag = "SELECT 1"
			case strings.HasPrefix(text, "SELECT id FROM public.upgrade WHERE"):
				// No rollback finishing record.
			case strings.HasPrefix(text, "SELECT id, COALESCE(recovery_parked_reason"):
				if s.parked {
					row = []string{"1", "disk park B"}
					oids = []uint32{23, 25}
					tag = "SELECT 1"
				}
			case strings.HasPrefix(text, "UPDATE public.upgrade") && strings.Contains(text, "SET state = 'superseded'"):
				s.parked = false
				s.displacedPending = true
				tag = "UPDATE 1"
			case strings.HasPrefix(text, "WITH claimed AS"):
				fallthrough
			case strings.HasPrefix(text, "WITH box_obligation AS MATERIALIZED"):
				if s.state == "scheduled" {
					s.state = "in_progress"
					usesDurableObligation := strings.Contains(text, "tree_convergence_required")
					if s.preColumn && usesDurableObligation {
						pgErrorCode = "42703"
						break
					}
					if usesDurableObligation && s.displacedPending {
						s.convergenceRequired = true
					}
					if strings.Contains(text, "(SELECT required FROM box_obligation)") && s.otherConvergenceRequired {
						s.convergenceRequired = true
					}
					s.displacedPending = false
					claimID := 33
					commitVersion := "v2026.09.99"
					if s.target == strings.Repeat("d", 40) {
						claimID = 44
						commitVersion = "v2026.09.100"
					}
					snap, _ := json.Marshal(map[string]any{"id": claimID, "commit_version": commitVersion, "commit_sha": s.target, "from_commit_version": s.from, "started_at": "2026-09-21T22:00:00Z"})
					row = []string{"{" + commitVersion + "}", "f", fmt.Sprint(claimID), commitVersion, s.target, s.from, "2026-09-21 22:00:00+00"}
					oids = []uint32{1009, 16, 23, 25, 25, 25, 1184}
					if usesDurableObligation {
						row = append(row, map[bool]string{false: "f", true: "t"}[s.convergenceRequired])
						oids = append(oids, 16)
					}
					row = append(row, string(snap))
					oids = append(oids, 25)
					tag = "SELECT 1"
				}
			case strings.HasPrefix(text, "UPDATE public.upgrade") && strings.Contains(text, "SET tree_convergence_required = false"):
				if s.convergenceRequired || s.otherConvergenceRequired {
					s.convergenceRequired = false
					s.otherConvergenceRequired = false
					tag = "UPDATE 2"
				}
			case strings.HasPrefix(text, "UPDATE public.upgrade") && strings.Contains(text, "state = 'scheduled'") && strings.Contains(text, "state IN ('in_progress', 'failed')"):
				if s.state == "in_progress" || s.state == "failed" {
					s.state = "scheduled"
					tag = "UPDATE 1"
				}
			case strings.Contains(text, "bool_or(tree_convergence_required)"):
				if s.preColumn {
					pgErrorCode = "42703"
					break
				}
				row = []string{map[bool]string{false: "f", true: "t"}[s.convergenceRequired || s.otherConvergenceRequired], s.state}
				oids = []uint32{16, 25}
				tag = "SELECT 1"
			case strings.HasPrefix(text, "UPDATE public.upgrade SET log_relative_file_path"):
				tag = "UPDATE 1"
			case strings.HasPrefix(text, "UPDATE public.upgrade SET state = 'scheduled'"):
				s.state = "scheduled"
				tag = "UPDATE 1"
			case strings.HasPrefix(text, "SELECT to_jsonb(u)::text"):
				// A missing optional diagnostic row avoids exercising the bundle shell.
			case strings.HasPrefix(text, "UPDATE public.upgrade SET state = 'failed'"):
				s.state = "failed"
				s.lastFailure = text
				row = []string{`{"id":33,"state":"failed"}`}
				oids = []uint32{25}
				tag = "UPDATE 1"
			default:
				t.Errorf("unexpected SQL at review protocol boundary: %s", text)
			}
			if pgErrorCode != "" {
				b.Send(&pgproto3.ErrorResponse{Severity: "ERROR", Code: pgErrorCode, Message: `column "tree_convergence_required" does not exist`})
				b.Send(&pgproto3.ReadyForQuery{TxStatus: 'I'})
				s.mu.Unlock()
				if b.Flush() != nil {
					return
				}
				continue
			}
			if row != nil {
				fields := make([]pgproto3.FieldDescription, len(row))
				values := make([][]byte, len(row))
				for i, v := range row {
					fields[i] = pgproto3.FieldDescription{Name: []byte(fmt.Sprintf("col%d", i)), DataTypeOID: oids[i], DataTypeSize: -1, TypeModifier: -1}
					values[i] = []byte(v)
				}
				b.Send(&pgproto3.RowDescription{Fields: fields})
				b.Send(&pgproto3.DataRow{Values: values})
			}
			b.Send(&pgproto3.CommandComplete{CommandTag: []byte(tag)})
			b.Send(&pgproto3.ReadyForQuery{TxStatus: 'I'})
			s.mu.Unlock()
			if b.Flush() != nil {
				return
			}
		}
	}()
	cfg, err := pgx.ParseConfig("postgres://review@" + ln.Addr().String() + "/review?sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	cfg.DefaultQueryExecMode = pgx.QueryExecModeSimpleProtocol
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	c, err := pgx.ConnectConfig(ctx, cfg)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = c.Close(context.Background()) })
	return c
}

type astraRoundTrip func(*http.Request) (*http.Response, error)

func (f astraRoundTrip) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func astraManifestBoundary(t *testing.T, unavailable *bool) {
	t.Helper()
	original := http.DefaultTransport
	http.DefaultTransport = astraRoundTrip(func(r *http.Request) (*http.Response, error) {
		if !strings.Contains(r.URL.Path, "release-manifest.json") {
			return original.RoundTrip(r)
		}
		status := 200
		body := fmt.Sprintf(`{"binaries":{"%s":{"url":"https://invalid.test/unused","sha256":"unused"}}}`, selfupdate.Platform())
		if *unavailable {
			status = 404
			body = "unavailable"
		}
		return &http.Response{StatusCode: status, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(body)), Request: r}, nil
	})
	t.Cleanup(func() { http.DefaultTransport = original })
}
func astraSignatureBoundary(t *testing.T) {
	t.Helper()
	realGit, err := exec.LookPath("git")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	script := "#!/bin/sh\ncase \"$*\" in *verify-commit*) echo 'review signature-boundary success'; exit 0;; esac\nexec '" + realGit + "' \"$@\"\n"
	if err := os.WriteFile(filepath.Join(dir, "git"), []byte(script), 0755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
}
func TestAstraClosureActualConvergenceFailureIsTerminal(t *testing.T) {
	git := newGitRepoFixture(t)
	t.Setenv("HOME", t.TempDir())
	logPath := installParkedSuccessorConvergenceShim(t, git.newSHA[:8], git.oldSHA[:8], true)
	astraSignatureBoundary(t)
	unavailable := false
	astraManifestBoundary(t, &unavailable)
	db := &astraClaimDB{parked: true, state: "scheduled", target: strings.Repeat("c", 40), from: git.newSHA}
	d := &Service{projDir: git.dir, version: git.newSHA, queryConn: astraClaimConnection(t, db), allowedSignersPath: "review-boundary"}
	claim, err := d.claimScheduledUpgrade(context.Background(), 33)
	if err != nil {
		t.Fatal(err)
	}
	if !claim.Snapshot.RequiresServingTreeConvergence {
		t.Fatal("displaced claim lost convergence")
	}
	err = d.executeUpgrade(context.Background(), claim.Snapshot, "v2026.09.99", claim.CommitTags, "scheduled", "scheduled", false)
	if err == nil || !strings.Contains(err.Error(), "PARKED_SERVING_TREE_CONVERGENCE_FAILED") {
		t.Fatalf("wrong terminal: %v", err)
	}
	parked, required, state, failure := db.snapshot()
	if parked || !required || state != "failed" || !strings.Contains(failure, "PARKED_SERVING_TREE_CONVERGENCE_FAILED") {
		t.Fatalf("terminal did not land with durable retry: parked=%t required=%t state=%s SQL=%s", parked, required, state, failure)
	}
	if flag, err := ReadFlagFile(git.dir); err != nil || flag == nil {
		t.Fatalf("terminal marker not retained for ./sb install repair: flag=%#v err=%v", flag, err)
	}
	if got := strings.Count(readParkedTargetDockerLog(t, logPath), "compose up -d --no-build --no-deps app worker rest proxy\n"); got != 1 {
		t.Fatalf("convergence repeated: %d", got)
	}
	if _, err := os.Stat(sourceServingImagesCarrierPath(git.dir)); !os.IsNotExist(err) {
		t.Fatalf("capture ran despite convergence failure: %v", err)
	}
	log := readParkedTargetDockerLog(t, logPath)
	upIdx := strings.Index(log, "compose up -d --no-build --no-deps app worker rest proxy\n")
	stopIdx := strings.Index(log, "compose stop app worker rest\n")
	postVerifyIdx := strings.LastIndex(log, "compose ps -a --format json\n")
	if upIdx < 0 || stopIdx < upIdx || postVerifyIdx < stopIdx {
		t.Fatalf("partial convergence containment must be failed up -> stop -> positive reinspection:\n%s", log)
	}
	t.Logf("real claim -> execute -> contained failure writer: %v; DB state=%s, marker retained, one up, no capture", err, state)
}
func TestAstraClosureManifestRetryMustRetainConvergence(t *testing.T) {
	git := newGitRepoFixture(t)
	t.Setenv("HOME", t.TempDir())
	writeParkedSourceIdentityFlag(t, git.dir, git.newSHA, git.oldSHA[:8])
	writeParkedSourceIdentityCarrier(t, git.dir, git.newSHA, git.oldSHA[:8])
	logPath := installParkedSuccessorConvergenceShim(t, git.newSHA[:8], git.oldSHA[:8], false)
	srv, _ := sourceStackHealthServer(t)
	astraSignatureBoundary(t)
	unavailable := true
	astraManifestBoundary(t, &unavailable)
	db := &astraClaimDB{parked: true, state: "scheduled", target: strings.Repeat("c", 40), from: git.newSHA}
	d := &Service{projDir: git.dir, version: git.newSHA, queryConn: astraClaimConnection(t, db), allowedSignersPath: "review-boundary", cachedURL: srv.URL + "/rpc/auth_status", cachedReadyURL: srv.URL + "/ready"}
	first, err := d.claimScheduledUpgrade(context.Background(), 33)
	if err != nil {
		t.Fatal(err)
	}
	if !first.Snapshot.RequiresServingTreeConvergence {
		t.Fatal("first claim did not displace fixture park")
	}
	err = d.executeUpgrade(context.Background(), first.Snapshot, "v2026.09.99", first.CommitTags, "scheduled", "scheduled", false)
	if err != nil {
		t.Fatalf("manifest unavailable must reschedule: %v", err)
	}
	parked, _, state, _ := db.snapshot()
	if parked || state != "scheduled" {
		t.Fatalf("reset shape: parked=%t C=%s", parked, state)
	}
	second, err := d.claimScheduledUpgrade(context.Background(), 33)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("first displacement requires convergence=%t; manifest reset; second claim convergence=%t", first.Snapshot.RequiresServingTreeConvergence, second.Snapshot.RequiresServingTreeConvergence)
	unavailable = false
	err = d.executeUpgrade(context.Background(), second.Snapshot, "v2026.09.99", second.CommitTags, "scheduled", "scheduled", false)
	log := readParkedTargetDockerLog(t, logPath)
	_, _, state, _ = db.snapshot()
	t.Logf("second actual execute result: %v; C state=%s; Docker transcript:\n%s", err, state, log)
	if strings.Contains(fmt.Sprint(err), "current tree is neither the captured source compose model") {
		t.Fatalf("original B/A/C capture deadlock remains after ordinary manifest retry: ephemeral convergence obligation was lost; error=%v", err)
	}
	if !second.Snapshot.RequiresServingTreeConvergence {
		t.Fatal("successor retry lost its convergence obligation")
	}
}

func TestNewCandidateInheritsBoxConvergenceAfterManifestRetry(t *testing.T) {
	git := newGitRepoFixture(t)
	t.Setenv("HOME", t.TempDir())
	writeParkedSourceIdentityFlag(t, git.dir, git.newSHA, git.oldSHA[:8])
	writeParkedSourceIdentityCarrier(t, git.dir, git.newSHA, git.oldSHA[:8])
	logPath := installParkedSuccessorConvergenceShim(t, git.newSHA[:8], git.oldSHA[:8], false)
	srv, _ := sourceStackHealthServer(t)
	astraSignatureBoundary(t)
	unavailable := true
	astraManifestBoundary(t, &unavailable)
	db := &astraClaimDB{parked: true, state: "scheduled", target: strings.Repeat("c", 40), from: git.newSHA}
	d := &Service{projDir: git.dir, version: git.newSHA, queryConn: astraClaimConnection(t, db), allowedSignersPath: "review-boundary", cachedURL: srv.URL + "/rpc/auth_status", cachedReadyURL: srv.URL + "/ready"}

	claimC, err := d.claimScheduledUpgrade(context.Background(), 33)
	if err != nil {
		t.Fatal(err)
	}
	if err := d.executeUpgrade(context.Background(), claimC.Snapshot, "v2026.09.99", claimC.CommitTags, "scheduled", "scheduled", false); err != nil {
		t.Fatalf("C manifest wait must reschedule cleanly: %v", err)
	}
	// The protocol fixture models the real public.upgrade_schedule(D) transition:
	// C becomes superseded with its true carrier bit; D is newly scheduled false.
	db.scheduleReplacement(strings.Repeat("d", 40))
	claimD, err := d.claimScheduledUpgrade(context.Background(), 44)
	if err != nil {
		t.Fatal(err)
	}
	if !claimD.Snapshot.RequiresServingTreeConvergence {
		t.Fatal("D did not inherit the box convergence obligation stranded on superseded C")
	}

	unavailable = false
	err = d.executeUpgrade(context.Background(), claimD.Snapshot, "v2026.09.100", claimD.CommitTags, "scheduled", "scheduled", false)
	if strings.Contains(fmt.Sprint(err), "current tree is neither the captured source compose model") {
		t.Fatalf("D reproduced the original B-tree/A-serving capture deadlock: %v", err)
	}
	if got := strings.Count(readParkedTargetDockerLog(t, logPath), "compose up -d --no-build --no-deps app worker rest proxy\n"); got != 1 {
		t.Fatalf("D convergence attempts = %d, want 1", got)
	}
	carrier, readErr := readSourceServingImagesCarrier(git.dir)
	if readErr != nil || carrier == nil || carrier.ID != 44 || carrier.CommitSHA != strings.Repeat("d", 40) {
		t.Fatalf("D capture did not bind the converged B baseline: carrier=%#v err=%v execute=%v", carrier, readErr, err)
	}
	_, required, _, _ := db.snapshot()
	if required {
		t.Fatal("positive D convergence did not clear every box-obligation carrier")
	}
}

func TestPreColumnClaimAndRecoveryReadUseLegacyNoObligationBehavior(t *testing.T) {
	db := &astraClaimDB{preColumn: true, state: "scheduled", target: strings.Repeat("c", 40), from: strings.Repeat("b", 40)}
	d := &Service{projDir: t.TempDir(), version: strings.Repeat("b", 40), queryConn: astraClaimConnection(t, db)}
	claim, err := d.claimScheduledUpgrade(context.Background(), 33)
	if err != nil {
		t.Fatalf("claim against the pre-migration schema failed: %v", err)
	}
	if claim.Snapshot.RequiresServingTreeConvergence {
		t.Fatal("pre-column schema invented a convergence obligation")
	}
	required, state, err := d.servingTreeConvergenceObligation(context.Background(), 33)
	if err != nil || required || state != "" {
		t.Fatalf("pre-column 42703 compatibility read = required:%t state:%q err:%v", required, state, err)
	}
}

// assertParkDisplacementCarriesObligation is the end-state oracle every
// pre-column park test shares: after the claim and any concurrent migration have
// both finished, the park is displaced ONLY IF a true obligation carrier exists,
// and the returned snapshot agrees with the durable bit. An obligation-less
// displacement is the exact failure class Astra's claim-first probe reproduced.
func assertParkDisplacementCarriesObligation(t *testing.T, label string, db *astraClaimDB, claim scheduledUpgradeClaim) {
	t.Helper()
	parked, required, state, _ := db.snapshot()
	if parked {
		t.Fatalf("%s: park was not displaced: state=%s", label, state)
	}
	if state != "in_progress" {
		t.Fatalf("%s: candidate not claimed: state=%s", label, state)
	}
	if !required {
		t.Fatalf("%s: OBLIGATION-LESS COMMIT: park displaced with zero true carriers", label)
	}
	if !claim.Snapshot.RequiresServingTreeConvergence {
		t.Fatalf("%s: durable carrier exists but the returned snapshot is false", label)
	}
}

// claimQueryOrder returns the indexes of the claim's key statements in the
// fixture's query log: the LAST migrate_up acquisition, catalog probe,
// displacement, and commit (the last transactional pass is the one that lands).
func claimQueryOrder(db *astraClaimDB) (queries []string, lockIndex, probeIndex, displacementIndex, commitIndex, rollbackCount int) {
	db.mu.Lock()
	queries = append([]string(nil), db.queries...)
	db.mu.Unlock()
	lockIndex, probeIndex, displacementIndex, commitIndex = -1, -1, -1, -1
	for i, query := range queries {
		switch {
		case strings.Contains(query, "pg_advisory_xact_lock(hashtext('migrate_up'))"):
			lockIndex = i
		case strings.Contains(query, "FROM pg_catalog.pg_attribute"):
			probeIndex = i
		case strings.Contains(query, "SET state = 'superseded'"):
			displacementIndex = i
		case strings.TrimSpace(query) == "commit":
			commitIndex = i
		case strings.TrimSpace(query) == "rollback":
			rollbackCount++
		}
	}
	return queries, lockIndex, probeIndex, displacementIndex, commitIndex, rollbackCount
}

// TestPreColumnParkClaimFirstNeverCommitsObligationless is Astra's claim-first
// interleaving, made deterministic with a barrier: the claim wins migrate_up,
// observes the column ABSENT, and is paused; only then does the migration start
// and (correctly) block on the key. Before this fix the paused claim went on to
// commit a legacy displacement, the migration then landed DEFAULT false, and the
// box had zero obligation carriers. Now the pass refuses without writing, the
// claim applies the floor through ./sb (which waits for the in-flight migration
// on the same session key), and one fresh pass observes the column and records
// the obligation atomically with the displacement.
func TestPreColumnParkClaimFirstNeverCommitsObligationless(t *testing.T) {
	for attempt := 1; attempt <= 25; attempt++ {
		projDir := t.TempDir()
		shim := installClaimFloorMigrateShim(t, projDir, true)
		db := &astraClaimDB{
			parked:             true,
			preColumn:          true,
			state:              "scheduled",
			target:             strings.Repeat("c", 40),
			from:               strings.Repeat("b", 40),
			migrationReady:     make(chan struct{}),
			migrationCommitted: make(chan struct{}),
			floorAppliedPath:   shim.applied,
		}
		db.claimMigrateLockReleased = make(chan struct{})
		probeObserved := make(chan struct{})
		allowClaim := make(chan struct{})
		var probeOnce sync.Once
		d := &Service{
			projDir:   projDir,
			version:   strings.Repeat("b", 40),
			queryConn: astraClaimConnection(t, db),
			claimSchemaProbeForTest: func(hasColumn bool) {
				probeOnce.Do(func() {
					if hasColumn {
						t.Errorf("attempt %d: first probe unexpectedly saw the new column", attempt)
					}
					close(probeObserved)
					<-allowClaim
				})
			},
		}
		// The ./sb floor shim must not land the column before the modeled
		// migration commits: it models the session-scoped migrate_up wait.
		if err := os.WriteFile(shim.migrationPending, []byte("pending\n"), 0o600); err != nil {
			t.Fatal(err)
		}

		claimDone := make(chan error, 1)
		var claim scheduledUpgradeClaim
		go func() {
			c, err := d.claimScheduledUpgrade(context.Background(), 33)
			claim = c
			claimDone <- err
		}()
		<-probeObserved
		go db.migrateTreeConvergenceColumn()
		<-db.migrationReady
		select {
		case <-db.migrationCommitted:
			close(allowClaim)
			<-claimDone
			t.Fatalf("attempt %d: migration committed while the claim held migrate_up", attempt)
		default:
		}
		close(allowClaim)
		// The migration lands as soon as the refused pass rolls back and releases
		// the key; the floor shim waits for exactly that before it may land.
		select {
		case <-db.migrationCommitted:
		case <-time.After(5 * time.Second):
			t.Fatalf("attempt %d: migration never resumed after the refused pass released migrate_up", attempt)
		}
		if err := os.WriteFile(shim.migrationCommitted, []byte("committed\n"), 0o600); err != nil {
			t.Fatal(err)
		}
		select {
		case err := <-claimDone:
			if err != nil {
				t.Fatalf("attempt %d: claim after floor apply failed: %v", attempt, err)
			}
		case <-time.After(10 * time.Second):
			t.Fatalf("attempt %d: claim did not finish", attempt)
		}

		assertParkDisplacementCarriesObligation(t, fmt.Sprintf("attempt %d", attempt), db, claim)
		queries, lockIndex, probeIndex, displacementIndex, commitIndex, rollbacks := claimQueryOrder(db)
		if lockIndex < 0 || probeIndex <= lockIndex || displacementIndex <= probeIndex || commitIndex <= displacementIndex {
			t.Fatalf("attempt %d: landing pass lock/probe/displacement/commit order is unsafe: lock=%d probe=%d displacement=%d commit=%d\nqueries=%v", attempt, lockIndex, probeIndex, displacementIndex, commitIndex, queries)
		}
		if strings.Count(strings.Join(queries, "\n"), "SET state = 'superseded'") != 1 {
			t.Fatalf("attempt %d: displacement must be written exactly once, on the durable pass:\n%v", attempt, queries)
		}
		if rollbacks < 1 {
			t.Fatalf("attempt %d: the refused pre-column pass must roll back before the floor apply:\n%v", attempt, queries)
		}
		if got := readClaimFloorShimLog(t, shim); !strings.Contains(got, fmt.Sprintf("migrate up --to %d --verbose", migrate.DaemonSchemaFloor)) {
			t.Fatalf("attempt %d: floor apply must run the bounded daemon-floor migrate; shim log:\n%s", attempt, got)
		}
	}
}

// TestPreColumnParkMigrationFirstWaitsThenClaimsDurably is Luna's ordering: the
// migration owns the session migrate_up key before the claim begins. The claim's
// transaction-scoped acquisition must wait, then observe the column PRESENT and
// record the obligation on its first pass, with no floor subprocess at all.
func TestPreColumnParkMigrationFirstWaitsThenClaimsDurably(t *testing.T) {
	for attempt := 1; attempt <= 25; attempt++ {
		projDir := t.TempDir()
		shim := installClaimFloorMigrateShim(t, projDir, true)
		db := &astraClaimDB{
			parked:           true,
			preColumn:        true,
			state:            "scheduled",
			target:           strings.Repeat("c", 40),
			from:             strings.Repeat("b", 40),
			floorAppliedPath: shim.applied,
		}
		db.holdMigrationLock()
		lockRequested := make(chan struct{})
		var lockOnce sync.Once
		d := &Service{projDir: projDir, version: strings.Repeat("b", 40), queryConn: astraClaimConnection(t, db)}
		d.claimSchemaProbeForTest = func(hasColumn bool) {
			if !hasColumn {
				t.Errorf("attempt %d: probe ran before the in-flight migration committed", attempt)
			}
		}
		claimDone := make(chan error, 1)
		var claim scheduledUpgradeClaim
		go func() {
			c, err := d.claimScheduledUpgrade(context.Background(), 33)
			claim = c
			claimDone <- err
		}()
		// Positively observe the claim waiting on the key before the migration
		// commits, then release it.
		deadline := time.After(5 * time.Second)
	wait:
		for {
			db.mu.Lock()
			for _, q := range db.queries {
				if strings.Contains(q, "pg_advisory_xact_lock(hashtext('migrate_up'))") {
					lockOnce.Do(func() { close(lockRequested) })
				}
			}
			db.mu.Unlock()
			select {
			case <-lockRequested:
				break wait
			case <-deadline:
				t.Fatalf("attempt %d: claim never requested migrate_up", attempt)
			case <-time.After(time.Millisecond):
			}
		}
		select {
		case err := <-claimDone:
			t.Fatalf("attempt %d: claim finished while the migration still held migrate_up: %v", attempt, err)
		default:
		}
		db.commitHeldMigration()
		select {
		case err := <-claimDone:
			if err != nil {
				t.Fatalf("attempt %d: claim after waiting migration failed: %v", attempt, err)
			}
		case <-time.After(10 * time.Second):
			t.Fatalf("attempt %d: claim did not finish after the migration released migrate_up", attempt)
		}
		assertParkDisplacementCarriesObligation(t, fmt.Sprintf("attempt %d", attempt), db, claim)
		if got := readClaimFloorShimLog(t, shim); got != "" {
			t.Fatalf("attempt %d: migration-first must not run a floor subprocess; shim log:\n%s", attempt, got)
		}
	}
}

// TestPreColumnParkClaimAppliesFloorBeforeDisplacing is the no-concurrency
// case: a new binary claims a fix release against a parked box whose schema is
// still the predecessor's (the parked-skip boot never ran the floor). The claim
// must apply the floor itself and then displace with the obligation recorded.
func TestPreColumnParkClaimAppliesFloorBeforeDisplacing(t *testing.T) {
	projDir := t.TempDir()
	shim := installClaimFloorMigrateShim(t, projDir, true)
	writeParkedSourceIdentityFlag(t, projDir, strings.Repeat("b", 40), "aaaaaaaa")
	db := &astraClaimDB{parked: true, preColumn: true, state: "scheduled", target: strings.Repeat("c", 40), from: strings.Repeat("b", 40), floorAppliedPath: shim.applied}
	d := &Service{projDir: projDir, version: strings.Repeat("b", 40), queryConn: astraClaimConnection(t, db)}
	claim, err := d.claimScheduledUpgrade(context.Background(), 33)
	if err != nil {
		t.Fatalf("claim against a parked predecessor schema must apply the floor and succeed: %v", err)
	}
	assertParkDisplacementCarriesObligation(t, "floor-apply", db, claim)
	if got := readClaimFloorShimLog(t, shim); strings.Count(got, fmt.Sprintf("migrate up --to %d --verbose\n", migrate.DaemonSchemaFloor)) != 1 {
		t.Fatalf("exactly one bounded floor migrate expected; shim log:\n%s", got)
	}
	if flag, ferr := ReadFlagFile(projDir); ferr != nil || flag != nil {
		t.Fatalf("displaced park's stale service flag must be removed on the landing pass: flag=%#v err=%v", flag, ferr)
	}
	_, _, _, displacementIndex, _, rollbacks := claimQueryOrder(db)
	if displacementIndex < 0 || rollbacks != 1 {
		t.Fatalf("expected one refused pass (rollback) then one landing pass: displacement=%d rollbacks=%d", displacementIndex, rollbacks)
	}
}

// TestPreColumnParkClaimRefusesWhenFloorFailsDeterministically: a broken floor
// migration (exit 20) must leave the park standing, the candidate scheduled, the
// stale flag untouched, and produce an actionable refusal. Nothing displaces.
func TestPreColumnParkClaimRefusesWhenFloorFailsDeterministically(t *testing.T) {
	projDir := t.TempDir()
	shim := installClaimFloorMigrateShim(t, projDir, true)
	if err := os.WriteFile(shim.failDeterministic, []byte("broken\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	writeParkedSourceIdentityFlag(t, projDir, strings.Repeat("b", 40), "aaaaaaaa")
	db := &astraClaimDB{parked: true, preColumn: true, state: "scheduled", target: strings.Repeat("c", 40), from: strings.Repeat("b", 40), floorAppliedPath: shim.applied}
	d := &Service{projDir: projDir, version: strings.Repeat("b", 40), queryConn: astraClaimConnection(t, db)}
	_, err := d.claimScheduledUpgrade(context.Background(), 33)
	if err == nil {
		t.Fatal("claim must refuse when the floor cannot be applied")
	}
	for _, want := range []string{"refusing to claim upgrade id=33", "park stands", "candidate remains scheduled", "failed deterministically"} {
		if !strings.Contains(err.Error(), want) {
			t.Fatalf("refusal is missing %q: %v", want, err)
		}
	}
	parked, required, state, _ := db.snapshot()
	if !parked || required || state != "scheduled" {
		t.Fatalf("refused claim mutated durable state: parked=%t required=%t state=%s", parked, required, state)
	}
	if flag, ferr := ReadFlagFile(projDir); ferr != nil || flag == nil || flag.ID != 1 {
		t.Fatalf("refused claim must not remove the parked row's flag: flag=%#v err=%v", flag, ferr)
	}
	queries, _, _, displacementIndex, commitIndex, _ := claimQueryOrder(db)
	if displacementIndex >= 0 || commitIndex >= 0 {
		t.Fatalf("refused claim must not displace or commit:\n%v", queries)
	}
}

// TestPreColumnParkClaimRefusesWhenFloorMigrationMissingOnDisk: the claim checks
// its own migration set (migrate.DiskVersions) before launching a migrate that
// could only no-op. A checkout without the floor file refuses without a subprocess.
func TestPreColumnParkClaimRefusesWhenFloorMigrationMissingOnDisk(t *testing.T) {
	projDir := t.TempDir()
	shim := installClaimFloorMigrateShim(t, projDir, false)
	db := &astraClaimDB{parked: true, preColumn: true, state: "scheduled", target: strings.Repeat("c", 40), from: strings.Repeat("b", 40), floorAppliedPath: shim.applied}
	d := &Service{projDir: projDir, version: strings.Repeat("b", 40), queryConn: astraClaimConnection(t, db)}
	_, err := d.claimScheduledUpgrade(context.Background(), 33)
	if err == nil || !strings.Contains(err.Error(), fmt.Sprintf("migration %d is not in this checkout", migrate.DaemonSchemaFloor)) {
		t.Fatalf("claim must refuse naming the missing floor migration: %v", err)
	}
	parked, required, state, _ := db.snapshot()
	if !parked || required || state != "scheduled" {
		t.Fatalf("refused claim mutated durable state: parked=%t required=%t state=%s", parked, required, state)
	}
	if got := readClaimFloorShimLog(t, shim); got != "" {
		t.Fatalf("no migrate subprocess may run when the floor file is absent; shim log:\n%s", got)
	}
}

// TestPreColumnNoParkClaimStaysLegacyWithoutFloor is the harmless predecessor
// compatibility control: without a standing park there is no obligation to
// lose, so the legacy claim proceeds and no floor subprocess runs.
func TestPreColumnNoParkClaimStaysLegacyWithoutFloor(t *testing.T) {
	projDir := t.TempDir()
	shim := installClaimFloorMigrateShim(t, projDir, true)
	db := &astraClaimDB{preColumn: true, state: "scheduled", target: strings.Repeat("c", 40), from: strings.Repeat("b", 40), floorAppliedPath: shim.applied}
	d := &Service{projDir: projDir, version: strings.Repeat("b", 40), queryConn: astraClaimConnection(t, db)}
	claim, err := d.claimScheduledUpgrade(context.Background(), 33)
	if err != nil {
		t.Fatalf("no-park predecessor claim must stay compatible: %v", err)
	}
	if claim.Snapshot.RequiresServingTreeConvergence {
		t.Fatal("no-park predecessor claim invented an obligation")
	}
	if got := readClaimFloorShimLog(t, shim); got != "" {
		t.Fatalf("no-park claim must not run a floor subprocess; shim log:\n%s", got)
	}
	_, _, _, _, _, rollbacks := claimQueryOrder(db)
	if rollbacks != 0 {
		t.Fatal("no-park predecessor claim must land on its first pass")
	}
}

func TestDisplacedParkConvergenceSurvivesCrashBeforeConvergence(t *testing.T) {
	git := newGitRepoFixture(t)
	t.Setenv("HOME", t.TempDir())
	writeParkedSourceIdentityFlag(t, git.dir, git.newSHA, git.oldSHA[:8])
	writeParkedSourceIdentityCarrier(t, git.dir, git.newSHA, git.oldSHA[:8])
	logPath := installParkedSuccessorConvergenceShim(t, git.newSHA[:8], git.oldSHA[:8], false)
	srv, _ := sourceStackHealthServer(t)
	db := &astraClaimDB{parked: true, state: "scheduled", target: strings.Repeat("c", 40), from: git.newSHA}
	d := &Service{projDir: git.dir, version: git.newSHA, queryConn: astraClaimConnection(t, db), cachedURL: srv.URL + "/rpc/auth_status", cachedReadyURL: srv.URL + "/ready"}
	claim, err := d.claimScheduledUpgrade(context.Background(), 33)
	if err != nil {
		t.Fatal(err)
	}
	if !claim.Snapshot.RequiresServingTreeConvergence {
		t.Fatal("claim did not persist convergence before simulated process death")
	}

	// Simulate a new process after death in the claim->flag gap. It owns a fresh
	// canonical marker and drives the production recovery boundary from row state.
	restarted := &Service{projDir: git.dir, version: git.newSHA, queryConn: d.queryConn, cachedURL: srv.URL + "/rpc/auth_status", cachedReadyURL: srv.URL + "/ready"}
	lock, err := acquireFreshFlock(git.dir, UpgradeFlag{ID: 33, CommitSHA: db.target, Holder: HolderService, Trigger: "recovery", InvokedBy: "test-crash-recovery", StartedAt: time.Now()})
	if err != nil {
		t.Fatal(err)
	}
	restarted.flagLock = lock
	progress := NewUpgradeLog(git.dir, 33, "crash-recovery", time.Now().UTC())
	defer progress.Close()
	if err := restarted.recoverServingTreeConvergence(context.Background(), 33, progress); err != nil {
		t.Fatalf("next process did not converge durable obligation: %v", err)
	}
	_, required, state, _ := db.snapshot()
	if required || state != "scheduled" {
		t.Fatalf("crash recovery durable state = required:%t state:%s, want cleared+scheduled", required, state)
	}
	if got := strings.Count(readParkedTargetDockerLog(t, logPath), "compose up -d --no-build --no-deps app worker rest proxy\n"); got != 1 {
		t.Fatalf("crash recovery convergence attempts = %d, want 1", got)
	}
}

func TestDisplacedParkMissingTreeImagesContainsAndRetainsObligation(t *testing.T) {
	git := newGitRepoFixture(t)
	t.Setenv("HOME", t.TempDir())
	t.Setenv("STATBUS_TEST_MISSING_TREE_IMAGES", "1")
	logPath := installParkedSuccessorConvergenceShim(t, git.newSHA[:8], git.oldSHA[:8], false)
	astraSignatureBoundary(t)
	unavailable := false
	astraManifestBoundary(t, &unavailable)
	db := &astraClaimDB{parked: true, state: "scheduled", target: strings.Repeat("c", 40), from: git.newSHA}
	d := &Service{projDir: git.dir, version: git.newSHA, queryConn: astraClaimConnection(t, db), allowedSignersPath: "review-boundary"}
	claim, err := d.claimScheduledUpgrade(context.Background(), 33)
	if err != nil {
		t.Fatal(err)
	}
	err = d.executeUpgrade(context.Background(), claim.Snapshot, "v2026.09.99", claim.CommitTags, "scheduled", "scheduled", false)
	if err == nil || !strings.Contains(err.Error(), "PARKED_SERVING_TREE_CONVERGENCE_FAILED") {
		t.Fatalf("missing current-tree images terminal = %v", err)
	}
	_, required, state, _ := db.snapshot()
	if !required || state != "failed" {
		t.Fatalf("missing-image terminal lost durable repair: required=%t state=%s", required, state)
	}
	log := readParkedTargetDockerLog(t, logPath)
	if !strings.Contains(log, "compose stop app worker rest\n") || strings.LastIndex(log, "compose ps -a --format json\n") < strings.Index(log, "compose stop app worker rest\n") {
		t.Fatalf("missing-image convergence failure was not stopped and positively verified:\n%s", log)
	}
}

func TestServingTreeConvergenceRecoveryIsWiredIntoBothCrashEntrypoints(t *testing.T) {
	source := readUpgradeServiceSource(t)
	flagged := extractFuncBody(t, source, "func (d *Service) recoverFromFlag(")
	flagless := extractFuncBody(t, source, "func (d *Service) completeInProgressUpgrade(")
	for name, body := range map[string]string{"flagged": flagged, "flagless": flagless} {
		if !strings.Contains(body, "ServingTreeConvergence") {
			t.Errorf("%s crash entry does not consult/recover the durable serving-tree convergence obligation", name)
		}
	}
}
