package upgrade

import (
	"context"
	"fmt"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// STATBUS-294. Three tests, DB-free by the package's own standing rule
// (STATBUS-182: the go-test lane is deliberately Docker/DB-free — a live,
// working *pgx.Conn is not constructible without one, same reasoning
// recovery_backoff_test.go's TestClassifyPathReadsBounded already documents
// for this package). What CAN run here without a database is exactly what
// the bug and the fix are about: what listenLoop touches when it is handed
// a connection value versus reaching into shared state — the ownership
// question, not the network protocol.

// TestNilPgxConnWaitForNotificationPanics reproduces the CRASH MECHANISM
// itself, independent of this ticket's fix: the evidence in STATBUS-294
// (arc run 33115731212, transient-db-backoff) is a SIGSEGV at conn.go:419
// inside pgx, fault address 0x90 — a nil-base field offset. This pins that a
// nil *pgx.Conn's WaitForNotification is EXACTLY that crash, in-process, no
// network needed: the panic happens dereferencing the receiver's fields
// before any I/O is attempted. This is the "before" the rest of this file's
// fix makes unreachable in listenLoop specifically.
func TestNilPgxConnWaitForNotificationPanics(t *testing.T) {
	var conn *pgx.Conn // exactly what d.listenConn becomes at service.go:5984
	defer func() {
		r := recover()
		if r == nil {
			t.Fatal("calling WaitForNotification on a nil *pgx.Conn did not panic — " +
				"the STATBUS-294 evidence (SIGSEGV at conn.go:419) no longer reproduces; " +
				"re-verify against the current pgx version before trusting this test's premise")
		}
		msg := fmt.Sprint(r)
		if !strings.Contains(msg, "nil pointer") && !strings.Contains(msg, "invalid memory address") {
			t.Fatalf("panic was not a nil-pointer dereference as expected, got: %v", r)
		}
	}()
	_, _ = conn.WaitForNotification(context.Background())
	t.Fatal("unreachable: the call above must panic or the deferred recover above must fire")
}

// TestListenLoopNilConnReturnsWithoutPanic is the FIX's direct regression
// test. Before STATBUS-294, listenLoop had no conn parameter — it read
// d.listenConn on every loop iteration (service.go:2625, pre-fix), so a nil
// value once written to that field (executeUpgrade, :5984) was read on the
// abandoned listener's next pass and crashed exactly as the sibling test
// above reproduces. The fix's nil-guard is the direct answer: listenLoop
// now takes conn as a parameter and checks it before ever calling
// WaitForNotification. This calls the REAL production listenLoop — not a
// simulation of it — with conn=nil, the exact value the old code would have
// read after the abandon-and-empty sequence, and asserts it returns
// promptly with no panic.
func TestListenLoopNilConnReturnsWithoutPanic(t *testing.T) {
	d := &Service{}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	notifyCh := make(chan *pgconn.Notification)
	errCh := make(chan error)

	done := make(chan struct{})
	go func() {
		defer close(done)
		d.listenLoop(ctx, nil, notifyCh, errCh)
	}()

	select {
	case <-done:
		// Reaching here at all is the proof: a panic in the goroutine above
		// would fail this test via the Go runtime's own crash report before
		// this select ever observed anything, not through this branch.
	case <-time.After(2 * time.Second):
		t.Fatal("listenLoop(ctx, nil, ...) did not return promptly — the nil-conn guard is not firing")
	}
}

// TestListenLoopIgnoresConcurrentSharedFieldMutation is the race-detector
// proof (run with -race). It reproduces the SHAPE of the real incident:
// concurrently with the listener running, another goroutine mutates the
// SAME field executeUpgrade writes at service.go:5984 (d.listenConn = nil)
// after stopListenLoop gives up waiting on an abandoned goroutine. Before
// STATBUS-294 this was a genuine unsynchronized data race — write :5984 vs
// read :2625 (the ticket's own diagnosis). listenLoop no longer reads
// d.listenConn at all (it takes conn as a parameter instead), so there is
// nothing left on that field for this goroutine to race against; `go test
// -race` on this test must be clean. If a future change reintroduced a read
// of the shared field inside listenLoop, this test would start failing
// under -race without any other change required.
func TestListenLoopIgnoresConcurrentSharedFieldMutation(t *testing.T) {
	d := &Service{}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	notifyCh := make(chan *pgconn.Notification)
	errCh := make(chan error)

	stop := make(chan struct{})
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			select {
			case <-stop:
				return
			default:
				d.listenConn = nil // the exact write from service.go:5984
			}
		}
	}()

	done := make(chan struct{})
	go func() {
		defer close(done)
		d.listenLoop(ctx, nil, notifyCh, errCh)
	}()

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		close(stop)
		wg.Wait()
		t.Fatal("listenLoop(ctx, nil, ...) did not return promptly under concurrent field mutation")
	}

	close(stop)
	wg.Wait()
}

