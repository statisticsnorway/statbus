package migrate

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// TestMigrationChannelClass covers the STATBUS-106 channel-only classification:
// the decision depends ONLY on UPGRADE_CHANNEL (the upgrade axis), never on
// CADDY_DEPLOYMENT_MODE (the front-door axis). stable/prerelease→
// release; local/unset/unknown→the safe localDev default. CADDY_DEPLOYMENT_MODE
// is deliberately present in some fixtures to prove it is IGNORED.
func TestMigrationChannelClass(t *testing.T) {
	cases := []struct {
		name string
		env  string
		want migrationChannel
	}{
		{"local channel is localDev", "UPGRADE_CHANNEL=local\n", channelLocalDev},
		{"RETIRED edge is unrecognised — safe default, mode still ignored", "CADDY_DEPLOYMENT_MODE=development\nUPGRADE_CHANNEL=edge\n", channelLocalDev},
		{"dev mode is IGNORED — stable channel still classifies release", "CADDY_DEPLOYMENT_MODE=development\nUPGRADE_CHANNEL=stable\n", channelRelease},
		{"dev mode + local channel is localDev", "CADDY_DEPLOYMENT_MODE=development\nUPGRADE_CHANNEL=local\n", channelLocalDev},
		{"RETIRED edge on a deployed box — safe default", "CADDY_DEPLOYMENT_MODE=private\nUPGRADE_CHANNEL=edge\n", channelLocalDev},
		{"stable channel is release", "CADDY_DEPLOYMENT_MODE=standalone\nUPGRADE_CHANNEL=stable\n", channelRelease},
		{"prerelease channel is release", "CADDY_DEPLOYMENT_MODE=private\nUPGRADE_CHANNEL=prerelease\n", channelRelease},
		{"unrecognized channel falls to localDev (safe)", "UPGRADE_CHANNEL=weird\n", channelLocalDev},
		{"missing channel falls to localDev (safe)", "CADDY_DEPLOYMENT_MODE=private\n", channelLocalDev},
		{"RETIRED edge with no mode — safe default", "UPGRADE_CHANNEL=edge\n", channelLocalDev},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(tc.env), 0o644); err != nil {
				t.Fatal(err)
			}
			if got := migrationChannelClass(dir); got != tc.want {
				t.Errorf("migrationChannelClass(%q) = %d, want %d", tc.env, got, tc.want)
			}
		})
	}
}

// TestMigrationChannelClass_NoEnvFile: an unreadable/missing .env is the SAFE
// default localDev (never auto-bless/redo when the channel is uncertain).
func TestMigrationChannelClass_NoEnvFile(t *testing.T) {
	if got := migrationChannelClass(t.TempDir()); got != channelLocalDev {
		t.Errorf("missing .env: migrationChannelClass = %d, want channelLocalDev (%d)", got, channelLocalDev)
	}
}

// TestEdgeRemovalDidNotShiftNeighbours is the guard the edge retirement was
// gated on, and it exists because of WHERE the change was made rather than how
// big it was.
//
// migrationChannelClass decides how a content_hash MISMATCH on an
// already-applied migration is handled: re-stamp and trust the cut gate
// (release), fall back to a full rebuild (seed-build), or refuse and hand the
// problem to a human (localDev). Deleting a branch from a classifier is exactly
// where a NEIGHBOURING case silently changes meaning — and a channel that
// quietly moved from "stop for a human" to "re-stamp without re-running" would
// bless an unvetted migration edit on a real box, invisibly.
//
// So every input is asserted, not just the one that changed:
//   - stable / prerelease MUST still classify release,
//   - seed-build MUST still classify seedBuild,
//   - local, unset, unreadable and unknown MUST still classify localDev,
//   - and edge, now unknown, MUST classify localDev — the SAFE direction. A box
//     with a stale UPGRADE_CHANNEL=edge in .env gets human guidance, never an
//     auto-redo and never an auto-bless.
func TestEdgeRemovalDidNotShiftNeighbours(t *testing.T) {
	cases := []struct {
		name string
		env  string
		want migrationChannel
	}{
		{"stable is unchanged", "UPGRADE_CHANNEL=stable\n", channelRelease},
		{"prerelease is unchanged", "UPGRADE_CHANNEL=prerelease\n", channelRelease},
		{"seed-build is unchanged", "UPGRADE_CHANNEL=seed-build\n", channelSeedBuild},
		{"local is unchanged", "UPGRADE_CHANNEL=local\n", channelLocalDev},
		{"unset is unchanged", "CADDY_DEPLOYMENT_MODE=private\n", channelLocalDev},
		{"unknown is unchanged", "UPGRADE_CHANNEL=weird\n", channelLocalDev},
		// The retirement itself: edge is no longer a channel, so it is simply an
		// unrecognised value and takes the safe default with every other one.
		{"RETIRED edge falls to the SAFE default", "UPGRADE_CHANNEL=edge\n", channelLocalDev},
		// Mode must still be ignored on every one of them — the upgrade axis and
		// the front-door axis stay decoupled (STATBUS-106).
		{"mode is still ignored for stable", "CADDY_DEPLOYMENT_MODE=development\nUPGRADE_CHANNEL=stable\n", channelRelease},
		{"mode is still ignored for edge", "CADDY_DEPLOYMENT_MODE=development\nUPGRADE_CHANNEL=edge\n", channelLocalDev},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(c.env), 0o644); err != nil {
				t.Fatal(err)
			}
			if got := migrationChannelClass(dir); got != c.want {
				t.Errorf(`CLASSIFICATION SHIFTED: %q classified %d, want %d.

Removing the edge branch must not change what any OTHER channel means. A channel
that moved from "refuse and ask a human" to "re-stamp and trust the gate" would
bless an unvetted migration edit on a real box, and nothing would say so.`,
					c.env, got, c.want)
			}
		})
	}
}

