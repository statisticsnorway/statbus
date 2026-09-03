package upgrade

// STATBUS-228 oracles: the restore identity is recorded on each carrier at the
// moment that carrier can hold it TRUTHFULLY — the flag at the swap, the row at
// the first reconnect after it.
//
// STATBUS-197 recorded both at the backup-commit moment, which is inside the
// window where Step 4 has STOPPED the postgres server:
//   - the row UPDATE could never land (Defect 1) — deterministic, every upgrade;
//     on crashed rows the column stayed NULL, which killed STATBUS-111's replay
//     AND failed the abort-hold guard OPEN;
//   - the flag stamp gave a PreSwap flag a BackupPath (Defect 2), falsifying the
//     PreSwap branch's "empty by construction" premise, so restoreDatabase
//     stopped refusing and a database no-op became a volume rewind — which also
//     reverted recovery_attempts (the 1-vs-3 the arcs saw).
//
// The behavioural arm below runs against a STOPPED SERVER, not a closed
// connection. That distinction IS the defect: terminalExec is teardown-immune
// against our own connection dying, and a connection-only test passes against
// the broken code.

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// stoppedServerService builds a Service whose recoveryDSN points at a port with
// NOTHING listening — the in-test equivalent of `docker compose stop db`. It
// binds a real listener to claim a free port, then closes it, so the port is
// genuinely dead rather than merely unlikely to be used.
func stoppedServerService(t *testing.T) *Service {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	if cerr := ln.Close(); cerr != nil { // the server is now STOPPED
		t.Fatal(cerr)
	}

	dir := t.TempDir()
	env := fmt.Sprintf(""+
		"CADDY_DB_BIND_ADDRESS=127.0.0.1\n"+
		"CADDY_DB_PORT=%d\n"+
		"POSTGRES_APP_DB=statbus_test\n"+
		"POSTGRES_ADMIN_USER=postgres\n"+
		"POSTGRES_ADMIN_PASSWORD=\n", port)
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0644); err != nil {
		t.Fatal(err)
	}
	return &Service{projDir: dir}
}

// TestTerminalExec_CannotReachAStoppedServer_STATBUS228 is the behavioural arm.
// terminalExec's doc calls it "teardown-immune"; STATBUS-197 read that as
// covering the consistent-backup window and put the backup_path row write inside
// it. Teardown-immunity covers OUR CONNECTION dying (154/163) — it opens a fresh
// one — and cannot cover a server that is not running.
//
// If this ever starts passing (i.e. the write succeeds against a stopped
// server), the premise of the whole fix has changed and the row write may move
// back.
func TestTerminalExec_CannotReachAStoppedServer_STATBUS228(t *testing.T) {
	d := stoppedServerService(t)

	err := d.terminalExec("UPDATE public.upgrade SET backup_path = $1 WHERE id = $2", "/tmp/x", 1)
	if err == nil {
		t.Fatal("terminalExec SUCCEEDED against a stopped server — teardown-immunity covers a dying CONNECTION, never a server that is not running. If this is genuinely reachable now, STATBUS-228's fix needs revisiting")
	}
	// It must be a CONNECT failure, not something else that would mask the point.
	if !strings.Contains(err.Error(), "connect") && !strings.Contains(err.Error(), "refused") {
		t.Errorf("expected a connect failure against the stopped server, got: %v", err)
	}
}

// TestExecuteUpgrade_NoRowWriteWhileTheServerIsStopped_STATBUS228 is the source
// pin: between "Stopping database..." (Step 4) and the binary-swap handoff, no
// public.upgrade write may appear. Anything added there cannot land — silently
// on successful upgrades (a later write repairs the column) and permanently on
// crashed ones, which is the population that needs it.
func TestExecuteUpgrade_NoRowWriteWhileTheServerIsStopped_STATBUS228(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])
	body := extractFuncBody(t, src, "func (d *Service) executeUpgrade(")

	stopIdx := strings.Index(body, `runCommand(projDir, "docker", "compose", "stop", "db")`)
	if stopIdx < 0 {
		t.Fatal("could not locate the Step 4 database stop — re-anchor this pin rather than letting it stop checking")
	}
	handoffIdx := strings.Index(body, "d.updateFlagNewSbSwapped(")
	if handoffIdx < 0 || handoffIdx < stopIdx {
		t.Fatal("could not locate the swap-boundary flag stamp after the database stop")
	}

	window := body[stopIdx:handoffIdx]
	for _, forbidden := range []string{
		"UPDATE public.upgrade",
		"INSERT INTO public.upgrade",
	} {
		// Ignore comment lines: this window DOCUMENTS the removed write at length.
		for _, line := range strings.Split(window, "\n") {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "//") {
				continue
			}
			if strings.Contains(trimmed, forbidden) {
				t.Errorf("STATBUS-228: a `%s` write sits between the Step 4 database STOP and the swap handoff — the postgres SERVER is stopped across that whole window, so this write cannot land (it fails silently on successful upgrades and permanently on crashed ones). Record it at the first reconnect instead.\n  offending line: %s", forbidden, trimmed)
			}
		}
	}
}

