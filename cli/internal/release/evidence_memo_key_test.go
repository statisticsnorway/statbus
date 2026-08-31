package release

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// evidenceGoPath resolves evidence.go's own path from this test file's
// location, so the pin reads the REAL tree-side source, never a fixture.
func evidenceGoPath(t *testing.T) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	return filepath.Join(filepath.Dir(thisFile), "evidence.go")
}

// TestEvidenceMemoKeysExcludeScenario is STATBUS-252's required structural
// pin (architect's ruling, 2026-08-31, his third option — replacing both the
// mechanic's and foreman's proposals): runsAtCommitMemoized and
// jobsForRunMemoized key their caches on (apiBase, workflow, commitSHA) and
// (apiBase, runID) respectively — NEVER on scenario. That is exactly what
// lets N scenarios asking about the SAME commit collapse to one real API
// call instead of N (STATBUS-252 precondition 2, DecideCoverage step 1: every
// scenario's first evidence check is Evidence(rcCommit), sharing the
// identical key). A future edit that folded scenario into either key would
// defeat that sharing silently — it would surface as an HTTP 403 mid-
// promotion (STATBUS-249's first live run already saw 7 of 20 candidates
// come back unreadable on an unauthenticated budget), not as a failing test,
// unless this pin exists.
//
// Source-text scan bounded to each function's OWN body via the AST (no seam,
// no live API) — the same genre as this session's other body-inspection
// pins (e.g. STATBUS-252's now-retired TestShadowCannotFeedTheDecision,
// STATBUS-321's funcBodiesContaining).
func TestEvidenceMemoKeysExcludeScenario(t *testing.T) {
	path := evidenceGoPath(t)
	src, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read evidence.go: %v", err)
	}
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, path, src, 0)
	if err != nil {
		t.Fatalf("parse evidence.go: %v", err)
	}

	for _, fnName := range []string{"runsAtCommitMemoized", "jobsForRunMemoized"} {
		var body string
		var found bool
		ast.Inspect(f, func(n ast.Node) bool {
			fn, ok := n.(*ast.FuncDecl)
			if !ok || fn.Name.Name != fnName {
				return true
			}
			found = true
			start := fset.Position(fn.Body.Lbrace).Offset
			end := fset.Position(fn.Body.Rbrace).Offset
			body = string(src[start:end])
			return false
		})
		if !found {
			t.Fatalf("%s not found in evidence.go — if it was renamed, this pin must follow it; the property it protects has not stopped mattering", fnName)
		}
		if strings.Contains(strings.ToLower(body), "scenario") {
			t.Errorf(`%s's body now mentions "scenario".

The memo key must be (apiBase, workflow, commitSHA) for run listings and
(apiBase, runID) for job listings — ONLY. Folding scenario into either key
defeats the sharing that collapses N scenarios' identical lookups into one
real API call (STATBUS-252 precondition 2). The failure mode is silent: it
would surface as an HTTP 403 mid-promotion (a resource-starvation outage,
exactly what this memo exists to prevent — STATBUS-249's first live run hit
this for real), not as a test failure, without this pin.

%s body:
%s`, fnName, fnName, body)
		}
	}
}
