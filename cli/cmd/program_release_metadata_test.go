package cmd

import (
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

func TestProgramReleaseMetadataUsesResolvedFullSHA(t *testing.T) {
	sha, err := upgrade.NewCommitSHA(strings.Repeat("a", 40))
	if err != nil {
		t.Fatal(err)
	}
	sql := programReleaseMetadataSQL(sha)
	if !strings.Contains(sql, "public.release_identity('"+string(sha)+"')") {
		t.Fatalf("metadata must use exact resolved executable SHA: %s", sql)
	}
	if !strings.Contains(sql, "not serving app") {
		t.Fatalf("program/app distinction missing: %s", sql)
	}
}

func TestProgramReleaseMetadataUnknownDoesNotQueryHistory(t *testing.T) {
	for _, sha := range []upgrade.CommitSHA{"", "short", "'untrusted'"} {
		sql := programReleaseMetadataSQL(sha)
		if strings.Contains(sql, "FROM") || strings.Contains(sql, "'untrusted'") {
			t.Fatalf("unproven program must remain unknown without metadata/history substitution: %s", sql)
		}
		if !strings.Contains(sql, "'unknown' AS commit_sha") {
			t.Fatalf("missing explicit unknown: %s", sql)
		}
	}
}
