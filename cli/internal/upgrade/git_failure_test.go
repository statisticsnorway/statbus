package upgrade

import (
	"errors"
	"strings"
	"testing"
)

// STATBUS-324 third item. The repo is PUBLIC, so a credential demand from this
// remote is never an auth failure — it is git falling back to auth after the
// request failed for another reason. These pin that we say so.

// The exact text gh produced, and the text the same failure produces now that
// GIT_TERMINAL_PROMPT=0 is set. Both must be translated: the flag changed only
// the trailing clause, which is why the flag alone did not fix the message.
const (
	gitOutBeforeFlag = "fatal: could not read Username for 'https://github.com': Device not configured\n"
	gitOutAfterFlag  = "fatal: could not read Username for 'https://github.com': terminal prompts disabled\n"
	gitOutRefListing = "fatal: could not read Username for 'https://github.com': terminal prompts disabled\nfatal: expected flush after ref listing\n"
)

func TestCredentialDemandIsReportedAsAnUnreachableRemote(t *testing.T) {
	for name, out := range map[string]string{
		"before the prompt flag":  gitOutBeforeFlag,
		"after the prompt flag":   gitOutAfterFlag,
		"gh's full two-line form": gitOutRefListing,
	} {
		t.Run(name, func(t *testing.T) {
			got := explainGitFailure("git", out, errors.New("exit status 128"))
			if got == nil {
				t.Fatal("a failed git command must still return an error")
			}
			msg := got.Error()

			// The claim we are entitled to make.
			if !strings.Contains(msg, "could not reach") {
				t.Errorf("must report an unreachable/refused remote:\n%s", msg)
			}
			// The correction that saves the support cycle.
			if !strings.Contains(msg, "NOT an authentication problem") {
				t.Errorf("must say plainly that this is not an auth failure:\n%s", msg)
			}
			// The reason it is safe to say so — a fact about our own remote.
			if !strings.Contains(msg, "public") {
				t.Errorf("must give the reason (the repo is public):\n%s", msg)
			}
			// Never destroy the raw text: a support bundle needs it.
			if !strings.Contains(msg, "could not read Username") {
				t.Errorf("git's own output must be preserved for diagnosis:\n%s", msg)
			}
			// The original error must remain unwrappable for callers that classify.
			if !strings.Contains(msg, "exit status 128") {
				t.Errorf("underlying error must survive:\n%s", msg)
			}
		})
	}
}

// It must say only what we know. Throttling is the OBSERVED cause on niue, but
// an unreachable host or a refusing proxy produces the same symptom, so the
// message may not assert a specific cause as fact.
func TestMessageDoesNotAssertACauseWeHaveNotObserved(t *testing.T) {
	msg := explainGitFailure("git", gitOutAfterFlag, errors.New("exit status 128")).Error()

	// Rate limiting is offered as the common case, hedged — never stated as the
	// diagnosis of this particular failure.
	if strings.Contains(msg, "is rate-limited") || strings.Contains(msg, "you are being throttled") {
		t.Errorf("must not assert throttling as the established cause of THIS failure:\n%s", msg)
	}
	if !strings.Contains(msg, "Most often seen when") {
		t.Errorf("the common cause should be offered as a hint, hedged:\n%s", msg)
	}
}

// Untouched cases: a successful command, a non-git command, and a git failure
// with unrelated output all pass through exactly as before. The translator must
// not become a general error rewriter.
func TestUnrelatedFailuresArePassedThroughUnchanged(t *testing.T) {
	underlying := errors.New("exit status 1")

	if got := explainGitFailure("git", "anything", nil); got != nil {
		t.Errorf("success must stay nil, got %v", got)
	}
	// A non-git command whose output happens to contain the phrase must not be
	// rewritten — the reasoning rests on it being OUR git remote.
	if got := explainGitFailure("docker", gitOutAfterFlag, underlying); got != underlying {
		t.Errorf("non-git command must pass through unchanged, got %v", got)
	}
	ordinary := "fatal: not a git repository (or any of the parent directories): .git\n"
	if got := explainGitFailure("git", ordinary, underlying); got != underlying {
		t.Errorf("an unrelated git failure must pass through unchanged, got %v", got)
	}
}

// "Authentication failed" is the other shape the same non-auth situation takes
// (a refusing proxy, a 401 from a rate limiter). Same reasoning, same treatment.
func TestAuthenticationFailedIsAlsoTranslated(t *testing.T) {
	out := "remote: Authentication failed for 'https://github.com/statisticsnorway/statbus.git/'\n"
	msg := explainGitFailure("git", out, errors.New("exit status 128")).Error()
	if !strings.Contains(msg, "NOT an authentication problem") {
		t.Errorf("the 'Authentication failed' shape must be translated too:\n%s", msg)
	}
}
