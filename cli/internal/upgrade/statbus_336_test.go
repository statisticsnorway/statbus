package upgrade

import (
	"strings"
	"testing"
)

func TestDiscoverPrunesAgainstAllGitTags_STATBUS336(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) discover(")
	if !strings.Contains(body, "d.pruneDeletedTags(ctx, tags)") {
		t.Fatal("discover must pass the unfiltered git tag list to pruneDeletedTags; channel filtering decides offers, not tag existence")
	}
	if strings.Contains(body, "d.pruneDeletedTags(ctx, filtered)") {
		t.Fatal("discover still passes the channel-filtered tag list to pruneDeletedTags, so live off-channel tags are treated as deleted")
	}
}

func TestChannelExcludedTagSurvivesTicksUntilDeletedInGit_STATBUS336(t *testing.T) {
	rowSHA := CommitSHA("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
	offChannelTag := "v2026.09.1-rc.01"
	allGitTags := []GitTag{
		{TagName: "v2026.09.1", CommitSHA: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
		{TagName: offChannelTag, CommitSHA: string(rowSHA)},
	}
	if filtered := FilterTagsByChannel(allGitTags, "stable"); len(filtered) != 1 || filtered[0].TagName == offChannelTag {
		t.Fatalf("test fixture is invalid: %s must exist in git but be excluded by the stable channel", offChannelTag)
	}

	rowTags := []string{offChannelTag}
	for tick := 1; tick <= 2; tick++ {
		gitTagSHAs := make(map[string]CommitSHA, len(allGitTags))
		for _, tag := range allGitTags {
			gitTagSHAs[tag.TagName] = CommitSHA(tag.CommitSHA)
		}
		var kept []string
		for _, tag := range rowTags {
			if keepTagForRow(tag, gitTagSHAs, rowSHA) {
				kept = append(kept, tag)
			}
		}
		rowTags = kept
		if len(rowTags) != 1 || rowTags[0] != offChannelTag {
			t.Fatalf("discovery tick %d pruned live channel-excluded tag %s from its row", tick, offChannelTag)
		}
	}

	// Git deletion, unlike channel exclusion, removes the tag on the next tick.
	gitTagSHAs := map[string]CommitSHA{
		"v2026.09.1": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
	}
	if keepTagForRow(offChannelTag, gitTagSHAs, rowSHA) {
		t.Fatalf("genuinely git-deleted tag %s survived pruning", offChannelTag)
	}
}

func TestCINotReadyReturnsClaimToScheduled_STATBUS336(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) executeUpgrade(")
	start := strings.Index(body, "// Verify release manifest and binary exist before starting.")
	end := strings.Index(body, "// Check disk space.")
	if start < 0 || end < 0 || end <= start {
		t.Fatal("could not isolate executeUpgrade's release-assets-not-ready branch")
	}
	branch := body[start:end]

	if strings.Contains(branch, "state = 'available'") {
		t.Fatal("CI-not-ready must never return a claimed row to available; that recreates the off-channel sweepable shape")
	}
	if !strings.Contains(branch, "state = 'scheduled'") {
		t.Fatal("CI-not-ready must return the claimed row to scheduled so operator intent survives and the claim loop retries")
	}
	if strings.Contains(branch, "scheduled_at = NULL") {
		t.Fatal("CI-not-ready must preserve scheduled_at; it is both operator intent and the waiting-age clock")
	}
	for _, want := range []string{"started_at = NULL", "from_commit_version = NULL", "RowsAffected()"} {
		if !strings.Contains(branch, want) {
			t.Errorf("CI-not-ready scheduled step-back is missing %q", want)
		}
	}
	for _, want := range []string{"upgrade_single_scheduled", "state = 'superseded'", "superseded_at = now()"} {
		if !strings.Contains(branch, want) {
			t.Errorf("CI-not-ready scheduled-slot collision handling is missing %q", want)
		}
	}
}

func TestScheduledClaimLoopRepicksRowWhenImagesBecomeReady_STATBUS336(t *testing.T) {
	body := funcBody(t, "service.go", "func (d *Service) executeScheduled(")
	for _, want := range []string{
		"WHERE state = 'scheduled'",
		"docker_images_status::text",
		"case imageClaimWait:",
		"d.verifyArtifacts(ctx)",
		"case imageClaimReady:",
		"d.claimScheduledUpgrade(ctx, id)",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("scheduled claim retry path is missing %q", want)
		}
	}
	if strings.Contains(body, "WHERE state = 'scheduled' AND docker_images_status = 'ready'") {
		t.Fatal("claim SELECT must re-pick the scheduled row while it is waiting so verifyArtifacts can observe readiness on later ticks")
	}
}

func TestUpgradeListShowsScheduledImageWaitSince_STATBUS336(t *testing.T) {
	src := readCLIUpgradeSource(t)
	for _, want := range []string{
		"state = 'scheduled'",
		"docker_images_status",
		"release_builds_status",
		"WHEN superseded_at IS NOT NULL THEN 'superseded'",
		"scheduled, waiting for images since",
		"scheduled_at::text",
	} {
		if !strings.Contains(src, want) {
			t.Errorf("upgrade list waiting-age display is missing %q", want)
		}
	}
}
