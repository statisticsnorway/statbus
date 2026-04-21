package invariants

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRegister_Duplicate_Panics(t *testing.T) {
	inv := Invariant{
		Name: "TEST_INV_A", Class: FailFast,
		SourceLocation: "a.go:10",
		ExpectedToHold: "x", WhyExpected: "y",
		ViolationShape: "z", TranscriptFormat: "INVARIANT TEST_INV_A violated: %v",
	}
	Register(inv)
	t.Cleanup(func() {
		mu.Lock()
		delete(registry, "TEST_INV_A")
		mu.Unlock()
	})
	// Same fields — idempotent, no panic.
	Register(inv)

	// Conflicting fields — must panic.
	defer func() {
		if recover() == nil {
			t.Fatal("expected panic on duplicate name with conflicting fields")
		}
	}()
	conflicting := inv
	conflicting.WhyExpected = "different"
	Register(conflicting)
}

func TestRegister_EmptyName_Panics(t *testing.T) {
	defer func() {
		if recover() == nil {
			t.Fatal("expected panic on empty name")
		}
	}()
	Register(Invariant{Class: FailFast})
}

func TestMarkTerminal_AppendsLines(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "terminal.txt")
	SetTerminalPathForTest(path)
	t.Cleanup(func() { SetTerminalPathForTest("") })

	MarkTerminal("", "INV_ONE", "first observed state")
	MarkTerminal("", "INV_TWO", "second observed state")

	got := ReadTerminal("")
	wantLines := []string{
		"INVARIANT INV_ONE violated: first observed state",
		"INVARIANT INV_TWO violated: second observed state",
	}
	for _, w := range wantLines {
		if !strings.Contains(got, w) {
			t.Errorf("terminal file missing %q; got:\n%s", w, got)
		}
	}
}

func TestClearTerminal_RemovesFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "terminal.txt")
	SetTerminalPathForTest(path)
	t.Cleanup(func() { SetTerminalPathForTest("") })

	MarkTerminal("", "INV", "something")
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("precondition: terminal file should exist: %v", err)
	}
	if err := ClearTerminal(""); err != nil {
		t.Fatalf("ClearTerminal: %v", err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Errorf("terminal file should have been removed; Stat err = %v", err)
	}
	// Second clear on missing file must be a no-op.
	if err := ClearTerminal(""); err != nil {
		t.Errorf("ClearTerminal on missing file: %v", err)
	}
}

func TestDump_IncludesAllFields(t *testing.T) {
	inv := Invariant{
		Name: "TEST_DUMP_INV", Class: FailFast,
		SourceLocation: "dump.go:42",
		ExpectedToHold: "the thing holds",
		WhyExpected:    "because of the thing",
		ViolationShape: "the thing broke",
		TranscriptFormat: `INVARIANT TEST_DUMP_INV violated: %v`,
	}
	Register(inv)
	t.Cleanup(func() {
		mu.Lock()
		delete(registry, "TEST_DUMP_INV")
		mu.Unlock()
	})

	var buf bytes.Buffer
	Dump(&buf)
	got := buf.String()

	for _, field := range []string{
		"Name: TEST_DUMP_INV",
		"Class: fail-fast",
		"Location: dump.go:42",
		"ExpectedToHold: the thing holds",
		"WhyExpected: because of the thing",
		"ViolationShape: the thing broke",
		"TranscriptFormat: INVARIANT TEST_DUMP_INV violated: %v",
	} {
		if !strings.Contains(got, field) {
			t.Errorf("Dump output missing %q", field)
		}
	}
}

func TestNames_Sorted(t *testing.T) {
	// Register in reverse order; Names must come back sorted.
	for _, n := range []string{"ZED", "ALPHA", "MIKE"} {
		Register(Invariant{
			Name: "TEST_SORT_" + n, Class: LogOnly,
			SourceLocation: "x.go:1", ExpectedToHold: "x",
			WhyExpected: "y", ViolationShape: "z",
			TranscriptFormat: "INVARIANT TEST_SORT_" + n + " violated: %v",
		})
	}
	t.Cleanup(func() {
		mu.Lock()
		for _, n := range []string{"ZED", "ALPHA", "MIKE"} {
			delete(registry, "TEST_SORT_"+n)
		}
		mu.Unlock()
	})
	names := Names()
	var got []string
	for _, n := range names {
		if strings.HasPrefix(n, "TEST_SORT_") {
			got = append(got, n)
		}
	}
	want := []string{"TEST_SORT_ALPHA", "TEST_SORT_MIKE", "TEST_SORT_ZED"}
	if len(got) != len(want) {
		t.Fatalf("Names(): got %v, want %v", got, want)
	}
	for i := range got {
		if got[i] != want[i] {
			t.Errorf("Names()[%d]: got %q, want %q", i, got[i], want[i])
		}
	}
}
