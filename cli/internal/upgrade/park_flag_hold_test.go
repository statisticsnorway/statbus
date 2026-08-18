package upgrade

// STATBUS-212 oracles: parkServiceRecovery's truth-restoration must land at the
// BUDGET-park sites too, not only on the deterministic path the arcs exercise.
//
// The load-bearing mechanism is the flag HOLD: mutateHeldFlag writes through the
// already-open file handle under the flock, so a caller that does not hold it gets a
// warning and a marker that keeps lying. These tests drive the real production
// functions (adoptOrAcquireFlagHold → mutateHeldFlag) against a real flag file on
// disk, and assert the resulting BYTES — the phase a later crash-recovery classifier
// would actually read.
//
// The DB-dependent remainder of parkServiceRecovery (parkEraVerdict →
// StartDBForRecovery, restoreSourceServices) is not unit-reachable; the source pins
// below cover its ordering, and the VM proof rides whichever suite exercises budget
// parks.

import (
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

// writeTestFlag lays down a post-swap flag file — the state a budget park finds after
// the binary swap, and the marker that lies once the source services are restored.
func writeTestFlag(t *testing.T, projDir string) UpgradeFlag {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(projDir, "tmp"), 0755); err != nil {
		t.Fatal(err)
	}
	flag := UpgradeFlag{
		ID:         4242,
		CommitSHA:  "0123456789abcdef0123456789abcdef01234567",
		CommitTags: []string{"v2026.08.0-rc.02"},
		StartedAt:  time.Now().Truncate(time.Second),
		InvokedBy:  "test",
		Trigger:    "notify",
		Holder:     HolderService,
		Phase:      PhaseNewSbSwapped,
		BackupPath: "dbdumps/statbus-before-upgrade.sql.gz",
	}
	data, err := json.MarshalIndent(flag, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(flagFilePath(projDir), data, 0644); err != nil {
		t.Fatal(err)
	}
	return flag
}

func readTestFlag(t *testing.T, projDir string) UpgradeFlag {
	t.Helper()
	flag, err := ReadFlagFile(projDir)
	if err != nil {
		t.Fatalf("ReadFlagFile: %v", err)
	}
	if flag == nil {
		t.Fatal("no flag file on disk")
	}
	return *flag
}

// TestFlagHold_UnheldBudgetPark_RewritesPhaseOnDisk_STATBUS212 is the site-2 arm and
// the one that proves the ruling did more than reorder site 1: resumeNewSb's
// same-step-twice branch never acquired the flock AT ALL (its only acquireFlock sits
// after the branch has returned), so there was nothing to reorder. Entering with NO
// hold, the helper must still leave a truthful pre-swap marker on disk.
//
// RED before STATBUS-212: mutateHeldFlag returns "no flag file held" and the on-disk
// Phase stays new-sb-swapped — the lying marker that gets a just-un-parked row rolled
// back.
func TestFlagHold_UnheldBudgetPark_RewritesPhaseOnDisk_STATBUS212(t *testing.T) {
	dir := t.TempDir()
	original := writeTestFlag(t, dir)
	d := &Service{projDir: dir}

	release, err := d.adoptOrAcquireFlagHold()
	if err != nil {
		t.Fatalf("adoptOrAcquireFlagHold with no prior hold must succeed: %v", err)
	}

	// FINDING-3 TRAP: acquireFlock truncates and rewrites the file with whatever value
	// it is handed, so a naive acquire would have clobbered the marker before anyone
	// could rewrite it truthfully. The acquisition must be VERBATIM.
	if mid := readTestFlag(t, dir); mid.Phase != original.Phase || mid.ID != original.ID || mid.BackupPath != original.BackupPath {
		t.Fatalf("the acquisition changed the flag it was only supposed to HOLD: got phase=%q id=%d backup=%q, want phase=%q id=%d backup=%q",
			mid.Phase, mid.ID, mid.BackupPath, original.Phase, original.ID, original.BackupPath)
	}

	if err := d.mutateHeldFlag(func(f *UpgradeFlag) { f.Phase = PhaseOldSbUpgrading }); err != nil {
		t.Fatalf("the truth-restoration rewrite must succeed once the hold is adopted-or-acquired: %v", err)
	}
	release()

	got := readTestFlag(t, dir)
	if got.Phase != PhaseOldSbUpgrading {
		t.Errorf("on-disk Phase = %q, want %q — a budget-parked, source-restored box must carry a PRE-SWAP marker, or the un-park's fresh attempt is rolled back by an honest reader (STATBUS-210/212)", got.Phase, PhaseOldSbUpgrading)
	}
	// BackupPath is the attempt's snapshot identity (STATBUS-197) — the rewrite keeps it.
	if got.BackupPath != original.BackupPath {
		t.Errorf("BackupPath = %q, want %q kept — the rewrite changes the phase only", got.BackupPath, original.BackupPath)
	}
	if got.ID != original.ID || got.CommitSHA != original.CommitSHA {
		t.Errorf("identity fields changed: id=%d sha=%q, want id=%d sha=%q", got.ID, got.CommitSHA, original.ID, original.CommitSHA)
	}
}

// TestFlagHold_ReleasedThenAdopted_RewritesPhaseOnDisk_STATBUS212 is the site-1 arm:
// RecoveryBudgetGuard acquires the flock, parks, RELEASES, and only then calls the
// helper. The released state must be re-acquirable and the rewrite must still land —
// and the guard's own release must not have damaged the marker on the way out.
func TestFlagHold_ReleasedThenAdopted_RewritesPhaseOnDisk_STATBUS212(t *testing.T) {
	dir := t.TempDir()
	original := writeTestFlag(t, dir)
	d := &Service{projDir: dir}

	// Reproduce the guard's own acquire/release cycle (`base := *flag`, acquire, Close).
	base := original
	lock, lerr := acquireFlock(dir, base)
	if lerr != nil {
		t.Fatalf("guard-shaped acquire: %v", lerr)
	}
	d.flagLock = lock
	d.flagLock = nil
	lock.Close()

	release, err := d.adoptOrAcquireFlagHold()
	if err != nil {
		t.Fatalf("adopt-or-acquire after the guard's release must succeed: %v", err)
	}
	if err := d.mutateHeldFlag(func(f *UpgradeFlag) { f.Phase = PhaseOldSbUpgrading }); err != nil {
		t.Fatalf("rewrite after re-acquire: %v", err)
	}
	release()

	if got := readTestFlag(t, dir); got.Phase != PhaseOldSbUpgrading {
		t.Errorf("on-disk Phase = %q, want %q at the RecoveryBudgetGuard site", got.Phase, PhaseOldSbUpgrading)
	}
}

// TestFlagHold_AlreadyHeldIsAdoptedNotReacquired_STATBUS212 pins the deterministic
// path unchanged: when the caller already holds the lock, the helper must adopt it —
// not acquire, and above all not RELEASE it, which would pull the flock out from
// under an upgrade still running inside applyNewSbUpgrading. Byte-for-byte unchanged
// there is what keeps STATBUS-210's arc-proven coverage valid.
func TestFlagHold_AlreadyHeldIsAdoptedNotReacquired_STATBUS212(t *testing.T) {
	dir := t.TempDir()
	writeTestFlag(t, dir)
	d := &Service{projDir: dir}

	lock, lerr := acquireFlockVerbatim(dir)
	if lerr != nil {
		t.Fatalf("pre-acquire: %v", lerr)
	}
	d.flagLock = lock

	release, err := d.adoptOrAcquireFlagHold()
	if err != nil {
		t.Fatalf("adopting an existing hold must succeed: %v", err)
	}
	if d.flagLock != lock {
		t.Fatal("an already-held lock must be ADOPTED, not replaced — the caller still owns it")
	}
	release()
	if d.flagLock != lock || d.flagLock.file == nil {
		t.Fatal("release must be a NO-OP for an adopted lock: the helper may only release what IT acquired, never its caller's hold")
	}
	// Still usable by the owner after the helper returned.
	if err := d.mutateHeldFlag(func(f *UpgradeFlag) { f.Phase = PhaseOldSbUpgrading }); err != nil {
		t.Fatalf("the caller's hold must survive the helper: %v", err)
	}
	lock.Close()
}

// TestFlagHold_NoFlagFileConjuresNothing_STATBUS212: with no flag file, there is no
// marker to hold and none that could be lying. acquireFlock opens O_CREATE, so a
// naive acquire here would CONJURE an upgrade-in-progress marker out of nothing —
// which `./sb install`'s state probe would then read as a crashed upgrade.
func TestFlagHold_NoFlagFileConjuresNothing_STATBUS212(t *testing.T) {
	dir := t.TempDir()
	d := &Service{projDir: dir}

	release, err := d.adoptOrAcquireFlagHold()
	if err != nil {
		t.Fatalf("no flag file is not an error — there is simply nothing to hold: %v", err)
	}
	release()

	if _, statErr := os.Stat(flagFilePath(dir)); !os.IsNotExist(statErr) {
		t.Fatalf("a flag file was CREATED where none existed (stat err: %v) — acquiring a hold must never invent an upgrade-in-progress marker", statErr)
	}
	if d.flagLock != nil {
		t.Error("no flag file must leave d.flagLock nil")
	}
}

// TestFlagHold_ContendedFlockIsAnError_STATBUS212: a live holder must surface as an
// error so the caller can refuse. flock is per open-file-description, so a second
// open in this same process contends exactly as another process would.
func TestFlagHold_ContendedFlockIsAnError_STATBUS212(t *testing.T) {
	dir := t.TempDir()
	writeTestFlag(t, dir)

	f, err := os.OpenFile(flagFilePath(dir), os.O_RDWR, 0644)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = f.Close() }()
	if lerr := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); lerr != nil {
		t.Fatalf("could not take the contending lock: %v", lerr)
	}

	d := &Service{projDir: dir}
	release, err := d.adoptOrAcquireFlagHold()
	if err == nil {
		release()
		t.Fatal("a CONTENDED flock must be an error — the live holder is the signal that another actor owns box mutations (STATBUS-111), and the caller must be able to refuse")
	}
	if d.flagLock != nil {
		t.Error("a failed acquisition must leave d.flagLock nil")
	}
}

