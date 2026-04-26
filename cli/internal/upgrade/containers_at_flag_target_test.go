package upgrade

import (
	"strings"
	"testing"
)

// TestParseDockerComposePsJSON_NDJSON covers the Compose v2 path: one
// JSON object per line.
func TestParseDockerComposePsJSON_NDJSON(t *testing.T) {
	in := []byte(strings.Join([]string{
		`{"Service":"db","State":"running","Image":"postgres:18-alpine"}`,
		`{"Service":"app","State":"running","Image":"ghcr.io/statisticsnorway/statbus-app:9ac0666c"}`,
		``,
		`  `,
		`{"Service":"worker","State":"running","Image":"ghcr.io/statisticsnorway/statbus-worker:9ac0666c"}`,
	}, "\n"))
	got, err := parseDockerComposePsJSON(in)
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	if len(got) != 3 {
		t.Fatalf("got %d entries, want 3", len(got))
	}
	if got[0].Service != "db" || got[1].Service != "app" || got[2].Service != "worker" {
		t.Errorf("Service field mismatch: %+v", got)
	}
}

// TestParseDockerComposePsJSON_Array covers the older single-array form.
func TestParseDockerComposePsJSON_Array(t *testing.T) {
	in := []byte(`[
		{"Service":"db","State":"running","Image":"postgres:18-alpine"},
		{"Service":"app","State":"running","Image":"ghcr.io/statisticsnorway/statbus-app:9ac0666c"}
	]`)
	got, err := parseDockerComposePsJSON(in)
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("got %d entries, want 2", len(got))
	}
}

// TestParseDockerComposePsJSON_Empty: ps on empty project → no error,
// no entries.
func TestParseDockerComposePsJSON_Empty(t *testing.T) {
	got, err := parseDockerComposePsJSON([]byte("   \n\n  "))
	if err != nil {
		t.Fatalf("parse error: %v", err)
	}
	if len(got) != 0 {
		t.Errorf("got %d entries, want 0", len(got))
	}
}

func TestParseDockerComposePsJSON_Malformed(t *testing.T) {
	if _, err := parseDockerComposePsJSON([]byte("not-json")); err == nil {
		t.Error("expected error for malformed input, got nil")
	}
}

