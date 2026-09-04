package upgrade

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPromotionSameCommitGuardPrecedesCandidateWrite_STATBUS355(t *testing.T) {
	srcPath := filepath.Join(repoRootFromTest(t), "cli", "internal", "upgrade", "service.go")
	srcBytes, err := os.ReadFile(srcPath)
	if err != nil {
		t.Fatal(err)
	}
	src := string(srcBytes)
	guard := `if installed := d.installedCommitSHA(); installed != "" && t.CommitSHA == installed {`
	guardAt := strings.Index(src, guard)
	if guardAt < 0 {
		t.Fatal("same-commit promotion guard is missing")
	}
	writeAt := strings.Index(src[guardAt:], "d.upsertCandidate(")
	if writeAt < 0 {
		t.Fatal("candidate write following the same-commit guard was not found")
	}
	between := src[guardAt : guardAt+writeAt]
	if !strings.Contains(between, "continue") {
		t.Fatal("same-commit promotion no longer exits before candidate registration")
	}
	for _, forbidden := range []string{"backup", "maintenance", "migrate"} {
		if strings.Contains(strings.ToLower(between), forbidden) {
			t.Fatalf("same-commit guard performs %s work before skipping; promotion must be metadata-only", forbidden)
		}
	}
}
