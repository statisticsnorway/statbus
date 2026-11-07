package upgrade

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// Exercise the backup publication and the exact formatter consumed by the service.
// Docker is replaced only at the process boundary, so no developer volume is read.
func TestBackupSnapshotMetrics(t *testing.T) {
	for _, tc := range []struct {
		name, stats, want string
		bytes             int64
		reuse             bool
	}{
		{"full", "Total file size: 56,908,316,672 bytes\nTotal transferred file size: 56,908,316,672 bytes\n", "53.0 GB snapshot, 53.0 GB copied, 12.9s", 56908316672, false},
		{"unchanged", "Total file size: 56,908,316,672 bytes\nTotal transferred file size: 0 bytes\n", "53.0 GB snapshot, 0 B copied, 12.9s", 56908316672, true},
		{"unknown", "", "snapshot size unknown, copied amount unknown, 12.9s", -1, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := scopedBackupRoot(t)
			if tc.reuse {
				makeBackupDir(t, root, backupActiveName)
			}
			shim := t.TempDir()
			if err := os.WriteFile(filepath.Join(shim, "docker"), []byte("#!/bin/sh\nprintf '%s' \"$STATBUS_TEST_RSYNC_STATS\" >&2\n"), 0755); err != nil {
				t.Fatal(err)
			}
			t.Setenv("PATH", shim+string(os.PathListSeparator)+os.Getenv("PATH"))
			t.Setenv("STATBUS_TEST_RSYNC_STATS", tc.stats)
			project := t.TempDir()
			d := &Service{projDir: project}
			backup, err := d.backupDatabase(&ProgressLog{projDir: project}, "metrics-test")
			if err != nil {
				t.Fatal(err)
			}
			if backup.Bytes != tc.bytes {
				t.Errorf("logical snapshot bytes = %d, want %d", backup.Bytes, tc.bytes)
			}
			if backup.Path != filepath.Join(root, backupActiveName) {
				t.Errorf("published path = %q", backup.Path)
			}
			if info, err := os.Stat(backup.Path); err != nil || !info.IsDir() {
				t.Fatalf("published snapshot: %v", err)
			}
			backup.Elapsed = 12900 * time.Millisecond
			got := fmt.Sprintf("Backing up database ... ok (%s)", backup.summary())
			want := fmt.Sprintf("Backing up database ... ok (%s)", tc.want)
			if got != want {
				t.Errorf("completion = %q, want %q", got, want)
			}
		})
	}
}
