package cmd

import (
	"os"
	"strings"
	"testing"
)

func TestOperatorRerunHintsUsePublicInstallCommand(t *testing.T) {
	for _, path := range []string{
		thisRepoFile(t, "cli/cmd/install.go"),
		thisRepoFile(t, "cli/internal/unitfloor/unitfloor.go"),
		thisRepoFile(t, "install.sh"),
	} {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		body := string(data)
		for _, forbidden := range []string{"re-run: ./sb install", "Steps 1-"} {
			if strings.Contains(body, forbidden) {
				t.Errorf("%s contains forbidden operator rerun hint %q", path, forbidden)
			}
		}
	}
}
