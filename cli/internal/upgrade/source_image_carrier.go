package upgrade

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"time"
)

const sourceServingImagesCarrierName = "upgrade-source-images.json"

// sourceServingImagesCarrier is the independent pre-pull record used when the
// recovery marker itself is corrupt or missing. It deliberately contains the
// upgrade identity as well as the immutable image map so a stale carrier can
// never silently authorize a different upgrade's rollback.
type sourceServingImagesCarrier struct {
	ID                  int                            `json:"id"`
	CommitSHA           string                         `json:"commit_sha"`
	CapturedAt          time.Time                      `json:"captured_at"`
	SourceServingImages map[string]sourceImageIdentity `json:"source_serving_images"`
}

func sourceServingImagesCarrierPath(projDir string) string {
	return filepath.Join(projDir, "tmp", sourceServingImagesCarrierName)
}

// writeSourceServingImagesCarrierAtomically installs the independent carrier
// with the same durability shape as the recovery marker: a complete temp inode
// is flocked, written, fsynced, renamed over the canonical path, and followed by
// a directory fsync. The canonical recovery-marker flock serializes every
// in-tree carrier writer and remover. The carrier inode's flock closes the
// open-before-rename exposure while it becomes canonical.
func (d *Service) writeSourceServingImagesCarrierAtomically(flag UpgradeFlag, images map[string]sourceImageIdentity) error {
	if d.flagLock == nil || d.flagLock.file == nil {
		return fmt.Errorf("source-image carrier write requires the canonical recovery-marker flock")
	}
	carrier := sourceServingImagesCarrier{
		ID:                  flag.ID,
		CommitSHA:           flag.CommitSHA,
		CapturedAt:          time.Now().UTC(),
		SourceServingImages: images,
	}
	data, err := json.MarshalIndent(carrier, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal source-image carrier: %w", err)
	}
	path := sourceServingImagesCarrierPath(d.projDir)
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("prepare source-image carrier directory: %w", err)
	}
	tmp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".tmp-*")
	if err != nil {
		return fmt.Errorf("create temporary source-image carrier: %w", err)
	}
	tmpPath := tmp.Name()
	installed := false
	defer func() {
		_ = tmp.Close()
		if !installed {
			_ = os.Remove(tmpPath)
		}
	}()
	if err := tmp.Chmod(0o644); err != nil {
		return fmt.Errorf("chmod temporary source-image carrier: %w", err)
	}
	if err := syscall.Flock(int(tmp.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return fmt.Errorf("lock temporary source-image carrier: %w", err)
	}
	if _, err := tmp.Write(data); err != nil {
		return fmt.Errorf("write temporary source-image carrier: %w", err)
	}
	if err := tmp.Sync(); err != nil {
		return fmt.Errorf("sync temporary source-image carrier: %w", err)
	}
	if err := os.Rename(tmpPath, path); err != nil {
		return fmt.Errorf("rename temporary source-image carrier: %w", err)
	}
	installed = true
	dirFile, err := os.Open(dir)
	if err != nil {
		return fmt.Errorf("open source-image carrier directory for sync: %w", err)
	}
	defer func() { _ = dirFile.Close() }()
	if err := dirFile.Sync(); err != nil {
		return fmt.Errorf("sync source-image carrier directory: %w", err)
	}
	return nil
}

func readSourceServingImagesCarrier(projDir string) (*sourceServingImagesCarrier, error) {
	path := sourceServingImagesCarrierPath(projDir)
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	var carrier sourceServingImagesCarrier
	if err := json.Unmarshal(data, &carrier); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	return &carrier, nil
}

func (d *Service) removeSourceServingImagesCarrier() error {
	path := sourceServingImagesCarrierPath(d.projDir)
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("remove source-image carrier %s: %w", path, err)
	}
	return nil
}
