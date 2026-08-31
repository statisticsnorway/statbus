package cmd

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

// STATBUS-323: the structural tests pin that install.sh SAYS the right things.
// This one proves the mechanism actually excludes — that the perl-on-inherited-fd
// idiom is a real kernel lock on THIS machine, not a construct that reads well
// and grants twice.
//
// It runs the exact idiom install.sh uses rather than a paraphrase: bash opens
// fd 9 on the flag with `exec 9<>`, perl fdopens it and takes flock(LOCK_EX|
// LOCK_NB). A second process attempting the same must be refused while the first
// holds it, and must succeed once the first exits — including when the first is
// KILLED, since the whole point of a kernel lock over a pidfile is that the
// kernel releases it on process death with no cleanup handler to forget.
func TestRepoLockIsARealKernelLock(t *testing.T) {
	if _, err := exec.LookPath("perl"); err != nil {
		t.Skip("perl not available; install.sh degrades with a warning in this case")
	}

	dir := t.TempDir()
	flag := filepath.Join(dir, "upgrade-in-progress.json")

	// Exactly install.sh's acquisition, reduced to acquire-and-report.
	tryAcquire := `
exec 9<>"$1" || exit 9
if perl -e 'use Fcntl ":flock"; open(my $f, "<&=9") or exit 2; exit(flock($f, LOCK_EX|LOCK_NB) ? 0 : 1);'; then
    echo ACQUIRED
    exit 0
fi
echo REFUSED
exit 1
`
	// Holder: takes the lock and waits to be killed, keeping fd 9 open.
	holdScript := `
exec 9<>"$1" || exit 9
perl -e 'use Fcntl ":flock"; open(my $f, "<&=9") or exit 2; exit(flock($f, LOCK_EX|LOCK_NB) ? 0 : 1);' || exit 1
echo HELD
sleep 60
`
	holdPath := filepath.Join(dir, "hold.sh")
	if err := os.WriteFile(holdPath, []byte(holdScript), 0o755); err != nil {
		t.Fatal(err)
	}

	holder := exec.Command("bash", holdPath, flag)
	// Own process group, so the kill below reaches the whole TREE. This is not
	// incidental: the lock lives with the open file description, and bash's
	// `sleep` child inherits fd 9 — so killing bash alone leaves the lock held
	// by the surviving child. That is a documented FEATURE (dev.sh's test-run
	// lock relies on it: a SIGKILLed parent whose child is still mutating the
	// database keeps the lock until that child exits, where a pidfile would
	// false-reclaim mid-mutation). The property under test here is release on
	// process-TREE death, so the test must kill the tree.
	holder.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	stdout, err := holder.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := holder.Start(); err != nil {
		t.Fatal(err)
	}
	killTree := func() {
		_ = syscall.Kill(-holder.Process.Pid, syscall.SIGKILL)
		_, _ = holder.Process.Wait()
	}
	defer killTree()

	// Wait for the holder to report it actually has the lock — never assume it
	// won by the time we look, or the exclusion test proves nothing.
	buf := make([]byte, 4)
	if _, err := stdout.Read(buf); err != nil {
		t.Fatalf("holder never reported HELD: %v", err)
	}
	if !strings.HasPrefix(string(buf), "HELD") {
		t.Fatalf("holder reported %q, want HELD", string(buf))
	}

	// A second acquirer must be REFUSED while the first holds it.
	out, _ := exec.Command("bash", "-c", tryAcquire, "try", flag).CombinedOutput()
	if got := strings.TrimSpace(string(out)); got != "REFUSED" {
		t.Fatalf("second acquirer got %q while the lock was held — the mutex does not exclude", got)
	}

	// SIGKILL the whole tree, with no cleanup path whatsoever — no EXIT trap, no
	// unlink, nothing that could have been forgotten. The kernel alone must drop
	// the lock. This is the property a pidfile or mkdir lock cannot offer, and
	// the reason a crashed install can never wedge every later one.
	killTree()

	out, _ = exec.Command("bash", "-c", tryAcquire, "try", flag).CombinedOutput()
	if got := strings.TrimSpace(string(out)); got != "ACQUIRED" {
		t.Fatalf("after the holder tree was SIGKILLed the lock was still refused (%q) — a crash would wedge every later install", got)
	}
}

// Opening the flag must not destroy an existing record. The file is also the
// install ladder's state marker: a live upgrade's record is how the ladder knows
// an upgrade is in flight, and truncating it would erase that mid-upgrade.
func TestOpeningTheFlagPreservesAnExistingRecord(t *testing.T) {
	dir := t.TempDir()
	flag := filepath.Join(dir, "upgrade-in-progress.json")

	existing := `{"id":42,"holder":"service","trigger":"scheduled"}`
	if err := os.WriteFile(flag, []byte(existing), 0o644); err != nil {
		t.Fatal(err)
	}

	// install.sh's open: read-write, create if absent, NO truncation.
	if out, err := exec.Command("bash", "-c", `exec 9<>"$1"; exit 0`, "open", flag).CombinedOutput(); err != nil {
		t.Fatalf("open failed: %v (%s)", err, out)
	}

	after, err := os.ReadFile(flag)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != existing {
		t.Errorf("opening the flag changed it:\n  before: %s\n  after:  %s\n  A live upgrade's record must survive — the ladder classifies from it.",
			existing, string(after))
	}
}
