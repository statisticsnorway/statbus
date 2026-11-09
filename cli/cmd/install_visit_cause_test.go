package cmd

import (
	"bytes"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"
)

// Manual box, November 9 at 10:32 UTC: every install step was DONE, then the
// advertised-site check refused the supplied certificate. The terminal showed
// only "Cause: the installer could not finish"; the reason ("its certificate
// is not trusted") stayed in the log. This follows a real site-check failure
// from the check itself, through ./sb install's failure report, to the text
// install.sh shows the operator.
func TestInstallShShowsWhyTheAdvertisedSiteIsNotServing(t *testing.T) {
	ca, caKey, _ := visitTestCA(t)
	now := time.Now()
	leaf := visitTestLeaf(t, ca, caKey, []string{"statbus.example.org"}, now.Add(-time.Hour), now.Add(time.Hour))
	port, _ := startVisitTestServer(t, &leaf, http.StatusOK)
	_, _, otherPool := visitTestCA(t)
	withVisitRoots(t, otherPool) // the site's CA is not in this trust store
	withVisitChecksSeam(t, []visitCheck{{origin: "https://statbus.example.org:" + port, verifyTLS: true, fatal: true}})

	var siteErr error
	captureStdout(t, func() { _, siteErr = verifyAdvertisedSite(t.TempDir(), 0, time.Millisecond) })
	if siteErr == nil {
		t.Fatal("the fixture did not reproduce an untrusted supplied certificate")
	}
	var sbOutput bytes.Buffer
	sbOutput.WriteString("[19/19] Upgrader             DONE\n\nAll services are running and the API is ready.\n")
	printInstallFailure(&sbOutput, siteErr)

	got := installShFailureTail(t, sbOutput.String(), 1)
	for _, want := range []string{
		"Cause: The site does not answer with a trusted certificate: the certificate's issuer is not in this server's trusted authorities.",
		"Outside fix: Install the full certificate chain with cd ~/statbus && ./sb cert install <file>, or add the issuing authority to this server's trusted authorities, then retry.",
		"Then run the same install command again:",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("install.sh output lacks %q:\n%s", want, got)
		}
	}
	if strings.Contains(got, "the installer could not finish") {
		t.Errorf("install.sh shows the generic cause:\n%s", got)
	}
}

// Every reason the site check can give has one fixed cause and fix that
// install.sh's allowlist admits; nothing from the probe is interpolated.
func TestAdvertisedSiteGuidanceMatchesShellAllowlist(t *testing.T) {
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
	for _, reason := range advertisedSiteReasons {
		guidance := advertisedSiteGuidance(reason)
		if !match(causeERE, "INSTALL_CAUSE: "+guidance.cause) {
			t.Errorf("%q cause not permitted by install.sh: %q", reason, guidance.cause)
		}
		if !match(fixERE, "INSTALL_FIX: "+guidance.fix) {
			t.Errorf("%q fix not permitted by install.sh: %q", reason, guidance.fix)
		}
	}
}