// TestPreSwapFlagCarriesNoBackupPath_STATBUS228 pins the invariant being
// restored — the one a future edit would silently break again, exactly as 197
// did. The PreSwap recovery branch's data-safety argument (service.go:1315-1318,
// :1348-1349) is only true while this holds: an unrecorded snapshot is what
// makes restoreDatabase REFUSE, and that refusal is what keeps a PreSwap
// rollback from touching an untouched volume.
//
// THIS TEST IS THE MECHANISM — DO NOT DELETE IT AS DUPLICATING THE COMMENTS IT
// CHECKS. STATBUS-228 asked whether the near-miss deserved a process guard
// ("when a change alters WHEN a field is populated, grep the field name in
// comments"). The architect ruled NO ticket, on the principle that A LOAD-BEARING
// INVARIANT STATED ONLY IN PROSE IS NOT A MECHANISM — and designated this pin as
// the mechanism instead: it is the one test that would have caught 197, which
// falsified the PreSwap premise while every other test stayed green for two
// days. The prose in service.go:1315-1349 is the explanation; this is the guard.
func TestPreSwapFlagCarriesNoBackupPath_STATBUS228(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])
	body := extractFuncBody(t, src, "func (d *Service) executeUpgrade(")

	stopIdx := strings.Index(body, `runCommand(projDir, "docker", "compose", "stop", "db")`)
	stampIdx := strings.Index(body, "d.updateFlagNewSbSwapped(")
	if stopIdx < 0 || stampIdx < 0 || stampIdx < stopIdx {
		t.Fatal("could not locate the stop/stamp anchors")
	}

	// No BackupPath may be written to the flag before the swap stamp. The swap
	// stamp (updateFlagNewSbSwapped) is the ONLY writer, which is what makes
	// "empty by construction at PreSwap" true.
	for _, line := range strings.Split(body[:stampIdx], "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "//") {
			continue
		}
		if strings.Contains(trimmed, "BackupPath =") || strings.Contains(trimmed, "f.BackupPath") {
			t.Errorf("STATBUS-228: the flag's BackupPath is stamped BEFORE the swap boundary — a PreSwap flag would then carry a snapshot identity, restoreDatabase would stop refusing, and a PreSwap rollback (where NOTHING has moved) would rewind the volume, reverting recovery_attempts with it.\n  offending line: %s", trimmed)
		}
	}

	// And the swap stamp itself must still carry it — the identity has to land
	// SOMEWHERE, or post-swap recovery loses the restore target entirely.
	if !strings.Contains(body[stampIdx:stampIdx+80], "backupPath") {
		t.Error("STATBUS-228: updateFlagNewSbSwapped must still receive backupPath — the swap is where the flag legitimately gains the identity")
	}
}

