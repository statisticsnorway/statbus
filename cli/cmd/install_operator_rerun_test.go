package cmd

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestOperatorRerunHintsUsePublicInstallCommand(t *testing.T) {
	for _, path := range []string{thisRepoFile(t, "cli/cmd/install.go"), thisRepoFile(t, "cli/internal/unitfloor/unitfloor.go"), thisRepoFile(t, "install.sh")} {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		for _, forbidden := range []string{"re-run: ./sb install", "Re-run without sudo to verify: ./sb install", "Then re-run ./sb install", "Management: cd ", "Steps 1-"} {
			if strings.Contains(string(data), forbidden) {
				t.Errorf("%s contains forbidden operator rerun hint %q", path, forbidden)
			}
		}
	}
}

// Usage help and the wrapper initializer are examples, not retry paths.
func TestEveryInstallerRerunHintUsesSavedCommand(t *testing.T) {
	goSource, err := os.ReadFile(thisRepoFile(t, "cli/cmd/install.go"))
	if err != nil {
		t.Fatal(err)
	}
	for n, line := range strings.Split(string(goSource), "\n") {
		if strings.Contains(line, "  curl -fsSL https://statbus.org/install.sh | bash`") {
			continue // CLI usage example, not a retry
		}
		if strings.Contains(line, "curl -fsSL https://statbus.org/install.sh | bash") {
			t.Errorf("install.go:%d hardcodes a retry", n+1)
		}
	}
	shellSource, err := os.ReadFile(thisRepoFile(t, "install.sh"))
	if err != nil {
		t.Fatal(err)
	}
	for n, line := range strings.Split(string(shellSource), "\n") {
		if n < 9 || strings.Contains(line, "STATBUS_INSTALL_RERUN_COMMAND='") {
			continue
		}
		if strings.Contains(line, "curl -fsSL https://statbus.org/install.sh | bash") {
			t.Errorf("install.sh:%d hardcodes a retry", n+1)
		}
	}
	if strings.Count(string(shellSource), "Then run: $STATBUS_INSTALL_RERUN_COMMAND") != 3 {
		t.Error("pull, git and settings-restore failure retry hints must use saved command")
	}
	if strings.Count(string(shellSource), "echo \"    $STATBUS_INSTALL_RERUN_COMMAND\"") != 2 {
		t.Error("rollback and step failure retry hints must use saved command")
	}
	unitSource, err := os.ReadFile(thisRepoFile(t, "cli/internal/unitfloor/unitfloor.go"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(unitSource), "curl -fsSL https://statbus.org/install.sh | bash") || !strings.Contains(string(unitSource), "diskpolicy.RerunCommand()") {
		t.Error("unit repair hint must preserve the saved install command")
	}
}

// rerunRetryKeyword matches an operator-facing retry instruction (STATBUS-387
// AC1): "re-run", "then run", "retry", or the two synonymous phrasings the
// installer/service already use.
var rerunRetryKeyword = regexp.MustCompile(`(?i)(re.?run|run the same install|run the installer again|then run|switch to that user|retry)`)

// rerunBareCommand matches a quoted, backtick-quoted, or bare `./sb install`
// reference that is NOT built from the saved rerun command
// (diskpolicy.RerunCommand() / $STATBUS_INSTALL_RERUN_COMMAND).
var rerunBareCommand = regexp.MustCompile("[`\"']?\\./sb install[`\"']?")

// TestEveryInstallerRerunHintUsesTheSavedCommand scans every non-test Go
// source file under cli/cmd and cli/internal, plus install.sh, for an
// operator-facing retry line that still hardcodes the directory-dependent
// `./sb install` instead of the saved, directory-independent command
// (diskpolicy.RerunCommand() in Go, $STATBUS_INSTALL_RERUN_COMMAND in
// install.sh). This is the STATBUS-387 AC1 invariant: under
// `curl ... | bash`, the operator sits in `~`, and `./sb install` printed
// from there fails exactly as it did in the Finland run
// (STATBUS-387 evidence).
//
// Exclusions, each narrow and justified:
//   - Lines that are pure comments (`//`) or doc lines: they describe
//     behaviour to engineers, not an instruction printed to an operator.
//   - `cli/cmd/install.go`'s usage string
//     ("  curl -fsSL https://statbus.org/install.sh | bash`") and its
//     "Installed via ./sb install (%s)" provenance label: neither is a retry
//     instruction.
//   - `*_test.go` files: fixtures and expectations, not product output.
//   - `install.sh` lines before the wrapper exports
//     STATBUS_INSTALL_RERUN_COMMAND (the command doesn't exist yet) and the
//     `STATBUS_INSTALL_RERUN_COMMAND='...'` assignment line itself, which
//     builds the one hardcoded fallback the saved-command function falls
//     back to (mirrors diskpolicy.RerunCommand()).
//   - `cli/cmd/db.go`'s remote-restore recovery hint: it runs
//     `ssh <user>@<host> "cd statbus && ./sb install"`, which IS
//     directory-independent (the ssh command names the remote user's home
//     and the cd), it is simply not built from diskpolicy.RerunCommand()
//     because it targets a different host than the one printing it.
//   - `dev.sh` and other developer-only scripts are out of scope entirely:
//     they are not reachable from the shipped `curl | bash` install path.
func TestEveryInstallerRerunHintUsesTheSavedCommand(t *testing.T) {
	repoRoot := thisRepoFile(t, ".")
	var goFiles []string
	for _, dir := range []string{"cli/cmd", "cli/internal"} {
		absDir := thisRepoFile(t, dir)
		if err := filepath.Walk(absDir, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			if info.IsDir() {
				return nil
			}
			if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
				return nil
			}
			goFiles = append(goFiles, path)
			return nil
		}); err != nil {
			t.Fatal(err)
		}
	}
	if len(goFiles) < 30 {
		t.Fatalf("only found %d non-test Go files under cli/cmd and cli/internal; the walk is broken", len(goFiles))
	}

	scanned := 0
	for _, path := range goFiles {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		rel, relErr := filepath.Rel(repoRoot, path)
		if relErr != nil {
			rel = path
		}
		isInstallGo := strings.HasSuffix(path, "cli/cmd/install.go") || strings.HasSuffix(filepath.ToSlash(path), "cli/cmd/install.go")
		for n, line := range strings.Split(string(data), "\n") {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "//") {
				continue // comment, not an instruction printed to an operator
			}
			if isInstallGo && strings.Contains(line, `Installed via ./sb install`) {
				continue // provenance label, not a retry instruction
			}
			if strings.Contains(path, filepath.Join("cmd", "db.go")) && strings.Contains(line, `ssh %[5]s@%[6]s`) {
				continue // directory-independent: ssh names the remote user's home and cd's there itself
			}
			if !rerunRetryKeyword.MatchString(line) || !rerunBareCommand.MatchString(line) {
				continue
			}
			t.Errorf("%s:%d: operator-facing retry hint hardcodes the directory-dependent `./sb install` instead of diskpolicy.RerunCommand(): %s", rel, n+1, trimmed)
		}
		if rerunBareCommand.MatchString(string(data)) || strings.Contains(string(data), "RerunCommand()") {
			scanned++
		}
	}

	shellPath := thisRepoFile(t, "install.sh")
	shellData, err := os.ReadFile(shellPath)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(string(shellData), "\n")
	rerunExportLine := -1
	for n, line := range lines {
		if strings.Contains(line, "export STATBUS_INSTALL_RERUN_COMMAND") {
			rerunExportLine = n
			break
		}
	}
	if rerunExportLine < 0 {
		t.Fatal("install.sh never exports STATBUS_INSTALL_RERUN_COMMAND")
	}
	for n, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "#") {
			continue
		}
		if n <= rerunExportLine || strings.HasPrefix(trimmed, "STATBUS_INSTALL_RERUN_COMMAND='") {
			continue // before the saved command exists, or building its one hardcoded fallback
		}
		if !rerunRetryKeyword.MatchString(line) || !rerunBareCommand.MatchString(line) {
			continue
		}
		t.Errorf("install.sh:%d: operator-facing retry hint hardcodes the directory-dependent `./sb install` instead of $STATBUS_INSTALL_RERUN_COMMAND: %s", n+1, trimmed)
	}

	if scanned < 5 {
		t.Fatalf("scanner found only %d files referencing the saved rerun command; the scan is too narrow", scanned)
	}

	// The mechanism itself: install.sh must build STATBUS_INSTALL_RERUN_COMMAND
	// from the same public curl|bash fallback diskpolicy.RerunCommand() uses,
	// export it so children (a possible re-exec into cli/cmd/install.go) see
	// it, and diskpolicy.RerunCommand() must read it back.
	if !strings.Contains(string(shellData), "STATBUS_INSTALL_RERUN_COMMAND='curl -fsSL https://statbus.org/install.sh | bash'") {
		t.Error("install.sh must seed STATBUS_INSTALL_RERUN_COMMAND with the public curl|bash fallback")
	}
	policyData, err := os.ReadFile(thisRepoFile(t, "cli/internal/diskpolicy/policy.go"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(policyData), `os.Getenv("STATBUS_INSTALL_RERUN_COMMAND")`) {
		t.Error("diskpolicy.RerunCommand() must read the saved STATBUS_INSTALL_RERUN_COMMAND")
	}
}
