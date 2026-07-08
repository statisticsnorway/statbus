package upgrade

import (
	"fmt"
	"os"
	"strings"
	"testing"
)

// TestEveryRunCallbackNamesEvent pins STATBUS-137: EVERY d.runCallback call site
// in service.go must pass a named STATBUS_EVENT — the documented integration
// surface (operator event streams key on it). r17 found the rollback-failure and
// catastrophic callbacks firing with STATBUS_EVENT unset (a leading space where
// the name belongs). This scan fails if any call site regresses to a nameless
// (nil or event-less) callback.
func TestEveryRunCallbackNamesEvent(t *testing.T) {
	body := mustRead(t, thisRepoFile(t, "cli/internal/upgrade/service.go"))
	const marker = "d.runCallback("

	var missing []string
	for pos := 0; ; {
		i := strings.Index(body[pos:], marker)
		if i < 0 {
			break
		}
		callStart := pos + i
		open := callStart + len(marker) - 1 // index of the '('
		span, ok := balancedParenSpan(body, open)
		if !ok {
			t.Fatalf("unbalanced runCallback( at offset %d — scanner needs review", callStart)
		}
		if !strings.Contains(span, "STATBUS_EVENT") {
			line := 1 + strings.Count(body[:callStart], "\n")
			missing = append(missing, fmt.Sprintf("service.go:%d: runCallback fires without a named STATBUS_EVENT", line))
		}
		pos = callStart + len(marker)
	}
	if len(missing) > 0 {
		t.Errorf("STATBUS-137: %d runCallback call site(s) fire nameless:\n  %s", len(missing), strings.Join(missing, "\n  "))
	}
}

// TestRunInstallCallbackNamesEvent pins the install-path callback (cmd pkg) —
// runInstallCallback builds cmd.Env directly, so its STATBUS_EVENT is a plain env
// entry rather than a runCallback map arg.
func TestRunInstallCallbackNamesEvent(t *testing.T) {
	body := mustRead(t, thisRepoFile(t, "cli/cmd/install.go"))
	// The runInstallCallback env block must carry a STATBUS_EVENT=.
	if !strings.Contains(body, `"STATBUS_EVENT=install_completed"`) {
		t.Error("STATBUS-137: runInstallCallback (install.go) must set STATBUS_EVENT in cmd.Env (was firing blank)")
	}
}

func mustRead(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(b)
}

// balancedParenSpan returns the substring from the '(' at openIdx through its
// matching ')', tracking nesting (the maps contain a nested fmt.Sprintf(...)).
// ok=false if the parens never balance. Adequate for this code — no parentheses
// appear inside the string literals in these call args.
func balancedParenSpan(s string, openIdx int) (string, bool) {
	depth := 0
	for i := openIdx; i < len(s); i++ {
		switch s[i] {
		case '(':
			depth++
		case ')':
			depth--
			if depth == 0 {
				return s[openIdx : i+1], true
			}
		}
	}
	return "", false
}
