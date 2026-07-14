// Package dbdump is the shared, in-process core for taking a logical
// (pg_dump -Fc) backup of the StatBus database and pruning the dump
// directory by retention count.
//
// It exists as a NEUTRAL package — imported by BOTH cli/cmd (the `sb db dump`
// / `sb db dumps purge` cobra commands) AND cli/internal/upgrade (the always-on
// service's scheduled-backup runner, STATBUS-113). The cores cannot live in
// cli/cmd because cmd imports internal/upgrade (10 files) — the service calling
// back into cmd would be an import cycle. dbdump imports neither, so both sides
// reach it cleanly.
//
// Physical per-upgrade rsync snapshots (backupDatabase/restoreDatabase) stay in
// internal/upgrade — those are upgrade-specific. Only the GENERAL logical dump +
// purge live here.
package dbdump

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// dumpFilenameTimestampLen is the width of the YYYYMMDD_HHMMSS stamp that
// dumpTimestamp() emits and that purge grouping strips to find the source prefix.
const dumpFilenameTimestampLen = len("20060102_150405") // 15

// DumpsDir is the directory under projDir where logical dumps live.
func DumpsDir(projDir string) string {
	return filepath.Join(projDir, "dbdumps")
}

// DumpDatabase takes a logical backup of the app database and writes it, ATOMICALLY,
// to <projDir>/dbdumps/<slot>_<ts>.pg_dump, returning the committed path.
//
// Atomicity (STATBUS-113 AC#2): the dump streams to a sibling <name>.pg_dump.tmp
// and is renamed to its final name ONLY after pg_dump exits 0 with a non-empty
// file. Any failure (pg_dump error, empty output) removes the .tmp and returns
// an error — a partial/empty dump is NEVER published under the final name, so a
// killed or preempted run leaves at most a discardable .tmp, never a corrupt
// restore source. The command itself is unchanged from the original `sb db dump`:
//
//	docker compose exec -T db pg_dump -Fc --no-owner \
//	    --exclude-table-data=auth.secrets -U postgres <db>
//
// This function performs NO user-facing I/O — callers (the cobra command, the
// service runner) handle their own progress/log messages.
func DumpDatabase(projDir string) (string, error) {
	dbName, err := loadDbName(projDir)
	if err != nil {
		return "", err
	}
	slotCode, err := loadSlotCode(projDir)
	if err != nil {
		return "", err
	}
	dumpsDir, err := ensureDumpsDir(projDir)
	if err != nil {
		return "", err
	}

	finalPath := filepath.Join(dumpsDir, fmt.Sprintf("%s_%s.pg_dump", slotCode, dumpTimestamp()))

	return finalPath, writeAtomic(finalPath, func(w io.Writer) error {
		c := exec.Command("docker", "compose", "exec", "-T", "db",
			"pg_dump", "-Fc", "--no-owner",
			"--exclude-table-data=auth.secrets",
			"-U", "postgres", dbName)
		c.Dir = projDir
		c.Stdout = w
		c.Stderr = os.Stderr
		if err := c.Run(); err != nil {
			return fmt.Errorf("pg_dump failed: %w", err)
		}
		return nil
	})
}

// writeAtomic runs produce() with its output streamed to <finalPath>.tmp, then
// commits the tmp to finalPath via rename iff produce() succeeds AND the file is
// non-empty. On any failure the .tmp is removed. Split out from DumpDatabase so
// the tmp→rename / cleanup / empty-guard invariants are unit-testable without
// docker (TestWriteAtomic_*).
func writeAtomic(finalPath string, produce func(io.Writer) error) error {
	tmpPath := finalPath + ".tmp"
	tmp, err := os.Create(tmpPath)
	if err != nil {
		return fmt.Errorf("create temp dump file: %w", err)
	}

	if err := produce(tmp); err != nil {
		_ = tmp.Close()        // best-effort; already erroring out
		_ = os.Remove(tmpPath) // best-effort cleanup of the partial dump
		return err
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpPath) // best-effort cleanup of the partial dump
		return fmt.Errorf("close temp dump file: %w", err)
	}

	info, err := os.Stat(tmpPath)
	if err != nil {
		_ = os.Remove(tmpPath) // best-effort cleanup
		return fmt.Errorf("stat temp dump file: %w", err)
	}
	if info.Size() == 0 {
		_ = os.Remove(tmpPath) // best-effort cleanup of the empty dump
		return fmt.Errorf("dump produced an empty file — check database connectivity")
	}

	if err := os.Rename(tmpPath, finalPath); err != nil {
		_ = os.Remove(tmpPath) // best-effort cleanup
		return fmt.Errorf("commit dump (rename .tmp -> .pg_dump): %w", err)
	}
	return nil
}

