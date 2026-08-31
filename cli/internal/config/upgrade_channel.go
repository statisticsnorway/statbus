package config

import (
	"errors"
	"fmt"
	"sort"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// ErrPrincipledRefusal marks an error as a DETERMINISTIC configuration
// refusal — invalid declared state that cannot be resolved by retrying, as
// opposed to a transient failure (disk full, permissions, a momentarily-locked
// file). STATBUS-298: every refusal here wraps this sentinel so a caller can ask
// `errors.Is(err, config.ErrPrincipledRefusal)` structurally, rather than
// matching the refusal TEXT — a text match creates a second copy of the message
// the pin does not cover; an edit that forgets to update a scattered text-match
// discriminator silently stops matching, and refusals go back to being retried
// five times into a db-down box. The compiler carries the meaning instead.
//
// (Moved here from upgrade_role.go, which STATBUS-307 deletes. The sentinel is
// used well beyond upgrade policy — cmd/config.go's exit-78 and service.go's
// park both key on it — so it outlives the mechanism it was born beside.)
var ErrPrincipledRefusal = errors.New("principled configuration refusal")

// refusalError wraps an already-composed, human-readable refusal message with
// ErrPrincipledRefusal via Unwrap — WITHOUT altering the displayed text
// (Error() returns msg verbatim; the sentinel never appears in the
// operator-facing string).
type refusalError struct{ msg string }

func (e *refusalError) Error() string { return e.msg }
func (e *refusalError) Unwrap() error { return ErrPrincipledRefusal }

// newRefusal is the sole constructor for a principled-refusal error here, so
// none can drift into a plain fmt.Errorf that the sentinel-based discriminator
// would silently miss.
func newRefusal(msg string) error { return &refusalError{msg: msg} }

// ─────────────────────────────────────────────────────────────────────────────
// STATBUS-307: A BOX DECLARES WHAT IT IS. THAT DECIDES WHAT IT FOLLOWS.
//
// Two variables, not three. CADDY_DEPLOYMENT_MODE says what the box IS;
// UPGRADE_CHANNEL exists only to record an EXCEPTION. An unremarkable
// installation stores nothing at all about upgrade policy.
//
//	development  → local
//	private      → stable
//	standalone   → stable      (standalone is the default mode)
//
// A WRITTEN UPGRADE_CHANNEL ALWAYS WINS. Topology never implies purpose:
// leading is a written choice, not something a box acquires by being deployed a
// particular way. Our niue slots and rune write `prerelease` because their
// purpose is to test and show before others do.
//
// DERIVATION IS LIVE; SEEDING STOPS. .env.config holds only what is SPECIFIED.
// The channel is derived on every `config generate` and written to the generated
// .env — NEVER back into .env.config. This overrules the previous rationale
// ("a box that changes mode does not silently change what it follows"), and it
// is safe for a reason worth stating: only a box that NEVER STATED a channel
// follows its mode, and for such a box the mode IS its statement. A box with an
// opinion has written it down, and a written value is untouched by a mode change.
//
// WHY STATBUS-254 CANNOT RECUR. 254 was two keys disagreeing. One of them no
// longer exists, so the disagreement has no second party. And because nothing is
// ever seeded, an unspecified box stores NOTHING — there is no previously-seeded
// value for a later hand-edit to contradict, and a single key cannot contradict
// itself. The guard therefore INVERTS: UPGRADE_CHANNEL is no longer "never a
// setting" but THE setting, visible exactly where someone chose it. One refusal
// survives — an unknown channel VALUE.
//
// THE BOUNDARY THAT MUST NOT BE MISREAD, written here because the misreading is
// natural ("defaults shall suit standalone, so when inputs disagree just take the
// standalone default"):
//
//	Absent input takes the declared default. Contradictory input refuses.
//	A default answers a question nobody asked; it never settles a question
//	two inputs answered differently.
//
// Defaulting an ABSENT value is the product having a defined identity.
// Defaulting a CONTRADICTORY one is resolving someone's conflict by preference —
// a guess wearing a default's clothes, and the STATBUS-291 harm arriving by
// convenience.
// ─────────────────────────────────────────────────────────────────────────────

// UpgradeChannelKey is named rather than spelled inline so every refusal message
// and every guard talks about the same string.
const UpgradeChannelKey = "UPGRADE_CHANNEL"

// modeChannels IS THE POLICY. One table, one place to change what a kind of box
// follows — and changing it here reaches every box that has not written a
// channel, on its next config generate.
var modeChannels = map[string]string{
	"development": "local",
	"private":     "stable",
	"standalone":  "stable",
}

// knownChannels is the closed set a box may DECLARE.
//
// Deliberately excludes "seed-build": that value is written directly into a .env
// by the hermetic seed-builder stage (postgres/Dockerfile), never through config
// generate and never into .env.config. It is a build-stage marker, not a policy
// declaration, and accepting it here would invite someone to declare it on a real
// box — where migrationChannelClass would then classify the box as a seed builder.
var knownChannels = map[string]struct{}{
	"local":      {},
	"stable":     {},
	"prerelease": {},
}

// ChannelForMode returns the channel a deployment mode derives.
//
// An unrecognised mode is a refusal, not a fallback: falling through to a
// channel nobody chose is precisely the fabricated policy this design exists to
// remove.
func ChannelForMode(mode string) (string, error) {
	ch, ok := modeChannels[mode]
	if !ok {
		return "", newRefusal(unknownModeRefusal(mode))
	}
	return ch, nil
}

// ResolveUpgradeChannel returns the channel this box follows.
//
// Order is load-bearing:
//  1. A WRITTEN channel in .env.config wins — validated against the closed set.
//  2. Otherwise DERIVE from the deployment mode.
//
// It never mutates the file. That is the whole point of "seeding stops": the
// caller has nothing to Save on account of upgrade policy, and an unremarkable
// box therefore carries no upgrade-policy key at all.
func ResolveUpgradeChannel(f *dotenv.File, deploymentMode string) (string, error) {
	if raw, ok := f.Get(UpgradeChannelKey); ok {
		declared := strings.TrimSpace(raw)
		if err := ValidateChannel(declared); err != nil {
			return "", err
		}
		return declared, nil
	}
	return ChannelForMode(deploymentMode)
}

// ValidateChannel reports whether a channel name is one this product knows.
//
// Exported so the `upgrade channel` verb validates against the SAME closed set
// config generate applies. A verb with its own list could accept a value the
// generator then refuses, handing the operator a box that will not configure
// itself — and the two lists would drift the first time one changed.
func ValidateChannel(channel string) error {
	if _, known := knownChannels[channel]; !known {
		return newRefusal(unknownChannelRefusal(channel))
	}
	return nil
}

// knownChannelNames renders the closed set for error messages, sorted so the
// text is stable across runs (map order is not).
func knownChannelNames() string {
	names := make([]string, 0, len(knownChannels))
	for c := range knownChannels {
		names = append(names, c)
	}
	sort.Strings(names)
	return strings.Join(names, ", ")
}

// knownModeNames renders the modes that derive a channel, sorted.
func knownModeNames() string {
	names := make([]string, 0, len(modeChannels))
	for m := range modeChannels {
		names = append(names, m)
	}
	sort.Strings(names)
	return strings.Join(names, ", ")
}

func unknownChannelRefusal(channel string) string {
	return fmt.Sprintf(`REFUSING: %s=%q in .env.config is not a channel this product knows.

  Accepted values: %s

  This key is an EXCEPTION, not a requirement. An ordinary installation sets
  nothing here and follows the channel its deployment mode derives:
%s
  To follow the derived channel, delete the %s line from .env.config.
  To follow a different one deliberately, set it to one of the accepted values.
`, UpgradeChannelKey, channel, knownChannelNames(), modeTableForMessage(), UpgradeChannelKey)
}

func unknownModeRefusal(mode string) string {
	return fmt.Sprintf(`REFUSING: CADDY_DEPLOYMENT_MODE=%q in .env.config is not a deployment mode this product knows.

  Accepted values: %s

  The mode decides what this box follows when no %s is written:
%s`, mode, knownModeNames(), UpgradeChannelKey, modeTableForMessage())
}

// modeTableForMessage renders the policy table itself into refusals, so an
// operator reading the error sees the actual rule rather than a description of
// it — and so the message cannot drift from the table it describes.
func modeTableForMessage() string {
	modes := make([]string, 0, len(modeChannels))
	for m := range modeChannels {
		modes = append(modes, m)
	}
	sort.Strings(modes)
	var b strings.Builder
	for _, m := range modes {
		fmt.Fprintf(&b, "      %-12s → %s\n", m, modeChannels[m])
	}
	return b.String()
}

// missingSiteDomainRefusal is the one place the product admits it cannot know
// something. Every other default in config generate is the product declaring
// what it is; this is a fact only the installation's owner holds.
//
// It refuses rather than guessing because a guessed domain produces a
// configuration that CANNOT SERVE — Caddy would request a certificate for a name
// the operator does not control — and the failure would surface later, further
// from its cause, as a TLS error rather than a missing setting.
func missingSiteDomainRefusal() string {
	return `REFUSING: SITE_DOMAIN is not set, and this is a standalone installation.

  A standalone box serves the public internet over HTTPS, so it must know the
  domain name it answers to. This is the one thing the product cannot decide for
  you: every other setting has a default suitable for a standard installation,
  but your domain belongs to you, not to us.

  Set it in .env.config:

      SITE_DOMAIN=statbus.example.org

  Then run this command again. Nothing else is required — the remaining defaults
  already suit a production installation.
`
}

// ─────────────────────────────────────────────────────────────────────────────
// FLEET TRANSITION — a one-time translation of the retired UPGRADE_ROLE key.
//
// THE DISCRIMINATOR, so no box needs a human judgement:
//
//	If the written role EQUALS the default for that box's mode, it was SEEDED —
//	delete it; the derived channel gives the identical answer.
//	If it DIFFERS, it was DECLARED — write the matching UPGRADE_CHANNEL.
//
// Safe in both directions, which is what makes it mechanical: deleting a seeded
// value changes nothing (the derivation reproduces it exactly), and a differing
// value is by definition someone's deliberate choice, so it is preserved as the
// channel it always meant.
//
// Worked through for the three shapes that exist:
//   - a development box seeded `development` → deleted; mode derives `local`.
//   - a private niue slot or standalone NSO box seeded `production` → deleted;
//     mode derives `stable`.
//   - a box declaring `canary` on any mode → differs from every default, so it
//     is preserved as UPGRADE_CHANNEL=prerelease.
//
// THIS IS A ONE-TIME CORRECTION, NOT A STANDING SELF-HEAL. It fires once per
// box, removes its own trigger, and can never fire again — the key is gone. Once
// the fleet has run it, this function and its caller should be DELETED rather
// than left in place; a permanent translator for a key nothing writes is a
// standing repair path, which this project does not keep.
// ─────────────────────────────────────────────────────────────────────────────

// legacyUpgradeRoleKey is the retired key. Named here, in the one function that
// still knows it exists, so nothing else in the tree carries the string.
const legacyUpgradeRoleKey = "UPGRADE_" + "ROLE"

// legacyRoleChannels is what each retired role derived, preserved only to
// translate a DECLARED value into the channel it always meant.
var legacyRoleChannels = map[string]string{
	"production":  "stable",
	"canary":      "prerelease",
	"development": "local",
}

// legacyDefaultRoleForMode reproduces the retired seeding rule: development mode
// seeded `development`, everything else seeded `production`. Needed to tell a
// seeded value from a declared one — the entire basis of the discriminator.
func legacyDefaultRoleForMode(mode string) string {
	if mode == "development" {
		return "development"
	}
	return "production"
}

// MigrateLegacyUpgradeRole translates a retired UPGRADE_ROLE into the new model.
// It mutates f; the caller saves. Returns a notice to print, empty when there
// was nothing to do (the overwhelmingly common case after the first run).
func MigrateLegacyUpgradeRole(f *dotenv.File, deploymentMode string) string {
	rawRole, hasRole := f.Get(legacyUpgradeRoleKey)
	if !hasRole {
		return ""
	}
	role := strings.TrimSpace(rawRole)
	f.Delete(legacyUpgradeRoleKey)

	if role == legacyDefaultRoleForMode(deploymentMode) {
		derived, err := ChannelForMode(deploymentMode)
		if err != nil {
			// An unknown mode is refused elsewhere with a better message; here
			// the honest report is that the key was seeded and is now gone.
			derived = "the channel its mode derives"
		}
		return fmt.Sprintf(
			"NOTE: removed the retired %s=%s from .env.config.\n"+
				"  It was the default for this box's deployment mode (%s), so it was seeded rather\n"+
				"  than chosen, and the derived channel is identical: %s. Nothing about this box\n"+
				"  changes — upgrade policy simply stops being configuration it has to carry.\n",
			legacyUpgradeRoleKey, role, deploymentMode, derived)
	}

	channel, ok := legacyRoleChannels[role]
	if !ok {
		// A role outside the retired closed set. Preserve nothing and say so
		// loudly: inventing a channel for an unrecognised declaration is exactly
		// the fabricated policy this design removes.
		return fmt.Sprintf(
			"WARNING: removed %s=%q from .env.config, which is not a role this product ever defined.\n"+
				"  No channel was written for it. This box now follows the channel its deployment\n"+
				"  mode (%s) derives. If it was meant to follow something else, set %s explicitly.\n",
			legacyUpgradeRoleKey, role, deploymentMode, UpgradeChannelKey)
	}
	f.Set(UpgradeChannelKey, channel)
	return fmt.Sprintf(
		"NOTE: translated the retired %s=%s in .env.config into %s=%s.\n"+
			"  It DIFFERED from this mode's default, so it was a deliberate choice and is\n"+
			"  preserved as the channel it always meant — now visible on the line that makes it.\n",
		legacyUpgradeRoleKey, role, UpgradeChannelKey, channel)
}
