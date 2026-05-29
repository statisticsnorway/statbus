package upgrade

import "testing"

// Test_matchSbVersionCommit exhaustively covers the fail-safe semantics
// of buildBinaryOnDisk's pre-staged-binary skip. The skip must ONLY fire
// on an EXACT match between the version-output's `commit XXXXXXXX` field
// and a known target prefix (commitSHA[:8] preferred, displayName as
// 8-char fallback). Every ambiguity — unparseable output, mismatched
// commit, empty target, UNSTAMPED — must return false so the caller
// falls through to the rebuild. A false positive here would silently
// run a STALE binary as if it were the target (the foreman's no-silent-
// wrong-version-upgrade correctness condition).
func Test_matchSbVersionCommit(t *testing.T) {
	cases := []struct {
		name        string
		versionOut  string
		commitSHA   string
		displayName string
		wantShort   string
		wantOk      bool
	}{
		// === GREEN paths: skip is correct ===
		{
			name:        "tagged_version_full_sha_match",
			versionOut:  "v2026.05.6-rc.03-31-gb6aa14b86 (commit b6aa14b8)",
			commitSHA:   "b6aa14b86026ce87a1ed7e2ed5d84a6104c29399",
			displayName: "v2026.05.6-rc.03",
			wantShort:   "b6aa14b8",
			wantOk:      true,
		},
		{
			name:        "dev_build_full_sha_match",
			versionOut:  "dev (commit b6aa14b8)",
			commitSHA:   "b6aa14b86026ce87a1ed7e2ed5d84a6104c29399",
			displayName: "b6aa14b8", // UntaggedTarget shape
			wantShort:   "b6aa14b8",
			wantOk:      true,
		},
		{
			name:        "displayname_short_fallback_no_commitSHA",
			versionOut:  "dev (commit deadbeef)",
			commitSHA:   "",
			displayName: "deadbeef",
			wantShort:   "deadbeef",
			wantOk:      true,
		},
		{
			name:        "case_insensitive_match",
			versionOut:  "dev (commit ABCDEF12)",
			commitSHA:   "abcdef12345678901234567890abcdef12345678",
			displayName: "abcdef12",
			wantShort:   "abcdef12",
			wantOk:      true,
		},

		// === RED paths: skip MUST NOT fire (fail-safe to build) ===
		{
			name:        "commit_mismatch_falls_through",
			versionOut:  "dev (commit deadbeef)",
			commitSHA:   "b6aa14b86026ce87a1ed7e2ed5d84a6104c29399",
			displayName: "b6aa14b8",
			wantOk:      false,
		},
		{
			name:        "unstamped_binary_falls_through",
			versionOut:  "dev (UNSTAMPED)",
			commitSHA:   "b6aa14b86026ce87a1ed7e2ed5d84a6104c29399",
			displayName: "b6aa14b8",
			wantOk:      false,
		},
		{
			name:        "empty_version_out_falls_through",
			versionOut:  "",
			commitSHA:   "b6aa14b86026ce87a1ed7e2ed5d84a6104c29399",
			displayName: "b6aa14b8",
			wantOk:      false,
		},
		{
			name:        "no_commit_field_in_output_falls_through",
			versionOut:  "sb version 2026.05.6-rc.03 garbled output without commit field",
			commitSHA:   "b6aa14b86026ce87a1ed7e2ed5d84a6104c29399",
			displayName: "b6aa14b8",
			wantOk:      false,
		},
		{
			name:        "short_commit_field_falls_through",
			versionOut:  "dev (commit b6aa14)", // only 6 chars, regex requires 8
			commitSHA:   "b6aa14b86026ce87a1ed7e2ed5d84a6104c29399",
			displayName: "b6aa14b8",
			wantOk:      false,
		},
		{
			name:        "displayname_not_8_chars_falls_through",
			versionOut:  "dev (commit b6aa14b8)",
			commitSHA:   "", // displayName-only path
			displayName: "v2026.05.6-rc.03", // tagged shape, not 8-char SHA — should not match
			wantOk:      false,
		},
		{
			name:        "empty_both_targets_falls_through",
			versionOut:  "dev (commit b6aa14b8)",
			commitSHA:   "",
			displayName: "",
			wantOk:      false,
		},
		{
			name:        "short_commitsha_under_8_chars_falls_through",
			versionOut:  "dev (commit b6aa14b8)",
			commitSHA:   "b6aa14", // 6 chars, below the [:8] cutoff
			displayName: "",
			wantOk:      false,
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			gotShort, gotOk := matchSbVersionCommit(c.versionOut, c.commitSHA, c.displayName)
			if gotOk != c.wantOk {
				t.Fatalf("ok mismatch: got=%v want=%v (versionOut=%q commitSHA=%q displayName=%q)",
					gotOk, c.wantOk, c.versionOut, c.commitSHA, c.displayName)
			}
			if c.wantOk && gotShort != c.wantShort {
				t.Fatalf("short mismatch: got=%q want=%q", gotShort, c.wantShort)
			}
			if !c.wantOk && gotShort != "" {
				t.Fatalf("expected empty short on miss, got=%q", gotShort)
			}
		})
	}
}
