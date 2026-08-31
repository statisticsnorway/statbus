package cmd

import (
	"os"
	"strings"
	"testing"
)

// STATBUS-330. The failure that started STATBUS-324 was observed in install.sh's
// OWN fetch, which handed git's raw text to the operator. These pin that the
// bash side now delegates to the product instead of reimplementing it.

func installScript(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile(thisRepoFile(t, "install.sh"))
	if err != nil {
		t.Fatalf("read install.sh: %v", err)
	}
	return string(b)
}

// executableLines strips comments, which discuss raw git at length precisely
// because the residue has to be explained. Only what the script DOES counts.
func executableLines(body string) []string {
	var out []string
	for _, line := range strings.Split(body, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		out = append(out, line)
	}
	return out
}

// AC#1: every fetch goes through the delegation, and raw git survives ONLY
// inside the fallback.
func TestEveryFetchDelegatesExceptTheDocumentedFallback(t *testing.T) {
	lines := executableLines(installScript(t))

	var rawFetches []string
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		// A COMMAND, not a mention. install.sh legitimately names `git fetch` in
		// an operator-facing error message, and flagging that told me the script
		// still called git directly when it did not. Only a line that INVOKES it
		// counts: one that begins with the command, optionally behind a negation
		// or an `if`.
		invocation := trimmed
		for _, prefix := range []string{"if ! ", "if ", "! "} {
			invocation = strings.TrimPrefix(invocation, prefix)
		}
		if !strings.HasPrefix(invocation, "git fetch") {
			continue
		}
		// The one permitted raw call is the fallback inside the helper itself.
		if strings.Contains(line, `git fetch "$@"`) {
			continue
		}
		rawFetches = append(rawFetches, trimmed)
	}
	if len(rawFetches) > 0 {
		t.Errorf(`install.sh still calls git fetch directly:

  %s

Those sites hand git's own text to the operator — including the credential
demand that reads as an auth failure when the cause was a refused request.
Route them through statbus_git_fetch so the product's translator applies.`,
			strings.Join(rawFetches, "\n  "))
	}
}

// AC#1: the delegation prefers the product, and raw git is the last resort.
//
// The middle branch this test once demanded — reach for ${HOME}/sb.tmp, the
// downloaded-but-not-yet-moved binary — is deliberately absent. Reading the call
// sites disproved the premise it rested on: no call site can be in that state.
// See TestTheRescueFetchIsReachedWithTheBinaryInPlace for the ordering that
// makes the reachable path delegate.
func TestDelegationPrefersTheProductOverRawGit(t *testing.T) {
	body := installScript(t)

	inPlace := strings.Index(body, `"$STATBUS_DIR/sb" repo-fetch`)
	fallback := strings.Index(body, `git fetch "$@"`)

	if inPlace == -1 {
		t.Error("no delegation to the installed binary")
	}
	if fallback == -1 {
		t.Error("no raw-git fallback for the genuinely-no-binary case")
	}
	if inPlace > fallback {
		t.Error("the delegation must try the product first and fall back last")
	}
}

// The rescue path is where the observed failure happened, and it is the ONLY
// fetch that can delegate. What makes it able to is an ordering: the binary is
// moved into $STATBUS_DIR/sb before the fetch runs. Reorder those two and the
// delegation silently degrades to raw git on the very path it was built for —
// with no error anywhere, because the fallback is legitimate elsewhere. So the
// ordering is pinned here rather than left to be noticed.
func TestTheRescueFetchIsReachedWithTheBinaryInPlace(t *testing.T) {
	body := installScript(t)

	move := strings.Index(body, `mv "${HOME}/sb.tmp" "${STATBUS_DIR}/sb"`)
	fetch := strings.Index(body, "statbus_git_fetch origin --tags")

	if move == -1 {
		t.Fatal("no move of the downloaded binary into place")
	}
	if fetch == -1 {
		t.Fatal("the rescue path no longer delegates its tag fetch")
	}
	if move > fetch {
		t.Error(`the rescue path fetches BEFORE the binary is in place.

The delegation then falls through to raw git on the one path that could have
used the product, and nothing reports it — the fallback is silent by design.`)
	}
}

// AC#2: NO SECOND TRANSLATOR. The bash side must not match on git's error text —
// that reasoning lives in explainGitFailure, once.
func TestBashContainsNoGitErrorTextMatching(t *testing.T) {
	lines := executableLines(installScript(t))

	// Fragments of git's failure text that a bash-side translator would have to
	// match on. Their presence in an executable line means a second translator.
	for _, fragment := range []string{
		"could not read Username",
		"Authentication failed",
		"terminal prompts disabled",
		"expected flush after ref listing",
	} {
		for _, line := range lines {
			if strings.Contains(line, fragment) {
				t.Errorf("install.sh matches git error text (%q) in: %s\n  The translation belongs in explainGitFailure, in one place.", fragment, strings.TrimSpace(line))
			}
		}
	}
}

// AC#3: the residue is documented AT the fallback, with the bootstrapping-order
// reasoning — otherwise the next reader files this ticket again.
func TestFallbackDocumentsTheBootstrapResidue(t *testing.T) {
	body := installScript(t)

	helper := strings.Index(body, "statbus_git_fetch() {")
	if helper == -1 {
		t.Fatal("no delegation helper")
	}
	// The explanation sits immediately above the helper.
	preamble := body[:helper]
	for _, phrase := range []string{
		"RESIDUE",
		"--commit",
		"commit_short",
	} {
		if !strings.Contains(preamble, phrase) {
			t.Errorf("the residue explanation must name %q — the reader has to learn WHICH path cannot delegate and WHY, not merely that one exists", phrase)
		}
	}
	if !strings.Contains(body, "GENUINE RESIDUE") {
		t.Error("the fallback branch itself must be marked as the accepted residue, at the line")
	}
}

// The delegation target must be registered read-only. Without it,
// isMutatingCommand treats it as mutating and the staleness guard hard-fails in
// the normal mid-rescue state — new binary in place, tree not yet checked out to
// match — which is exactly when install.sh calls it. The delegation would then
// break the install it exists to improve.
func TestRepoFetchIsRegisteredReadOnly(t *testing.T) {
	if !readOnlyCommandPaths["sb repo-fetch"] {
		t.Error(`"sb repo-fetch" is not in readOnlyCommandPaths.

install.sh calls it when the binary is newer than the worktree — the normal
mid-rescue state. As a mutating command the staleness guard exits 2 there, so
the delegation would fail at exactly the moment it is needed.`)
	}
}

// It must stay hidden: an internal delegation target, not a command an operator
// discovers in --help. `git fetch` remains the thing a human runs.
func TestRepoFetchIsHidden(t *testing.T) {
	if !repoFetchCmd.Hidden {
		t.Error("repo-fetch must be Hidden — it exists for install.sh, and advertising it adds the public surface the ruling was protecting")
	}
}
