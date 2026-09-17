package upgrade

import (
	"context"
	"encoding/json"
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

func TestAcquireFlockRejectsStalePreopenedInodeAfterAtomicRename(t *testing.T) {
	projDir := t.TempDir()
	seed := UpgradeFlag{ID: 17, CommitSHA: strings.Repeat("1", 40), Holder: HolderService, Phase: PhaseOldSbUpgrading}
	seedLock, err := acquireFreshFlock(projDir, seed)
	if err != nil {
		t.Fatal(err)
	}
	seedLock.Close()

	rivalFlag := UpgradeFlag{ID: 18, CommitSHA: strings.Repeat("2", 40), Holder: HolderService, Phase: PhaseNewSbUpgrading}
	var rivalLock *FlagLock
	hook := func(attempt int, _ *os.File) error {
		if attempt != 0 {
			return nil
		}
		lock, _, acquireErr := acquireRecoveryFlock(projDir, seed)
		if acquireErr != nil {
			return acquireErr
		}
		data, marshalErr := json.MarshalIndent(rivalFlag, "", "  ")
		if marshalErr != nil {
			lock.Close()
			return marshalErr
		}
		if replaceErr := replaceHeldFlagAtomically(lock, data, nil); replaceErr != nil {
			lock.Close()
			return replaceErr
		}
		rivalLock = lock
		return nil
	}
	claimant := UpgradeFlag{ID: 19, CommitSHA: strings.Repeat("3", 40), Holder: HolderService, Phase: PhaseOldSbUpgrading}
	claimLock, err := acquireFlockWithHook(projDir, claimant, hook)
	if claimLock != nil {
		claimLock.Close()
		t.Fatal("claimant acquired an orphaned pre-rename inode and reported success")
	}
	if err == nil {
		t.Fatal("claimant did not fail closed behind the live replacement marker")
	}
	if rivalLock == nil {
		t.Fatal("interleave did not install the rival marker")
	}
	t.Cleanup(func() {
		rivalLock.Close()
		_ = os.Remove(flagFilePath(projDir))
	})
	got, readErr := ReadFlagFile(projDir)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if got == nil || got.ID != rivalFlag.ID || got.CommitSHA != rivalFlag.CommitSHA {
		t.Fatalf("live replacement marker was overwritten: got %#v, want rival %#v", got, rivalFlag)
	}
}

func TestRecoverFromFlagDoesNotUnlinkCorruptLiveMarker(t *testing.T) {
	projDir := t.TempDir()
	path := flagFilePath(projDir)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("{corrupt"), 0o644); err != nil {
		t.Fatal(err)
	}
	holder, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = holder.Close() }()
	if err := syscall.Flock(int(holder.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		t.Fatal(err)
	}

	d := &Service{projDir: projDir}
	err = d.recoverFromFlag(context.Background())
	if err == nil || !strings.Contains(err.Error(), "remove corrupt upgrade marker while holding canonical flock") {
		t.Fatalf("recoverFromFlag error = %v, want canonical-flock refusal", err)
	}
	if _, statErr := os.Stat(path); statErr != nil {
		t.Fatalf("live corrupt marker was removed: %v", statErr)
	}
}

func TestAcquireFreshFlockScavengesOnlyUnlockedAtomicTemps(t *testing.T) {
	projDir := t.TempDir()
	tmpDir := filepath.Join(projDir, "tmp")
	if err := os.MkdirAll(tmpDir, 0o755); err != nil {
		t.Fatal(err)
	}
	stalePath := filepath.Join(tmpDir, ".upgrade-in-progress.json.tmp-stale")
	activePath := filepath.Join(tmpDir, ".upgrade-in-progress.json.tmp-active")
	if err := os.WriteFile(stalePath, []byte("stale"), 0o644); err != nil {
		t.Fatal(err)
	}
	active, err := os.OpenFile(activePath, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = active.Close() }()
	if err := syscall.Flock(int(active.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		t.Fatal(err)
	}

	lock, err := acquireFreshFlock(projDir, UpgradeFlag{ID: 17, Holder: HolderService, Phase: PhaseOldSbUpgrading})
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		_ = os.Remove(flagFilePath(projDir))
		lock.Close()
	}()
	if _, err := os.Stat(stalePath); !os.IsNotExist(err) {
		t.Fatalf("unlocked stale atomic temp remains: %v", err)
	}
	if _, err := os.Stat(activePath); err != nil {
		t.Fatalf("live locked atomic temp was removed: %v", err)
	}
}

func TestScavengeAtomicFlagTempsRequiresCanonicalFlock(t *testing.T) {
	if err := scavengeAtomicFlagTemps(nil); err == nil || !strings.Contains(err.Error(), "requires the canonical flock") {
		t.Fatalf("scavenge without canonical flock = %v, want refusal", err)
	}
}

func TestContendingMarkerWriterCreatesNoTempBeforeCanonicalFlock(t *testing.T) {
	projDir := t.TempDir()
	owner, err := acquireFreshFlock(projDir, UpgradeFlag{ID: 17, Holder: HolderService, Phase: PhaseOldSbUpgrading})
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		_ = os.Remove(flagFilePath(projDir))
		owner.Close()
	}()

	contender, err := acquireFlock(projDir, UpgradeFlag{ID: 18, Holder: HolderService, Phase: PhaseOldSbUpgrading})
	if contender != nil {
		contender.Close()
		t.Fatal("contending marker writer unexpectedly acquired the canonical flock")
	}
	if err == nil {
		t.Fatal("contending marker writer did not fail behind canonical flock")
	}
	matches, globErr := filepath.Glob(filepath.Join(projDir, "tmp", ".upgrade-in-progress.json.tmp-*"))
	if globErr != nil {
		t.Fatal(globErr)
	}
	if len(matches) != 0 {
		t.Fatalf("contending writer created temps before canonical flock acquisition: %v", matches)
	}
}
