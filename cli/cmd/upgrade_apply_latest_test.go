package cmd

import (
	"os"
	"regexp"
	"strings"
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

// TestApplyEmitsDeployedCommit_STATBUS258 pins that `upgrade apply` emits the
// same greppable line apply-latest does.
//
// For apply-latest the emit TELLS the caller what the box resolved, because only
// the box knew. For apply the caller already named the target — so the emit
// exists to be CHECKED against that name. deploy-to-dev asserts requested ==
// deployed and fails loudly on a mismatch (STATBUS-260), and without this emit
// that guard has nothing to compare and silently degrades to trust.
func TestApplyEmitsDeployedCommit_STATBUS258(t *testing.T) {
	src := readCLIUpgradeSourceForApply(t)
	body := src[strings.Index(src, "var upgradeApplyCmd = &cobra.Command{"):]
	body = body[:strings.Index(body, "\nvar ")]

	if !strings.Contains(body, "deployedCommitLine(") {
		t.Error(`upgrade apply never emits deployed_commit=.

The caller's requested-vs-deployed guard then has nothing to compare, and a
mismatch — the exact defect STATBUS-258 exists to remove — becomes invisible
again. Use the SHARED deployedCommitLine so both verbs stay in one format.`)
	}
	if !strings.Contains(body, "ResolveToCommit(") {
		t.Error("the emitted commit must come from the canonical resolver, not from the operator's raw argument — a tag is not a 40-hex commit and the workflow greps for 40 hex")
	}
	// A failure to resolve must not be silent: the guard downstream would then
	// read agreement into an absent line.
	if !strings.Contains(body, "deployed_commit line omitted") {
		t.Error("a resolution failure must SAY the emit was omitted — a caller checking requested-vs-deployed must never infer agreement from silence")
	}
}

func readCLIUpgradeSourceForApply(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile("upgrade.go")
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}
