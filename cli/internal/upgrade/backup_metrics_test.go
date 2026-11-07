package upgrade

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/testguard"
)

// This opt-in observation runs the production snapshot command twice, using a
// private bind mount instead of any named database volume. It supplements, but
// does not replace, released-image upgrade testing in a real guest.
func TestBackupSnapshotMetricsDocker(t *testing.T) {
	if !testguard.IsolatedDockerInvocation() {
		t.Skip("requires isolated Docker fixture authorization")
	}
	root := scopedBackupRoot(t)
	project := t.TempDir()
	instance := filepath.Join(project, "fixture")
	source := instance + "-db-data"
	if err := os.Mkdir(source, 0700); err != nil {
		t.Fatal(err)
	}
	data := []byte("snapshot fixture\n")
	if err := os.WriteFile(filepath.Join(source, "data"), data, 0600); err != nil {
		t.Fatal(err)
	}
	// An absolute instance path makes Docker interpret the production /source
	// mount as this private bind path. No existing named volume is opened.
	if err := os.WriteFile(filepath.Join(project, ".env"), []byte("COMPOSE_INSTANCE_NAME="+instance+"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	d := &Service{projDir: project}
	for i, copied := range []int64{int64(len(data)), 0} {
		backup, err := d.backupDatabase(&ProgressLog{projDir: project}, fmt.Sprintf("docker-metrics-%d", i))
		if err != nil {
			t.Fatal(err)
		}
		if backup.Bytes != int64(len(data)) || backup.CopiedBytes != copied {
			t.Fatalf("snapshot %d metrics = %d logical, %d copied, want %d, %d", i, backup.Bytes, backup.CopiedBytes, len(data), copied)
		}
		got, err := os.ReadFile(filepath.Join(root, backupActiveName, "data"))
		if err != nil || string(got) != string(data) {
			t.Fatalf("snapshot %d contents = %q, %v", i, got, err)
		}
		t.Logf("snapshot %d: %s", i, backup.summary())
	}
}

func TestRsyncSnapshotMetrics(t *testing.T) {
	for _, tc := range []struct {
		name, stats  string
		size, copied int64
	}{
		{"C locale", "Total file size: 56908316672 bytes\nTotal transferred file size: 1073741824 bytes\n", 56908316672, 1073741824},
		{"empty", "Total file size: 0 bytes\nTotal transferred file size: 0 bytes\n", 0, 0},
		{"grouped", "Total file size: 56,908,316,672 bytes\r\nTotal transferred file size: 1,073,741,824 bytes\r\n", 56908316672, 1073741824},
		{"missing", "rsync diagnostics\n", -1, -1},
		{"partial", "Total file size: 123 bytes\n", 123, -1},
		{"overflow", "Total file size: 9223372036854775808 bytes\nTotal transferred file size: 0 bytes\n", -1, 0},
		{"malformed grouping", "Total file size: 12,34 bytes\nTotal transferred file size: 0 bytes\n", -1, 0},
		{"humanized", "Total file size: 53.0G bytes\nTotal transferred file size: 0 bytes\n", -1, 0},
		{"negative", "Total file size: -1 bytes\nTotal transferred file size: 0 bytes\n", -1, 0},
		{"ambiguous", "Total file size: 123 bytes\nTotal file size: 456 bytes\nTotal transferred file size: 0 bytes\n", -1, 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			size, copied := rsyncSnapshotMetrics(tc.stats)
			if size != tc.size || copied != tc.copied {
				t.Errorf("metrics = (%d, %d), want (%d, %d)", size, copied, tc.size, tc.copied)
			}
		})
	}
}

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
		{"incremental", "Total file size: 56,908,316,672 bytes\nTotal transferred file size: 1,073,741,824 bytes\n", "53.0 GB snapshot, 1.0 GB copied, 12.9s", 56908316672, true},
		{"empty", "Total file size: 0 bytes\nTotal transferred file size: 0 bytes\n", "0 B snapshot, 0 B copied, 12.9s", 0, false},
		{"size only", "Total file size: 56,908,316,672 bytes\n", "53.0 GB snapshot, copied amount unknown, 12.9s", 56908316672, true},
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
