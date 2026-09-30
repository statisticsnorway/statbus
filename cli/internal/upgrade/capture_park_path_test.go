package upgrade

import (
	"context"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/jackc/pgx/v5/pgproto3"
)

// parkRecorderPG is a minimal multi-connection Postgres wire fake for the
// teardown-immune terminalUpdate path (fresh pgx.Connect per write). It records
// every statement and answers the park UPDATE with a row.
type parkRecorderPG struct {
	mu      sync.Mutex
	queries []string
	addr    string
}

func newParkRecorderPG(t *testing.T) *parkRecorderPG {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = ln.Close() })
	s := &parkRecorderPG{addr: ln.Addr().String()}
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
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
				stmtIsPark := false
				for {
					m, err := b.Receive()
					if err != nil {
						return
					}
					rowFields := []pgproto3.FieldDescription{{Name: []byte("r"), DataTypeOID: 25, DataTypeSize: -1, TypeModifier: -1}}
					isPark := func(sql string) bool {
						return strings.HasPrefix(strings.TrimSpace(sql), "UPDATE public.upgrade SET recovery_parked_at")
					}
					switch msg := m.(type) {
					case *pgproto3.Terminate:
						return
					case *pgproto3.Query:
						s.mu.Lock()
						s.queries = append(s.queries, msg.String)
						s.mu.Unlock()
						b.Send(&pgproto3.CommandComplete{CommandTag: []byte("SET")})
						b.Send(&pgproto3.ReadyForQuery{TxStatus: 'I'})
					case *pgproto3.Parse:
						s.mu.Lock()
						s.queries = append(s.queries, msg.Query)
						s.mu.Unlock()
						stmtIsPark = isPark(msg.Query)
						b.Send(&pgproto3.ParseComplete{})
					case *pgproto3.Bind:
						b.Send(&pgproto3.BindComplete{})
					case *pgproto3.Describe:
						if msg.ObjectType == 'S' {
							b.Send(&pgproto3.ParameterDescription{ParameterOIDs: []uint32{23, 25, 25, 25}})
						}
						if stmtIsPark {
							b.Send(&pgproto3.RowDescription{Fields: rowFields})
						} else {
							b.Send(&pgproto3.NoData{})
						}
					case *pgproto3.Execute:
						if stmtIsPark {
							b.Send(&pgproto3.DataRow{Values: [][]byte{[]byte(`{"id":33,"state":"in_progress"}`)}})
							b.Send(&pgproto3.CommandComplete{CommandTag: []byte("UPDATE 1")})
						} else {
							b.Send(&pgproto3.CommandComplete{CommandTag: []byte("SELECT 0")})
						}
					case *pgproto3.Sync:
						b.Send(&pgproto3.ReadyForQuery{TxStatus: 'I'})
					default:
						return
					}
					if b.Flush() != nil {
						return
					}
				}
			}()
		}
	}()
	return s
}

func (s *parkRecorderPG) log() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.queries...)
}

// STATBUS-436 loop containment: a deterministic REAL capture failure inside
// executeUpgrade (no injected seam) parks the claimed row once, removes the
// pre-destructive flag, never reaches the target pull, and leaves serving
// containers untouched.
func TestExecuteUpgradeRealCaptureFailureParksOnceAndLeavesServing(t *testing.T) {
	git := newGitRepoFixture(t)
	t.Setenv("HOME", t.TempDir())
	logPath := installParkedSuccessorConvergenceShim(t, git.newSHA[:8], git.oldSHA[:8], false)
	wrapDockerComposePsDisplay(t, true) // Config.Image empty: capture cannot prove the reference
	astraSignatureBoundary(t)
	unavailable := false
	astraManifestBoundary(t, &unavailable)

	pg := newParkRecorderPG(t)
	host, port, _ := net.SplitHostPort(pg.addr)
	env := "CADDY_DB_BIND_ADDRESS=" + host + "\nCADDY_DB_PORT=" + port + "\nPOSTGRES_APP_DB=review\nPOSTGRES_ADMIN_USER=review\nPOSTGRES_ADMIN_PASSWORD=\n"
	if err := os.WriteFile(filepath.Join(git.dir, ".env"), []byte(env), 0o644); err != nil {
		t.Fatal(err)
	}

	db := &astraClaimDB{state: "scheduled", target: git.newSHA, from: git.oldSHA}
	d := &Service{projDir: git.dir, version: git.oldSHA, queryConn: astraClaimConnection(t, db), allowedSignersPath: "review-boundary"}
	claim, err := d.claimScheduledUpgrade(context.Background(), 33)
	if err != nil {
		t.Fatal(err)
	}
	err = d.executeUpgrade(context.Background(), claim.Snapshot, "v2026.09.99", claim.CommitTags, "scheduled", "scheduled", false)
	t.Logf("executeUpgrade error: %v", err)
	if err == nil || !strings.Contains(err.Error(), "Could not record immutable source image identities") {
		t.Fatalf("want capture refusal, got %v", err)
	}
	parks := 0
	for _, q := range pg.log() {
		if strings.HasPrefix(strings.TrimSpace(q), "UPDATE public.upgrade SET recovery_parked_at") {
			parks++
		}
	}
	if parks != 1 {
		t.Fatalf("park writes = %d, want exactly 1; queries=%q", parks, pg.log())
	}
	if flag, ferr := ReadFlagFile(git.dir); ferr != nil || flag != nil {
		t.Fatalf("pre-destructive flag must be removed after park: flag=%v err=%v", flag, ferr)
	}
	docker := readParkedTargetDockerLog(t, logPath)
	for _, forbidden := range []string{" pull", "compose stop", "compose up", "compose down", "compose start", "compose rm"} {
		if strings.Contains(docker, forbidden) {
			t.Fatalf("serving must be untouched, docker saw %q:\n%s", forbidden, docker)
		}
	}
	if _, serr := os.Stat(sourceServingImagesCarrierPath(git.dir)); !os.IsNotExist(serr) {
		t.Fatalf("no carrier may be written by a failed capture: %v", serr)
	}
}
