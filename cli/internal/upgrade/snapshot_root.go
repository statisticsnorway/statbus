package upgrade

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/jackc/pgx/v5"
)

// SnapshotRootName is the folder in the install user's home that holds the
// upgrade snapshots: the raw copy of the database volume the upgrader takes
// before each upgrade so it can roll back (pre-upgrade-active /
// pre-upgrade-syncing), plus each upgrade's logs. A snapshot only fits the
// installation it was taken from. The portable copy an operator keeps and
// restores is the daily database backup in <checkout>/dbdumps instead
// (STATBUS-574: each copy is named for what it is).
const SnapshotRootName = "statbus-upgrade-snapshots"

// LegacySnapshotRootName is the folder the snapshots lived in before
// STATBUS-574. MigrateSnapshotRoot moves it to SnapshotRootName, and
// resolveRecordedSnapshot maps a path recorded under it to the moved folder.
const LegacySnapshotRootName = "statbus-backups"

// SnapshotRoot is the upgrade snapshot folder for the given home directory.
func SnapshotRoot(home string) string {
	return filepath.Join(home, SnapshotRootName)
}

// SnapshotRootMove reports what MigrateSnapshotRoot did, for the operator.
type SnapshotRootMove struct {
	// Moved is true when anything was carried from the legacy folder.
	Moved bool
	// LeftBehind names legacy entries kept where they were because the new
	// folder already holds an entry of the same name.
	LeftBehind []string
}

// Lines is the operator-facing report of the move: empty when nothing moved.
func (m SnapshotRootMove) Lines(home string) []string {
	legacy := "~/" + LegacySnapshotRootName
	current := "~/" + SnapshotRootName
	var lines []string
	if m.Moved {
		lines = append(lines, fmt.Sprintf("  Moved the upgrade snapshots from %s to %s.", legacy, current))
	}
	if len(m.LeftBehind) > 0 {
		lines = append(lines, fmt.Sprintf("  Left %s in %s: %s already has one. Remove %s when it is no longer needed.",
			strings.Join(m.LeftBehind, ", "), legacy, current, legacy))
	}
	return lines
}

// MigrateSnapshotRoot carries a pre-STATBUS-574 ~/statbus-backups into
// ~/statbus-upgrade-snapshots. It is idempotent and never overwrites:
//   - no legacy folder: nothing to do;
//   - the new folder is absent or empty: the legacy folder is renamed onto it;
//   - both hold entries: each legacy entry without a namesake is renamed
//     across, a namesake stays in the legacy folder (reported in LeftBehind),
//     and the legacy folder is removed once it is empty.
//
// Callers run it only while SnapshotRootMoveAllowed holds, so no recorded
// upgrade is mid-flight. A legacy path that is not a directory is refused.
func MigrateSnapshotRoot(home string) (SnapshotRootMove, error) {
	var move SnapshotRootMove
	legacy := filepath.Join(home, LegacySnapshotRootName)
	current := SnapshotRoot(home)
	info, err := os.Lstat(legacy)
	if errors.Is(err, os.ErrNotExist) {
		return move, nil
	}
	if err != nil {
		return move, fmt.Errorf("inspect %s: %w", legacy, err)
	}
	if !info.IsDir() {
		return move, fmt.Errorf("%s is not a folder; move or remove it so the upgrade snapshots can live in %s", legacy, current)
	}
	legacyEntries, err := os.ReadDir(legacy)
	if err != nil {
		return move, fmt.Errorf("read %s: %w", legacy, err)
	}
	if len(legacyEntries) == 0 {
		if err := os.Remove(legacy); err != nil {
			return move, fmt.Errorf("remove the empty %s: %w", legacy, err)
		}
		return move, nil
	}
	currentEntries, err := os.ReadDir(current)
	switch {
	case errors.Is(err, os.ErrNotExist):
		if err := os.Rename(legacy, current); err != nil {
			return move, fmt.Errorf("move %s to %s: %w", legacy, current, err)
		}
		move.Moved = true
		return move, nil
	case err != nil:
		return move, fmt.Errorf("read %s: %w", current, err)
	case len(currentEntries) == 0:
		if err := os.Remove(current); err != nil {
			return move, fmt.Errorf("replace the empty %s: %w", current, err)
		}
		if err := os.Rename(legacy, current); err != nil {
			return move, fmt.Errorf("move %s to %s: %w", legacy, current, err)
		}
		move.Moved = true
		return move, nil
	}
	for _, entry := range legacyEntries {
		target := filepath.Join(current, entry.Name())
		if _, err := os.Lstat(target); err == nil {
			move.LeftBehind = append(move.LeftBehind, entry.Name())
			continue
		} else if !errors.Is(err, os.ErrNotExist) {
			return move, fmt.Errorf("inspect %s: %w", target, err)
		}
		if err := os.Rename(filepath.Join(legacy, entry.Name()), target); err != nil {
			return move, fmt.Errorf("move %s to %s: %w", filepath.Join(legacy, entry.Name()), target, err)
		}
		move.Moved = true
	}
	sort.Strings(move.LeftBehind)
	if len(move.LeftBehind) == 0 {
		if err := os.Remove(legacy); err != nil {
			return move, fmt.Errorf("remove the emptied %s: %w", legacy, err)
		}
	}
	return move, nil
}

