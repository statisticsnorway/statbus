package unitfloor

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeRepoTemplate lays down a project dir containing the shipped unit.
func writeRepoTemplate(t *testing.T, body string) string {
	t.Helper()
	dir := t.TempDir()
	opsDir := filepath.Join(dir, "ops")
	if err := os.MkdirAll(opsDir, 0o755); err != nil {
		t.Fatalf("mkdir ops: %v", err)
	}
	if err := os.WriteFile(filepath.Join(opsDir, "statbus-upgrade.service"), []byte(body), 0o644); err != nil {
		t.Fatalf("write template: %v", err)
	}
	return dir
}

// withHome points UserUnitPath at a temp HOME, optionally installing a unit.
func withHome(t *testing.T, unitBody *string) {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	if unitBody == nil {
		return
	}
	unitDir := filepath.Join(home, ".config", "systemd", "user")
	if err := os.MkdirAll(unitDir, 0o755); err != nil {
		t.Fatalf("mkdir unit dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(unitDir, "statbus-upgrade@.service"), []byte(*unitBody), 0o644); err != nil {
		t.Fatalf("write unit: %v", err)
	}
}

func active(bool) runner   { return func(string) bool { return true } }
func inactive() runner     { return func(string) bool { return false } }
func alwaysActive() runner { return active(true) }

const shipped = "[Unit]\nDescription=statbus upgrade\nWatchdogSec=120\n"

// The demo incident, reproduced: no unit file at all. This is the case that sat
// silent for nine days, so it is the one the announce must name unmistakably.
func TestMissingUnitIsDetectedAndAnnounced(t *testing.T) {
	dir := writeRepoTemplate(t, shipped)
	withHome(t, nil)

	r := inspectWith(dir, "statbus_demo", "linux", alwaysActive())

	if r.State != UnitFileMissing {
		t.Fatalf("state = %v, want UnitFileMissing", r.State)
	}
	if r.Healthy() {
		t.Fatal("a box with no upgrade unit must not report healthy")
	}
	msg := r.Announce()
	if msg == "" {
		t.Fatal("a floor breach must produce an announcement")
	}
	// The whole point of the ticket: the message names the repair.
	if !strings.Contains(msg, "./sb install") {
		t.Errorf("announce must name the fix ./sb install, got:\n%s", msg)
	}
	// And it must say what the gap COSTS, not merely that a file is absent.
	if !strings.Contains(msg, "stale") {
		t.Errorf("announce must state the consequence, got:\n%s", msg)
	}
	if !strings.Contains(msg, r.UnitPath) {
		t.Errorf("announce must name the specific path, got:\n%s", msg)
	}
}

func TestDriftedUnitIsDetected(t *testing.T) {
	dir := writeRepoTemplate(t, shipped)
	old := "[Unit]\nDescription=statbus upgrade\nWatchdogSec=infinity\n"
	withHome(t, &old)

	r := inspectWith(dir, "statbus_demo", "linux", alwaysActive())

	if r.State != UnitFileDrifted {
		t.Fatalf("state = %v, want UnitFileDrifted", r.State)
	}
	if r.Healthy() {
		t.Fatal("a drifted unit must not report healthy")
	}
	if !strings.Contains(r.Announce(), "./sb install") {
		t.Error("drift announce must name the fix")
	}
}

// Unit correct but not running: the page still goes stale, so this is a breach.
func TestInactiveUnitIsDetected(t *testing.T) {
	dir := writeRepoTemplate(t, shipped)
	body := shipped
	withHome(t, &body)

	r := inspectWith(dir, "statbus_demo", "linux", inactive())

	if r.State != Inactive {
		t.Fatalf("state = %v, want Inactive", r.State)
	}
	if r.Healthy() {
		t.Fatal("an inactive service must not report healthy")
	}
	if !strings.Contains(r.Announce(), r.Instance) {
		t.Errorf("inactive announce must name the instance %q", r.Instance)
	}
}

func TestHealthyBoxIsSilent(t *testing.T) {
	dir := writeRepoTemplate(t, shipped)
	body := shipped
	withHome(t, &body)

	r := inspectWith(dir, "statbus_demo", "linux", alwaysActive())

	if r.State != OK {
		t.Fatalf("state = %v, want OK", r.State)
	}
	if !r.Healthy() {
		t.Fatal("a correct box must report healthy")
	}
	if r.Announce() != "" {
		t.Errorf("a healthy box must say nothing, got:\n%s", r.Announce())
	}
}

// A developer laptop has no user units. Alarming there would train people to
// ignore the message on the boxes where it matters.
func TestNonLinuxIsNotAlarmed(t *testing.T) {
	dir := writeRepoTemplate(t, shipped)
	withHome(t, nil)

	r := inspectWith(dir, "jhf", "darwin", inactive())

	if r.State != NotApplicable {
		t.Fatalf("state = %v, want NotApplicable", r.State)
	}
	if !r.Healthy() || r.Announce() != "" {
		t.Error("non-linux must be silent, not a false breach")
	}
}

// "Cannot tell" must not masquerade as either verdict.
func TestUnknownUserIsNotAlarmed(t *testing.T) {
	dir := writeRepoTemplate(t, shipped)
	withHome(t, nil)

	r := inspectWith(dir, "", "linux", inactive())

	if r.State != UnknownUser {
		t.Fatalf("state = %v, want UnknownUser", r.State)
	}
	if !r.Healthy() || r.Announce() != "" {
		t.Error("underivable instance must not be reported as a breach")
	}
}

// Missing repo template = no basis for comparison. Must not manufacture a
// breach on the surface whose credibility is the entire point.
func TestMissingRepoTemplateDoesNotFabricateBreach(t *testing.T) {
	dir := t.TempDir() // no ops/ at all
	withHome(t, nil)

	r := inspectWith(dir, "statbus_demo", "linux", alwaysActive())

	if !r.Healthy() {
		t.Fatalf("state = %v: a missing template must not be reported as a floor breach", r.State)
	}
}

// FileMatchesRepo is the install ladder's drift gate and MUST stay
// OS-independent. Wiring it through Inspect made it answer "matches" on macOS
// via the NotApplicable gate, silently disabling drift reconcile —
// cli/cmd/unit_reconcile_test.go caught it. This pins the seam here too, so the
// contract is defended in the package that owns it and not only by its caller.
func TestFileMatchesRepoIgnoresPlatformAndSystemd(t *testing.T) {
	shippedBody := shipped

	t.Run("drift is a mismatch regardless of host OS", func(t *testing.T) {
		dir := writeRepoTemplate(t, shippedBody)
		old := "[Unit]\nWatchdogSec=infinity\n"
		withHome(t, &old)
		if FileMatchesRepo(dir) {
			t.Error("a drifted unit must be a mismatch on every platform — this gate runs on developer laptops")
		}
	})

	t.Run("missing file is a mismatch regardless of host OS", func(t *testing.T) {
		dir := writeRepoTemplate(t, shippedBody)
		withHome(t, nil)
		if FileMatchesRepo(dir) {
			t.Error("a missing unit must be a mismatch so install writes it")
		}
	})

	t.Run("identical file matches", func(t *testing.T) {
		dir := writeRepoTemplate(t, shippedBody)
		body := shippedBody
		withHome(t, &body)
		if !FileMatchesRepo(dir) {
			t.Error("a byte-identical unit must match — no reconcile needed")
		}
	})

	t.Run("absent template is not a mismatch", func(t *testing.T) {
		dir := t.TempDir()
		withHome(t, nil)
		if !FileMatchesRepo(dir) {
			t.Error("no template means no basis to assert drift; must not wedge the install ladder")
		}
	})
}

func TestInstanceNameFollowsDeploymentUser(t *testing.T) {
	dir := writeRepoTemplate(t, shipped)
	body := shipped
	withHome(t, &body)

	for _, user := range []string{"statbus", "statbus_dev", "statbus_ma"} {
		r := inspectWith(dir, user, "linux", alwaysActive())
		want := "statbus-upgrade@" + user + ".service"
		if r.Instance != want {
			t.Errorf("user %q: instance = %q, want %q", user, r.Instance, want)
		}
	}
}
