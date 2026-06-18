package upgrade

import (
	"os"
	"strings"
	"testing"
)

// TestClassifyScheduleResult proves the require-register decision (STATBUS-086,
// AC#9): a promote-UPDATE that affects rows means the candidate was promoted; 0
// rows on an existing row is a benign already-scheduled no-op; 0 rows with NO
// row is Unregistered — which the caller turns into a loud no-op, NEVER an
// insert. This is the pure core of "schedule requires register, everywhere."
func TestClassifyScheduleResult(t *testing.T) {
	cases := []struct {
		name   string
		rows   int64
		exists bool
		want   scheduleResult
	}{
		{"promoted", 1, true, scheduleResultPromoted},
		{"promoted-regardless-of-exists-probe", 2, false, scheduleResultPromoted},
		{"already-scheduled-no-op", 0, true, scheduleResultAlreadyScheduled},
		{"unregistered-never-insert", 0, false, scheduleResultUnregistered},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := classifyScheduleResult(c.rows, c.exists); got != c.want {
				t.Errorf("classifyScheduleResult(%d, %v) = %v, want %v", c.rows, c.exists, got, c.want)
			}
		})
	}
}

// TestErrNotRegistered_Actionable proves AC#3: scheduling an unregistered
// target yields an ACTIONABLE error that names the fix (`./sb upgrade register
// <target>`) and echoes the operator's input — not a silent insert.
func TestErrNotRegistered_Actionable(t *testing.T) {
	err := errNotRegistered("v2026.03.1", "abc1234f")
	if err == nil {
		t.Fatal("errNotRegistered returned nil — expected an actionable error")
	}
	msg := err.Error()
	for _, want := range []string{"not registered", "./sb upgrade register", "abc1234f"} {
		if !strings.Contains(msg, want) {
			t.Errorf("error %q is missing the actionable fragment %q", msg, want)
		}
	}
}

// TestOnScheduledNotify_NoInsert is a structural guard for AC#9: the NOTIFY
// upgrade_apply handler must promote an EXISTING candidate via UPDATE and must
// NEVER insert-if-missing (the removed scheduleImmediate behavior). A future
// edit that reintroduces an INSERT into onScheduledNotify would silently revive
// the fabricate-a-row-from-a-NOTIFY path the require-register rule forbids.
func TestOnScheduledNotify_NoInsert(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) onScheduledNotify(")
	if strings.Contains(body, "INSERT INTO public.upgrade") {
		t.Error("onScheduledNotify must NOT INSERT — require-register forbids insert-if-missing (STATBUS-086 AC#9)")
	}
	if !strings.Contains(body, "UPDATE public.upgrade") {
		t.Error("onScheduledNotify must promote a registered candidate via UPDATE public.upgrade")
	}
}

// funcBody returns the source text of the function whose signature prefix is
// `sig`, from `file`, up to (not including) the next top-level `func ` after it.
// Mirrors the source-inspection guards already used in this package
// (rollback_terminal_write_test.go).
func funcBody(t *testing.T, file, sig string) string {
	t.Helper()
	src, err := os.ReadFile(file)
	if err != nil {
		t.Fatalf("read %s: %v", file, err)
	}
	s := string(src)
	start := strings.Index(s, sig)
	if start < 0 {
		t.Fatalf("signature %q not found in %s", sig, file)
	}
	rest := s[start+len(sig):]
	if end := strings.Index(rest, "\nfunc "); end >= 0 {
		return rest[:end]
	}
	return rest
}
