package upgrade

// STATBUS-241: backup_path must SURVIVE the volume rewind that precedes a
// rollback/abort terminal write — by the same mechanism STATBUS-181 established
// for recovery_attempts, one column over.
//
// THE DEFECT THESE PIN: the ABORT branch calls restoreDatabase (service.go, the
// git-corrupt arm) BEFORE its terminal write. That restore rewinds the database
// volume — and with it public.upgrade — to the pre-upgrade snapshot, taken
// BEFORE the post-reconnect recorder ran, where backup_path is NULL. No terminal
// UPDATE re-imposed the column, so the identity was silently erased and the
// abort-hold guard (`state='failed' AND backup_path IS NOT NULL`) read zero and
// FAILED OPEN — releasing the read-only hold protecting a broken volume, on
// exactly the population it exists for.
//
// WHY THE VALUE COMES FROM THE FLAG: the flag is the authoritative carrier
// across this gap (STATBUS-228), and STATBUS-229 made its value correct on BOTH
// routes by construction — empty at PreSwap, the identity once the swap stamps
// it. A remembered variable could resurrect an identity onto a route whose whole
// contract is that it carries none. That is the review point, so it is pinned
// here rather than left to the comment.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// flagServiceWithBackupPath writes a real flag file under projDir and returns a
// Service. holdIt controls whether the Service also holds the descriptor, so
// both read paths (held fd, on-disk fallback) are exercised for real rather
// than simulated.
func flagServiceWithBackupPath(t *testing.T, backupPath string, holdIt bool) *Service {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0755); err != nil {
		t.Fatal(err)
	}
	data, err := json.MarshalIndent(UpgradeFlag{
		ID:         7,
		CommitSHA:  "deadbeefdeadbeef",
		BackupPath: backupPath,
	}, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "tmp", "upgrade-in-progress.json")
	if err := os.WriteFile(path, data, 0644); err != nil {
		t.Fatal(err)
	}
	d := &Service{projDir: dir}
	if holdIt {
		f, oerr := os.OpenFile(path, os.O_RDWR, 0644)
		if oerr != nil {
			t.Fatal(oerr)
		}
		t.Cleanup(func() { _ = f.Close() })
		d.flagLock = &FlagLock{file: f}
	}
	return d
}

// TestFlagSourcedBackupPath_ThreeStates_STATBUS241 is the behavioural arm. The
// three states must stay DISTINCT: "unknown" is not "empty". Collapsing them —
// the obvious simplification, e.g. returning "" when no flag is readable — would
// make the terminal write impose NULL on the flagless STATBUS-111 replay path
// and erase a live identity that reconcileBackupDir still needs.
func TestFlagSourcedBackupPath_ThreeStates_STATBUS241(t *testing.T) {
	t.Run("held flag with an identity: imposed", func(t *testing.T) {
		d := flagServiceWithBackupPath(t, "/home/statbus/statbus/tmp/pre-upgrade-active", true)
		got, src := d.flagSourcedBackupPath()
		if got == nil {
			t.Fatalf("a held flag carrying an identity must be readable; source=%q", src)
		}
		if *got != "/home/statbus/statbus/tmp/pre-upgrade-active" {
			t.Errorf("wrong identity re-imposed: %q", *got)
		}
	})

	t.Run("held flag, PreSwap empty: imposed AS empty, never nil", func(t *testing.T) {
		d := flagServiceWithBackupPath(t, "", true)
		got, src := d.flagSourcedBackupPath()
		if got == nil {
			t.Fatalf("PreSwap empty must be a KNOWN answer (impose SQL NULL), not 'unknown' (leave the column) — conflating them lets a rewind resurrect an identity on a route that must carry none; source=%q", src)
		}
		if *got != "" {
			t.Errorf("PreSwap flag must report an EMPTY identity, got %q", *got)
		}
	})

	t.Run("no held descriptor: falls back to the on-disk flag", func(t *testing.T) {
		d := flagServiceWithBackupPath(t, "/snap/path", false)
		got, _ := d.flagSourcedBackupPath()
		if got == nil || *got != "/snap/path" {
			t.Fatalf("the on-disk flag must still answer when the descriptor is not held; got %v", got)
		}
	})

	t.Run("no flag at all: UNKNOWN, so the column is left alone", func(t *testing.T) {
		d := &Service{projDir: t.TempDir()}
		got, src := d.flagSourcedBackupPath()
		if got != nil {
			t.Fatalf("with no readable flag the answer must be UNKNOWN (nil) so the terminal write leaves backup_path as-is; got %q (source=%q). Returning \"\" here would erase the identity on STATBUS-111's flagless replay path", *got, src)
		}
	})
}

