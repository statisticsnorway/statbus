package migrate

import (
	"os"
	"path/filepath"
	"testing"
)

// TestMigrationChannelClass covers the STATBUS-106 channel-only classification:
// the decision depends ONLY on UPGRADE_CHANNEL (the upgrade axis), never on
// CADDY_DEPLOYMENT_MODE (the front-door axis). edge→edge; stable/prerelease→
// release; local/unset/unknown→the safe localDev default. CADDY_DEPLOYMENT_MODE
// is deliberately present in some fixtures to prove it is IGNORED.
func TestMigrationChannelClass(t *testing.T) {
	cases := []struct {
		name string
		env  string
		want migrationChannel
	}{
		{"local channel is localDev", "UPGRADE_CHANNEL=local\n", channelLocalDev},
		{"dev mode is IGNORED — edge channel still classifies edge", "CADDY_DEPLOYMENT_MODE=development\nUPGRADE_CHANNEL=edge\n", channelEdge},
		{"dev mode is IGNORED — stable channel still classifies release", "CADDY_DEPLOYMENT_MODE=development\nUPGRADE_CHANNEL=stable\n", channelRelease},
		{"dev mode + local channel is localDev", "CADDY_DEPLOYMENT_MODE=development\nUPGRADE_CHANNEL=local\n", channelLocalDev},
		{"deployed edge", "CADDY_DEPLOYMENT_MODE=private\nUPGRADE_CHANNEL=edge\n", channelEdge},
		{"stable channel is release", "CADDY_DEPLOYMENT_MODE=standalone\nUPGRADE_CHANNEL=stable\n", channelRelease},
		{"prerelease channel is release", "CADDY_DEPLOYMENT_MODE=private\nUPGRADE_CHANNEL=prerelease\n", channelRelease},
		{"unrecognized channel falls to localDev (safe)", "UPGRADE_CHANNEL=weird\n", channelLocalDev},
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
