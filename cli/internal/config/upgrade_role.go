package config

import (
	"errors"
	"fmt"
	"sort"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// ErrPrincipledRefusal marks an error as a DETERMINISTIC configuration
// refusal — ambiguous or invalid declared state that cannot be resolved by
// retrying, as opposed to a transient failure (disk full, permissions,
// a momentarily-locked file). STATBUS-298: every refusal this file returns
// wraps this sentinel so a caller can ask `errors.Is(err,
// config.ErrPrincipledRefusal)` structurally, rather than matching the
// refusal TEXT — a text match creates a second copy of the message the
// existing STATBUS-254 pin does not cover; an edit to the message that
// forgets to update a scattered text-match discriminator silently stops
// matching, and refusals go back to being retried five times into a
// db-down box (architect ruling, STATBUS-298 ticket comment #1). The
// compiler carries the meaning instead (the same move as STATBUS-293's
// typed CommitSHA/CommitShort/CommitVersion).
//
// Every refusal in THIS file is a member: an unknown role, and a channel
// present in .env.config at all (with or without a declared role — the
// one-time translation that used to distinguish those cases is retired) are
// both the SAME class (a human declared something ambiguous or invalid; the
// fix is to edit .env.config, never to wait) — so both wrap it identically.
var ErrPrincipledRefusal = errors.New("principled configuration refusal")

// refusalError wraps an already-composed, human-readable refusal message
// with ErrPrincipledRefusal via Unwrap — WITHOUT altering the displayed
// text (Error() returns msg verbatim; the sentinel never appears in the
// operator-facing string). errors.Is(err, ErrPrincipledRefusal) works
// structurally through Unwrap regardless.
type refusalError struct{ msg string }

func (e *refusalError) Error() string { return e.msg }
func (e *refusalError) Unwrap() error { return ErrPrincipledRefusal }

// newRefusal is the sole constructor for a principled-refusal error in this
// file — every one of the three refusal sites below uses it, so none can
// drift into a plain fmt.Errorf that the sentinel-based discriminator would
// silently miss.
func newRefusal(msg string) error { return &refusalError{msg: msg} }

// STATBUS-254: THE CHANNEL IS DERIVED FROM THE BOX'S ROLE, NOT REMEMBERED.
//
// Five statistical offices' production installations sat on the PRERELEASE
// channel for two months. Not because anyone chose it — because the value was
// written once at box creation and nothing ever recomputed it. The mode-aware
// default landed 2026-06-21 (2393c028a); the boxes predate it; `config
// generate` fills a key only when it is ABSENT (dotenv.Generate), so every
// later regenerate, every reinstall, and every change to what the default
// SHOULD be left the stale value untouched. The fleet could not self-correct.
//
// The fix is not a better default. It is to stop storing a value nobody
// recomputes:
//
//   - The ROLE is a STATEMENT OF INTENT — what this box is FOR. It changes only
//     when a human changes what the box is for, so remembering it is correct.
//     It lives in .env.config.
//   - The CHANNEL is a CONSEQUENCE OF POLICY — what boxes of that kind should
//     follow. When we change that policy (stable today, an LTS line tomorrow),
//     EVERY box must pick it up. It is derived on every config generate and
//     written to the generated .env only.
//
// The mapping is one-to-one today, and a reader who notices that will fairly
// ask whether this is just a rename. It is not, and the reason is the whole
// point: a renamed key would drift exactly as the old one did. What changes is
// WHICH OF THE TWO IS OURS TO CHANGE. The policy now lives in one table in this
// file, and changing it reaches the entire fleet through the one operator
// action the product already has. That is precisely what failed here — the
// default moved and not one box noticed.
//
// This is NOT a standing self-heal (which is forbidden). A self-heal silently
// repairs someone's input; this makes the value stop being an input. .env is a
// generated file already, and nobody calls regenerating it self-healing. There
// is nothing left to repair because there is nothing left to corrupt.

// UpgradeRole is what a box IS, on the upgrade axis. A closed set: an unknown
// value is refused rather than defaulted, because absent-means-default is the
// exact mechanism that produced this ticket.
//
// Deliberately NOT derived from an existing key:
//   - CADDY_DEPLOYMENT_MODE is the wrong axis. STATBUS-106 decoupled the upgrade
//     axis from the front-door mode on purpose, and re-coupling them cannot
//     express the case we have: Norway and an ordinary standalone share a mode
//     and need different channels.
//   - DEPLOYMENT_SLOT_CODE is a NAME. Deriving from it would bake OUR fleet's
//     names into a product statistical offices install — a customer whose slot
//     happened to be called "dev" would be treated as our canary. The product
//     must not know about our boxes.
type UpgradeRole string

const (
	// RoleProduction is an ordinary installation: it follows blessed releases.
	// Every NSO box is this.
	RoleProduction UpgradeRole = "production"
	// RoleCanary takes release candidates FIRST, deliberately, so that a bad
	// candidate is found on a box we own rather than in a statistical office.
	// A canary is always an explicit declaration, never arrived at by default.
	RoleCanary UpgradeRole = "canary"
	// RoleDevelopment is a developer's own machine: it follows nothing
	// automatically, and its migration-fix logic stops for a human rather than
	// auto-mutating.
	RoleDevelopment UpgradeRole = "development"
)

// UpgradeRoleKey and UpgradeChannelKey are named rather than spelled inline so
// every refusal message and every guard talks about the same two strings.
const (
	UpgradeRoleKey    = "UPGRADE_ROLE"
	UpgradeChannelKey = "UPGRADE_CHANNEL"
)

// roleChannels IS THE POLICY. One table, one place to change what a kind of box
// follows — and changing it here reaches every box on its next config generate,
// which is the entire point of this ticket.
var roleChannels = map[UpgradeRole]string{
	RoleProduction:  "stable",
	RoleCanary:      "prerelease",
	RoleDevelopment: "local",
}

// ChannelForRole returns the channel a role currently derives. The error is not
// decorative: an unrecognised role must stop config generate rather than fall
// through to a channel nobody chose.
func ChannelForRole(role UpgradeRole) (string, error) {
	ch, ok := roleChannels[role]
	if !ok {
		return "", newRefusal(unknownRoleRefusal(string(role)))
	}
	return ch, nil
}

// knownRoles renders the closed set for error messages, sorted so the text is
// stable across runs (map order is not).
func knownRoles() string {
	names := make([]string, 0, len(roleChannels))
	for r := range roleChannels {
		names = append(names, string(r))
	}
	sort.Strings(names)
	return strings.Join(names, ", ")
}

// defaultRoleForMode is the role a FRESH box declares when it has none yet.
//
// It is mode-aware for one specific reason, and the reason is equivalence: the
// channel this produces must match what the box would have had before this
// change. The old default was development mode → "local", everything else →
// "stable" (config.go, STATBUS-106). A flat "production" default would have
// derived "stable" on every developer's machine and quietly switched their
// migration-fix behaviour from stop-for-a-human to auto-bless. This ticket is
// about a value that changed under boxes without anyone noticing; introducing a
// second instance of that while fixing the first would be its own defect.
//
// Note what this is NOT: it is not a derivation of role from mode. The mode is
// consulted ONCE, to seed an explicit declaration into .env.config where the
// operator can see and change it. Afterwards the role is read, never re-derived
// — a box that changes mode does not silently change what it follows.
func defaultRoleForMode(deploymentMode string) UpgradeRole {
	if deploymentMode == "development" {
		return RoleDevelopment
	}
	return RoleProduction
}

// ResolveUpgradeRole is the whole mechanism, operating on the loaded
// .env.config so it is testable without touching a disk or a fleet.
//
// It returns the role, a notice to print (empty when there is nothing to say),
// and an error that must STOP config generate.
//
// Order is load-bearing:
//  1. REFUSE a present channel, unconditionally — with or without a
//     declared role, UPGRADE_CHANNEL in .env.config can only mean a
//     hand-added or leftover key (STATBUS-254's one-time fleet translation
//     is retired: every box has run it).
//  2. SEED — no role at all: declare the mode-appropriate default explicitly.
//  3. VALIDATE the role against the closed set.
//
// The caller must Save() the file: step 2 mutates it.
func ResolveUpgradeRole(f *dotenv.File, deploymentMode string) (UpgradeRole, string, error) {
	rawRole, hasRole := f.Get(UpgradeRoleKey)
	rawChannel, hasChannel := f.Get(UpgradeChannelKey)

	// STEP 1 — THE LOUD GUARD. A channel is present at all. The one-time
	// translation that used to promote a channel-only box into its implied
	// role is retired (STATBUS-254 removal marker; every box in the fleet
	// showed the role form as of the 2026-08-30 convergence check) — so
	// this now covers the key entirely, whether or not a role is also
	// declared.
	//
	// A refusal, not a warning: a warning is honoured-or-ignored ambiguously
	// and the operator never learns which. Silently ignoring it would be
	// worse — the operator would believe they had set the channel, which is
	// how the fleet ended up on the wrong one for two months in the first
	// place.
	if hasChannel {
		derived, _ := ChannelForRole(UpgradeRole(rawRole))
		return "", "", newRefusal(handAddedChannelRefusal(rawChannel, rawRole, derived))
	}

	if !hasRole {
		// STEP 2 — SEED. A fresh box has neither key. Declare the default
		// EXPLICITLY in .env.config rather than defaulting silently at every
		// read: the operator can then see what this box is and change it. The
		// role is a statement, so writing it down once is exactly right; it is
		// the CHANNEL that must never be stored this way.
		role := defaultRoleForMode(deploymentMode)
		f.Set(UpgradeRoleKey, string(role))
		return role, seedNotice(role, deploymentMode), nil
	}

	// STEP 3 — VALIDATE. An unknown role refuses rather than falling back.
	// Absent-means-default is the mechanism that produced this ticket; so is
	// unknown-means-default, and it is even harder to see.
	role := UpgradeRole(strings.TrimSpace(rawRole))
	if _, err := ChannelForRole(role); err != nil {
		return "", "", err
	}
	return role, "", nil
}

// The refusal and notice texts are built by pure functions so their exact
// wording is unit-tested directly, and so the operator-facing sentence a
// statistical office reads is reviewable in one place.

func seedNotice(role UpgradeRole, deploymentMode string) string {
	return fmt.Sprintf(
		"%s was not set — declared as %q for a %s-mode box, and written to .env.config.\n"+
			"This box will follow the %q channel. Set %s=%s in .env.config if this box is\n"+
			"meant to take release candidates first.\n",
		UpgradeRoleKey, role, deploymentMode,
		roleChannels[role], UpgradeRoleKey, RoleCanary)
}

// handAddedChannelRefusal covers BOTH shapes of "UPGRADE_CHANNEL present"
// after STATBUS-254's one-time translation retired: a channel alongside a
// declared role (role is non-empty), and a channel with no role at all
// (role is empty — the translation's own former input shape, now refused
// instead of promoted). The role line adapts so the message reads correctly
// either way instead of printing a hollow `UPGRADE_ROLE=   (declared)`.
func handAddedChannelRefusal(channel, role, derived string) string {
	roleLine := fmt.Sprintf("  %s=%s   (declared)", UpgradeRoleKey, role)
	if role == "" {
		roleLine = fmt.Sprintf("  %s is not set either", UpgradeRoleKey)
	}
	return fmt.Sprintf(
		"%s is set in .env.config, but it is no longer a setting — it is derived from %s.\n"+
			"%s\n"+
			"  %s=%s   (hand-set — ignored by nothing; this command refuses rather than pick one)\n"+
			"  derived channel for this role: %s\n"+
			"Five production installations once sat on the wrong channel for two months because a\n"+
			"stored channel outlived the policy that set it. That is why this key cannot be set.\n"+
			"To fix: state what this box IS — set %s to one of (%s) — and remove %s from\n"+
			".env.config.\n",
		UpgradeChannelKey, UpgradeRoleKey,
		roleLine,
		UpgradeChannelKey, channel,
		derivedOrUnknown(derived),
		UpgradeRoleKey, knownRoles(), UpgradeChannelKey)
}

func derivedOrUnknown(derived string) string {
	if derived == "" {
		return "(none — no role is declared, or the declared role is not recognised)"
	}
	return derived
}

func unknownRoleRefusal(role string) string {
	return fmt.Sprintf(
		"%s=%q in .env.config is not a role this version knows (%s).\n"+
			"Refusing rather than choosing a channel for you: a box that silently defaults is exactly\n"+
			"how five statistical offices' installations sat on the wrong channel without anyone\n"+
			"being able to see it.\n",
		UpgradeRoleKey, role, knownRoles())
}
