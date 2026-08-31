package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// STATBUS-307 acceptance criteria. A box declares WHAT IT IS; that decides what
// it follows unless someone writes otherwise.

func envConfigWith(t *testing.T, lines ...string) *dotenv.File {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, ".env.config")
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
		t.Fatalf("write .env.config: %v", err)
	}
	f, err := dotenv.Load(path)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	return f
}

// AC: the mode→channel table, live.
func TestModeDerivesChannel(t *testing.T) {
	for mode, want := range map[string]string{
		"development": "local",
		"private":     "stable",
		"standalone":  "stable",
	} {
		t.Run(mode, func(t *testing.T) {
			got, err := ResolveUpgradeChannel(envConfigWith(t, "X=1"), mode)
			if err != nil {
				t.Fatalf("resolve: %v", err)
			}
			if got != want {
				t.Errorf("mode %q derived %q, want %q", mode, got, want)
			}
		})
	}
}

// AC: a written channel ALWAYS wins. Topology never implies purpose — leading is
// a written choice, and our niue slots and rune depend on exactly this.
func TestWrittenChannelBeatsTheMode(t *testing.T) {
	// A private slot that has declared prerelease keeps it.
	f := envConfigWith(t, "UPGRADE_CHANNEL=prerelease")
	got, err := ResolveUpgradeChannel(f, "private")
	if err != nil {
		t.Fatalf("resolve: %v", err)
	}
	if got != "prerelease" {
		t.Errorf("a written channel must win over the mode's derivation; got %q", got)
	}

	// And in the other direction: a development box told to follow stable does.
	// This is what the install-recovery VMs rely on — development MODE, release
	// channel behaviour.
	f = envConfigWith(t, "UPGRADE_CHANNEL=stable")
	got, err = ResolveUpgradeChannel(f, "development")
	if err != nil {
		t.Fatalf("resolve: %v", err)
	}
	if got != "stable" {
		t.Errorf("a development-mode box declaring stable must follow stable; got %q", got)
	}
}

// AC: changing the mode MOVES the derived channel on a box with no written
// channel, and does NOT on a box with one. Both directions tested, because the
// second is the safety property that makes live derivation acceptable at all.
func TestModeChangeMovesOnlyUndeclaredBoxes(t *testing.T) {
	undeclared := envConfigWith(t, "X=1")
	if got, _ := ResolveUpgradeChannel(undeclared, "development"); got != "local" {
		t.Fatalf("setup: got %q", got)
	}
	if got, _ := ResolveUpgradeChannel(undeclared, "standalone"); got != "stable" {
		t.Errorf("an undeclared box must follow its mode when the mode changes; got %q", got)
	}

	declared := envConfigWith(t, "UPGRADE_CHANNEL=prerelease")
	for _, mode := range []string{"development", "private", "standalone"} {
		if got, _ := ResolveUpgradeChannel(declared, mode); got != "prerelease" {
			t.Errorf("mode %q moved a DECLARED channel to %q — a written value must be untouched by a mode change", mode, got)
		}
	}
}

// AC: an unknown channel value refuses, naming the accepted values.
func TestUnknownChannelRefuses(t *testing.T) {
	_, err := ResolveUpgradeChannel(envConfigWith(t, "UPGRADE_CHANNEL=nightly"), "standalone")
	if err == nil {
		t.Fatal("an unknown channel must refuse, not fall through to a channel nobody chose")
	}
	msg := err.Error()
	for _, want := range []string{"nightly", "local", "prerelease", "stable"} {
		if !strings.Contains(msg, want) {
			t.Errorf("refusal must name the offending value and the accepted set (missing %q):\n%s", want, msg)
		}
	}
}

// An unknown MODE refuses too — the same reasoning one level up. Falling through
// to a channel would be the fabricated policy this design removes.
func TestUnknownModeRefuses(t *testing.T) {
	_, err := ResolveUpgradeChannel(envConfigWith(t, "X=1"), "kubernetes")
	if err == nil {
		t.Fatal("an unknown deployment mode must refuse rather than derive a channel")
	}
	if !strings.Contains(err.Error(), "kubernetes") {
		t.Errorf("refusal must name the offending mode:\n%s", err)
	}
}

// AC (RED-VERIFIED BY CONSTRUCTION): resolution must never WRITE. Seeding is
// what let a stale value outlive the policy that set it on five production
// installations; if this ever seeds again, an unspecified box acquires a key
// that a later hand-edit can contradict, and STATBUS-254 returns.
func TestResolutionNeverSeedsTheChannel(t *testing.T) {
	for _, mode := range []string{"development", "private", "standalone"} {
		f := envConfigWith(t, "CADDY_DEPLOYMENT_MODE="+mode)
		if _, err := ResolveUpgradeChannel(f, mode); err != nil {
			t.Fatalf("resolve: %v", err)
		}
		if v, ok := f.Get(UpgradeChannelKey); ok {
			t.Errorf("mode %q seeded %s=%q into .env.config — the derived value belongs only in the generated .env", mode, UpgradeChannelKey, v)
		}
	}
}

