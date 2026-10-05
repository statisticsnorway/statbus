package upgrade

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

const operatorConfigSnapshotDirName = ".statbus-operator-config-snapshot"

type operatorConfigSnapshotEntry struct {
	Present bool        `json:"present"`
	Mode    os.FileMode `json:"mode,omitempty"`
}

type operatorConfigSnapshotManifest struct {
	EnvConfig      operatorConfigSnapshotEntry `json:"env_config"`
	EnvCredentials operatorConfigSnapshotEntry `json:"env_credentials"`
}

func operatorConfigSnapshotPath(backupPath string) string {
	return filepath.Join(backupPath, operatorConfigSnapshotDirName)
}

func snapshotOperatorConfig(projDir, backupPath string) error {
	snapshotPath := operatorConfigSnapshotPath(backupPath)
	stagingPath := snapshotPath + ".tmp"
	if err := os.RemoveAll(stagingPath); err != nil {
		return fmt.Errorf("remove stale operator config snapshot staging directory: %w", err)
	}
	if err := os.Mkdir(stagingPath, 0700); err != nil {
		return fmt.Errorf("create operator config snapshot staging directory: %w", err)
	}
	cleanupStaging := true
	defer func() {
		if cleanupStaging {
			_ = os.RemoveAll(stagingPath)
		}
	}()

	manifest := operatorConfigSnapshotManifest{}
	files := []struct {
		name  string
		entry *operatorConfigSnapshotEntry
		mode  os.FileMode
	}{
		{name: ".env.config", entry: &manifest.EnvConfig, mode: 0600},
		{name: ".env.credentials", entry: &manifest.EnvCredentials, mode: 0600},
	}
	for _, file := range files {
		sourcePath := filepath.Join(projDir, file.name)
		info, err := os.Stat(sourcePath)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return fmt.Errorf("stat %s for operator config snapshot: %w", file.name, err)
		}
		if !info.Mode().IsRegular() {
			return fmt.Errorf("snapshot operator config %s: not a regular file", sourcePath)
		}
		contents, err := os.ReadFile(sourcePath)
		if err != nil {
			return fmt.Errorf("read %s for operator config snapshot: %w", file.name, err)
		}
		file.entry.Present = true
		file.entry.Mode = info.Mode().Perm()
		if err := os.WriteFile(filepath.Join(stagingPath, file.name), contents, file.mode); err != nil {
			return fmt.Errorf("write %s operator config snapshot: %w", file.name, err)
		}
	}

	manifestContents, err := json.Marshal(manifest)
	if err != nil {
		return fmt.Errorf("encode operator config snapshot manifest: %w", err)
	}
	if err := os.WriteFile(filepath.Join(stagingPath, "manifest.json"), manifestContents, 0600); err != nil {
		return fmt.Errorf("write operator config snapshot manifest: %w", err)
	}
	if err := syncTree(stagingPath); err != nil {
		return fmt.Errorf("sync operator config snapshot: %w", err)
	}
	if err := os.RemoveAll(snapshotPath); err != nil {
		return fmt.Errorf("replace previous operator config snapshot: %w", err)
	}
	if err := os.Rename(stagingPath, snapshotPath); err != nil {
		return fmt.Errorf("commit operator config snapshot: %w", err)
	}
	cleanupStaging = false
	return nil
}

func restoreOperatorConfig(projDir, backupPath string) error {
	snapshotPath := operatorConfigSnapshotPath(backupPath)
	manifestContents, err := os.ReadFile(filepath.Join(snapshotPath, "manifest.json"))
	if err != nil {
		return fmt.Errorf("read operator config snapshot manifest: %w", err)
	}
	var manifest operatorConfigSnapshotManifest
	if err := json.Unmarshal(manifestContents, &manifest); err != nil {
		return fmt.Errorf("decode operator config snapshot manifest: %w", err)
	}

	files := []struct {
		name  string
		entry operatorConfigSnapshotEntry
		mode  os.FileMode
	}{
		{name: ".env.config", entry: manifest.EnvConfig},
		{name: ".env.credentials", entry: manifest.EnvCredentials, mode: 0600},
	}
	for _, file := range files {
		destinationPath := filepath.Join(projDir, file.name)
		if !file.entry.Present {
			if err := os.Remove(destinationPath); err != nil && !errors.Is(err, os.ErrNotExist) {
				return fmt.Errorf("restore absence of %s: %w", file.name, err)
			}
			continue
		}
		contents, err := os.ReadFile(filepath.Join(snapshotPath, file.name))
		if err != nil {
			return fmt.Errorf("read %s operator config snapshot: %w", file.name, err)
		}
		mode := file.mode
		if mode == 0 {
			mode = file.entry.Mode.Perm()
		}
		if mode == 0 {
			mode = 0600
		}
		if err := atomicWriteFile(destinationPath, contents, mode); err != nil {
			return fmt.Errorf("restore %s from operator config snapshot: %w", file.name, err)
		}
	}
	return nil
}

func atomicWriteFile(path string, contents []byte, mode os.FileMode) error {
	dir := filepath.Dir(path)
	temp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".restore-*")
	if err != nil {
		return err
	}
	tempPath := temp.Name()
	cleanup := true
	defer func() {
		_ = temp.Close()
		if cleanup {
			_ = os.Remove(tempPath)
		}
	}()
	if err := temp.Chmod(mode); err != nil {
		return err
	}
	if _, err := temp.Write(contents); err != nil {
		return err
	}
	if err := temp.Sync(); err != nil {
		return err
	}
	if err := temp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tempPath, path); err != nil {
		return err
	}
	cleanup = false
	return nil
}
