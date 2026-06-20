package migrate

import (
	"os"
	"path/filepath"
	"testing"
)

// TestMigrationChannelClass covers the STATBUS-102 ordered precedence
// (first match wins): development-mode wins over the channel; then edge;
// then stable/prerelease=release; everything uncertain falls to the safe
// localDev default.
func TestMigrationChannelClass(t *testing.T) {
	cases := []struct {
		name string
		env  string
		want migrationChannel
	}{
		{"development mode wins even with edge channel", "CADDY_DEPLOYMENT_MODE=development\nUPGRADE_CHANNEL=edge\n", channelLocalDev},
		{"development mode wins even with stable channel", "CADDY_DEPLOYMENT_MODE=development\nUPGRADE_CHANNEL=stable\n", channelLocalDev},
		{"deployed edge (non-dev mode)", "CADDY_DEPLOYMENT_MODE=private\nUPGRADE_CHANNEL=edge\n", channelEdge},
		{"stable channel is release", "CADDY_DEPLOYMENT_MODE=standalone\nUPGRADE_CHANNEL=stable\n", channelRelease},
		{"prerelease channel is release", "CADDY_DEPLOYMENT_MODE=private\nUPGRADE_CHANNEL=prerelease\n", channelRelease},
		{"unrecognized channel falls to localDev (safe)", "CADDY_DEPLOYMENT_MODE=private\nUPGRADE_CHANNEL=weird\n", channelLocalDev},
		{"missing channel falls to localDev (safe)", "CADDY_DEPLOYMENT_MODE=private\n", channelLocalDev},
		{"missing mode + edge still classifies edge", "UPGRADE_CHANNEL=edge\n", channelEdge},
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
