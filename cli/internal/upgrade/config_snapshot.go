package upgrade

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

const (
	operatorConfigSnapshotDirName       = ".statbus-operator-config-snapshot"
	operatorConfigSnapshotFormatVersion = 1
)

type operatorConfigSnapshotEntry struct {
	Present *bool `json:"present"`
}

type operatorConfigSnapshotManifest struct {
	Version        *int                         `json:"version"`
	EnvConfig      *operatorConfigSnapshotEntry `json:"env_config"`
	EnvCredentials *operatorConfigSnapshotEntry `json:"env_credentials"`
}

type operatorConfigSnapshotError struct {
	oldFormat bool
	err       error
}

func (e *operatorConfigSnapshotError) Error() string {
	return e.err.Error()
}

func (e *operatorConfigSnapshotError) Unwrap() error {
	return e.err
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

	version := operatorConfigSnapshotFormatVersion
	configPresent := false
	credentialsPresent := false
	manifest := operatorConfigSnapshotManifest{
		Version:        &version,
		EnvConfig:      &operatorConfigSnapshotEntry{Present: &configPresent},
		EnvCredentials: &operatorConfigSnapshotEntry{Present: &credentialsPresent},
	}
	files := []struct {
		name  string
		entry *operatorConfigSnapshotEntry
	}{
		{name: ".env.config", entry: manifest.EnvConfig},
		{name: ".env.credentials", entry: manifest.EnvCredentials},
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
		*file.entry.Present = true
		if err := os.WriteFile(filepath.Join(stagingPath, file.name), contents, 0600); err != nil {
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
	if _, err := os.Stat(snapshotPath); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return &operatorConfigSnapshotError{
				oldFormat: true,
				err:       fmt.Errorf("operator config was not snapshotted by the binary that created backup %s", backupPath),
			}
		}
		return &operatorConfigSnapshotError{err: fmt.Errorf("stat operator config snapshot directory: %w", err)}
	}
	manifestContents, err := os.ReadFile(filepath.Join(snapshotPath, "manifest.json"))
	if err != nil {
		return &operatorConfigSnapshotError{err: fmt.Errorf("read operator config snapshot manifest: %w", err)}
	}
	manifest, err := decodeOperatorConfigSnapshotManifest(manifestContents)
	if err != nil {
		return &operatorConfigSnapshotError{err: fmt.Errorf("decode operator config snapshot manifest: %w", err)}
	}

	files := []struct {
		name     string
		present  bool
		contents []byte
	}{
		{name: ".env.config", present: *manifest.EnvConfig.Present},
		{name: ".env.credentials", present: *manifest.EnvCredentials.Present},
	}
	// Validate the complete snapshot before changing either destination. A
	// missing payload must never restore one file and then discover that the
	// other half is unusable.
	for i := range files {
		file := &files[i]
		if !file.present {
			continue
		}
		contents, err := os.ReadFile(filepath.Join(snapshotPath, file.name))
		if err != nil {
			return &operatorConfigSnapshotError{err: fmt.Errorf("read %s operator config snapshot: %w", file.name, err)}
		}
		file.contents = contents
	}
	for _, file := range files {
		destinationPath := filepath.Join(projDir, file.name)
		if !file.present {
			if err := os.Remove(destinationPath); err != nil && !errors.Is(err, os.ErrNotExist) {
				return fmt.Errorf("restore absence of %s: %w", file.name, err)
			}
			continue
		}
		if err := atomicWriteFile(destinationPath, file.contents, 0600); err != nil {
			return fmt.Errorf("restore %s from operator config snapshot: %w", file.name, err)
		}
	}
	return nil
}

func decodeOperatorConfigSnapshotManifest(contents []byte) (operatorConfigSnapshotManifest, error) {
	var manifest operatorConfigSnapshotManifest
	if err := rejectDuplicateJSONKeys(contents); err != nil {
		return manifest, err
	}

	decoder := json.NewDecoder(bytes.NewReader(contents))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&manifest); err != nil {
		return manifest, err
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		if err == nil {
			return manifest, errors.New("trailing JSON value after manifest")
		}
		return manifest, fmt.Errorf("trailing data after manifest: %w", err)
	}
	if manifest.Version == nil {
		return manifest, errors.New("version is required and must not be null")
	}
	if *manifest.Version != operatorConfigSnapshotFormatVersion {
		return manifest, fmt.Errorf("manifest version %d is unsupported; expected %d", *manifest.Version, operatorConfigSnapshotFormatVersion)
	}
	if manifest.EnvConfig == nil || manifest.EnvCredentials == nil {
		return manifest, errors.New("both env_config and env_credentials records are required and must not be null")
	}
	if manifest.EnvConfig.Present == nil {
		return manifest, errors.New("env_config.present is required and must not be null")
	}
	if manifest.EnvCredentials.Present == nil {
		return manifest, errors.New("env_credentials.present is required and must not be null")
	}
	return manifest, nil
}

func rejectDuplicateJSONKeys(contents []byte) error {
	decoder := json.NewDecoder(bytes.NewReader(contents))
	if err := scanUniqueJSONValue(decoder); err != nil {
		return err
	}
	if _, err := decoder.Token(); !errors.Is(err, io.EOF) {
		if err == nil {
			return errors.New("trailing JSON value after manifest")
		}
		return fmt.Errorf("trailing data after manifest: %w", err)
	}
	return nil
}

func scanUniqueJSONValue(decoder *json.Decoder) error {
	token, err := decoder.Token()
	if err != nil {
		return err
	}
	delim, ok := token.(json.Delim)
	if !ok {
		return nil
	}
	switch delim {
	case '{':
		keys := make(map[string]struct{})
		for decoder.More() {
			keyToken, err := decoder.Token()
			if err != nil {
				return err
			}
			key, ok := keyToken.(string)
			if !ok {
				return fmt.Errorf("object key has type %T, want string", keyToken)
			}
			if _, duplicate := keys[key]; duplicate {
				return fmt.Errorf("duplicate object key %q", key)
			}
			keys[key] = struct{}{}
			if err := scanUniqueJSONValue(decoder); err != nil {
				return err
			}
		}
	case '[':
		for decoder.More() {
			if err := scanUniqueJSONValue(decoder); err != nil {
				return err
			}
		}
	default:
		return fmt.Errorf("unexpected JSON delimiter %q", delim)
	}
	closing, err := decoder.Token()
	if err != nil {
		return err
	}
	want := json.Delim('}')
	if delim == '[' {
		want = ']'
	}
	if closing != want {
		return fmt.Errorf("JSON delimiter %q closed by %q", delim, closing)
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
