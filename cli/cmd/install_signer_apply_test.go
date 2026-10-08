package cmd

import (
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// STATBUS-468: the install accepted the recommended signer, printed "Added
// UPGRADE_TRUSTED_SIGNER_jhf to .env.config", and its upgrade daemon then
// reported "No trusted signers configured": the signer was written to
// .env.config AFTER the step that generates .env, and the daemon reads .env.

const fixtureSignerKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZpeHR1cmVTaWduaW5nS2V5MDEyMzQ1Njc4OTAxMjM="

func stepTableOrder(t *testing.T) []string {
	t.Helper()
	source, err := os.ReadFile("install.go")
	if err != nil {
		t.Fatal(err)
	}
	table := strings.SplitN(string(source), "steps := []step{", 2)
	if len(table) != 2 {
		t.Fatal("step table not found")
	}
	table = strings.SplitN(table[1], "total := len(steps)", 2)
	var names []string
	for _, m := range regexp.MustCompile(`(?m)^\s*\{"([A-Za-z +]+)",`).FindAllStringSubmatch(table[0], -1) {
		names = append(names, m[1])
	}
	return names
}

// The signer must be written before the one step that generates .env, so the
// generator (not a second mechanism) carries it to the daemon.
func TestTrustedSignersStepRunsBeforeSettingsGeneration(t *testing.T) {
	names := stepTableOrder(t)
	index := func(name string) int {
		for i, n := range names {
			if n == name {
				return i
			}
		}
		t.Fatalf("step %q not in %v", name, names)
		return -1
	}
	if index("Trusted signers") >= index("Settings") {
		t.Fatalf("Trusted signers (position %d) must run before Settings (position %d), which generates the .env the upgrade daemon reads; order: %v",
			index("Trusted signers")+1, index("Settings")+1, names)
	}
	if index("Trusted signers") <= index("Repository") || index("Trusted signers") <= index("Configuration") {
		t.Fatalf("Trusted signers needs the checkout and .env.config before it; order: %v", names)
	}
}

func signerInstallFixture(t *testing.T) string {
	t.Helper()
	dir := credentialInstallFixture(t, false)
	if err := os.WriteFile(filepath.Join(dir, ".env.config"), []byte("CADDY_DEPLOYMENT_MODE=development\nSITE_DOMAIN=local.statbus.org\nDEPLOYMENT_SLOT_NAME=Signer Test\nDEPLOYMENT_SLOT_CODE=local\nDEPLOYMENT_SLOT_PORT_OFFSET=1\n"), 0600); err != nil {
		t.Fatal(err)
	}
	oldClient, oldTrust := http.DefaultClient, trustGitHubUser
	t.Cleanup(func() { http.DefaultClient, trustGitHubUser = oldClient, oldTrust })
	http.DefaultClient = &http.Client{Transport: signerRoundTripper(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(`[{"key":"` + fixtureSignerKey + `"}]`))}, nil
	})}
	trustGitHubUser = "jhf"
	if err := runCreateCreds(dir); err != nil {
		t.Fatal(err)
	}
	return dir
}

