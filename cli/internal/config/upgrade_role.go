package config

import (
	"fmt"
	"sort"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

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
		return "", fmt.Errorf("%s", unknownRoleRefusal(string(role)))
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

// roleFromLegacyChannel infers a role from a channel value, for the ONE-TIME
// translation below.
//
// `edge` maps to development, and after the edge channel's RETIREMENT (King,
// 2026-08-19) this is the last place in the tree that mentions it — deliberately.
// A box whose .env.config still carries UPGRADE_CHANNEL=edge is exactly the box
// this translation exists for: it has to be read ONCE and converted, or that box
// refuses on its next config generate with a key it cannot legally hold.
// Development is the right landing place, because what edge meant — follow
// whatever is newest, automatically — is the one thing no box does any more.
//
// So this arm outlives the channel it names, and it dies with the rest of the
// translation once the fleet has run it. It is not a surviving edge reference to
// be tidied away by someone grepping for the word.
func roleFromLegacyChannel(channel string) (UpgradeRole, bool) {
	switch strings.TrimSpace(channel) {
	case "stable":
		return RoleProduction, true
	case "prerelease":
		return RoleCanary, true
	case "local", "edge":
		return RoleDevelopment, true
	}
	return "", false
}

// ResolveUpgradeRole is the whole mechanism, operating on the loaded
// .env.config so it is testable without touching a disk or a fleet.
//
// It returns the role, a notice to print (empty when there is nothing to say),
// and an error that must STOP config generate.
//
// Order is load-bearing:
//  1. TRANSLATE — channel present, no role: promote the channel into a role.
//  2. SEED — no role at all: declare the mode-appropriate default explicitly.
//  3. REFUSE a hand-added channel — after (1), a channel alongside a role can
//     only mean someone re-added the key by hand.
//  4. VALIDATE the role against the closed set.
//
// The caller must Save() the file: steps 1 and 2 mutate it.
func ResolveUpgradeRole(f *dotenv.File, deploymentMode string) (UpgradeRole, string, error) {
	rawRole, hasRole := f.Get(UpgradeRoleKey)
	rawChannel, hasChannel := f.Get(UpgradeChannelKey)

	var notice string

	switch {
	case hasChannel && !hasRole:
		// STEP 1 — THE ONE-TIME TRANSLATION.
		//
		// Every box in the fleet holds an explicit UPGRADE_CHANNEL today,
		// including the seven an operator corrected by hand on 2026-08-19. Under
		// this design that key is an input that no longer exists — so a naive
		// rollout would refuse on every box we just fixed, breaking the fleet at
		// the moment the durable fix lands.
		//
		// So the operator's correction is not fought; it is READ ONCE and
		// promoted into the durable form. Every box lands on the role its
		// corrected channel already implies, with no second per-box pass. The
		// first fleet-wide run is self-verifying: if the seven boxes come out as
		// six production and one canary, the mechanism reproduced by computation
		// a state we established independently by hand.
		//
		// >>> THIS TRANSLATION IS A ONE-TIME CORRECTION AND MUST BE DELETED once
		// >>> every box has run it. It is not a compatibility shim. Leaving it in
		// >>> place would permanently re-admit the very key this ticket removes,
		// >>> and internal code here ships as clean breaks. Delete this case, and
		// >>> the translation notice with it; the guard below then covers the key
		// >>> entirely (a hand-added channel with no role becomes a refusal, which
		// >>> is the correct end state).
		role, ok := roleFromLegacyChannel(rawChannel)
		if !ok {
			return "", "", fmt.Errorf("%s", untranslatableChannelRefusal(rawChannel))
		}
		f.Set(UpgradeRoleKey, string(role))
		f.Delete(UpgradeChannelKey)
		notice = translationNotice(rawChannel, role)
		return role, notice, nil

	case !hasRole:
		// STEP 2 — SEED. A fresh box has neither key. Declare the default
		// EXPLICITLY in .env.config rather than defaulting silently at every
		// read: the operator can then see what this box is and change it. The
		// role is a statement, so writing it down once is exactly right; it is
		// the CHANNEL that must never be stored this way.
		role := defaultRoleForMode(deploymentMode)
		f.Set(UpgradeRoleKey, string(role))
		return role, seedNotice(role, deploymentMode), nil
	}

	// STEP 3 — THE LOUD GUARD. A role is declared AND a channel is present.
	// After the translation window that can only mean a hand-added key.
	//
	// A refusal, not a warning: a warning is honoured-or-ignored ambiguously and
	// the operator never learns which. Silently ignoring it would be worse — the
	// operator would believe they had set the channel, which is how the fleet
	// ended up here in the first place.
	if hasChannel {
		derived, _ := ChannelForRole(UpgradeRole(rawRole))
		return "", "", fmt.Errorf("%s", handAddedChannelRefusal(rawChannel, rawRole, derived))
	}

	// STEP 4 — VALIDATE. An unknown role refuses rather than falling back.
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

func translationNotice(channel string, role UpgradeRole) string {
	derived := roleChannels[role]
	return fmt.Sprintf(
		"%s is now derived from %s, so this box's setting has been converted once:\n"+
			"  %s=%s  (removed from .env.config)\n"+
			"  %s=%s  (added — this box's role)\n"+
			"The upgrade channel is written to .env as %q on every config generate.\n"+
			"Change %s in .env.config if this box's purpose is different.\n",
		UpgradeChannelKey, UpgradeRoleKey,
		UpgradeChannelKey, channel,
		UpgradeRoleKey, role,
		derived,
		UpgradeRoleKey)
}

func seedNotice(role UpgradeRole, deploymentMode string) string {
	return fmt.Sprintf(
		"%s was not set — declared as %q for a %s-mode box, and written to .env.config.\n"+
			"This box will follow the %q channel. Set %s=%s in .env.config if this box is\n"+
			"meant to take release candidates first.\n",
		UpgradeRoleKey, role, deploymentMode,
		roleChannels[role], UpgradeRoleKey, RoleCanary)
}

func handAddedChannelRefusal(channel, role, derived string) string {
	return fmt.Sprintf(
		"%s is set in .env.config, but it is no longer a setting — it is derived from %s.\n"+
			"  %s=%s   (declared)\n"+
			"  %s=%s   (hand-set — ignored by nothing; this command refuses rather than pick one)\n"+
			"  derived channel for this role: %s\n"+
			"Five production installations once sat on the wrong channel for two months because a\n"+
			"stored channel outlived the policy that set it. That is why this key cannot be set.\n"+
			"To fix: state what this box IS — set %s to one of (%s) — and remove %s from\n"+
			".env.config.\n",
		UpgradeChannelKey, UpgradeRoleKey,
		UpgradeRoleKey, role,
		UpgradeChannelKey, channel,
		derivedOrUnknown(derived),
		UpgradeRoleKey, knownRoles(), UpgradeChannelKey)
}

func derivedOrUnknown(derived string) string {
	if derived == "" {
		return "(none — the declared role is not recognised either)"
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

func untranslatableChannelRefusal(channel string) string {
	return fmt.Sprintf(
		"%s=%q in .env.config cannot be converted to a role automatically.\n"+
			"The channel is now derived from %s. Set %s to one of (%s) in .env.config and\n"+
			"remove %s.\n",
		UpgradeChannelKey, channel, UpgradeRoleKey, UpgradeRoleKey, knownRoles(), UpgradeChannelKey)
}
