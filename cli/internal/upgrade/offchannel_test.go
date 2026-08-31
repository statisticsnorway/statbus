package upgrade

import (
	"strings"
	"testing"
)

// STATBUS-328 arm 1. The decision is pure and tested without a database, the
// same shape selectStaleBelowInstalled uses beside supersedeBelowInstalled.

func ids(rows ...tagSet) []tagSet { return rows }

// THE LIVE CASE: et, jo and ug carry v2026.08.1-rc.01 rows that predate the
// channel filter, on boxes that follow stable. Those must disappear from the
// offer surface; everything legitimately on channel must survive.
func TestStableBoxRetiresPreFilterRCResidue(t *testing.T) {
	rows := ids(
		tagSet{ID: 1, Tags: []string{"v2026.08.1-rc.01"}}, // the residue
		tagSet{ID: 2, Tags: []string{"v2026.08.2-rc.1"}},  // more of it
		tagSet{ID: 3, Tags: []string{"v2026.08.1"}},       // a real release — keep
		tagSet{ID: 4, Tags: []string{"v2026.09.0"}},       // a newer release — keep
	)

	got := selectOffChannel("stable", rows)

	if len(got) != 2 {
		t.Fatalf("expected exactly the two rc rows retired, got %v", got)
	}
	for _, want := range []int{1, 2} {
		found := false
		for _, id := range got {
			if id == want {
				found = true
			}
		}
		if !found {
			t.Errorf("rc row %d was not retired — the residue stays on the shelf", want)
		}
	}
	for _, keep := range []int{3, 4} {
		for _, id := range got {
			if id == keep {
				t.Errorf("release row %d was retired on a stable box — an on-channel offer was destroyed", keep)
			}
		}
	}
}

// A PRERELEASE BOX RETIRES NOTHING. The channels are nested — prerelease ⊇
// stable — so every shape is legitimate there. A sweep that retired anything on
// such a box would be removing offers it should be making.
func TestPrereleaseBoxRetiresNothing(t *testing.T) {
	rows := ids(
		tagSet{ID: 1, Tags: []string{"v2026.08.1-rc.01"}},
		tagSet{ID: 2, Tags: []string{"v2026.08.1"}},
		tagSet{ID: 3, Tags: []string{"v2026.09.0"}},
	)

	if got := selectOffChannel("prerelease", rows); len(got) != 0 {
		t.Errorf("a prerelease box must retire nothing — the channels are nested, so every shape is on channel; got %v", got)
	}
}

// DUAL-TAGGED ROWS SURVIVE ON A STABLE BOX. A release and its final release
// candidate are two names for ONE commit, so a row carrying both is installable
// under the release name. Requiring every tag to match would retire exactly the
// rows a stable box most wants.
func TestDualTaggedRowSurvivesOnStable(t *testing.T) {
	rows := ids(tagSet{ID: 1, Tags: []string{"v2026.08.1-rc.01", "v2026.08.1"}})

	if got := selectOffChannel("stable", rows); len(got) != 0 {
		t.Errorf("a row tagged with BOTH the rc and the release it became must survive on stable — it is installable under the release name; got %v", got)
	}
}

// UNTAGGED ROWS ARE NEVER TOUCHED. No tags means the row was registered by
// commit SHA — a deliberate operator act, not something discovery shelved. It
// has no channel membership to test, and retiring it would destroy a human
// decision using a predicate that does not apply to it.
func TestUntaggedRowsAreNeverRetired(t *testing.T) {
	rows := ids(
		tagSet{ID: 1, Tags: nil},
		tagSet{ID: 2, Tags: []string{}},
	)

	for _, channel := range []string{"stable", "prerelease", "local"} {
		if got := selectOffChannel(channel, rows); len(got) != 0 {
			t.Errorf("channel %q retired an untagged row %v — those are operator registrations by SHA, not offers", channel, got)
		}
	}
}

// A box on an unrecognised channel must not sweep its whole shelf. TagMatchesChannel
// admits nothing for an unknown channel, so a naive reading of "no tag matches"
// would retire EVERY row — turning a stale config value into ledger destruction.
func TestUnknownChannelDoesNotRetireEverything(t *testing.T) {
	rows := ids(
		tagSet{ID: 1, Tags: []string{"v2026.08.1"}},
		tagSet{ID: 2, Tags: []string{"v2026.08.2-rc.1"}},
	)

	for _, channel := range []string{"edge", "nightly", ""} {
		if got := selectOffChannel(channel, rows); len(got) != 0 {
			t.Errorf("channel %q retired %v — an unrecognised channel must sweep nothing", channel, got)
		}
	}

	// A DEVELOPER BOX follows no channel automatically, so TagMatchesChannel
	// admits nothing for "local" either — same inversion, and this one is not
	// hypothetical: it is every developer machine.
	if got := selectOffChannel("local", rows); len(got) != 0 {
		t.Errorf("a local-channel box retired %v — a developer's registrations are deliberate, not offers to sweep", got)
	}

}

// AC#4: the predicate is channel membership, nothing else. No version-string
// reasoning, and no second copy of the membership rule — a private copy of this
// exact judgement was found and removed from selectLatestTagFromNames in
// STATBUS-307, and this is the place a new one would most naturally appear.
func TestDecisionUsesOnlyTagMatchesChannel(t *testing.T) {
	body := string(packageGoSources(t)["offchannel.go"])

	if !strings.Contains(body, "TagMatchesChannel(") {
		t.Error("the retirement predicate must use TagMatchesChannel — the one definition of on-channel")
	}
	for _, forbidden := range []string{"CompareVersions(", `"-rc."`, "ClassifyReleaseShape("} {
		// Comments may discuss these; only executable lines matter.
		for _, line := range strings.Split(body, "\n") {
			trimmed := strings.TrimSpace(line)
			if trimmed == "" || strings.HasPrefix(trimmed, "//") {
				continue
			}
			if strings.Contains(line, forbidden) {
				t.Errorf("retirement reasons about %s: channel membership and commit identity are the only permitted predicates (AC#4)", forbidden)
			}
		}
	}
}

// AC#3: the sweep must not touch scheduled rows, so the 291 announce remains the
// thing that governs anything still schedulable. A scheduled row is a human
// decision already taken, with that announce in front of them.
func TestSweepTouchesOnlyAvailableRows(t *testing.T) {
	body := string(packageGoSources(t)["offchannel.go"])

	if !strings.Contains(body, "WHERE state = 'available'") {
		t.Error("the SELECT must consider only available rows")
	}
	if !strings.Contains(body, "AND state = 'available'") {
		t.Error("the UPDATE must re-assert state='available' so a concurrently-scheduled row is not clobbered")
	}
	// EXECUTABLE LINES ONLY. The comments discuss scheduled rows at length —
	// explaining why they are deliberately excluded is the point — so a
	// whole-file scan flags the explanation as the violation. This assertion has
	// to look at what the code DOES, not at what it says about itself.
	for i, line := range strings.Split(body, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "//") {
			continue
		}
		if strings.Contains(line, "'scheduled'") {
			t.Errorf("line %d acts on scheduled rows: %q\n  A scheduled row is a decision already taken, with the 291 announce in front of it — not an offer this sweep may withdraw.", i+1, trimmed)
		}
	}
}
