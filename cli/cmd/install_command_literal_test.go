package cmd

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

var installCommandMention = regexp.MustCompile(`\./sb install\b`)

// hasBareInstallCommand finds `./sb install` that is not the tail of
// `cd <checkout> && ./sb install`. Only that shape runs the box's own program
// from any directory; a bare `./sb install` works only from inside the
// checkout, and an operator reading a journal, Slack or the admin UI is
// usually somewhere else.
func hasBareInstallCommand(s string) bool {
	for _, loc := range installCommandMention.FindAllStringIndex(s, -1) {
		if !strings.HasSuffix(s[:loc[0]], "&& ") {
			return true
		}
	}
	return false
}

// installCommandLiteralExemptions are the only non-test Go string literals
// under cli/ allowed to contain a bare `./sb install`. Each one NAMES the
// program in a description; none tells an operator what to run. Every entry
// must match exactly one literal, so a removed or reworded site cannot leave a
// stale exemption behind.
var installCommandLiteralExemptions = []struct{ file, literal, why string }{
	{"cli/cmd/install.go", "Installed via ./sb install (%s)", "provenance note stored on the install's upgrade row"},
	{"cli/cmd/install.go", "./sb install operates from inside a git clone", "invariant rationale for engineers"},
	{"cli/cmd/install_upgrade.go", "(this is what `./sb install` does here)", "legend naming the running program; an exact awk-allowlisted terminal line"},
	{"cli/cmd/support.go", "install.sh caught a non-zero exit from ./sb install", "--trigger help text describing install.sh"},
	{"cli/cmd/support.go", "Called by install.sh after a failed ./sb install", "command help text describing install.sh"},
}

// TestNoGoLiteralTellsTheOperatorToRunABareInstall is positive and needs no
// keyword list: EVERY non-test Go string literal under cli/ that contains
// `./sb install` must be the directory-independent `cd <checkout> && ./sb
// install` form (installcmd.Local builds it), or be one of the named
// descriptions above. A retry hint, an un-park instruction, a diagnosis hint
// or a concatenated constant cannot slip through by wording, because wording
// is not consulted. install.sh's echo/printf lines are held to the same rule.
func TestNoGoLiteralTellsTheOperatorToRunABareInstall(t *testing.T) {
	root := thisRepoFile(t, ".")
	used := make([]int, len(installCommandLiteralExemptions))
	files, literals := 0, 0
	err := filepath.WalkDir(thisRepoFile(t, "cli"), func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			if name := entry.Name(); name == "testdata" || name == "vendor" || strings.HasPrefix(name, ".") {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		rel, _ := filepath.Rel(root, path)
		rel = filepath.ToSlash(rel)
		fset := token.NewFileSet()
		file, err := parser.ParseFile(fset, path, nil, parser.SkipObjectResolution)
		if err != nil {
			return err
		}
		files++
		ast.Inspect(file, func(node ast.Node) bool {
			lit, ok := node.(*ast.BasicLit)
			if !ok || lit.Kind != token.STRING {
				return true
			}
			value, err := strconv.Unquote(lit.Value)
			if err != nil {
				t.Errorf("%s: cannot unquote %s: %v", fset.Position(lit.Pos()), lit.Value, err)
				return true
			}
			literals++
			if !hasBareInstallCommand(value) {
				return true
			}
			for i, exemption := range installCommandLiteralExemptions {
				if rel == exemption.file && strings.Contains(value, exemption.literal) {
					used[i]++
					return true
				}
			}
			t.Errorf("%s:%d: operator text names a bare `./sb install`, which only works from inside the checkout; build it with installcmd.Local/ForRunningBinary (`cd <checkout> && ./sb install`):\n\t%s",
				rel, fset.Position(lit.Pos()).Line, value)
			return true
		})
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if files < 100 || literals < 5000 {
		t.Fatalf("scanned only %d files and %d string literals under cli/; the walk is broken", files, literals)
	}
	for i, n := range used {
		if n != 1 {
			e := installCommandLiteralExemptions[i]
			t.Errorf("exemption %s %q (%s) matched %d literals, want exactly 1", e.file, e.literal, e.why, n)
		}
	}

	shell, err := os.ReadFile(thisRepoFile(t, "install.sh"))
	if err != nil {
		t.Fatal(err)
	}
	for n, line := range strings.Split(string(shell), "\n") {
		trimmed := strings.TrimSpace(line)
		if (strings.HasPrefix(trimmed, "echo ") || strings.HasPrefix(trimmed, "printf ")) && hasBareInstallCommand(trimmed) {
			t.Errorf("install.sh:%d prints a bare `./sb install`; print $STATBUS_INSTALL_RERUN_COMMAND: %s", n+1, trimmed)
		}
	}
}

// TestBareInstallCommandMatcher pins the matcher on the shapes the rule is
// about, including the three a keyword scanner missed.
func TestBareInstallCommandMatcher(t *testing.T) {
	for text, bare := range map[string]bool{
		"To try again: run ./sb install":                                             true,
		"Fix: run ./sb install to un-park it for one fresh attempt":                  true,
		"A later release or a deliberate ./sb install run can make a fresh attempt.": true,
		"./sb install":                                     true,
		"then run: `./sb install`":                         true,
		"cd /home/statbus/statbus && ./sb install":         false,
		`ssh host "cd statbus && ./sb install"`:            false,
		"cd ~/statbus && ./sb install; then ./sb install":  true,
		"./sb installer":                                   false,
		"curl -fsSL https://statbus.org/install.sh | bash": false,
	} {
		if got := hasBareInstallCommand(text); got != bare {
			t.Errorf("hasBareInstallCommand(%q) = %v, want %v", text, got, bare)
		}
	}
}
