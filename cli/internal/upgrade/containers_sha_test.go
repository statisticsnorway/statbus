package upgrade

import (
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
)

// Sibling audit (STATBUS-436): evaluateContainersAtFlagTarget derives the tag
// from PsEntry.Image, so a sha256 display value reads as "not at target".
// containersAtFlagTarget must therefore hand it authoritative references.
func TestEvaluateContainersAtFlagTargetSha256DisplayIsNotTarget(t *testing.T) {
	sha := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	ok, _ := evaluateContainersAtFlagTarget([]compose.PsEntry{
		{Service: "db", State: "running", Image: "postgres"},
		{Service: "app", State: "running", Image: "ghcr.io/x/statbus-app:deadbeef"},
		{Service: "worker", State: "running", Image: "sha256:" + sha},
		{Service: "proxy", State: "running", Image: "ghcr.io/x/statbus-proxy:deadbeef"},
		{Service: "rest", State: "running", Image: "postgrest/postgrest:v12"},
	}, "deadbeefcafe0000000000000000000000000000", "v1")
	if ok {
		t.Fatal("sha256 display must not count as target; caller must resolve Config.Image first")
	}
}
