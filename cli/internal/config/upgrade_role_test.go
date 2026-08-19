package config

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// STATBUS-254. Five statistical offices' PRODUCTION installations followed
// release candidates for two months. Nobody chose that: the channel was written
// once at box creation and nothing ever recomputed it, so when the default
// changed on 2026-06-21 not one box noticed.
//
// These tests pin the property that makes that impossible again — the channel
// is DERIVED from the box's declared role on every config generate — and each
// guard that keeps a stored channel from creeping back in.

func loadEnv(t *testing.T, content string) *dotenv.File {
	t.Helper()
	path := filepath.Join(t.TempDir(), ".env.config")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	f, err := dotenv.Load(path)
	if err != nil {
		t.Fatal(err)
	}
	return f
}

// TestEveryRoleDerivesAChannel_STATBUS254: the policy table is total. A role in
// the closed set that derives nothing would fall through to whatever the caller
// does on error — which is how a box ends up on a channel nobody chose.
func TestEveryRoleDerivesAChannel_STATBUS254(t *testing.T) {
	want := map[UpgradeRole]string{
		RoleProduction:  "stable",
		RoleCanary:      "prerelease",
		RoleDevelopment: "local",
	}
	for role, expected := range want {
		got, err := ChannelForRole(role)
		if err != nil {
			t.Errorf("role %q derives no channel: %v", role, err)
			continue
		}
		if got != expected {
			t.Errorf("role %q derives %q, want %q", role, got, expected)
		}
	}
	if len(roleChannels) != len(want) {
		t.Errorf(`the role set changed (%d entries, this test knows %d).

The set is closed on purpose. A new role is a policy decision about what a KIND
of box follows — add it here deliberately, with the channel it derives, rather
than letting it appear untested.`, len(roleChannels), len(want))
	}
}

// TestUnknownRoleRefuses_STATBUS254 is AC#5's symmetric half, and the one most
// easily got wrong: it is tempting to fall back to "stable" for an unrecognised
// role. That is the same mechanism as the original defect, one level deeper —
// a box quietly following something nobody declared.
func TestUnknownRoleRefuses_STATBUS254(t *testing.T) {
	f := loadEnv(t, "UPGRADE_ROLE=producton\n") // a plausible typo
	_, _, err := ResolveUpgradeRole(f, "standalone")
	if err == nil {
		t.Fatal("an unknown role must REFUSE — a silent default is exactly how five installations sat on the wrong channel unseen")
	}
	msg := err.Error()
	for _, want := range []string{"producton", "canary", "development", "production"} {
		if !strings.Contains(msg, want) {
			t.Errorf("the refusal must name the bad value and the valid set; %q missing from:\n%s", want, msg)
		}
	}
}

// TestHandAddedChannelRefuses_STATBUS254 is AC#5's main half. After the
// translation window, UPGRADE_CHANNEL in .env.config can only be a hand-added
// key. Honouring it silently would restore the defect; ignoring it silently
// would leave the operator believing they had set the channel. Neither is
// acceptable, so it refuses.
func TestHandAddedChannelRefuses_STATBUS254(t *testing.T) {
	f := loadEnv(t, "UPGRADE_ROLE=production\nUPGRADE_CHANNEL=prerelease\n")
	_, _, err := ResolveUpgradeRole(f, "standalone")
	if err == nil {
		t.Fatal("a hand-added UPGRADE_CHANNEL must REFUSE, not be silently honoured or silently ignored")
	}
	msg := err.Error()
	// The refusal has to be actionable: name the key, the declared role, the
	// channel that role derives, and the one action that resolves it.
	for _, want := range []string{"UPGRADE_CHANNEL", "UPGRADE_ROLE", "production", "prerelease", "stable", "remove"} {
		if !strings.Contains(msg, want) {
			t.Errorf("the refusal is not actionable — %q missing from:\n%s", want, msg)
		}
	}
}

