package cmd

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// operatorKeptBackupsDirName is the folder in the operator's home where an
// uninstall that keeps the database backups moves them, beside the kept
// ~/statbus.users.yml and ~/statbus.env.credentials. ~/statbus itself is then
// removed completely, and the next install moves the backups back into
// <checkout>/dbdumps, where ./sb db restore finds them (STATBUS-419 AC9-10).
const operatorKeptBackupsDirName = "statbus.dbdumps"

// keptBackupsAdopted records how many backups this install moved back, so the
// final report can name how to restore one. Set by adoptKeptBackups.
var keptBackupsAdopted int

// adoptKeptBackups moves every file in ~/statbus.dbdumps into the checkout's
// dbdumps folder and removes the then-empty folder. A file of the same name
// that differs is never overwritten: the install stops and names both. An
// identical file already in the checkout makes the kept copy a duplicate.
func adoptKeptBackups(dir string) error {
	keptBackupsAdopted = 0
	keptDir, err := operatorHomeFilePath(operatorKeptBackupsDirName)
	if err != nil {
		return err
	}
	entries, err := os.ReadDir(keptDir)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("cannot read the kept backups in %s: %w", keptDir, err)
	}
	dumpsDir := filepath.Join(dir, "dbdumps")
	if err := os.MkdirAll(dumpsDir, 0o755); err != nil {
		return fmt.Errorf("cannot create %s: %w", dumpsDir, err)
	}
	// Check every name first, so a refusal moves nothing.
	for _, entry := range entries {
		keptPath := filepath.Join(keptDir, entry.Name())
		if !entry.Type().IsRegular() {
			return fmt.Errorf("%s is not a regular file. Move it out of %s and run the same install command again", keptPath, keptDir)
		}
		target := filepath.Join(dumpsDir, entry.Name())
		if fits, err := keptBackupFits(keptPath, target); err != nil {
			return err
		} else if !fits {
			return fmt.Errorf("the kept backup %s and %s differ. Keep one and rename the other, then run the same install command again", keptPath, target)
		}
	}
	dumps := 0
	for _, entry := range entries {
		keptPath := filepath.Join(keptDir, entry.Name())
		target := filepath.Join(dumpsDir, entry.Name())
		if _, statErr := os.Stat(target); statErr == nil {
			if err := os.Remove(keptPath); err != nil {
				return fmt.Errorf("cannot remove the duplicate %s: %w", keptPath, err)
			}
		} else if err := os.Rename(keptPath, target); err != nil {
			return fmt.Errorf("cannot move %s to %s: %w", keptPath, target, err)
		}
		if strings.HasSuffix(entry.Name(), ".pg_dump") {
			dumps++
		}
	}
	if err := os.Remove(keptDir); err != nil {
		return fmt.Errorf("cannot remove the emptied %s: %w", keptDir, err)
	}
	keptBackupsAdopted = dumps
	fmt.Printf("  Moved the %d kept %s from %s to %s.\n", dumps, plural(dumps, "backup", "backups"), keptDir, dumpsDir)
	return nil
}

// keptBackupFits reports whether the kept backup can go to target: target is
// absent, or already holds the same bytes. Only a present, different target is
// a conflict.
func keptBackupFits(source, target string) (bool, error) {
	if _, err := os.Stat(target); errors.Is(err, os.ErrNotExist) {
		return true, nil
	} else if err != nil {
		return false, fmt.Errorf("cannot inspect %s: %w", target, err)
	}
	same, err := sameFileContent(source, target)
	if err != nil {
		return false, fmt.Errorf("cannot compare %s with %s: %w", source, target, err)
	}
	return same, nil
}

// reportKeptBackups tells the operator, at the end of an install that moved
// kept backups back, how to put the newest one's data into this installation.
// The install never restores by itself: which data belongs here is the
// operator's decision (owner decision 2026-11-05).
func reportKeptBackups(dir string) {
	if keptBackupsAdopted == 0 {
		return
	}
	dumpsDir := filepath.Join(dir, "dbdumps")
	matches, _ := filepath.Glob(filepath.Join(dumpsDir, "*.pg_dump"))
	if len(matches) == 0 {
		return
	}
	// Dump names end in their UTC timestamp (<slot>_<YYYYMMDD>_<HHMMSS>), so
	// the newest sorts last.
	sort.Slice(matches, func(i, j int) bool { return dumpNameTimestamp(matches[i]) < dumpNameTimestamp(matches[j]) })
	newest := filepath.Base(matches[len(matches)-1])
	fmt.Printf("%d database %s from the earlier installation %s in %s. The newest is %s.\n",
		len(matches), plural(len(matches), "backup", "backups"), plural(len(matches), "is", "are"), dumpsDir, newest)
	fmt.Println("To put its data into this installation, run:")
	fmt.Printf("    cd ~/statbus && ./sb db restore %s\n", newest)
}

// dumpNameTimestamp is the <YYYYMMDD>_<HHMMSS> tail of a dump file name, the
// stamp dumpTimestamp (db.go) writes.
func dumpNameTimestamp(path string) string {
	name := strings.TrimSuffix(filepath.Base(path), ".pg_dump")
	parts := strings.Split(name, "_")
	if len(parts) < 3 {
		return name
	}
	return strings.Join(parts[len(parts)-2:], "_")
}

func plural(n int, one, many string) string {
	if n == 1 {
		return one
	}
	return many
}
