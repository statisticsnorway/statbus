package upgrade

import (
	"context"
	"net"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgproto3"
)

// SYNTHETIC: a pgx wire-protocol recorder. It is NOT Postgres and does not run
// public.upgrade_schedule; it answers the state probe with a fixed (state,
// parked) row and records whether the Go code ever asks for upgrade_schedule.
// It proves only the Go-side decision of the real promoteExistingCandidate.
type promoteRecorder struct {
	mu        sync.Mutex
	scheduled int
	probes    int
}

func promoteRecorderConn(t *testing.T, state string, parked bool) (*pgx.Conn, *promoteRecorder) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = ln.Close() })
	rec := &promoteRecorder{}
	go func() {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
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
		for {
			m, err := b.Receive()
			if err != nil {
				return
			}
			q, ok := m.(*pgproto3.Query)
			if !ok {
				return
			}
			text := q.String
			field := func(name string, oid uint32) pgproto3.FieldDescription {
				return pgproto3.FieldDescription{Name: []byte(name), DataTypeOID: oid, DataTypeSize: -1, TypeModifier: -1}
			}
			rec.mu.Lock()
			switch {
			case strings.Contains(text, "upgrade_schedule"):
				rec.scheduled++
				b.Send(&pgproto3.RowDescription{Fields: []pgproto3.FieldDescription{field("a", 25), field("b", 23), field("c", 25), field("d", 23)}})
				b.Send(&pgproto3.DataRow{Values: [][]byte{[]byte("scheduled"), []byte("1"), []byte("scheduled"), []byte("0")}})
			case strings.Contains(text, "FROM public.upgrade WHERE commit_sha"):
				rec.probes++
				b.Send(&pgproto3.RowDescription{Fields: []pgproto3.FieldDescription{field("s", 25), field("p", 16)}})
				b.Send(&pgproto3.DataRow{Values: [][]byte{[]byte(state), []byte(map[bool]string{false: "f", true: "t"}[parked])}})
			}
			rec.mu.Unlock()
			b.Send(&pgproto3.CommandComplete{CommandTag: []byte("SELECT 1")})
			b.Send(&pgproto3.ReadyForQuery{TxStatus: 'I'})
			if b.Flush() != nil {
				return
			}
		}
	}()
	cfg, err := pgx.ParseConfig("postgres://fake@" + ln.Addr().String() + "/fake?sslmode=disable")
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
	return c, rec
}

// A stale notification for a failed, dismissed or parked candidate must never
// re-arm it: the real promoteExistingCandidate answers operator_required and
// never calls upgrade_schedule. Only an available candidate is scheduled.
func TestPromoteExistingCandidateNeverSchedulesFailedDismissedOrParked(t *testing.T) {
	cases := []struct {
		name   string
		state  string
		parked bool
		want   scheduleResult
		calls  int
	}{
		{"failed", "failed", false, scheduleResultOperatorRequired, 0},
		{"dismissed", "dismissed", false, scheduleResultOperatorRequired, 0},
		{"parked in_progress", "in_progress", true, scheduleResultOperatorRequired, 0},
		{"live in_progress", "in_progress", false, scheduleResultInProgress, 0},
		{"already scheduled", "scheduled", false, scheduleResultAlreadyScheduled, 0},
		{"available is scheduled", "available", false, scheduleResultScheduled, 1},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			conn, rec := promoteRecorderConn(t, c.state, c.parked)
			d := &Service{queryConn: conn}
			got, err := d.promoteExistingCandidate(context.Background(), CommitSHA(strings.Repeat("a", 40)))
			if err != nil {
				t.Fatal(err)
			}
			rec.mu.Lock()
			defer rec.mu.Unlock()
			if got != c.want || rec.scheduled != c.calls || rec.probes != 1 {
				t.Fatalf("result=%q schedule calls=%d probes=%d, want %q calls=%d probes=1", got, rec.scheduled, rec.probes, c.want, c.calls)
			}
		})
	}
}
