package cmd

import (
	"os"
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
	if strings.Count(string(shellSource), "Then run: $STATBUS_INSTALL_RERUN_COMMAND") != 2 {
		t.Error("pull and git failure retry hints must use saved command")
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
