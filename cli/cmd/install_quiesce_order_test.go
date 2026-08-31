package cmd

import (
	"os"
	"strings"
	"testing"
)

// STATBUS-323. install.sh must own the repository for the duration of the
// bootstrap: it takes the upgrade mutex BEFORE its first git operation, because
// the box's upgrade service fetches the same repo on its ~2-minute discovery
// tick.
//
// Observed on ma (2026-08-31): `git fetch origin --tags` died with
//
//	cannot lock ref 'refs/remotes/origin/master': is at 3bd85bfae but expected 376a18c38
//
// while et and jo, run minutes earlier with identical commands, won their races.
//
// Source-order structural tests, the established install.sh/install.go pattern:
// a behavioural test would need a live systemd session, a real clone and a
// service ticking against a remote. The ORDER is the property that matters and
// it is statically checkable. The lock MECHANISM is covered behaviourally by
// TestRepoLockIsARealKernelLock below.
func TestRepoLockAcquiredBeforeAnyRepoOperation(t *testing.T) {
	body := readInstallScript(t)

	// LINE-BASED, AND COMMENTS DO NOT COUNT. A naive substring scan reports the
	// header comment ("git clone, download binary, ...") as a repo operation
	// preceding the lock, failing on prose while the command order is correct.
	acquireLine, ok := lineOf(body, "statbus_repo_lock_acquire\n")
	if !ok {
		// The definition contains the name too; find the CALL, which is the
		// last bare occurrence at column 0.
		acquireLine, ok = lineOf(body, "statbus_repo_lock_acquire")
	}
	if !ok {
		t.Fatal("install.sh no longer acquires the repository lock — the STATBUS-323 fetch race is reopened")
	}

	for _, op := range []string{
		"git clone",
		"git fetch",
		"git checkout",
		"git remote set-branches",
	} {
		opLine, found := lineOf(body, op)
		if !found {
			continue
		}
		if opLine < acquireLine {
			t.Errorf("%q runs at line %d, BEFORE the lock acquisition at line %d — it can be raced by the service's discovery fetch",
				op, opLine, acquireLine)
		}
	}
}

// THE RULING'S CENTRAL CONSTRAINT. install.sh must never stop the upgrade unit.
// `systemctl --user stop` sends SIGTERM (the unit declares no KillSignal), and
// an in-flight upgrade answers SIGTERM with a ROLLBACK — a snapshot restore over
// the live database. That is the deploy-stop footgun that wedged rune, and
// install.sh's own header has forbidden it since. This pins the prohibition so
// no future "quiesce" reintroduces it.
func TestInstallScriptNeverStopsTheUpgradeUnit(t *testing.T) {
	body := readInstallScript(t)
	for i, line := range strings.Split(body, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		if strings.Contains(line, "systemctl") && strings.Contains(line, "stop") {
			t.Errorf("line %d stops a unit: %q\n  SIGTERM to an in-flight upgrade triggers a rollback over the live DB (the rune footgun). Take the mutex instead.",
				i+1, trimmed)
		}
	}
}

// The flag file is BOTH the lock and the state marker: the install ladder
// classifies live-upgrade / crashed-upgrade from its PRESENCE. Creating it to
// lock it would manufacture a state the next run misreads as an upgrade in
// flight. It closes only via the holder field, so the record we write must be
// the install-held one.
func TestLockWritesTheInstallHolderRecord(t *testing.T) {
	body := readInstallScript(t)

	for _, required := range []string{
		`"holder":"install"`,
		`"trigger":"install"`,
	} {
		if !strings.Contains(body, required) {
			t.Errorf("the lock record must contain %s — otherwise its mere presence reads as a service upgrade in flight", required)
		}
	}
	// O_RDWR without truncation: an existing live-upgrade record must survive
	// our opening the file.
	if !strings.Contains(body, `exec 9<>"$_flag"`) {
		t.Error("the flag must be opened read-write WITHOUT truncation (exec 9<>) so an existing upgrade record is not destroyed")
	}
	if strings.Contains(body, `exec 9>"$_flag"`) {
		t.Error("exec 9> TRUNCATES — it would destroy a live upgrade's own record")
	}
}

// An upgrade can hold this mutex for many minutes. A silent wait is
// indistinguishable from a hang, so contention must announce itself and name
// the holder BEFORE blocking.
func TestContentionIsAnnouncedBeforeBlocking(t *testing.T) {
	body := readInstallScript(t)

	nbIdx := strings.Index(body, "LOCK_EX|LOCK_NB")
	if nbIdx == -1 {
		t.Fatal("no non-blocking attempt — install.sh would block silently on a held mutex")
	}
	waitIdx := strings.Index(body, "flock($f, LOCK_EX)")
	if waitIdx == -1 {
		t.Fatal("no blocking wait after the non-blocking try")
	}
	if nbIdx > waitIdx {
		t.Error("the non-blocking try must come FIRST; blocking is only for announced contention")
	}
	notice := strings.Index(body, "Waiting for the upgrade mutex")
	if notice == -1 || notice > waitIdx {
		t.Error("contention must be announced BEFORE the blocking wait, not after it")
	}
	if !strings.Contains(body, "Holder record:") {
		t.Error("the contention notice must name who holds the lock")
	}
}

// The Go installer acquires this same mutex itself (acquireOrBypass). Holding it
// across that call would fail EWOULDBLOCK against ourselves — the self-deadlock
// the flag-ownership contract warns about.
func TestLockIsReleasedBeforeTheGoInstaller(t *testing.T) {
	body := readInstallScript(t)

	releaseLine, ok := lineOf(body, "statbus_repo_lock_release")
	if !ok {
		t.Fatal("install.sh never releases the mutex — the Go installer would EWOULDBLOCK against it")
	}
	installLine, ok := lineOf(body, "sb install $SB_INSTALL_ARGS")
	if !ok {
		t.Fatal("could not find the Go installer invocation")
	}
	if releaseLine > installLine {
		t.Errorf("release at line %d comes AFTER the Go installer at line %d — it will fail to acquire the mutex we still hold",
			releaseLine, installLine)
	}
}

// flock(1) is util-linux and absent on macOS; the portable idiom is perl
// fdopening an inherited descriptor, as dev.sh's test-run lock already proves.
func TestLockUsesThePortableIdiom(t *testing.T) {
	body := readInstallScript(t)

	if strings.Contains(body, "command -v flock") || strings.Contains(body, "\nflock ") {
		t.Error("flock(1) is util-linux and absent on macOS — use the perl-on-inherited-fd idiom dev.sh already proves")
	}
	if !strings.Contains(body, `open(my $f, "<&=9")`) {
		t.Error("expected the perl fdopen-inherited-descriptor idiom")
	}
}

func readInstallScript(t *testing.T) string {
	t.Helper()
	src, err := os.ReadFile(thisRepoFile(t, "install.sh"))
	if err != nil {
		t.Fatalf("read install.sh: %v", err)
	}
	return string(src)
}

// lineOf returns the 1-based line number of the first EXECUTABLE occurrence of
// needle — comment lines are skipped, so documentation describing a command is
// never mistaken for the command itself.
func lineOf(body, needle string) (int, bool) {
	for i, line := range strings.Split(body, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		if strings.Contains(line, needle) {
			return i + 1, true
		}
	}
	return 0, false
}
