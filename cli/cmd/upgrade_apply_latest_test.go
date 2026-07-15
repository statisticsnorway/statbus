package cmd

import (
	"regexp"
	"testing"
)

// TestDeployedCommitLine_WorkflowGrepContract pins the STATBUS-170 green-means-converged
// contract between the CLI emit and the deploy workflow's poll: apply-latest prints
// `deployed_commit=<40hex>` on its own line, and the workflow greps exactly
// `^deployed_commit=[a-f0-9]{40}$` to capture the commit to poll. Both sides are asserted
// here together so neither can drift silently (a format change that broke the grep would
// otherwise degrade every cloud deploy to poke-only green with no test catching it).
func TestDeployedCommitLine_WorkflowGrepContract(t *testing.T) {
	const sha = "0123456789abcdef0123456789abcdef01234567"

	line := deployedCommitLine(sha)
	if want := "deployed_commit=" + sha; line != want {
		t.Fatalf("emit format drifted: got %q, want %q", line, want)
	}

	// The EXACT regex the deploy workflows use (keep in lockstep with the .yaml grep).
	re := regexp.MustCompile(`^deployed_commit=([a-f0-9]{40})$`)
	m := re.FindStringSubmatch(line)
	if m == nil {
		t.Fatalf("workflow grep `^deployed_commit=[a-f0-9]{40}$` did not match the emit %q", line)
	}
	if m[1] != sha {
		t.Errorf("captured commit %q != emitted %q", m[1], sha)
	}

	// A release tag (what latestVersion is on prerelease/stable) must NOT satisfy the
	// 40-hex contract — the emit must carry the RESOLVED commit, never the tag; else the
	// workflow would poll a non-existent commit_sha and false-red every cloud deploy.
	if re.MatchString(deployedCommitLine("v1.2.3-rc.04")) {
		t.Error("a release tag passed the 40-hex grep — the emit must carry the resolved commit, not the tag")
	}
	// A short commit (edge channel's latestVersion pre-resolution) must also be rejected
	// by the 40-hex contract — only the fully-resolved 40-hex is valid.
	if re.MatchString(deployedCommitLine("0123abcd")) {
		t.Error("an 8-char commit-short passed the 40-hex grep — the emit must carry the resolved 40-hex")
	}
}
