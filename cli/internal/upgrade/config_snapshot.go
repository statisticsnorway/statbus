package upgrade

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

const (
	operatorConfigSnapshotDirName = ".statbus-operator-config-snapshot"
	operatorConfigSnapshotFormat  = "statbus-operator-config-snapshot v2\n"
)

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

	if err := os.WriteFile(filepath.Join(stagingPath, "FORMAT"), []byte(operatorConfigSnapshotFormat), 0600); err != nil {
		return fmt.Errorf("write operator config snapshot format: %w", err)
	}
	for _, file := range []struct {
		destinationName string
		snapshotBase    string
	}{
		{destinationName: ".env.config", snapshotBase: "env.config"},
		{destinationName: ".env.credentials", snapshotBase: "env.credentials"},
	} {
		sourcePath := filepath.Join(projDir, file.destinationName)
		info, err := os.Stat(sourcePath)
		if errors.Is(err, os.ErrNotExist) {
			if err := os.WriteFile(filepath.Join(stagingPath, file.snapshotBase+".absent"), nil, 0600); err != nil {
				return fmt.Errorf("write %s operator config absence marker: %w", file.destinationName, err)
			}
			continue
		}
		if err != nil {
			return fmt.Errorf("stat %s for operator config snapshot: %w", file.destinationName, err)
		}
		if !info.Mode().IsRegular() {
			return fmt.Errorf("snapshot operator config %s: not a regular file", sourcePath)
		}
		contents, err := os.ReadFile(sourcePath)
		if err != nil {
			return fmt.Errorf("read %s for operator config snapshot: %w", file.destinationName, err)
		}
		if err := os.WriteFile(filepath.Join(stagingPath, file.snapshotBase+".present"), contents, 0600); err != nil {
			return fmt.Errorf("write %s operator config snapshot: %w", file.destinationName, err)
		}
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
	snapshotInfo, err := os.Lstat(snapshotPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return &operatorConfigSnapshotError{
				oldFormat: true,
				err:       fmt.Errorf("operator config was not snapshotted by the binary that created backup %s", backupPath),
			}
		}
		return &operatorConfigSnapshotError{err: fmt.Errorf("stat operator config snapshot directory: %w", err)}
	}
	if !snapshotInfo.IsDir() {
		return &operatorConfigSnapshotError{err: fmt.Errorf("operator config snapshot path %s is not a directory", snapshotPath)}
	}

	files, err := validateOperatorConfigSnapshot(snapshotPath)
	if err != nil {
		return &operatorConfigSnapshotError{err: err}
	}
	for _, file := range files {
		destinationPath := filepath.Join(projDir, file.destinationName)
		if !file.present {
			if err := os.Remove(destinationPath); err != nil && !errors.Is(err, os.ErrNotExist) {
				return fmt.Errorf("restore absence of %s: %w", file.destinationName, err)
			}
			continue
		}
		if err := atomicWriteFile(destinationPath, file.contents, 0600); err != nil {
			return fmt.Errorf("restore %s from operator config snapshot: %w", file.destinationName, err)
		}
	}
	return nil
}

type validatedOperatorConfigSnapshotFile struct {
	destinationName string
	present         bool
	contents        []byte
}

func validateOperatorConfigSnapshot(snapshotPath string) ([]validatedOperatorConfigSnapshotFile, error) {
	entries, err := os.ReadDir(snapshotPath)
	if err != nil {
		return nil, fmt.Errorf("read operator config snapshot directory: %w", err)
	}
	names := make(map[string]struct{}, len(entries))
	for _, entry := range entries {
		names[entry.Name()] = struct{}{}
	}
	if len(names) != 3 {
		return nil, fmt.Errorf("operator config snapshot has %d entries; expected exactly 3", len(names))
	}
	if _, ok := names["FORMAT"]; !ok {
		return nil, errors.New("operator config snapshot FORMAT is missing")
	}

	files := []validatedOperatorConfigSnapshotFile{
		{destinationName: ".env.config"},
		{destinationName: ".env.credentials"},
	}
	for i := range files {
		file := &files[i]
		base := file.destinationName[1:]
		presentName := base + ".present"
		absentName := base + ".absent"
		_, hasPresent := names[presentName]
		_, hasAbsent := names[absentName]
		if hasPresent == hasAbsent {
			return nil, fmt.Errorf("operator config snapshot must contain exactly one of %s and %s", presentName, absentName)
		}
		entryName := absentName
		if hasPresent {
			entryName = presentName
			file.present = true
		}
		info, err := os.Lstat(filepath.Join(snapshotPath, entryName))
		if err != nil {
			return nil, fmt.Errorf("stat operator config snapshot entry %s: %w", entryName, err)
		}
		if !info.Mode().IsRegular() {
			return nil, fmt.Errorf("operator config snapshot entry %s is not a regular file", entryName)
		}
		contents, err := os.ReadFile(filepath.Join(snapshotPath, entryName))
		if err != nil {
			return nil, fmt.Errorf("read operator config snapshot entry %s: %w", entryName, err)
		}
		if !hasPresent && len(contents) != 0 {
			return nil, fmt.Errorf("operator config snapshot absence marker %s is not empty", entryName)
		}
		file.contents = contents
	}

	formatPath := filepath.Join(snapshotPath, "FORMAT")
	formatInfo, err := os.Lstat(formatPath)
	if err != nil {
		return nil, fmt.Errorf("stat operator config snapshot FORMAT: %w", err)
	}
	if !formatInfo.Mode().IsRegular() {
		return nil, errors.New("operator config snapshot FORMAT is not a regular file")
	}
	formatContents, err := os.ReadFile(formatPath)
	if err != nil {
		return nil, fmt.Errorf("read operator config snapshot FORMAT: %w", err)
	}
	if !bytes.Equal(formatContents, []byte(operatorConfigSnapshotFormat)) {
		return nil, fmt.Errorf("operator config snapshot FORMAT has unexpected contents %q", formatContents)
	}
	return files, nil
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
