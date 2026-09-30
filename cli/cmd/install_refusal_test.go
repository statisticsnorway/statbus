package cmd

import (
	"bytes"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/install"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// The rc.16 upgrade arcs (run 36468921894) found two named recovery refusals
// swallowed into "The installation stopped before it could finish": the
// severed proxy route (postswap-severed-proxy-refusal, STATBUS-143 AC#4) and
// the git-corrupt restore re-attempt (restore-broke-reattempt, STATBUS-111).
// These tests follow each named refusal from where the product raises it to
// the text the operator sees, from `./sb install` directly and through
// install.sh.

// installRefusalFixture builds an install directory whose crash-recovery path
// is real: runCrashRecovery runs against a fake docker (no proxy container)
// and a .env whose database route has nothing listening.
func installRefusalFixture(t *testing.T) string {
	t.Helper()
	dir := withRunInstallDetectionHooks(t)
	// Prefer a short temp root for the fake docker: the unit-test guard
	// only permits docker resolved under os.TempDir().
	bin := t.TempDir()
	docker := `#!/bin/sh
# Fake docker for the severed-proxy route: db exists, proxy was removed.
case "$*" in
  info*) printf '%s\n' "$STATBUS_TEST_DOCKER_ROOT" ;;
  "compose ps -a --format json") printf '{"ID":"db1","Service":"db","State":"running"}\n' ;;
  "compose ps -a -q proxy") ;;
  *) echo "fake docker: unexpected $*" >&2; exit 97 ;;
esac
`
	if err := os.WriteFile(filepath.Join(bin, "docker"), []byte(docker), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	// `./sb config generate` is the recovery's first subprocess; a no-op here.
	if err := os.WriteFile(filepath.Join(dir, "sb"), []byte("#!/bin/sh\nexit 0\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	if err := listener.Close(); err != nil {
		t.Fatal(err)
	}
	env := fmt.Sprintf("CADDY_DB_BIND_ADDRESS=127.0.0.1\nCADDY_DB_PORT=%d\nPOSTGRES_APP_DB=statbus_test\nPOSTGRES_ADMIN_USER=postgres\nPOSTGRES_ADMIN_PASSWORD=x\n", port)
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("USER", "") // no systemd unit to quiesce in a unit test
	return dir
}

// TestInstallShowsSeveredProxyRemedy: the whole ./sb install command, with the
// real crash recovery finding no proxy container. The operator's stderr must
// carry the STATBUS-143 refusal the arc asserts, never the generic line.
func TestInstallShowsSeveredProxyRemedy(t *testing.T) {
	dir := installRefusalFixture(t)
	detectInstallState = func(string, string) (install.State, *install.Detail, error) {
		return install.StateCrashedUpgrade, &install.Detail{Flag: &upgrade.UpgradeFlag{Holder: upgrade.HolderService}}, nil
	}
	runInstallStepTableTestHook = func() error { t.Fatal("a refused recovery reached the step table"); return nil }
	var stderr bytes.Buffer
	installCmd.SetErr(&stderr)
	t.Cleanup(func() { installCmd.SetErr(nil) })
	err := installCmd.RunE(installCmd, nil)
	if err == nil {
		t.Fatal("severed proxy route did not refuse")
	}
	got := stderr.String()
	for _, want := range []string{
		// test/install-recovery/arcs/postswap-severed-proxy-refusal-arc.sh:184-188
		"the db's connection route — the proxy container — does not exist",
		"docker compose up -d proxy",
		"CADDY_DB_BIND_ADDRESS",
		// The rerun keeps this box's program and tree, from any directory.
		"then re-run `" + upgrade.InstallCommand(dir) + "`",
		"INSTALL_CAUSE: " + installRefusalCatalogue[upgrade.RefusalProxyRouteMissing].cause,
		"INSTALL_FIX: " + installRefusalCatalogue[upgrade.RefusalProxyRouteMissing].fix,
	} {
		if !strings.Contains(got, want) {
			t.Errorf("operator stderr lacks %q:\n%s", want, got)
		}
	}
	if strings.Contains(got, "stopped before it could finish") || strings.Contains(got, "connection refused") {
		t.Errorf("operator stderr shows the generic line or a raw error:\n%s", got)
	}
	diagnostics, readErr := os.ReadFile(filepath.Join(dir, "tmp", "install-last-run-output.txt"))
	if readErr != nil || !strings.Contains(string(diagnostics), "connection refused") {
		t.Errorf("the raw recovery error must stay in the installation diagnostics: %v\n%s", readErr, diagnostics)
	}
}

// Every named refusal class, as it reaches runInstall's caller: the refusal's
// own text and its fixed cause/fix pair reach the operator, its internal
// detail does not.
func TestEveryNamedRefusalReachesTheOperator(t *testing.T) {
	const secret = "pgx: dial tcp 10.0.0.9:5432 secret=hunter2"
	cases := map[upgrade.RefusalClass]error{}
	for _, class := range upgrade.RefusalClasses() {
		cases[class] = &upgrade.OperatorRefusalError{Class: class, Text: "named refusal " + string(class), Detail: errors.New(secret)}
	}
	// The real constructors and classifiers, wrapped as runInstall wraps them.
	cases[upgrade.RefusalProxyRouteMissing] = fmt.Errorf("crash recovery: %w", recoveryDBRouteRefusal(errors.New(secret), upgrade.NewProxyRouteMissingError("/home/statbus/statbus"), "/home/statbus/statbus"))
	cases[upgrade.RefusalRestoreGitCorrupt] = restoreReattemptFailure(upgrade.NewRestoreGitCorruptError(errors.New(secret), ""), "/home/statbus/statbus")
	cases[upgrade.RefusalRecoveryDBUnreachable] = fmt.Errorf("crash recovery: %w", recoveryDBRouteRefusal(errors.New(secret), errors.New("docker compose start db: exit status 1"), "/home/statbus/statbus"))
	cases[upgrade.RefusalRestoreDegraded] = restoreReattemptFailure(errors.New(secret), "/home/statbus/statbus")
	for class, err := range cases {
		t.Run(string(class), func(t *testing.T) {
			var named *upgrade.OperatorRefusalError
			if !errors.As(err, &named) || named.Class != class {
				t.Fatalf("error is not the named %s refusal: %v", class, err)
			}
			var stderr bytes.Buffer
			printInstallFailure(&stderr, err)
			got := stderr.String()
			guidance := installRefusalCatalogue[class]
			for _, want := range []string{named.Text, "INSTALL_CAUSE: " + guidance.cause, "INSTALL_FIX: " + guidance.fix} {
				if !strings.Contains(got, want) {
					t.Errorf("operator output lacks %q:\n%s", want, got)
				}
			}
			if strings.Contains(got, "hunter2") || strings.Contains(got, "stopped before it could finish") {
				t.Errorf("operator output shows internal detail or the generic line:\n%s", got)
			}
		})
	}
}

// The restore-broke arc's 7th dispatch expects the git-corrupt refusal
// itself, not the degraded forecast that used to wrap it.
func TestRestoreReattemptKeepsGitCorruptRefusal(t *testing.T) {
	var stderr bytes.Buffer
	printInstallFailure(&stderr, restoreReattemptFailure(upgrade.NewRestoreGitCorruptError(errors.New("unknown revision"), ""), "/home/statbus/statbus"))
	got := stderr.String()
	// test/install-recovery/arcs/restore-broke-reattempt-arc.sh:620-622
	for _, want := range []string{"ROLLBACK_FAILED_GIT_CORRUPT", "the git tree is corrupt", "do NOT proceed"} {
		if !strings.Contains(got, want) {
			t.Errorf("operator output lacks %q:\n%s", want, got)
		}
	}
	if strings.Contains(got, "will re-attempt the same restore") {
		t.Errorf("a refusal before anything changed is not a failed restore:\n%s", got)
	}
}

func TestEveryRefusalClassHasInstallGuidance(t *testing.T) {
	forbidden := installOperatorForbiddenDiagnostics(t)
	for _, class := range upgrade.RefusalClasses() {
		guidance, ok := installRefusalCatalogue[class]
		if !ok || guidance.cause == "" || guidance.fix == "" {
			t.Errorf("refusal class %s has no operator cause/fix", class)
			continue
		}
		if forbidden.MatchString(guidance.cause) || forbidden.MatchString(guidance.fix) {
			t.Errorf("refusal class %s guidance contains internal diagnostics: %+v", class, guidance)
		}
	}
	if len(installRefusalCatalogue) != len(upgrade.RefusalClasses()) {
		t.Errorf("catalogue has %d entries for %d classes", len(installRefusalCatalogue), len(upgrade.RefusalClasses()))
	}
}

// installShellERE extracts the grep ERE on the line after marker.
func installShellERE(t *testing.T, lines []string, marker, prefix string) string {
	t.Helper()
	for i, line := range lines {
		if !strings.Contains(line, marker) {
			continue
		}
		for _, next := range lines[i+1:] {
			if !strings.Contains(next, prefix) {
				continue
			}
			start := strings.Index(next, "grep -E '") + len("grep -E '")
			end := strings.LastIndex(next, "' \"$install_output\"")
			if end <= start {
				t.Fatalf("cannot extract ERE after %s: %q", marker, next)
			}
			return strings.ReplaceAll(next[start:end], `'"'"'`, "'")
		}
	}
	t.Fatalf("missing %s ... %s in install.sh", marker, prefix)
	return ""
}

func TestInstallRefusalGuidanceMatchesShellAllowlist(t *testing.T) {
	script, err := os.ReadFile("../../install.sh")
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(string(script), "\n")
	causeERE := installShellERE(t, lines, "INSTALL_REFUSAL_ALLOWLIST:", "failure_detail=$(grep -E")
	fixERE := installShellERE(t, lines, "INSTALL_REFUSAL_ALLOWLIST:", "failure_fix=$(grep -E")
	match := func(pattern, value string) bool {
		cmd := exec.Command("grep", "-E", "-q", pattern)
		cmd.Stdin = strings.NewReader(value + "\n")
		return cmd.Run() == nil
	}
	for _, class := range upgrade.RefusalClasses() {
		guidance := installRefusalCatalogue[class]
		if !match(causeERE, "INSTALL_CAUSE: "+guidance.cause) {
			t.Errorf("%s cause not permitted by install.sh: %q", class, guidance.cause)
		}
		if !match(fixERE, "INSTALL_FIX: "+guidance.fix) {
			t.Errorf("%s fix not permitted by install.sh: %q", class, guidance.fix)
		}
	}
	for _, hostile := range []string{
		"INSTALL_CAUSE: The images for the scheduled upgrade failed to publish. secret=hunter2",
		"INSTALL_CAUSE: pgx: connection refused",
	} {
		if match(causeERE, hostile) {
			t.Errorf("install.sh allowlist admits arbitrary text: %q", hostile)
		}
	}
	if !strings.Contains(string(script), `| tee -a "$install_output"`) || strings.Contains(string(script), `| tee "$install_output"`) {
		t.Error("install.sh must append to the diagnostics file: a truncating tee overwrites what ./sb install appended")
	}
}

// installShFailureTail is install.sh from its post-run handling to the end,
// run against a recorded ./sb install output. ./sb is replaced by a stub for
// the support commands.
func installShFailureTail(t *testing.T, sbOutput string, rc int) string {
	t.Helper()
	return installShFailureTailIn(t, t.TempDir(), "curl -fsSL https://statbus.org/install.sh | bash", sbOutput, rc)
}

// shellSingleQuote produces a single-quoted shell word for splicing a test
// value into a `bash -c` prelude, escaping any embedded single quote.
func shellSingleQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// installShFailureTailIn is installShFailureTail with an explicit STATBUS_DIR
// and STATBUS_INSTALL_RERUN_COMMAND, for callers that need install.sh's
// support-bundle path validation (case "$STATBUS_DIR"/support-bundle-*.txt)
// to match a bundle they wrote themselves, or an exact rerun command.
func installShFailureTailIn(t *testing.T, dir, rerun, sbOutput string, rc int) string {
	t.Helper()
	script, err := os.ReadFile("../../install.sh")
	if err != nil {
		t.Fatal(err)
	}
	source := string(script)
	start := strings.Index(source, "\n# Exit 78 (sysexits EX_CONFIG)")
	if start < 0 {
		t.Fatal("install.sh post-run handling not found")
	}
	if err := os.MkdirAll(filepath.Join(dir, "tmp"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "sb"), []byte("#!/bin/sh\nexit 0\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	output := filepath.Join(dir, "tmp", "install-last-run-output.txt")
	if err := os.WriteFile(output, []byte(sbOutput), 0o600); err != nil {
		t.Fatal(err)
	}
	prelude := fmt.Sprintf("set -e\nsb_rc=%d\nSTATBUS_DIR=\"$1\"\ninstall_output=\"$2\"\nSTATBUS_INSTALL_RERUN_COMMAND=%s\ncd \"$STATBUS_DIR\"\n", rc, shellSingleQuote(rerun))
	cmd := exec.Command("bash", "-c", prelude+source[start:], "install-tail", dir, output)
	got, _ := cmd.CombinedOutput()
	return string(got)
}

// Through install.sh: the named refusal's fixed cause and fix reach the
// terminal, both for a retry remedy (the severed proxy) and a keep-the-box
// remedy (the corrupt git tree), which must never say "run it again".
func TestInstallShShowsNamedRefusal(t *testing.T) {
	for _, tc := range []struct {
		class   upgrade.RefusalClass
		refusal error
		rerun   bool
	}{
		{upgrade.RefusalProxyRouteMissing, upgrade.NewProxyRouteMissingError("/home/statbus/statbus"), true},
		{upgrade.RefusalRestoreGitCorrupt, upgrade.NewRestoreGitCorruptError(errors.New("unknown revision"), ""), false},
	} {
		t.Run(string(tc.class), func(t *testing.T) {
			var sbOutput bytes.Buffer
			sbOutput.WriteString("StatBus Installation\ncrash recovery: DB not reachable\n")
			printInstallFailure(&sbOutput, tc.refusal)
			got := installShFailureTail(t, sbOutput.String(), 1)
			guidance := installRefusalCatalogue[tc.class]
			for _, want := range []string{"Cause: " + guidance.cause, guidance.fix} {
				if !strings.Contains(got, want) {
					t.Errorf("install.sh output lacks %q:\n%s", want, got)
				}
			}
			if got, want := strings.Contains(got, "Then run the same install command again"), tc.rerun; got != want {
				t.Errorf("rerun instruction shown=%v, want %v", got, want)
			}
			if strings.Contains(got, "the installer could not finish") || strings.Contains(got, "unknown revision") {
				t.Errorf("install.sh shows the generic cause or a raw error:\n%s", got)
			}
		})
	}
}