// SnapshotRootMovePending reports whether MigrateSnapshotRoot has anything
// left to do in home: a legacy folder exists and is empty, or holds an entry
// the new folder has no namesake for. Entries left behind beside a namesake
// are settled, so a box in that state is not re-reported on every run.
func SnapshotRootMovePending(home string) bool {
	legacyEntries, err := os.ReadDir(filepath.Join(home, LegacySnapshotRootName))
	if err != nil {
		// Absent is settled; any other error is surfaced by MigrateSnapshotRoot.
		return !errors.Is(err, os.ErrNotExist)
	}
	if len(legacyEntries) == 0 {
		return true
	}
	for _, entry := range legacyEntries {
		if _, err := os.Lstat(filepath.Join(SnapshotRoot(home), entry.Name())); err != nil {
			return true
		}
	}
	return false
}

// SnapshotRootMoveAllowed reports whether the snapshot folder may move now.
// A marker that records an upgrade (an id, a target commit, or a snapshot
// path) belongs to recovery, which restores the snapshot it recorded; the
// folder stays put until that marker is gone. Install's own claim records no
// upgrade and does not block the move. An unreadable marker blocks it.
func SnapshotRootMoveAllowed(projDir string) (bool, string) {
	flag, err := ReadFlagFile(projDir)
	if err != nil {
		return false, fmt.Sprintf("the upgrade marker is unreadable (%v)", err)
	}
	if flag == nil {
		return true, ""
	}
	if flag.ID != 0 || flag.CommitSHA != "" || flag.BackupPath != "" {
		return false, fmt.Sprintf("upgrade %d is recorded in the upgrade marker", flag.ID)
	}
	return true, ""
}

// rewriteRecordedSnapshotPathSQL points one public.upgrade.backup_path that
// was recorded under the legacy folder at the same entry under the new
// folder. It matches the exact old value, so a row changed in between is left
// alone.
const rewriteRecordedSnapshotPathSQL = `UPDATE public.upgrade SET backup_path = $3 WHERE id = $1 AND backup_path = $2`