// TestNoEdgeChannelRemains: the retirement is a clean break, so the value must
// not survive anywhere in this classifier. A leftover branch here would be
// worse than the old behaviour — it would apply edge semantics on a box that
// can no longer be deliberately put on edge.
func TestNoEdgeChannelRemains(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	b, err := os.ReadFile(filepath.Join(filepath.Dir(thisFile), "migrate.go"))
	if err != nil {
		t.Fatal(err)
	}
	src := stripComments(string(b))

	if !strings.Contains(src, "migrationChannelClass") {
		t.Fatal("the classifier was not found — the scan lost its subject, and a check that examines nothing must fail rather than pass")
	}
	for _, gone := range []string{`case "edge"`, "channelEdge"} {
		if strings.Contains(src, gone) {
			t.Errorf(`the retired edge channel is still live in migrate.go (%s).

Edge was retired deliberately (King, 2026-08-19): no role derives it, so no box
can be put on it on purpose. A surviving branch would apply always-latest
semantics — including auto-redo with data loss — to a box that arrived at the
value by accident.`, gone)
		}
	}
}

// stripComments removes // line comments so the guard above is not tripped by
// the very prose that explains the retirement.
func stripComments(src string) string {
	var b strings.Builder
	for _, line := range strings.Split(src, "\n") {
		if t := strings.TrimSpace(line); strings.HasPrefix(t, "//") {
			continue
		}
		b.WriteString(line)
		b.WriteString("\n")
	}
	return b.String()
}

// TestZeroValueIsTheConservativeClassification encodes the LESSON rather than
// the current answer.
//
// The edge retirement turned on the fact that these constants are `iota` — that
// removing one renumbers the rest. That was safe because no value is persisted
// or compared numerically. But it left a second property load-bearing and
// unguarded: channelLocalDev is now the ZERO value, so anything that reaches a
// classification without being assigned one gets the conservative branch.
//
// The two branches are not symmetric. localDev REFUSES a changed migration and
// asks a human; channelRelease RE-STAMPS it, trusting the cut gate. So if a
// future tidy-up sorts this block alphabetically, or moves the "most common"
// case to the top, an uninitialised value silently starts meaning TRUST THE
// BLESS — on a real box, with no error, from a change whose diff looks like
// housekeeping.
func TestZeroValueIsTheConservativeClassification(t *testing.T) {
	var unset migrationChannel // exactly what any unassigned path yields

	if unset != channelLocalDev {
		t.Fatalf(`THE ZERO VALUE IS NO LONGER THE CONSERVATIVE CLASSIFICATION (it is now %d).

These constants are iota, so whichever is declared FIRST is what an unassigned
migrationChannel means — a var never assigned, a struct field never set, a
future map lookup that misses.

That value must be channelLocalDev, which REFUSES a changed migration and asks a
human. If channelRelease takes position zero, an uninitialised classification
silently means RE-STAMP IT, TRUSTING THE CUT GATE: a migration edit nobody
vetted gets blessed on a production box, with nothing printed to say so.

Move channelLocalDev back to the top of the const block. If a reorder is
genuinely wanted, the conservative case still has to be first.`, unset)
	}

	// And state the asymmetry the property rests on, so a reader who wonders why
	// the order matters does not have to reconstruct it: the two classifications
	// must remain DIFFERENT, or "conservative" stops meaning anything here.
	if channelLocalDev == channelRelease {
		t.Error("localDev and release must be distinct classifications — they take opposite actions on a content_hash mismatch (refuse-and-ask vs re-stamp-and-trust)")
	}
}