// TestListenLoopChannelSendsSelectOnCtxDone is the structural half for the
// "no eternal block" part of the fix (service.go :2630/:2632 in the ticket's
// numbering — the two channel sends inside listenLoop; re-verified against
// current master at the exact statements, not the ticket's line numbers,
// which had drifted by one line for the notifyCh send by the time this
// landed). An abandoned listener whose conn errors or receives a
// notification must not block forever offering it to a reader that may no
// longer exist — the same ownership gap as the conn field, one channel-op
// later. Exercising this end-to-end needs a live connection to make
// WaitForNotification return something to send, which STATBUS-182 rules out
// for this lane; asserting the source shape is the same genre as
// TestClassifyPathReadsBounded elsewhere in this package for exactly this
// reason.
//
// SECOND-LINE, not the floor (architect, STATBUS-294 review): the
// executable -race test in this file is what actually stands behind the
// property; this textual pin only catches the regression a reviewer would
// otherwise miss in a diff. Text can be right while behaviour is wrong —
// STATBUS-293's first pin was textually satisfied by `_ = ordered` while
// the property was dead. Never let this genre be the only guard.
func TestListenLoopChannelSendsSelectOnCtxDone(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	body := extractFuncBody(t, string(src), "func (d *Service) listenLoop(")

	if !strings.Contains(body, "case errCh <- err:") {
		t.Error("listenLoop's error send must be inside a select (case errCh <- err:) — a bare `errCh <- err` blocks forever once the reader is gone (STATBUS-294 part 2)")
	}
	if !strings.Contains(body, "case notifyCh <- notification:") {
		t.Error("listenLoop's notification send must be inside a select (case notifyCh <- notification:) — a bare `notifyCh <- notification` blocks forever once the reader is gone (STATBUS-294 part 2)")
	}
	if strings.Count(body, "case <-ctx.Done():") < 2 {
		t.Errorf("listenLoop must select on <-ctx.Done() at BOTH channel sends, found %d occurrence(s)", strings.Count(body, "case <-ctx.Done():"))
	}
}

// TestListenLoopNeverReadsSharedListenConn is the structural companion to
// TestListenLoopIgnoresConcurrentSharedFieldMutation: it pins the ABSENCE
// that makes the race test meaningful. If listenLoop ever again referenced
// d.listenConn directly, the race test above could start flaking (racing
// only when the timing lines up) instead of failing outright — this catches
// the regression unconditionally, every run.
func TestListenLoopNeverReadsSharedListenConn(t *testing.T) {
	src, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatalf("read service.go: %v", err)
	}
	body := extractFuncBody(t, string(src), "func (d *Service) listenLoop(")
	if strings.Contains(body, "d.listenConn") {
		t.Error("listenLoop must not read d.listenConn — it must use the conn parameter exclusively (STATBUS-294: the shared field is what executeUpgrade nils out from under an abandoned listener)")
	}

	startBody := extractFuncBody(t, string(src), "func (d *Service) startListenLoop(")
	if !strings.Contains(startBody, "conn := d.listenConn") {
		t.Error("startListenLoop must capture d.listenConn into a local before starting the goroutine (STATBUS-294 ownership fix)")
	}
	if !strings.Contains(startBody, "d.listenLoop(listenCtx, conn, notifyCh, errCh)") {
		t.Error("startListenLoop must pass the captured local, not d.listenConn, to listenLoop")
	}
}

