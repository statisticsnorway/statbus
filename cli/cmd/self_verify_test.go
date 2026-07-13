package cmd

import (
	"strings"
	"testing"
)

// TestSelfVerifyIdentity_STATBUS171 pins AC#1+#2: `upgrade self-verify` confirms a
// procured binary is the upgrade TARGET by comparing the binary's EMBEDDED commit
// against the expected target — never against the worktree. The worktree does not
// appear in selfVerifyIdentity's signature AT ALL, which is the whole point: under
// STATBUS-060 the worktree is deliberately left at the SOURCE commit during the
// swap, so the old worktree-relative stalenessGuard judged every tag-identified
// target binary "stale" and rolled the upgrade back (dev row 331014). A target
// binary now passes whenever its embedded commit equals the target — regardless of
// what HEAD the worktree is parked at.
func TestSelfVerifyIdentity_STATBUS171(t *testing.T) {
	const target = "49b2e6eaed5cba18b53ef3cfcc885033e39ff821"
	const source = "17d47c5eaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

	cases := []struct {
		name     string
		embedded string
		expect   string
		wantErr  string // "" = expect success
	}{
		{"target binary matches target (full==full)", target, target, ""},
		{"target binary matches target, short expect", target, target[:8], ""},
		{"target binary matches target, short embedded", target[:8], target, ""},
		{"wrong/mis-built artifact embeds the SOURCE → fail", source, target, "wrong or mis-built artifact"},
		{"unidentifiable binary (no ldflags) with a target → fail", "", target, "no reliable commit identity"},
		{"no target demanded → boot-only, pass", target, "", ""},
		{"no target demanded, unidentifiable → boot-only, pass", "", "", ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := selfVerifyIdentity(c.embedded, c.expect)
			if c.wantErr == "" {
				if err != nil {
					t.Fatalf("selfVerifyIdentity(%q, %q) = %v, want nil", c.embedded, c.expect, err)
				}
				return
			}
			if err == nil {
				t.Fatalf("selfVerifyIdentity(%q, %q) = nil, want error containing %q", c.embedded, c.expect, c.wantErr)
			}
			if !strings.Contains(err.Error(), c.wantErr) {
				t.Errorf("error %q missing fragment %q", err.Error(), c.wantErr)
			}
		})
	}
}

// TestSelfVerifyCmd_GuardExempt_STATBUS171 pins AC#1's other half: the
// stalenessGuard-vs-worktree path is REMOVED from this call site. stalenessGuard
// (root.go) returns early for any command annotated freshness_probe=true — the
// same exemption `committed-drift` carries — so the mid-upgrade self-verify never
// runs the worktree-relative staleness check. If a future edit drops this
// annotation, the STATBUS-060 category error returns and every tag upgrade rolls
// back again.
func TestSelfVerifyCmd_GuardExempt_STATBUS171(t *testing.T) {
	if upgradeSelfVerifyCmd.Annotations["freshness_probe"] != "true" {
		t.Error("upgrade self-verify must be annotated freshness_probe=true so stalenessGuard exempts it (STATBUS-171 AC#1) — else the mid-upgrade staleness check re-breaks every tag-identified upgrade")
	}
}
