package upgrade

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"syscall"
	"testing"
)

func assertNoAtomicFlagTemps(t *testing.T, projDir string) {
	t.Helper()
	matches, err := filepath.Glob(filepath.Join(projDir, "tmp", ".upgrade-in-progress.json.tmp-*"))
	if err != nil {
		t.Fatal(err)
	}
	if len(matches) != 0 {
		t.Fatalf("atomic marker temp files remain: %v", matches)
	}
}

func TestMutateHeldFlagAtomicallyReplacesCompleteMarkerAndRetainsFlock(t *testing.T) {
	projDir := t.TempDir()
	d := &Service{projDir: projDir}
	if err := d.writeUpgradeFlag(17, strings.Repeat("a", 40), []string{"v1.0.0-rc.17"}, "test", "test", false); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.removeUpgradeFlag() })

	wantImages := map[string]sourceImageIdentity{
		"app": {Reference: "ghcr.io/statisticsnorway/statbus-app:source", ImageID: servingEraTestImageID('1')},
	}
	if err := d.mutateHeldFlag(func(flag *UpgradeFlag) {
		flag.SourceServingImages = wantImages
	}); err != nil {
		t.Fatalf("mutateHeldFlag: %v", err)
	}

	assertNoAtomicFlagTemps(t, projDir)
	flag, err := ReadFlagFile(projDir)
	if err != nil {
		t.Fatalf("parse atomically replaced marker: %v", err)
	}
	if flag == nil || !reflect.DeepEqual(flag.SourceServingImages, wantImages) {
		t.Fatalf("atomically replaced marker = %#v, want SourceServingImages %#v", flag, wantImages)
	}

	contender, err := os.OpenFile(d.flagPath(), os.O_RDWR, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = contender.Close() }()
	if err := syscall.Flock(int(contender.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err == nil {
		t.Fatal("atomically replaced marker path is not protected by the transferred flock")
	}
}

func TestMutateHeldFlagFailureBeforeRenamePreservesOldMarker(t *testing.T) {
	projDir := t.TempDir()
	d := &Service{projDir: projDir}
	if err := d.writeUpgradeFlag(17, strings.Repeat("b", 40), nil, "test", "test", false); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = d.removeUpgradeFlag() })

	oldBytes, err := os.ReadFile(d.flagPath())
	if err != nil {
		t.Fatal(err)
	}
	injected := errors.New("injected failure before rename")
	err = d.mutateHeldFlagBeforeRename(func(flag *UpgradeFlag) {
		flag.OriginalError = "must not become visible"
	}, func() error { return injected })
	if !errors.Is(err, injected) {
		t.Fatalf("mutateHeldFlagBeforeRename error = %v, want injected failure", err)
	}

	newBytes, err := os.ReadFile(d.flagPath())
	if err != nil {
		t.Fatal(err)
	}
	if string(newBytes) != string(oldBytes) {
		t.Fatalf("marker changed before atomic rename\nold: %s\nnew: %s", oldBytes, newBytes)
	}
	assertNoAtomicFlagTemps(t, projDir)
	flag, err := ReadFlagFile(projDir)
	if err != nil {
		t.Fatalf("preserved marker no longer parses: %v", err)
	}
	if flag == nil || flag.OriginalError != "" {
		t.Fatalf("failed pre-rename mutation leaked into marker: %#v", flag)
	}
}
