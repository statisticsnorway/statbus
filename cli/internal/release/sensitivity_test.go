package release

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadSensitivePaths(t *testing.T) {
	t.Run("comments and blanks are ignored, entries kept in order", func(t *testing.T) {
		dir := t.TempDir()
		full := filepath.Join(dir, SensitivePathsFile)
		if err := os.MkdirAll(filepath.Dir(full), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte("# header\n\ninstall.sh\n  cli/  \n# trailing\n"), 0644); err != nil {
			t.Fatal(err)
		}
		got, err := LoadSensitivePaths(dir)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if strings.Join(got, ",") != "install.sh,cli/" {
			t.Errorf("got %v, want [install.sh cli/]", got)
		}
	})
	t.Run("an empty list is refused, not treated as 'nothing is sensitive'", func(t *testing.T) {
		dir := t.TempDir()
		full := filepath.Join(dir, SensitivePathsFile)
		if err := os.MkdirAll(filepath.Dir(full), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte("# only comments\n\n"), 0644); err != nil {
			t.Fatal(err)
		}
		if _, err := LoadSensitivePaths(dir); err == nil {
			t.Fatal("want an error for an empty list")
		}
	})
	t.Run("a missing file is an error naming the file", func(t *testing.T) {
		_, err := LoadSensitivePaths(t.TempDir())
		if err == nil || !strings.Contains(err.Error(), SensitivePathsFile) {
			t.Fatalf("want an error naming %s, got %v", SensitivePathsFile, err)
		}
	})
}

func TestMatchesSensitivePath(t *testing.T) {
	paths := []string{"install.sh", "cli/", "docker-compose"}
	cases := map[string]bool{
		"install.sh":             true,
		"cli/cmd/release.go":     true,
		"docker-compose.app.yml": true,
		"test/install-recovery/scenarios/0-happy-install.sh": true, // substring, deliberately over-inclusive
		"app/src/page.tsx": false,
		"doc/CLOUD.md":     false,
	}
	for file, want := range cases {
		if got := MatchesSensitivePath(file, paths); got != want {
			t.Errorf("%s: got %v, want %v", file, got, want)
		}
	}
}