// In the step table's order (signers, then Settings), the generated .env
// carries the signer, the daemon's own reader returns it, and the end-state
// check passes.
func TestApprovedSignerReachesTheDaemonsSettings(t *testing.T) {
	dir := signerInstallFixture(t)
	for _, name := range stepTableOrder(t) {
		switch name {
		case "Trusted signers":
			if err := runTrustSigners(dir); err != nil {
				t.Fatal(err)
			}
		case "Settings":
			if err := runGenerateEnv(dir); err != nil {
				t.Fatal(err)
			}
		}
	}
	env, err := os.ReadFile(filepath.Join(dir, ".env"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(env), "\nUPGRADE_TRUSTED_SIGNER_jhf="+fixtureSignerKey+"\n") {
		t.Fatalf("generated .env lacks the approved signer:\n%s", env)
	}
	signers, err := upgrade.TrustedSignersFromEnv(dir)
	if err != nil || len(signers) != 1 || signers[0] != (upgrade.TrustedSigner{Name: "jhf", Key: fixtureSignerKey}) {
		t.Fatalf("daemon's signer reader got %+v %v", signers, err)
	}
	if err := verifyTrustedSignersApplied(dir); err != nil {
		t.Fatalf("end-state check rejected an applied signer: %v", err)
	}
}

// The whole chain the field log broke: run the install's two signer-relevant
// steps in the step table's ACTUAL order, then start the daemon's own trust
// load on the resulting .env and read the allowed-signers file it would verify
// commits against. Before STATBUS-468's reorder (Settings, then Trusted
// signers) the daemon found no signer and wrote no file.
func TestInstallStepOrderGivesTheDaemonTheApprovedSigner(t *testing.T) {
	dir := signerInstallFixture(t)
	for _, name := range stepTableOrder(t) {
		switch name {
		case "Trusted signers":
			if err := runTrustSigners(dir); err != nil {
				t.Fatal(err)
			}
		case "Settings":
			if err := runGenerateEnv(dir); err != nil {
				t.Fatal(err)
			}
		}
	}
	daemon := upgrade.NewService(dir, false, "test", "unknown")
	allowedSigners, err := daemon.LoadTrustedSigners()
	if err != nil {
		t.Fatalf("daemon trust load: %v", err)
	}
	if allowedSigners == "" {
		t.Fatal("daemon loaded no trusted signer from the .env this install generated, so it would refuse every upgrade")
	}
	got, err := os.ReadFile(allowedSigners)
	if err != nil {
		t.Fatal(err)
	}
	if want := "jhf " + fixtureSignerKey + "\n"; string(got) != want {
		t.Fatalf("daemon allowed-signers content:\n got %q\nwant %q", got, want)
	}
}

// The pre-fix order (Settings, then signers) is the field defect. The
// end-state check catches it truthfully instead of the banner contradiction.
func TestSignerWrittenAfterGenerationIsReportedNotHidden(t *testing.T) {
	dir := signerInstallFixture(t)
	if err := runGenerateEnv(dir); err != nil {
		t.Fatal(err)
	}
	if err := runTrustSigners(dir); err != nil {
		t.Fatal(err)
	}
	if signers, _ := upgrade.TrustedSignersFromEnv(dir); len(signers) != 0 {
		t.Fatalf("fixture did not reproduce the stale .env: %+v", signers)
	}
	err := verifyTrustedSignersApplied(dir)
	if err == nil || !strings.HasPrefix(err.Error(), "the trusted signer UPGRADE_TRUSTED_SIGNER_jhf is in .env.config but not in the generated settings the upgrade service reads") {
		t.Fatalf("stale signer not reported: %v", err)
	}
	// The operator sees the classified cause and its remedy (install.sh
	// relays exactly these INSTALL_CAUSE/INSTALL_FIX lines), not the generic
	// "could not finish" line.
	out := captureStdout(t, func() { printInstallStepFailure("Trusted signers", "[7/18] Trusted signers     ", err, true) })
	for _, want := range []string{
		"[7/18] Trusted signers      FAILED: This part of installation could not finish.\n",
		"INSTALL_CAUSE: The approved release signer did not reach the settings the update service reads.\n",
		"INSTALL_FIX: Run cd ~/statbus && ./sb config generate, then retry.\n",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("operator output lacks %q:\n%s", want, out)
		}
	}
}

// An explicit "n" at the signer prompt stops the install at the Trusted
// signers step, as the prompt promises. Before, a fresh-install decline
// returned nil: the step printed DONE and the install finished with no signer
// and a daemon that refuses every upgrade. The step's error is the phrase
// install.sh reports as "release signer approval was declined".
func TestDeclinedSignerFailsTheTrustedSignersStep(t *testing.T) {
	dir := signerInstallFixture(t)
	trustGitHubUser = ""
	stdin, err := os.CreateTemp(t.TempDir(), "stdin")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := stdin.WriteString("n\n"); err != nil {
		t.Fatal(err)
	}
	if _, err := stdin.Seek(0, 0); err != nil {
		t.Fatal(err)
	}
	oldStdin := os.Stdin
	os.Stdin = stdin
	t.Cleanup(func() { os.Stdin = oldStdin })
	signerPromptAnswered, signerPromptAccepted, signerPromptDeclined = false, false, false
	t.Cleanup(func() { signerPromptAnswered, signerPromptAccepted, signerPromptDeclined = false, false, false })

	if !strings.Contains(installStepTableSource(t), `{"Trusted signers", checkSignersDone, runTrustSignersStep},`) {
		t.Fatal("the step table no longer runs runTrustSignersStep for Trusted signers")
	}
	trusted := step{"Trusted signers", checkSignersDone, runTrustSignersStep}
	alreadyDone, err := executeInstallStep(trusted, dir, func() {})
	if alreadyDone || err == nil || !strings.HasPrefix(err.Error(), "release signer approval was declined") {
		t.Fatalf("declined signer: alreadyDone=%v err=%v", alreadyDone, err)
	}
	if cause, _ := classifyInstallFailure("Trusted signers", err); cause != "The release signature could not be verified." {
		t.Fatalf("decline classified as %q", cause)
	}
	cfg, _ := os.ReadFile(filepath.Join(dir, ".env.config"))
	if strings.Contains(string(cfg), "UPGRADE_TRUSTED_SIGNER_") {
		t.Fatalf("declined signer was written:\n%s", cfg)
	}
}

func installStepTableSource(t *testing.T) string {
	t.Helper()
	source, err := os.ReadFile("install.go")
	if err != nil {
		t.Fatal(err)
	}
	return string(source)
}