// TestNilProgressLogIsADiscardWriter_STATBUS204Nit pins the behavior the site-1 nit
// fix relies on: a nil *ProgressLog narrates to stdout/journal, writes no file, and
// hands io.Discard to child processes — a genuine discard writer. That is what makes
// "run the restoration even when the log will not open" safe, rather than a panic
// waiting on a rare path.
func TestNilProgressLogIsADiscardWriter_STATBUS204Nit(t *testing.T) {
	if plog := AppendProgressLog(t.TempDir(), ""); plog != nil {
		t.Fatal("AppendProgressLog with no relPath must return nil — that nil IS the discard writer")
	}
	var discard *ProgressLog
	discard.Write("park narrative with no file behind it: %d", 1) // must not panic
	if discard.File() != io.Discard {
		t.Error("a nil ProgressLog must hand io.Discard to child-process writers")
	}
	if discard.RelPath() != "" || discard.AbsPath() != "" {
		t.Error("a nil ProgressLog must report empty paths")
	}
	discard.Close() // must not panic
}

// TestParkServiceRecovery_OwnsItsFlagHold_STATBUS212 is the source-parsing pin, in
// the family that already guards this function (the STATBUS-204 watchdog-cover pin):
// the adopt-or-acquire must PRECEDE the era verdict and its release must be deferred,
// so a refactor cannot silently drop the hold and quietly return the budget sites to
// a lying marker.
func TestParkServiceRecovery_OwnsItsFlagHold_STATBUS212(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])
	psr := extractFuncBody(t, src, "func (d *Service) parkServiceRecovery(")

	holdIdx := strings.Index(psr, "d.adoptOrAcquireFlagHold()")
	if holdIdx < 0 {
		t.Fatal("STATBUS-212: parkServiceRecovery must OWN its flag hold (adoptOrAcquireFlagHold) — the truth-restoration cannot depend on whether the caller happens to hold the flock; both budget-park sites do not")
	}
	verdictIdx := strings.Index(psr, "d.parkEraVerdict(")
	if verdictIdx < 0 || holdIdx > verdictIdx {
		t.Errorf("STATBUS-212: the adopt-or-acquire must PRECEDE parkEraVerdict (hold@%d, verdict@%d) — the hold covers the whole span that ends in the flag rewrite", holdIdx, verdictIdx)
	}
	if !strings.Contains(psr, "defer releaseFlagHold()") {
		t.Error("STATBUS-212: the acquired hold must be released via defer — released on EVERY exit arm, and only what was acquired")
	}

	// CONTENTION ARM: refuse the whole helper BEFORE any service is started. The
	// refusal narrative must come before the era verdict and the restoration, so a
	// contended flock can never reach restoreSourceServices.
	refusalIdx := strings.Index(psr, "the upgrade flag's lock is held by another live actor")
	restoreIdx := strings.Index(psr, "d.restoreSourceServices(")
	if refusalIdx < 0 {
		t.Fatal("STATBUS-212 AC#1: the contention arm must narrate a NAMED refusal (a live holder means another actor owns box mutations)")
	}
	if refusalIdx > verdictIdx || refusalIdx > restoreIdx {
		t.Errorf("STATBUS-212 AC#1: the contention refusal must return BEFORE any service is started — never 'restore anyway and skip the rewrite' (refusal@%d, verdict@%d, restore@%d)", refusalIdx, verdictIdx, restoreIdx)
	}
}