// TestExtractImageTag covers the supported reference shapes.
func TestExtractImageTag(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"ghcr.io/statisticsnorway/statbus-app:9ac0666c", "9ac0666c"},
		{"ghcr.io/statisticsnorway/statbus-app:v2026.04.0-rc.55", "v2026.04.0-rc.55"},
		{"postgres:18-alpine", "18-alpine"},
		{"postgrest/postgrest:v12.2.8", "v12.2.8"},
		{"postgres", ""},
		{"registry.example.com:5000/myapp", ""}, // host:port without trailing tag
	}
	for _, tc := range cases {
		t.Run(tc.in, func(t *testing.T) {
			if got := extractImageTag(tc.in); got != tc.want {
				t.Errorf("extractImageTag(%q): got %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

// TestEvaluateContainersAtFlagTarget runs the table from the plan.
func TestEvaluateContainersAtFlagTarget(t *testing.T) {
	const flagSHA = "96e07627abcdef1234567890abcdef1234567890"
	const flagDisplay = "v2026.04.0-rc.55"

	allFiveAtTagScheme := []dockerPsEntry{
		{Service: "db", State: "running", Image: "postgres:" + flagDisplay},
		{Service: "app", State: "running", Image: "ghcr.io/x/statbus-app:" + flagDisplay},
		{Service: "worker", State: "running", Image: "ghcr.io/x/statbus-worker:" + flagDisplay},
		{Service: "proxy", State: "running", Image: "ghcr.io/x/statbus-proxy:" + flagDisplay},
		{Service: "rest", State: "running", Image: "postgrest/postgrest:v12.2.8"},
	}
	allFiveAtSHAScheme := []dockerPsEntry{
		{Service: "db", State: "running", Image: "postgres:96e07627"},
		{Service: "app", State: "running", Image: "ghcr.io/x/statbus-app:96e07627"},
		{Service: "worker", State: "running", Image: "ghcr.io/x/statbus-worker:96e07627"},
		{Service: "proxy", State: "running", Image: "ghcr.io/x/statbus-proxy:96e07627"},
		{Service: "rest", State: "running", Image: "postgrest/postgrest:v12.2.8"},
	}

	cases := []struct {
		name           string
		statuses       []dockerPsEntry
		wantOK         bool
		wantMismatched int // count of mismatched entries
	}{
		{
			name:     "rc.55-era_scheme_all_at_target",
			statuses: allFiveAtTagScheme,
			wantOK:   true,
		},
		{
			name:     "rc.65-era_scheme_all_at_target",
			statuses: allFiveAtSHAScheme,
			wantOK:   true,
		},
		{
			name: "version_tracked_at_older_release",
			statuses: []dockerPsEntry{
				{Service: "db", State: "running", Image: "postgres:v2026.04.0-rc.50"},
				{Service: "app", State: "running", Image: "ghcr.io/x/statbus-app:v2026.04.0-rc.50"},
				{Service: "worker", State: "running", Image: "ghcr.io/x/statbus-worker:v2026.04.0-rc.50"},
				{Service: "proxy", State: "running", Image: "ghcr.io/x/statbus-proxy:v2026.04.0-rc.50"},
				{Service: "rest", State: "running", Image: "postgrest/postgrest:v12.2.8"},
			},
			wantOK:         false,
			wantMismatched: 4,
		},
		{
			name: "single_service_mismatched_app",
			statuses: []dockerPsEntry{
				{Service: "db", State: "running", Image: "postgres:" + flagDisplay},
				{Service: "app", State: "running", Image: "ghcr.io/x/statbus-app:v2026.04.0-rc.50"},
				{Service: "worker", State: "running", Image: "ghcr.io/x/statbus-worker:" + flagDisplay},
				{Service: "proxy", State: "running", Image: "ghcr.io/x/statbus-proxy:" + flagDisplay},
				{Service: "rest", State: "running", Image: "postgrest/postgrest:v12.2.8"},
			},
			wantOK:         false,
			wantMismatched: 1,
		},
		{
			name: "rest_not_running",
			statuses: []dockerPsEntry{
				{Service: "db", State: "running", Image: "postgres:" + flagDisplay},
				{Service: "app", State: "running", Image: "ghcr.io/x/statbus-app:" + flagDisplay},
				{Service: "worker", State: "running", Image: "ghcr.io/x/statbus-worker:" + flagDisplay},
				{Service: "proxy", State: "running", Image: "ghcr.io/x/statbus-proxy:" + flagDisplay},
				{Service: "rest", State: "exited", Image: "postgrest/postgrest:v12.2.8"},
			},
			wantOK:         false,
			wantMismatched: 1,
		},
		{
			name: "missing_db_container",
			statuses: []dockerPsEntry{
				{Service: "app", State: "running", Image: "ghcr.io/x/statbus-app:" + flagDisplay},
				{Service: "worker", State: "running", Image: "ghcr.io/x/statbus-worker:" + flagDisplay},
				{Service: "proxy", State: "running", Image: "ghcr.io/x/statbus-proxy:" + flagDisplay},
				{Service: "rest", State: "running", Image: "postgrest/postgrest:v12.2.8"},
			},
			wantOK:         false,
			wantMismatched: 1,
		},
		{
			name:           "empty_input",
			statuses:       nil,
			wantOK:         false,
			wantMismatched: 5,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ok, mismatched := evaluateContainersAtFlagTarget(tc.statuses, flagSHA, flagDisplay)
			if ok != tc.wantOK {
				t.Errorf("ok=%v, want %v (mismatched=%v)", ok, tc.wantOK, mismatched)
			}
			if !tc.wantOK && len(mismatched) != tc.wantMismatched {
				t.Errorf("len(mismatched)=%d, want %d (entries=%v)",
					len(mismatched), tc.wantMismatched, mismatched)
			}
		})
	}
}

// TestEvaluateContainersAtFlagTarget_ShortSHA: a flag whose CommitSHA is
// already <= 8 chars (synthetic test fixture) must be matched verbatim,
// not panic on an out-of-bounds slice.
func TestEvaluateContainersAtFlagTarget_ShortSHA(t *testing.T) {
	statuses := []dockerPsEntry{
		{Service: "db", State: "running", Image: "postgres:abc"},
		{Service: "app", State: "running", Image: "ghcr.io/x/statbus-app:abc"},
		{Service: "worker", State: "running", Image: "ghcr.io/x/statbus-worker:abc"},
		{Service: "proxy", State: "running", Image: "ghcr.io/x/statbus-proxy:abc"},
		{Service: "rest", State: "running", Image: "postgrest/postgrest:v12.2.8"},
	}
	ok, mismatched := evaluateContainersAtFlagTarget(statuses, "abc", "abc")
	if !ok {
		t.Errorf("got ok=false (mismatched=%v) for short-SHA fixture, want true", mismatched)
	}
}