// TestOneTimeTranslation_STATBUS254 covers the case the whole rollout turns on.
//
// Every box in the fleet holds an explicit UPGRADE_CHANNEL right now, including
// the seven an operator corrected by hand. If the durable fix simply refused
// that key, it would break every box we had just fixed, at the moment it
// landed. Instead the correction is READ ONCE and promoted into the role it
// already implies.
func TestOneTimeTranslation_STATBUS254(t *testing.T) {
	cases := []struct {
		channel string
		want    UpgradeRole
	}{
		{"stable", RoleProduction}, // et/jo/ma/tcc/ug/demo after the correction
		{"prerelease", RoleCanary}, // dev after the correction
		{"local", RoleDevelopment}, // a developer machine
		{"edge", RoleDevelopment},  // the old always-latest setting
	}
	for _, c := range cases {
		f := loadEnv(t, "UPGRADE_CHANNEL="+c.channel+"\n")
		role, notice, err := ResolveUpgradeRole(f, "standalone")
		if err != nil {
			t.Fatalf("channel %q must translate, not refuse: %v", c.channel, err)
		}
		if role != c.want {
			t.Errorf("channel %q translated to role %q, want %q", c.channel, role, c.want)
		}
		// The key must be GONE, not left behind — a leftover would make the very
		// next config generate refuse on a box that just translated cleanly.
		if _, still := f.Get(UpgradeChannelKey); still {
			t.Errorf("channel %q: UPGRADE_CHANNEL survived the translation; the next config generate would then refuse", c.channel)
		}
		if got, ok := f.Get(UpgradeRoleKey); !ok || got != string(c.want) {
			t.Errorf("channel %q: UPGRADE_ROLE not written (got %q, present=%v)", c.channel, got, ok)
		}
		if notice == "" {
			t.Errorf("channel %q translated SILENTLY — a one-time conversion of an operator's setting must say what it did", c.channel)
		}
	}
}

// TestTranslationIsIdempotentByConstruction_STATBUS254: running config generate
// twice must not fail the second time. This is what makes the rollout safe on a
// fleet where nobody controls how often the command runs.
func TestTranslationIsIdempotentByConstruction_STATBUS254(t *testing.T) {
	f := loadEnv(t, "UPGRADE_CHANNEL=stable\n")
	first, notice, err := ResolveUpgradeRole(f, "standalone")
	if err != nil {
		t.Fatal(err)
	}
	if notice == "" {
		t.Error("the first run must announce the conversion")
	}
	second, notice2, err := ResolveUpgradeRole(f, "standalone")
	if err != nil {
		t.Fatalf("the SECOND run refused — the translation is not idempotent, so every box would fail on its next config generate: %v", err)
	}
	if second != first {
		t.Errorf("the second run resolved a different role (%q vs %q)", second, first)
	}
	if notice2 != "" {
		t.Error("the conversion must announce ONCE; repeating it every run trains operators to ignore it")
	}
}

// TestFreshBoxDerivesTheSameChannelAsBefore_STATBUS254 is the equivalence
// guard, and it is why the seeded role is mode-aware.
//
// The old default was: development mode → "local", everything else → "stable".
// A flat "production" default would have derived "stable" on every developer's
// machine and silently switched their migration-fix behaviour from
// stop-for-a-human to auto-bless. Fixing a value that changed under boxes
// unnoticed, by changing a value under boxes unnoticed, would be its own defect.
func TestFreshBoxDerivesTheSameChannelAsBefore_STATBUS254(t *testing.T) {
	cases := []struct {
		mode        string
		wantRole    UpgradeRole
		wantChannel string // exactly what the pre-STATBUS-254 default produced
	}{
		{"development", RoleDevelopment, "local"},
		{"standalone", RoleProduction, "stable"},
		{"private", RoleProduction, "stable"},
	}
	for _, c := range cases {
		f := loadEnv(t, "")
		role, notice, err := ResolveUpgradeRole(f, c.mode)
		if err != nil {
			t.Fatalf("mode %q: a fresh box must resolve, not refuse: %v", c.mode, err)
		}
		if role != c.wantRole {
			t.Errorf("mode %q seeded role %q, want %q", c.mode, role, c.wantRole)
		}
		ch, err := ChannelForRole(role)
		if err != nil {
			t.Fatal(err)
		}
		if ch != c.wantChannel {
			t.Errorf(`mode %q now derives channel %q, but the pre-STATBUS-254 default gave %q.

This change must not move any existing box to a different channel. Deriving
"stable" on a developer machine would switch its migration-fix logic from
stop-for-a-human to auto-bless — silently, which is the defect this ticket is
about.`, c.mode, ch, c.wantChannel)
		}
		// Seeded, not silently defaulted: the declaration must land in the file
		// where an operator can read and change it.
		if got, ok := f.Get(UpgradeRoleKey); !ok || got != string(c.wantRole) {
			t.Errorf("mode %q: the seeded role must be WRITTEN to .env.config (got %q, present=%v)", c.mode, got, ok)
		}
		if notice == "" {
			t.Errorf("mode %q: seeding a role must be announced — an operator has to know what this box was declared to be", c.mode)
		}
	}
}