// ── Fleet transition ─────────────────────────────────────────────────────────

// SEEDED: the written role equals the mode's old default, so it was never a
// choice. Delete it; the derived channel is identical.
func TestTransitionDeletesASeededRole(t *testing.T) {
	for _, tc := range []struct{ mode, role, wantChannel string }{
		{"development", "development", "local"},
		{"private", "production", "stable"},
		{"standalone", "production", "stable"},
	} {
		t.Run(tc.mode+"/"+tc.role, func(t *testing.T) {
			f := envConfigWith(t, "UPGRADE_"+"ROLE="+tc.role)
			notice := MigrateLegacyUpgradeRole(f, tc.mode)

			if _, ok := f.Get("UPGRADE_" + "ROLE"); ok {
				t.Error("a seeded role must be deleted")
			}
			if v, ok := f.Get(UpgradeChannelKey); ok {
				t.Errorf("a seeded role must NOT leave a written channel behind (got %q) — that would re-create the very key the design removes", v)
			}
			got, err := ResolveUpgradeChannel(f, tc.mode)
			if err != nil {
				t.Fatalf("resolve after transition: %v", err)
			}
			if got != tc.wantChannel {
				t.Errorf("effective channel changed across the transition: got %q, want %q", got, tc.wantChannel)
			}
			if notice == "" {
				t.Error("the transition must say what it did — a box silently rewriting its own config is what this ticket exists to stop")
			}
		})
	}
}

// DECLARED: the written role differs from the mode's default, so it was
// deliberate. Preserve it as the channel it always meant.
func TestTransitionPreservesADeclaredRole(t *testing.T) {
	// A canary on any mode, and a production box in development mode — both are
	// choices somebody made against their mode's default.
	for _, tc := range []struct{ mode, role, wantChannel string }{
		{"private", "canary", "prerelease"},
		{"standalone", "canary", "prerelease"},
		{"development", "production", "stable"},
	} {
		t.Run(tc.mode+"/"+tc.role, func(t *testing.T) {
			f := envConfigWith(t, "UPGRADE_"+"ROLE="+tc.role)
			MigrateLegacyUpgradeRole(f, tc.mode)

			if _, ok := f.Get("UPGRADE_" + "ROLE"); ok {
				t.Error("the retired key must be removed even when its meaning is preserved")
			}
			got, err := ResolveUpgradeChannel(f, tc.mode)
			if err != nil {
				t.Fatalf("resolve after transition: %v", err)
			}
			if got != tc.wantChannel {
				t.Errorf("a DECLARED choice was not preserved: got %q, want %q", got, tc.wantChannel)
			}
		})
	}
}

// AC 8, per box shape: EVERY existing installation keeps its current effective
// channel across the transition. This is the criterion that says nobody's box
// moves, and it is proven rather than asserted.
func TestEveryExistingBoxShapeKeepsItsChannel(t *testing.T) {
	for _, tc := range []struct {
		name, mode, role, effectiveBefore string
	}{
		{"developer laptop", "development", "development", "local"},
		{"niue private slot", "private", "production", "stable"},
		{"standalone NSO box", "standalone", "production", "stable"},
		{"canary", "private", "canary", "prerelease"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := envConfigWith(t, "UPGRADE_"+"ROLE="+tc.role)
			MigrateLegacyUpgradeRole(f, tc.mode)
			after, err := ResolveUpgradeChannel(f, tc.mode)
			if err != nil {
				t.Fatalf("resolve: %v", err)
			}
			if after != tc.effectiveBefore {
				t.Errorf("%s changed channel across the transition: was %q, now %q",
					tc.name, tc.effectiveBefore, after)
			}
		})
	}
}

// A box with no retired key is untouched — the overwhelmingly common case after
// the first run, and the reason this is a one-time correction rather than a
// standing repair path.
func TestTransitionIsANoOpWithoutTheRetiredKey(t *testing.T) {
	f := envConfigWith(t, "CADDY_DEPLOYMENT_MODE=standalone")
	if notice := MigrateLegacyUpgradeRole(f, "standalone"); notice != "" {
		t.Errorf("nothing to migrate must be silent, got: %s", notice)
	}
	if _, ok := f.Get(UpgradeChannelKey); ok {
		t.Error("a box with no retired key must not acquire a channel")
	}
}