// TestBudgetParkSites_EnterWithoutTheHold_STATBUS212 pins the premise the ruling
// CORRECTED, so the correction cannot rot: site 2 never held the flock on the park
// branch (its single acquireFlock comes AFTER that branch returns), which is why a
// reorder-site-1 fix would have left site 2 lying. Both sites reach the helper
// unheld — that is precisely what the helper now handles for them.
func TestBudgetParkSites_EnterWithoutTheHold_STATBUS212(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])

	// SITE 2 — resumeNewSb: the helper call precedes the function's ONLY acquireFlock.
	resume := extractFuncBody(t, src, "func (d *Service) resumeNewSb(")
	helperIdx := strings.Index(resume, "d.parkServiceRecovery(")
	acquireIdx := strings.Index(resume, "acquireFlock(")
	if helperIdx < 0 || acquireIdx < 0 {
		t.Fatal("resumeNewSb must contain both the park-recovery call and its flock re-acquire")
	}
	if strings.Count(resume, "acquireFlock(") != 1 {
		t.Errorf("resumeNewSb is expected to touch the flock EXACTLY ONCE (found %d) — if that changed, re-verify which sites reach parkServiceRecovery unheld", strings.Count(resume, "acquireFlock("))
	}
	if helperIdx > acquireIdx {
		t.Error("STATBUS-212: the same-step-twice park calls parkServiceRecovery BEFORE resumeNewSb's only acquireFlock — on that branch the flock is never held, so the helper must own the hold itself (a call-site reorder cannot fix this site)")
	}

	// SITE 1 — RecoveryBudgetGuard: the helper call comes after the guard's release().
	guard := extractFuncBody(t, src, "func (d *Service) RecoveryBudgetGuard(")
	if !strings.Contains(guard, "d.parkServiceRecovery(") {
		t.Fatal("RecoveryBudgetGuard must route its budget park through parkServiceRecovery")
	}
	branchStart := strings.Index(guard, "if action, reason := resumeEscalation(")
	if branchStart < 0 {
		t.Fatal("RecoveryBudgetGuard's escalation branch could not be located — this pin reads that branch; re-anchor it rather than letting it silently stop checking")
	}
	parkBranch := guard[branchStart:]
	releaseIdx := strings.Index(parkBranch, "release()")
	guardHelperIdx := strings.Index(parkBranch, "d.parkServiceRecovery(")
	if releaseIdx < 0 || guardHelperIdx < 0 || releaseIdx > guardHelperIdx {
		t.Errorf("STATBUS-212: RecoveryBudgetGuard releases the flock BEFORE calling parkServiceRecovery (release@%d, helper@%d) — the helper therefore enters unheld and must acquire its own", releaseIdx, guardHelperIdx)
	}
}

