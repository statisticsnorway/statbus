package cmd

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/install"
)

// TestInstallOperatorOutputContainsNoInternalDiagnostics guards the boundary
// between diagnostic files and text rendered to an operator.
func TestInstallOperatorOutputContainsNoInternalDiagnostics(t *testing.T) {
	states := installStateNames(t)
	count := len(states)
	for i := 0; i < count; i++ {
		states = append(states, install.State(i).String())
	}
	for i := range states {
		states[i] = regexp.QuoteMeta(states[i])
	}
	forbidden := regexp.MustCompile(`(?i)INVARIANT|state:|step-table|pgx|\(target=|\b(?:` + strings.Join(states, "|") + `|POST_COMPLETION_[A-Z_]+|GIT_HEAD_RESOLVABLE)\b`)
	prints := regexp.MustCompile(`(?m)(?:fmt\.(?:Print(?:f|ln)?|Fprint(?:f|ln)?)|log\.Print\w*|echo|printf|cat|tee)\s*\([^\n]*|^\s*(?:echo|printf|cat|tee)\b[^\n]*`)
	files, err := filepath.Glob("install*.go")
	if err != nil {
		t.Fatal(err)
	}
	files = append(files, filepath.Join("..", "..", "install.sh"))
	for _, file := range files {
		data, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		for _, line := range strings.Split(string(data), "\n") {
			if strings.Contains(line, "fmt.Sprintf(") {
				continue
			}
			// "fresh" in these phrases is an adjective, not a state label.
			checked := strings.NewReplacer("fresh database", "new database", "fresh attempt", "new attempt", "FRESH attempt", "NEW attempt").Replace(line)
			if !prints.MatchString(line) || !forbidden.MatchString(checked) {
				continue
			}
			// Explicit allow-list: writes directly into the support log, never stdout/stderr.
			if strings.Contains(line, "installLog.File()") {
				continue
			}
			// Diagnostic logger is captured by the shell into install-last-run-output.txt.
			if strings.Contains(line, "log.Printf(") || strings.Contains(line, "log.Panicf(") {
				continue
			}
			// The shell's diagnostic capture is not a terminal print.
			if strings.Contains(line, `>"$install_output"`) {
				continue
			}
			t.Errorf("%s: operator-facing print contains internal diagnostics: %s", file, strings.TrimSpace(line))
		}
	}
}

// Read the source declaration so newly added State names are guarded too.
func installStateNames(t *testing.T) []string {
	t.Helper()
	file, err := parser.ParseFile(token.NewFileSet(), "../internal/install/state.go", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, decl := range file.Decls {
		group, ok := decl.(*ast.GenDecl)
		if !ok || group.Tok != token.CONST {
			continue
		}
		inStateBlock := false
		for _, spec := range group.Specs {
			value := spec.(*ast.ValueSpec)
			if ident, ok := value.Type.(*ast.Ident); ok && ident.Name == "State" {
				inStateBlock = true
			}
			if inStateBlock {
				for _, name := range value.Names {
					names = append(names, name.Name)
				}
			}
		}
	}
	if len(names) == 0 {
		t.Fatal("no install.State constants found")
	}
	return names
}
