// Package invariants is the runtime registry of named invariants checked
// by the currently-shipped binary. Each guard site (fail-fast, log-only,
// bundle-only, panic-regression) registers once at package init() so the
// support bundle can enumerate every invariant the binary knows about —
// the single source of truth that couples plan ↔ code ↔ bundle.
//
// The full contract lives in the plan under "Invariant triad" and E3;
// this package is the machinery.
package invariants

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"sync"
)

// Class of invariant. The four classes correspond to the behavioural
// categories from the plan's triad preamble.
type Class string

const (
	// FailFast: site emits the transcript, calls MarkTerminal, and returns
	// a wrapped error. The wrapper (install.sh or upgrade service) gathers
	// the support bundle and propagates.
	FailFast Class = "fail-fast"

	// LogOnly: site emits the "INVARIANT NAME violated ..." line but does
	// NOT call MarkTerminal and does NOT return — the primary fail-fast
	// path is already driving termination elsewhere. Purpose is to leave
	// a greppable breadcrumb in the support bundle.
	LogOnly Class = "log-only"

	// PanicRegression: the site is a bug-class assert that aborts via
	// log.Panicf. A future release fixing the bug removes the panic; the
	// invariant remains as a regression aperture.
	PanicRegression Class = "panic-regression"

	// BundleOnly: the site runs inside the upgrade service and merely
	// records context for the support bundle. Not operator-visible.
	BundleOnly Class = "bundle-only"
)

// Invariant is one registered guard site. Keep fields short strings —
// the whole registry is dumped verbatim into invariants.txt.
type Invariant struct {
	Name             string
	Class            Class
	SourceLocation   string // "file.go:NNN"
	ExpectedToHold   string
	WhyExpected      string
	ViolationShape   string
	TranscriptFormat string
}

var (
	mu       sync.RWMutex
	registry = map[string]Invariant{}
)

// Register adds an invariant. Called from init() in each guard site's
// source file. Idempotent for identical re-registration; panics on
// name collision with conflicting fields — two packages trying to
// register the same invariant differently is a plan violation we want
// to catch at program startup, not on a cold bundle path.
func Register(inv Invariant) {
	if inv.Name == "" {
		panic("invariants.Register: Name is required")
	}
	if inv.Class == "" {
		panic(fmt.Sprintf("invariants.Register(%q): Class is required", inv.Name))
	}
	mu.Lock()
	defer mu.Unlock()
	if existing, dup := registry[inv.Name]; dup && existing != inv {
		panic(fmt.Sprintf("invariants.Register(%q): duplicate with conflicting fields", inv.Name))
	}
	registry[inv.Name] = inv
}

// Get looks up a registered invariant.
func Get(name string) (Invariant, bool) {
	mu.RLock()
	defer mu.RUnlock()
	inv, ok := registry[name]
	return inv, ok
}

// Names returns every registered invariant name, sorted. Used by tests
// and by Dump.
func Names() []string {
	mu.RLock()
	defer mu.RUnlock()
	names := make([]string, 0, len(registry))
	for n := range registry {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}

// Count returns the number of registered invariants. Used by the
// cardinality test to assert registry coverage matches source-grep.
func Count() int {
	mu.RLock()
	defer mu.RUnlock()
	return len(registry)
}

// Dump writes every registered invariant to w in the invariants.txt
// format that ships inside the support bundle. Deterministic ordering
// (sorted by name) so two bundles from the same binary diff cleanly.
func Dump(w io.Writer) {
	mu.RLock()
	defer mu.RUnlock()
	names := make([]string, 0, len(registry))
	for n := range registry {
		names = append(names, n)
	}
	sort.Strings(names)

	fmt.Fprintln(w, "# Invariants registered by the currently-shipped binary.")
	fmt.Fprintln(w, "# Each block documents one guard site the binary is capable of")
	fmt.Fprintln(w, "# checking at runtime. A violation whose name is NOT listed here is")
	fmt.Fprintln(w, "# a forward-compat mismatch or an extraction bug.")
	fmt.Fprintln(w)
	for _, n := range names {
		inv := registry[n]
		fmt.Fprintf(w, "Name: %s\n", inv.Name)
		fmt.Fprintf(w, "Class: %s\n", inv.Class)
		fmt.Fprintf(w, "Location: %s\n", inv.SourceLocation)
		fmt.Fprintf(w, "ExpectedToHold: %s\n", inv.ExpectedToHold)
		fmt.Fprintf(w, "WhyExpected: %s\n", inv.WhyExpected)
		fmt.Fprintf(w, "ViolationShape: %s\n", inv.ViolationShape)
		fmt.Fprintf(w, "TranscriptFormat: %s\n", inv.TranscriptFormat)
		fmt.Fprintln(w)
	}
}

// terminalPathOverride lets tests point MarkTerminal at a tempfile
// without needing a real projDir layout. Zero value = use the default
// `<projDir>/tmp/install-terminal.txt` location.
var terminalPathOverride string

// SetTerminalPathForTest is test-only; callers under /cli outside tests
// must not use it. Kept unexported-by-convention-but-exported for cross
// package tests.
func SetTerminalPathForTest(path string) { terminalPathOverride = path }

// MarkTerminal appends "INVARIANT <name> violated: <observed>\n" to
// <projDir>/tmp/install-terminal.txt. Both the install.sh wrapper and
// the upgrade service's failure paths read this file to surface the
// named invariant in the SYSTEM UNUSABLE banner / admin-UI state.
//
// Best-effort: filesystem errors are logged to stderr and swallowed —
// the primary signal (stderr line at the call site) has already fired.
// This is the secondary, on-disk audit channel.
func MarkTerminal(projDir, name, observed string) {
	path := terminalPathOverride
	if path == "" {
		path = filepath.Join(projDir, "tmp", "install-terminal.txt")
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "invariants.MarkTerminal: mkdir %s: %v\n", filepath.Dir(path), err)
		return
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		fmt.Fprintf(os.Stderr, "invariants.MarkTerminal: open %s: %v\n", path, err)
		return
	}
	defer f.Close()
	if _, err := fmt.Fprintf(f, "INVARIANT %s violated: %s\n", name, observed); err != nil {
		fmt.Fprintf(os.Stderr, "invariants.MarkTerminal: write %s: %v\n", path, err)
	}
}

// ReadTerminal returns the contents of <projDir>/tmp/install-terminal.txt
// or the empty string if the file does not exist. install.sh reads this
// to fill the banner's "Invariant breached" slot.
func ReadTerminal(projDir string) string {
	path := terminalPathOverride
	if path == "" {
		path = filepath.Join(projDir, "tmp", "install-terminal.txt")
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return string(b)
}

// ClearTerminal removes the terminal file. Called at the start of a
// fresh install.sh run so stale invariant lines from a prior failed
// run don't pollute the banner.
func ClearTerminal(projDir string) error {
	path := terminalPathOverride
	if path == "" {
		path = filepath.Join(projDir, "tmp", "install-terminal.txt")
	}
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}