// THE FLAG INVARIANT, STATED ONCE, AT FLAG LEVEL (STATBUS-232):
//
//	NO PERSISTED FLAG MAY PAIR A PRE-SWAP PHASE WITH A SNAPSHOT IDENTITY.
//
// A flag saying "nothing has changed yet" while naming a database snapshot is
// read by recovery as permission to restore a volume that was never touched.
// That has now happened TWICE, from two different functions, by two different
// routes into the same illegal pair:
//
//   - STATBUS-197 wrote the BACKUP PATH onto a flag whose phase was pre-swap.
//   - STATBUS-210 wrote the PHASE onto a flag that already, legitimately, named
//     a snapshot — touching BackupPath not at all.
//
// The first guard enumerated BackupPath writers only, so it would not have
// caught 210 — a pin watching one door of two reports a safety it cannot see.
// This one covers BOTH doors: every write of EITHER field must be accounted for
// with the reason it is allowed. The invariant is expressed once here rather
// than once per field, because it is a property of the FLAG, not of a column.
//
// Nothing is wrong today (229 removed the only phase-blanking writer). The
// exposure this guards is the NEXT writer, in a codebase where this exact
// invariant has already been broken twice by people who had not read the
// comment explaining it.
func TestFlagInvariant_EveryPhaseAndBackupPathWriterIsAccountedFor_STATBUS232(t *testing.T) {
	// Every write of EITHER field, each with the reason it is legal. A new
	// writer fails here until someone states its reason — which is the only
	// form in which "no further producer exists" stays true over time.
	known := map[string]string{
		// ── BackupPath writers (the STATBUS-197 door) ──
		"flag.BackupPath = backupPath":           "updateFlagNewSbSwapped — THE swap stamp; it sets Phase=PhaseNewSbSwapped in the SAME write, which is what makes 'a pre-swap flag carries no snapshot' structural rather than conventional",
		"flag.BackupPath = authorizedBackupPath": "ReattemptRestore — rewrites the held operator-authorized replay marker in the same callback that sets PhaseNewSbUpgrading; this is an actual snapshot replay and therefore deliberately post-swap/resuming",
		"BackupPath:     flag.BackupPath":        "resumeNewSb's reacquire — carries the identity forward across NewSbSwapped→NewSbUpgrading; both are post-swap phases",
		"BackupPath: rowBackupPath.String":       "completeInProgressUpgrade — TWO literals share this text; each is checked for the pairing below (one is in-memory-only with a pre-swap phase, one is persisted with a post-swap phase)",

		// ── Phase writers (the STATBUS-210 door, the half that was missing) ──
		"f.Phase = normalizePhaseBytes(f.Phase)": "UnmarshalJSON's decode chokepoint — re-labels a legacy wire spelling to its canonical slug; it never changes WHICH state is meant, so it cannot create the illegal pair",
		"Phase:      PhaseOldSbUpgrading":        "writeUpgradeFlag's initial flag (no snapshot exists yet — nothing has been backed up) and completeInProgressUpgrade's in-memory rollback record; both checked for the pairing below",
		"flag.Phase = PhaseNewSbSwapped":         "updateFlagNewSbSwapped — the swap stamp again, POST-swap by definition; this is the write that legitimises carrying the identity",
		"flag.Phase = PhaseNewSbUpgrading":       "ReattemptRestore — paired in the same held-marker rewrite with authorizedBackupPath; a human-authorized snapshot replay is already in rollback/resume territory, never PreSwap",
		"Phase:      PhaseNewSbSwapped":          "parkAtTarget's persisted flag — a post-swap phase, the at-target truth; carrying the identity there is the legal shape",
		"Phase:          PhaseNewSbUpgrading":    "resumeNewSb's reacquire — post-swap, resume-began",
	}

	var offenders []string
	for name, srcBytes := range packageGoSources(t) {
		if strings.HasSuffix(name, "_test.go") {
			continue
		}
		for i, line := range strings.Split(string(srcBytes), "\n") {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "//") {
				continue
			}
			// Only assignments/initialisations of the two fields the invariant
			// couples — not reads, not comparisons.
			//
			// STATBUS-241 amendment: `X =` also matches `X ==`, so the original
			// matcher flagged COMPARISONS as writes — contradicting the sentence
			// directly above it. It surfaced when a new READER
			// (`if flagBackupPath == nil`) was reported as an unaccounted writer.
			// Adding that reader to `known` would have been the wrong repair: it
			// would have left the matcher mis-classifying every future comparison
			// and taught the next person to silence the pin rather than answer it.
			// Assignment now excludes `==`/`!=` so the check means what it says.
			assigns := func(field string) bool {
				i := strings.Index(trimmed, field+" =")
				if i < 0 {
					return false
				}
				rest := trimmed[i+len(field)+2:]
				return !strings.HasPrefix(rest, "=") // `X ==` is a comparison
			}
			comparesOnly := strings.Contains(trimmed, "BackupPath !=") || strings.Contains(trimmed, "Phase !=")
			writesField := !comparesOnly &&
				(assigns("BackupPath") || strings.Contains(trimmed, "BackupPath:") ||
					assigns(".Phase") || strings.Contains(trimmed, "Phase:"))
			if !writesField {
				continue
			}
			accounted := false
			for k := range known {
				if strings.Contains(trimmed, k) {
					accounted = true
					break
				}
			}
			if !accounted {
				offenders = append(offenders, fmt.Sprintf("%s:%d: %s", name, i+1, trimmed))
			}
		}
	}
	if len(offenders) > 0 {
		t.Errorf("STATBUS-232: %d unaccounted writer(s) of flag.Phase or flag.BackupPath. Both fields are listed because the invariant couples them: a PERSISTED flag pairing a pre-swap phase with a snapshot identity tells recovery to restore a volume nothing touched. It has been reached from BOTH sides — 197 wrote the snapshot onto a pre-swap flag, 210 wrote the phase onto a flag that already had one. If this new writer is safe, add it to `known` with the reason it cannot form that pair:\n  %s",
			len(offenders), strings.Join(offenders, "\n  "))
	}

	// THE ACTUAL INVARIANT, checked per construction site: a flag literal may pair
	// a BackupPath with a POST-SWAP phase freely (that is the normal, correct
	// shape). What must never reach recoverFromFlag's classifier is a PERSISTED
	// flag pairing a PRE-SWAP phase with a BackupPath — the state 197 produced from
	// executeUpgrade and 210 produced from parkServiceRecovery.
	//
	// Both synthesized-flag sites are checked here and both are legal today, for
	// DIFFERENT reasons — which is exactly why the check has to read the phase
	// rather than the shape:
	//   - completeInProgressUpgrade's flagless rollback: Phase=PhaseOldSbUpgrading
	//     (PreSwap) WITH a BackupPath — safe ONLY because the record is handed
	//     straight to recoveryRollback and never written to disk.
	//   - parkAtTarget: Phase=PhaseNewSbSwapped WITH a BackupPath, and it IS
	//     persisted — legal, because a post-swap phase carrying the identity is the
	//     shape the invariant exists to preserve.
	src := string(packageGoSources(t)["service.go"])
	for _, idx := range indexAll(src, "BackupPath: rowBackupPath.String") {
		literalStart := strings.LastIndex(src[:idx], "UpgradeFlag{")
		if literalStart < 0 {
			t.Errorf("STATBUS-229: could not find the flag literal enclosing the BackupPath assignment at offset %d — re-anchor this pin", idx)
			continue
		}
		literal := src[literalStart:idx]
		if !strings.Contains(literal, "Phase:      PhaseOldSbUpgrading") {
			continue // a post-swap phase carrying the identity is the legal shape
		}
		// PreSwap + BackupPath: legal only while it stays in memory.
		window := src[max0(literalStart-1200) : idx+200]
		if !strings.Contains(window, "d.recoveryRollback(ctx, UpgradeFlag{") {
			t.Errorf("STATBUS-229: a flag literal at offset %d pairs a PRE-SWAP phase with a BackupPath and is NOT handed straight to recoveryRollback — if it is persisted, recoverFromFlag will classify it as \"died before the swap\" and roll back destructively over a volume the phase says was never touched. That is 197 and 210 for a third time", literalStart)
		}
	}
}