// DumpsToPurge returns the dump paths that PurgeDumps would delete for the given
// retention count — the pure selection, no deletion. keepN newest are kept PER
// source prefix (filenames sort lexicographically = chronologically). Exposed so
// the cobra command can preview + confirm before deleting; the service does not
// use it (it deletes headlessly via PurgeDumps).
func DumpsToPurge(projDir string, keepN int) ([]string, error) {
	if keepN < 0 {
		return nil, fmt.Errorf("keepN must be non-negative, got %d", keepN)
	}
	entries, err := filepath.Glob(filepath.Join(DumpsDir(projDir), "*.pg_dump"))
	if err != nil {
		return nil, err
	}

	// Group by source prefix (everything before the _YYYYMMDD_HHMMSS stamp).
	groups := make(map[string][]string)
	for _, path := range entries {
		name := strings.TrimSuffix(filepath.Base(path), ".pg_dump")
		if len(name) > dumpFilenameTimestampLen+1 && name[len(name)-dumpFilenameTimestampLen-1] == '_' {
			prefix := name[:len(name)-dumpFilenameTimestampLen-1]
			groups[prefix] = append(groups[prefix], path)
		} else {
			// Unparseable name — treat the whole name as its own group.
			groups[name] = append(groups[name], path)
		}
	}

	var toDelete []string
	for _, paths := range groups {
		sort.Strings(paths)
		if len(paths) <= keepN {
			continue
		}
		toDelete = append(toDelete, paths[:len(paths)-keepN]...)
	}
	sort.Strings(toDelete)
	return toDelete, nil
}

// PurgeDumps deletes all but the newest keepN dumps per source prefix and
// returns the deleted paths. Headless (no confirmation) — the retention core
// the service runner calls directly; the cobra command does its own confirm
// then calls this.
func PurgeDumps(projDir string, keepN int) ([]string, error) {
	toDelete, err := DumpsToPurge(projDir, keepN)
	if err != nil {
		return nil, err
	}
	var deleted []string
	for _, p := range toDelete {
		if err := os.Remove(p); err != nil {
			return deleted, fmt.Errorf("remove %s: %w", filepath.Base(p), err)
		}
		deleted = append(deleted, p)
	}
	return deleted, nil
}

// NewestDumpModTime returns the modification time of the most recent *.pg_dump in
// the dumps dir. ok is false when no dump exists yet. The service's due-check
// uses this — the dump artifacts ARE the schedule state (no separate persistence).
func NewestDumpModTime(projDir string) (modTime time.Time, ok bool) {
	matches, err := filepath.Glob(filepath.Join(DumpsDir(projDir), "*.pg_dump"))
	if err != nil {
		return time.Time{}, false
	}
	for _, m := range matches {
		info, err := os.Stat(m)
		if err != nil {
			continue
		}
		if !ok || info.ModTime().After(modTime) {
			modTime, ok = info.ModTime(), true
		}
	}
	return modTime, ok
}

// ── small env/dir helpers (dbdump keeps its own so the package is import-clean;
//    cli/cmd retains its equivalents for its other commands) ────────────────────

// loadDbName reads POSTGRES_APP_DB from .env.
func loadDbName(projDir string) (string, error) {
	f, err := dotenv.Load(filepath.Join(projDir, ".env"))
	if err != nil {
		return "", fmt.Errorf("load .env: %w", err)
	}
	db, ok := f.Get("POSTGRES_APP_DB")
	if !ok || db == "" {
		return "", fmt.Errorf("POSTGRES_APP_DB not set in .env")
	}
	return db, nil
}

// loadSlotCode reads DEPLOYMENT_SLOT_CODE from .env.config (the dump filename prefix).
func loadSlotCode(projDir string) (string, error) {
	f, err := dotenv.Load(filepath.Join(projDir, ".env.config"))
	if err != nil {
		return "", fmt.Errorf("load .env.config: %w", err)
	}
	code, ok := f.Get("DEPLOYMENT_SLOT_CODE")
	if !ok || code == "" {
		return "", fmt.Errorf("DEPLOYMENT_SLOT_CODE not set in .env.config")
	}
	return code, nil
}

// dumpTimestamp returns a filename-safe timestamp: YYYYMMDD_HHMMSS.
func dumpTimestamp() string {
	return time.Now().Format("20060102_150405")
}

// ensureDumpsDir creates the dbdumps/ directory if it does not exist.
func ensureDumpsDir(projDir string) (string, error) {
	dir := DumpsDir(projDir)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", fmt.Errorf("create dbdumps directory: %w", err)
	}
	return dir, nil
}