// ─── STATBUS-306: a nil-conn start must not wedge the restart guard ─────────
//
// The 294 fix made a nil-conn start SAFE and LOUD. It did not make it
// RECOVERABLE: startListenLoop set d.listenCancel before the goroutine ran, and
// the nil path never cleared it, so the guard looked like a live listener
// forever. The four `if d.listenCancel == nil { startListenLoop }` sites in the
// idle loop were then permanently false and the daemon could never hear NOTIFY
// again — a box that parked during an outage stayed deaf for the life of the
// process, degraded from on-poke to the 6-hour tick while reporting healthy.
//
// DB-free like the rest of this file: the property is entirely about guard
// bookkeeping, which needs no connection to observe.

// TestNilConnStartLeavesGuardNeverStarted_STATBUS306 asserts the STATE
// directly — the exact fields every consumer branches on.
func TestNilConnStartLeavesGuardNeverStarted_STATBUS306(t *testing.T) {
	d := &Service{} // listenConn nil: the parked-box shape
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	d.startListenLoop(ctx, make(chan *pgconn.Notification), make(chan error))

	if d.listenCancel != nil {
		t.Error("listenCancel is set after a nil-conn start — the restart guard is wedged.\n" +
			"Every `if d.listenCancel == nil { startListenLoop }` in the idle loop is now\n" +
			"permanently false, so this daemon can never start listening again.")
	}
	if d.listenDone != nil {
		t.Error("listenDone is set after a nil-conn start — the bookkeeping is half-initialised.\n" +
			"The state after a refused start must be INDISTINGUISHABLE from never-started;\n" +
			"a done channel nobody will ever close is not that.")
	}
}

// TestNilConnStartPermitsASubsequentStart_STATBUS306 is the BEHAVIOURAL half.
//
// Asserting the fields alone would pass against a fix that cleared them while
// leaving some other state stuck. This drives the actual entry point twice and
// asks whether the second call still REACHES its work — observed through the
// announce, which only prints on the path that got past the already-running
// guard.
//
// Pre-fix, the second call returns silently at `if d.listenCancel != nil` and
// the line appears once. That difference is the whole bug, expressed in the
// only output a DB-free test can see.
func TestNilConnStartPermitsASubsequentStart_STATBUS306(t *testing.T) {
	d := &Service{}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	out := captureStdout(t, func() {
		d.startListenLoop(ctx, make(chan *pgconn.Notification), make(chan error))
		d.startListenLoop(ctx, make(chan *pgconn.Notification), make(chan error))
	})

	got := strings.Count(out, "listenLoop NOT started")
	if got != 2 {
		t.Errorf("the nil-conn announce appeared %d time(s) across two starts; want 2.\n"+
			"A second start that says nothing was refused by the already-running guard —\n"+
			"meaning the first start left the guard set and the listener can never be retried.\n"+
			"captured output:\n%s", got, out)
	}
}

// captureStdout runs fn with os.Stdout redirected and returns what it wrote.
// The announce is the only externally observable effect of the refused start,
// so reading it is how a DB-free test asks "did this call reach its work?".
func captureStdout(t *testing.T, fn func()) string {
	t.Helper()
	orig := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	os.Stdout = w

	var wg sync.WaitGroup
	var buf strings.Builder
	wg.Add(1)
	go func() {
		defer wg.Done()
		b := make([]byte, 4096)
		for {
			n, err := r.Read(b)
			if n > 0 {
				buf.Write(b[:n])
			}
			if err != nil {
				return
			}
		}
	}()

	fn()

	// Restore BEFORE waiting on the reader: closing the writer is what ends the
	// read loop, and leaving os.Stdout pointing at a closed pipe would break
	// every later test in the package.
	_ = w.Close()
	os.Stdout = orig
	wg.Wait()
	_ = r.Close()
	return buf.String()
}
