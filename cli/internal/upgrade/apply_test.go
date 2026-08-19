package upgrade

import (
	"strings"
	"testing"
)

// STATBUS-258. The product could already install a named version — as two
// commands an operator had to know to pair, in an order that fails if you get it
// wrong. So callers reached for apply-latest instead, which installs whatever is
// NEWEST rather than what was asked for, and a chain waiting on one specific
// commit could be handed a different one.
//
// These pin the properties that make `apply` the right shape rather than a
// convenience wrapper: it composes the existing paths, it installs exactly what
// was named, and it stays general.

// TestApplyComposesRegisterAndSchedule_STATBUS258: apply must REUSE the
// registration and promotion paths, not reimplement them.
//
// A second implementation is the real risk here. registerStep carries the
// STATBUS-169 tag↔commit write-guard and the ensureCommitLocal fetch;
// scheduleStep carries the un-park carve-out and the atomic recovery-budget
// reset. A hand-rolled INSERT or UPDATE in apply would silently lack all of
// that, and would look correct in review.
func TestApplyComposesRegisterAndSchedule_STATBUS258(t *testing.T) {
	body := extractFuncBody(t, readUpgradeApplySource(t), "func (d *Service) RunApply(")

	for _, want := range []string{"d.registerStep(ctx, input)", "d.scheduleStep(ctx, input, recreate)"} {
		if !strings.Contains(body, want) {
			t.Errorf("RunApply must call %s — composing the existing guarded paths is the whole design", want)
		}
	}
	// No second way to write the row. These are the shapes a reimplementation
	// would take, and each would bypass a guard that exists for a reason.
	for _, forbidden := range []string{"INSERT INTO public.upgrade", "UPDATE public.upgrade", "upsertCandidate("} {
		if strings.Contains(body, forbidden) {
			t.Errorf(`RunApply writes the upgrade row directly (%q).

It must go through registerStep and scheduleStep. Those carry the tag↔commit
write-guard, the commit fetch, the parked-row carve-out and the atomic
recovery-budget reset — a direct write has none of them and looks fine.`, forbidden)
		}
	}
}

// TestApplyRunsInOneConnection_STATBUS258: register and schedule happen inside a
// SINGLE runOneShot.
//
// Two would open two connections and leave a window where the candidate is
// registered but unscheduled — a state visible in `upgrade list` that no other
// product path produces, and one an operator would reasonably act on.
func TestApplyRunsInOneConnection_STATBUS258(t *testing.T) {
	body := extractFuncBody(t, readUpgradeApplySource(t), "func (d *Service) RunApply(")
	if n := strings.Count(body, "runOneShot"); n != 1 {
		t.Errorf("RunApply opens %d one-shot connections, want exactly 1 — a second leaves a registered-but-unscheduled window", n)
	}
}

// TestApplyIsGeneral_STATBUS258 is the architect's test, pinned: any operator of
// any installation would want this verb.
//
// The moment it learns about roles, channels, our fleet's box names, or "latest",
// it stops being the general verb and becomes our deployment script wearing a
// product command's name.
func TestApplyIsGeneral_STATBUS258(t *testing.T) {
	body := extractFuncBody(t, readUpgradeApplySource(t), "func (d *Service) RunApply(")

	for _, leak := range []string{
		"UPGRADE_ROLE", "RoleCanary", "RoleProduction",
		"prerelease", "stable", "ResolveChannelToLatestTag",
		"statbus_dev", "niue",
	} {
		if strings.Contains(body, leak) {
			t.Errorf(`RunApply references %q.

This verb installs EXACTLY what it was given. A channel, a role, or one of our
box names inside it would make the product know about our fleet — and would give
the command a second behaviour nobody asked for at the call site.`, leak)
		}
	}
}

// TestApplyRegistersUnconditionally_STATBUS258: the register step is not guarded
// by "is it already registered?".
//
// registerStep is idempotent, so the guard would buy nothing and cost the
// property an operator actually relies on when repeating a command after a
// failure: that apply behaves identically whether or not the box has seen this
// candidate before.
func TestApplyRegistersUnconditionally_STATBUS258(t *testing.T) {
	body := extractFuncBody(t, readUpgradeApplySource(t), "func (d *Service) RunApply(")
	regAt := strings.Index(body, "d.registerStep(")
	schedAt := strings.Index(body, "d.scheduleStep(")
	if regAt < 0 || schedAt < 0 {
		t.Fatal("both steps must be present — the scan lost its subject, and a check that examines nothing must fail rather than pass")
	}
	if regAt > schedAt {
		t.Error("register must run BEFORE schedule — schedule fails fast on an unregistered target, which is exactly the pairing this verb exists to remove")
	}
	before := body[:regAt]
	for _, cond := range []string{"if exists", "alreadyRegistered", "SELECT state", "if registered"} {
		if strings.Contains(before, cond) {
			t.Errorf("registration is conditional (%q) — it must be unconditional, so a repeat of this command behaves the same as the first run", cond)
		}
	}
}

// TestApplyRefusalIsActionable_STATBUS258: a refusal must tell the operator what
// to DO, and cover each distinct reason separately, because they need different
// actions.
//
// The assets-not-ready case matters most: it is NOT a failure, it resolves
// itself when CI lands, and an operator who reads it as an error will go hunting
// for a problem that does not exist.
func TestApplyRefusalIsActionable_STATBUS258(t *testing.T) {
	advice := applyRegisterAdvice("v2026.08.1")

	if !strings.Contains(advice, "v2026.08.1") {
		t.Error("the refusal must quote the target the operator actually typed — a generic message cannot be checked against what they meant")
	}
	for _, want := range []struct{ needle, why string }{
		{"commit_short", "the accepted vocabulary must be spelled out; 'invalid target' does not tell anyone what a valid one looks like"},
		{"upgrade list", "the operator needs a way to see what this box already knows"},
		{"clone", "a commit pushed minutes ago may not be on the box yet — a different problem with a different fix"},
		{"Release assets not ready", "the CI-still-building case must be named as a WAIT, not diagnosed as an error"},
		{"nothing is lost by waiting", "and it must say so plainly, or the operator goes looking for a fault that is not there"},
	} {
		if !strings.Contains(advice, want.needle) {
			t.Errorf("the refusal never mentions %q — %s", want.needle, want.why)
		}
	}
}

// TestApplySaysWhatHappensNext_STATBUS258: "scheduled" is not "installed", and
// the gap between them is where an operator stands waiting with no idea what
// they are waiting for.
func TestApplySaysWhatHappensNext_STATBUS258(t *testing.T) {
	body := extractFuncBody(t, readUpgradeApplySource(t), "func (d *Service) RunApply(")
	for _, want := range []string{"scheduled", "backs up", "rolls back", "upgrade list"} {
		if !strings.Contains(body, want) {
			t.Errorf("the success message never mentions %q — the operator is left guessing what the command actually set in motion", want)
		}
	}
}

func readUpgradeApplySource(t *testing.T) string {
	t.Helper()
	return string(packageGoSources(t)["apply.go"])
}
