package upgrade

import "testing"

func TestParseLedgerEnums(t *testing.T) {
	tests := []struct {
		name    string
		valid   []string
		parse   func(string) (string, error)
		invalid string
	}{
		{
			name:  "upgrade state",
			valid: []string{"available", "scheduled", "in_progress", "completed", "failed", "rolled_back", "dismissed", "skipped", "superseded"},
			parse: func(value string) (string, error) {
				parsed, err := ParseUpgradeState(value)
				return parsed.String(), err
			},
			invalid: "unknown",
		},
		{
			name:  "release status",
			valid: []string{"commit", "prerelease", "release"},
			parse: func(value string) (string, error) {
				parsed, err := ParseReleaseStatus(value)
				return parsed.String(), err
			},
			invalid: "stable",
		},
		{
			name:  "docker images status",
			valid: []string{"building", "ready", "failed"},
			parse: func(value string) (string, error) {
				parsed, err := ParseDockerImagesStatus(value)
				return parsed.String(), err
			},
			invalid: "missing",
		},
		{
			name:  "release builds status",
			valid: []string{"building", "ready", "failed"},
			parse: func(value string) (string, error) {
				parsed, err := ParseReleaseBuildsStatus(value)
				return parsed.String(), err
			},
			invalid: "published",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			for _, value := range tt.valid {
				got, err := tt.parse(value)
				if err != nil {
					t.Errorf("parse valid value %q: %v", value, err)
				} else if got != value {
					t.Errorf("parse valid value %q returned %q", value, got)
				}
			}
			if got, err := tt.parse(tt.invalid); err == nil {
				t.Errorf("parse invalid value %q returned %q without error", tt.invalid, got)
			}
		})
	}
}