// migrateSnapshotRoot is the upgrader's half of STATBUS-574: while no upgrade
// is recorded in the marker it moves ~/statbus-backups to
// ~/statbus-upgrade-snapshots (MigrateSnapshotRoot) and rewrites the snapshot
// paths recorded in public.upgrade.backup_path to the moved folder. A row is
// rewritten whenever its recorded path is no longer there, so only the new
// name remains (a snapshot that was already missing stays reported missing,
// under the new name); a namesake left behind keeps its own path. Holding off
// while the marker records an upgrade keeps every live
// attempt's identity (recoveryAttemptPredicate matches on backup_path)
// unchanged under it. It runs at boot after recovery and on every idle tick,
// so a box whose install left the folder in place for a recorded upgrade
// converges once that upgrade ends. Each step is idempotent; a failure is
// reported and retried on the next tick.
func migrateSnapshotRoot(ctx context.Context, projDir, home string, conn *pgx.Conn) {
	if home == "" {
		return
	}
	if allowed, _ := SnapshotRootMoveAllowed(projDir); !allowed {
		return
	}
	if SnapshotRootMovePending(home) {
		move, err := MigrateSnapshotRoot(home)
		for _, line := range move.Lines(home) {
			fmt.Println(strings.TrimSpace(line))
		}
		if err != nil {
			fmt.Printf("SNAPSHOT_ROOT_MOVE_FAILED: %v\n", err)
			return
		}
	}
	if conn == nil {
		return
	}
	legacyPrefix := filepath.Join(home, LegacySnapshotRootName) + string(filepath.Separator)
	rows, err := conn.Query(ctx, `SELECT id, backup_path FROM public.upgrade WHERE starts_with(backup_path, $1)`, legacyPrefix)
	if err != nil {
		fmt.Printf("SNAPSHOT_ROOT_PATHS_NOT_REWRITTEN: %v\n", err)
		return
	}
	type recorded struct {
		id   int
		path string
	}
	var found []recorded
	for rows.Next() {
		var r recorded
		if err := rows.Scan(&r.id, &r.path); err != nil {
			rows.Close()
			fmt.Printf("SNAPSHOT_ROOT_PATHS_NOT_REWRITTEN: %v\n", err)
			return
		}
		found = append(found, r)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		fmt.Printf("SNAPSHOT_ROOT_PATHS_NOT_REWRITTEN: %v\n", err)
		return
	}
	rewritten := 0
	for _, r := range found {
		if _, err := os.Lstat(r.path); err == nil {
			continue // left behind beside a namesake; still the recorded snapshot
		}
		moved := filepath.Join(SnapshotRoot(home), strings.TrimPrefix(r.path, legacyPrefix))
		tag, err := conn.Exec(ctx, rewriteRecordedSnapshotPathSQL, r.id, r.path, moved)
		if err != nil {
			fmt.Printf("SNAPSHOT_ROOT_PATHS_NOT_REWRITTEN: upgrade %d: %v\n", r.id, err)
			return
		}
		rewritten += int(tag.RowsAffected())
	}
	if rewritten > 0 {
		fmt.Printf("Recorded upgrade snapshot paths now point at %s (%d upgrade row(s))\n", homeRelativePath(SnapshotRoot(home)), rewritten)
	}
}

// resolveRecordedSnapshot returns the folder that holds a recorded snapshot.
// The recorded path is used as recorded when it exists. A path recorded under
// the legacy folder before MigrateSnapshotRoot moved it is mapped to the same
// entry under the new folder, so a marker BackupPath or a
// public.upgrade.backup_path written before the move still rolls back from
// the very snapshot that upgrade took. Anything else is returned unchanged,
// so a missing snapshot is still reported as missing.
func resolveRecordedSnapshot(recorded string) string {
	if recorded == "" {
		return recorded
	}
	if _, err := os.Lstat(recorded); err == nil {
		return recorded
	}
	home := os.Getenv("HOME")
	if home == "" {
		return recorded
	}
	rel, err := filepath.Rel(filepath.Join(home, LegacySnapshotRootName), recorded)
	if err != nil || rel == "." || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return recorded
	}
	moved := filepath.Join(SnapshotRoot(home), rel)
	if _, err := os.Lstat(moved); err == nil {
		return moved
	}
	return recorded
}