// TestRoleIsNotReDerivedFromMode_STATBUS254: the mode is consulted ONCE, to
// seed. A box whose deployment mode later changes must keep the role it
// declared — otherwise the role becomes just as derived as the channel, and a
// developer-mode debugging session on a production box would silently change
// what it follows.
func TestRoleIsNotReDerivedFromMode_STATBUS254(t *testing.T) {
	f := loadEnv(t, "UPGRADE_ROLE=canary\n")
	role, _, err := ResolveUpgradeRole(f, "development")
	if err != nil {
		t.Fatal(err)
	}
	if role != RoleCanary {
		t.Errorf("a declared role must survive a mode change; got %q under development mode, want canary", role)
	}
}

// TestChannelIsNeverSetIfAbsent_STATBUS254 is AC#7 as a MECHANISM rather than a
// comment, and it guards the exact line that caused this ticket.
//
// dotenv.Generate preserves an existing value FOREVER — correct for a
// declaration, catastrophic for a value that must follow policy. If anyone
// reintroduces UPGRADE_CHANNEL into that set-if-absent tier, the whole defect
// returns: boxes keep whatever they were born with, and a later policy change
// reaches none of them.
func TestChannelIsNeverSetIfAbsent_STATBUS254(t *testing.T) {
	src := readConfigSource(t, "config.go")

	for _, forbidden := range []string{
		`gen("UPGRADE_CHANNEL"`,
		`Generate("UPGRADE_CHANNEL"`,
		`Generate(UpgradeChannelKey`,
		`gen(UpgradeChannelKey`,
	} {
		if strings.Contains(src, forbidden) {
			t.Errorf(`UPGRADE_CHANNEL is being written through the set-if-absent tier (%s).

THAT IS THE DEFECT THIS TICKET EXISTS TO REMOVE. dotenv.Generate writes only on
a miss, so the value a box was created with survives every regenerate, every
reinstall, and every change to what the default should be. Five statistical
offices' production installations followed release candidates for two months
because of exactly this line.

The channel is DERIVED from UPGRADE_ROLE (upgrade_role.go) and written only to
the generated .env.`, forbidden)
		}
	}

	// And the generated .env must write the DERIVED value, not read a stored one
	// back out of .env.config — that read is the other half of the same defect.
	if strings.Contains(src, `getOrDefault("UPGRADE_CHANNEL"`) {
		t.Error(`.env is being written from a stored UPGRADE_CHANNEL in .env.config.

A stored channel is what outlived the policy that set it. The generated value
must come from ChannelForRole(cfg.UpgradeRole).`)
	}
	if !strings.Contains(src, "cfg.UpgradeChannel") {
		t.Error("the generated .env must write the derived channel (cfg.UpgradeChannel) — the scan lost its subject, and a check that examines nothing must fail rather than pass")
	}
}

// TestGenerateCarriesTheWarning_STATBUS254 is AC#7's second half. The pin above
// catches a regression; this makes the next author not write it in the first
// place, at the single place every one of them passes through.
func TestGenerateCarriesTheWarning_STATBUS254(t *testing.T) {
	src := readDotenvSource(t)
	i := strings.Index(src, "func (f *File) Generate(")
	if i < 0 {
		t.Fatal("dotenv.Generate not found — the scan lost its subject")
	}
	// The doc comment sits immediately above the signature.
	head := src[:i]
	start := strings.LastIndex(head, "\n\n")
	if start < 0 {
		start = 0
	}
	doc := head[start:]

	for _, want := range []string{"UPGRADE_CHANNEL", "derive"} {
		if !strings.Contains(doc, want) {
			t.Errorf(`dotenv.Generate's doc comment must warn that this preserves a value FOREVER, and that a value which must follow policy has to be derived instead (%q missing).

This is the one place every future author meets the behaviour. It has already
cost five production installations two months on the wrong channel; a sentence
here is cheaper than rediscovering it.`, want)
		}
	}
}

func readConfigSource(t *testing.T, name string) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	b, err := os.ReadFile(filepath.Join(filepath.Dir(thisFile), name))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func readDotenvSource(t *testing.T) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	b, err := os.ReadFile(filepath.Join(filepath.Dir(thisFile), "..", "dotenv", "dotenv.go"))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}