// TestBudgetParkSite1_RestorationNotGatedOnItsLog_STATBUS204Nit closes the nit 204
// recorded for its next touch: the restoration must run whether or not the progress
// log opens. Gating it left the box DARK for a bookkeeping failure — losing the
// narrative is acceptable, losing the box is not.
func TestBudgetParkSite1_RestorationNotGatedOnItsLog_STATBUS204Nit(t *testing.T) {
	src := string(packageGoSources(t)["service.go"])
	guard := extractFuncBody(t, src, "func (d *Service) RecoveryBudgetGuard(")

	if strings.Contains(guard, "if plog := AppendProgressLog(") {
		t.Error("STATBUS-204 nit: the park-recovery call must NOT be nested inside an `if plog := AppendProgressLog(...)` guard — a missing or unopenable log then skips the restoration and the box stays dark for a bookkeeping failure. Pass the (possibly nil) log through instead: nil is this codebase's discard writer")
	}
	if !strings.Contains(guard, "plog := AppendProgressLog(") {
		t.Error("STATBUS-204 nit: RecoveryBudgetGuard should still OPEN the row's progress log — the park story belongs on the row's log when it is available")
	}
	logIdx := strings.Index(guard, "plog := AppendProgressLog(")
	callIdx := strings.Index(guard, "d.parkServiceRecovery(")
	if logIdx < 0 || callIdx < 0 || logIdx > callIdx {
		t.Errorf("the log open must precede the helper call (log@%d, call@%d)", logIdx, callIdx)
	}
}
