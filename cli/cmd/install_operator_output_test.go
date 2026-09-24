package cmd

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// TestInstallOperatorOutputContainsNoInternalDiagnostics guards the boundary
// between diagnostic files and text rendered to an operator.
func TestInstallOperatorOutputContainsNoInternalDiagnostics(t *testing.T) {
	forbidden := regexp.MustCompile(`(?i)INVARIANT|state:|step-table|pgx|\(target=|\b(?:StateFresh|StateCrashedUpgrade|StateDBUnreachable|POST_COMPLETION_[A-Z_]+|GIT_HEAD_RESOLVABLE)\b`)
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
			if !prints.MatchString(line) || !forbidden.MatchString(line) {
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
