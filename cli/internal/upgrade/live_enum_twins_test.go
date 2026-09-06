package upgrade

import (
	"context"
	"os"
	"sort"
	"testing"
	"time"
)

func TestLiveEnumTwins(t *testing.T) {
	if os.Getenv("STATBUS_LIVE_DB") == "" {
		t.Skip("set STATBUS_LIVE_DB=1 to exercise the real database")
	}

	tests := []struct {
		pgType string
		goSet  []string
	}{
		{"upgrade_state", []string{UpgradeStateAvailable.String(), UpgradeStateScheduled.String(), UpgradeStateInProgress.String(), UpgradeStateCompleted.String(), UpgradeStateFailed.String(), UpgradeStateRolledBack.String(), UpgradeStateDismissed.String(), UpgradeStateSkipped.String(), UpgradeStateSuperseded.String()}},
		{"release_status_type", []string{ReleaseStatusCommit.String(), ReleaseStatusPrerelease.String(), ReleaseStatusRelease.String()}},
		{"docker_images_status_type", []string{DockerImagesStatusBuilding.String(), DockerImagesStatusReady.String(), DockerImagesStatusFailed.String()}},
		{"release_builds_status_type", []string{ReleaseBuildsStatusBuilding.String(), ReleaseBuildsStatusReady.String(), ReleaseBuildsStatusFailed.String()}},
	}

	projDir := findProjDir(t)
	d := NewService(projDir, false, "test", "")
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	if err := d.loadConfig(); err != nil {
		t.Fatal(err)
	}
	if err := d.connect(ctx); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(d.Close)

	for _, tt := range tests {
		t.Run(tt.pgType, func(t *testing.T) {
			rows, err := d.queryConn.Query(ctx, `
				SELECT e.enumlabel
				FROM pg_type AS t
				JOIN pg_enum AS e ON e.enumtypid = t.oid
				WHERE t.typname = $1`, tt.pgType)
			if err != nil {
				t.Fatal(err)
			}
			defer rows.Close()

			pgSet := make(map[string]struct{})
			for rows.Next() {
				var label string
				if err := rows.Scan(&label); err != nil {
					t.Fatal(err)
				}
				pgSet[label] = struct{}{}
			}
			if err := rows.Err(); err != nil {
				t.Fatal(err)
			}

			goSet := make(map[string]struct{}, len(tt.goSet))
			for _, label := range tt.goSet {
				goSet[label] = struct{}{}
			}

			for _, label := range setDifference(pgSet, goSet) {
				t.Errorf("PostgreSQL enum %s has value %q missing from Go", tt.pgType, label)
			}
			for _, label := range setDifference(goSet, pgSet) {
				t.Errorf("Go enum twin for %s has value %q missing from PostgreSQL", tt.pgType, label)
			}
		})
	}
}

func setDifference(left, right map[string]struct{}) []string {
	var difference []string
	for value := range left {
		if _, ok := right[value]; !ok {
			difference = append(difference, value)
		}
	}
	sort.Strings(difference)
	return difference
}