func indexAll(s, sub string) []int {
	var out []int
	for i := 0; ; {
		j := strings.Index(s[i:], sub)
		if j < 0 {
			return out
		}
		out = append(out, i+j)
		i += j + len(sub)
	}
}

func max0(i int) int {
	if i < 0 {
		return 0
	}
	return i
}

// TestPreSwapRecoveryDoesNotRestore_STATBUS228 pins the OBSERVABLE that exposed
// Defect 2: the PreSwap branch tells the operator "the database was not
// modified, so nothing needs restoring" — and must not then restore. The
// message and the behaviour have to agree.
//
// The branch hands recoveryRollback a flag whose BackupPath is empty, and
// restoreDatabase refuses on empty; the pin therefore asserts the branch's
// message and its documented premise are both still present, so a future change
// that reintroduces a stamped PreSwap flag fails here with the reason attached.
func TestPreSwapRecoveryDoesNotRestore_STATBUS228(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])

	const claim = "flag.BackupPath is empty by construction at PreSwap"
	if !strings.Contains(src, claim) {
		t.Fatalf("the PreSwap branch's premise comment (%q) is gone — if the premise changed, the branch's data-safety argument and its operator message must change WITH it (STATBUS-228 Defect 2)", claim)
	}
	const message = "The database was not modified, so nothing needs restoring"
	if !strings.Contains(src, message) {
		t.Fatalf("the PreSwap branch's operator message (%q) is gone — it is the observable that exposed Defect 2 (it printed while a restore ran)", message)
	}

	// The premise must be ENFORCED, not merely asserted in prose: the only
	// BackupPath writer is the swap stamp (pinned by the test above), so a
	// PreSwap flag reaches recoveryRollback empty — and restoreDatabase's
	// empty-path branch is what turns that emptiness into an actual refusal.
	// Without this branch the invariant would be a comment, not a guarantee.
	restore := extractFuncBody(t, string(packageGoSources(t)["exec.go"]), "func (d *Service) restoreDatabase(")
	emptyGuard := strings.Index(restore, `if backupPath == ""`)
	if emptyGuard < 0 {
		t.Fatal("restoreDatabase no longer refuses on an empty backupPath — that refusal IS the PreSwap no-touch guarantee; without it, 'nothing needs restoring' becomes a claim the code does not keep (STATBUS-228 Defect 2)")
	}
	// The refusal must come FIRST — before any stat/rsync work — so an empty
	// identity can never reach the volume.
	if rsyncIdx := strings.Index(restore, "os.Stat("); rsyncIdx >= 0 && rsyncIdx < emptyGuard {
		t.Error("restoreDatabase inspects the path before refusing on empty — the empty-identity refusal must be the first thing it does")
	}
}