// TestTerminalWritesReimposeBackupPath_STATBUS241 is the source pin, mirroring
// the STATBUS-181 recovery_attempts pin's shape: a re-imposition that is missing
// from any single updateSQL is a SILENT no-op on that path, so the requirement
// is stated over EVERY terminal write rather than over one of them.
func TestTerminalWritesReimposeBackupPath_STATBUS241(t *testing.T) {
	source := string(packageGoSources(t)["service.go"])

	// `d.writeRollbackTerminal(` matches call sites only — the definition reads
	// `func (d *Service) writeRollbackTerminal(`.
	callSites := strings.Count(source, "d.writeRollbackTerminal(")
	if callSites == 0 {
		t.Fatal("no writeRollbackTerminal call sites found — the pin lost its subject (a check that examines nothing must FAIL, not pass)")
	}

	// Every terminal UPDATE that re-imposes recovery_attempts must re-impose
	// backup_path too: both columns are reverted by the SAME volume rewind, so
	// treating them differently IS the defect. Counting them also proves the loop
	// examined one UPDATE per call site rather than silently matching none.
	terminalUpdates := 0
	for _, line := range strings.Split(source, "\n") {
		if !strings.Contains(line, "UPDATE public.upgrade") || !strings.Contains(line, "recovery_attempts = $2") {
			continue
		}
		terminalUpdates++
		if !strings.Contains(line, "terminalBackupPathSQL") {
			t.Errorf("terminal UPDATE re-imposes recovery_attempts but NOT backup_path — both are reverted by the same volume rewind, and omitting it is a SILENT no-op on this path:\n  %s", strings.TrimSpace(line))
		}
	}
	if terminalUpdates != callSites {
		t.Errorf("examined %d terminal UPDATE strings for %d writeRollbackTerminal call sites — the pin must cover every call site, and a mismatch means it silently skipped one", terminalUpdates, callSites)
	}
}

// TestWriteRollbackTerminalSourcesBackupPathFromTheFlag_STATBUS241 pins the
// architect's whole review point: the value must come FROM THE FLAG, never from
// a caller's remembered variable. The flag's value is correct on both routes by
// construction (STATBUS-229); a parameter is not, and would let a post-swap
// identity be handed to a PreSwap terminal.
func TestWriteRollbackTerminalSourcesBackupPathFromTheFlag_STATBUS241(t *testing.T) {
	source := string(packageGoSources(t)["service.go"])
	body := extractFuncBody(t, source, "func (d *Service) writeRollbackTerminal(")

	if !strings.Contains(body, "d.flagSourcedBackupPath()") {
		t.Error("writeRollbackTerminal must read the identity FROM THE FLAG via flagSourcedBackupPath() — the flag is the authoritative carrier across the rewind (STATBUS-228/-229)")
	}

	// The signature must NOT grow a backupPath parameter. If a future change adds
	// one, the flag-sourcing guarantee is gone even if flagSourcedBackupPath is
	// still called somewhere in the body.
	// Start AFTER the opening paren of the PARAMETER LIST. Taking the first ")"
	// from the start of the line would close the RECEIVER `(d *Service)` and
	// capture no parameters at all — a check examining nothing, which passes
	// against everything. (That is what this pin did on first write; it was
	// caught by mutating the signature and watching it stay green.)
	const sigHead = "func (d *Service) writeRollbackTerminal("
	sigStart := strings.Index(source, sigHead)
	if sigStart < 0 {
		t.Fatal("writeRollbackTerminal not found — the pin lost its subject")
	}
	paramsStart := sigStart + len(sigHead)
	closeIdx := strings.Index(source[paramsStart:], ")")
	if closeIdx < 0 {
		t.Fatal("could not find the end of writeRollbackTerminal's parameter list")
	}
	sig := source[paramsStart : paramsStart+closeIdx]
	if !strings.Contains(sig, "attempts int") {
		t.Fatalf("parameter list extraction is wrong — it must contain the known `attempts int` parameter, got %q", sig)
	}
	if strings.Contains(strings.ToLower(sig), "backuppath") {
		t.Errorf("writeRollbackTerminal must NOT take a backupPath parameter — a remembered variable can resurrect an identity onto a route that must not carry one; the flag is the only correct source. Signature: %s", sig)
	}

	// The three-state SQL must keep UNKNOWN and EMPTY distinct. COALESCE-style
	// simplifications conflate them, which is precisely the failure mode.
	if !strings.Contains(source, "CASE WHEN $4::text IS NULL THEN backup_path ELSE NULLIF($4::text, '') END") {
		t.Error("terminalBackupPathSQL must distinguish THREE states: $4 NULL (unknown → keep the column), '' (PreSwap → impose SQL NULL), '<path>' (impose it). A COALESCE form would treat 'unknown' as 'empty' and erase a live identity on the flagless replay path")
	}
}
