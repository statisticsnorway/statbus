// install_cert_picker_test.go: the one-pick certificate list that runs after
// "Do you have a certificate to install now? y", plus the typed-path retry.
// The tests keep the search inside a temporary HOME so they describe the
// operator's list, not the machine running them.
package cmd

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// pickerHome creates an empty temporary HOME and restricts the picker search to
// it.
func pickerHome(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	saved := certCandidateRoots
	certCandidateRoots = func(string) []certSearchRoot {
		return []certSearchRoot{{Path: home, MaxDepth: certSearchHomeDepth}}
	}
	t.Cleanup(func() { certCandidateRoots = saved })
	return home
}

// pickerWrite creates a file (and its parent folders) with a fixed mtime.
func pickerWrite(t *testing.T, path string, mod time.Time, data []byte) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(path, mod, mod); err != nil {
		t.Fatal(err)
	}
}

// pickerPrompts answers the installer's questions by label substring and
// records every label asked, so a test can assert the picker did (or did not)
// ask something.
func pickerPrompts(t *testing.T, answers map[string]string) *[]string {
	t.Helper()
	var labels []string
	savedPrompt, savedYesNo, savedChoose := questionnairePrompt, askCertificateYesNo, chooseCertFolder
	questionnairePrompt = func(label, fallback string) string {
		labels = append(labels, label)
		for key, answer := range answers {
			if strings.Contains(label, key) {
				return answer
			}
		}
		return fallback
	}
	askCertificateYesNo = func(string) bool { return true }
	t.Cleanup(func() {
		questionnairePrompt, askCertificateYesNo, chooseCertFolder = savedPrompt, savedYesNo, savedChoose
	})
	return &labels
}

// pickerCapture runs fn and returns what it printed on stdout.
func pickerCapture(t *testing.T, fn func()) string {
	t.Helper()
	read, write, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	saved := os.Stdout
	os.Stdout = write
	done := make(chan string, 1)
	go func() {
		out, _ := io.ReadAll(read)
		done <- string(out)
	}()
	fn()
	os.Stdout = saved
	if err := write.Close(); err != nil {
		t.Fatal(err)
	}
	return <-done
}

func pickerLabelAsked(labels []string, substring string) bool {
	for _, label := range labels {
		if strings.Contains(label, substring) {
			return true
		}
	}
	return false
}

// TestInstallCertPickerOnePickListsCertificates: the picker lists installable
// certificates themselves, not folders. The same certificate as a PEM pair and
// as a (password-free) PFX is one candidate, the PEM pair; a single candidate
// asks the Y/n question with no password and no numbered list.
func TestInstallCertPickerOnePickListsCertificates(t *testing.T) {
	home := pickerHome(t)
	folder := filepath.Join(home, "Downloads")
	cert, key := testCertificate(t, "statbus.example.org", []string{"statbus.example.org"}, time.Now().Add(-time.Hour), time.Now().Add(24*time.Hour))
	bundle := filepath.Join(folder, "fullchain.pem")
	pickerWrite(t, bundle, time.Now(), append(certPEM(t, cert), keyPEM(t, key)...))
	writePFX(t, filepath.Join(folder, "site.pfx"), cert, key, "")
	asked := stubCertificateDefaultYes(t, true)
	labels := pickerAnswerSequence(t)

	var args []string
	out := pickerCapture(t, func() { args, _ = askInstallCert(t.TempDir()) })

	if len(args) != 1 || args[0] != bundle {
		t.Fatalf("one certificate produced %q, want [%q]", args, bundle)
	}
	if *asked != "  Install this certificate?" {
		t.Fatalf("question = %q, want the single-certificate confirmation", *asked)
	}
	for _, unwanted := range []string{"Use which", "Install which certificate number", "PFX password"} {
		if strings.Contains(out, unwanted) {
			t.Fatalf("one pick must not ask %q:\n%s", unwanted, out)
		}
	}
	if !strings.Contains(out, "CN=statbus.example.org") {
		t.Fatalf("the PEM pair is not described by its certificate:\n%s", out)
	}
	if !strings.Contains(out, "also in site.pfx") {
		t.Fatalf("the duplicate PFX is not named on the line:\n%s", out)
	}
	if pickerLabelAsked(*labels, "Certificate file") {
		t.Fatalf("one pick must not ask for a path; labels: %q", *labels)
	}
	for _, unwanted := range []string{"Use which", "Install which certificate number"} {
		if pickerLabelAsked(*labels, unwanted) {
			t.Fatalf("one pick must not ask %q; labels: %q", unwanted, *labels)
		}
	}
}

// TestInstallCertPickerPEMPairPlusDifferentPFX: two different certificates are
// two candidates; choosing the PFX asks its password once, shows the
// certificate it contains, and installs it, with no second numbered question.
func TestInstallCertPickerPEMPairPlusDifferentPFX(t *testing.T) {
	home := pickerHome(t)
	folder := filepath.Join(home, "Downloads")
	pemCert, pemKey := testCertificate(t, "pem.example.org", []string{"pem.example.org"}, time.Now().Add(-time.Hour), time.Now().Add(24*time.Hour))
	bundle := filepath.Join(folder, "fullchain.pem")
	pickerWrite(t, bundle, time.Now(), append(certPEM(t, pemCert), keyPEM(t, pemKey)...))
	pfxCert, pfxKey := testCertificate(t, "pfx.example.org", []string{"pfx.example.org"}, time.Now().Add(-time.Hour), time.Now().Add(24*time.Hour))
	pfx := filepath.Join(folder, "other.pfx")
	writePFX(t, pfx, pfxCert, pfxKey, "RightPass")

	labels := pickerAnswerSequence(t, "2")
	stdinReader, stdinWriter, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	originalStdin := os.Stdin
	os.Stdin = stdinReader
	if _, err := stdinWriter.WriteString("RightPass\n"); err != nil {
		t.Fatal(err)
	}
	_ = stdinWriter.Close()

	var args []string
	var password *string
	out := pickerCapture(t, func() { args, password = askInstallCert(t.TempDir()) })
	os.Stdin = originalStdin

	if len(args) != 1 || args[0] != pfx {
		t.Fatalf("choosing the PFX produced %q, want [%q]", args, pfx)
	}
	if password == nil || *password != "RightPass" {
		t.Fatalf("password = %v, want one read of RightPass", password)
	}
	if !strings.Contains(out, "CN=pfx.example.org") {
		t.Fatalf("the chosen PFX's certificate was not shown:\n%s", out)
	}
	if got := pickerCountLabels(*labels, "Use which"); got != 1 {
		t.Fatalf("Use which asked %d times, want 1:\n%s", got, out)
	}
	for _, unwanted := range []string{"Install which certificate number"} {
		if strings.Contains(out, unwanted) || pickerLabelAsked(*labels, unwanted) {
			t.Fatalf("a second numbered question was asked (%q):\n%s", unwanted, out)
		}
	}
	if !strings.Contains(out, bundle) || !strings.Contains(out, "other.pfx") {
		t.Fatalf("both candidates are not listed:\n%s", out)
	}
}

// pickerTwoPEMPairs writes two different PEM pairs into the home and returns
// their folder.
func pickerTwoPEMPairs(t *testing.T, home string) string {
	t.Helper()
	folder := filepath.Join(home, "Downloads")
	for _, name := range []string{"first.example.org", "second.example.org"} {
		cert, key := testCertificate(t, name, []string{name}, time.Now().Add(-time.Hour), time.Now().Add(24*time.Hour))
		pickerWrite(t, filepath.Join(folder, name+".pem"), time.Now(), append(certPEM(t, cert), keyPEM(t, key)...))
	}
	return folder
}

// TestInstallCertPickerAnotherFileOrFolder: the last option is today's path
// question, unchanged.
func TestInstallCertPickerAnotherFileOrFolder(t *testing.T) {
	home := pickerHome(t)
	pickerTwoPEMPairs(t, home)
	cert, key := testCertificate(t, "typed.example.org", []string{"typed.example.org"}, time.Now().Add(-time.Hour), time.Now().Add(24*time.Hour))
	bundle := filepath.Join(t.TempDir(), "fullchain.pem")
	pickerWrite(t, bundle, time.Now(), append(certPEM(t, cert), keyPEM(t, key)...))

	labels := pickerAnswerSequence(t, "3", bundle)

	var args []string
	pickerCapture(t, func() { args, _ = askInstallCert(t.TempDir()) })

	if len(args) != 1 || args[0] != bundle {
		t.Fatalf("typed path produced %q, want [%q]", args, bundle)
	}
	if !pickerLabelAsked(*labels, "Certificate file") {
		t.Fatalf("path question was not asked; labels: %q", *labels)
	}
}

// TestInstallCertPickerInvalidNumberFallsBackToPath: a number that is not on
// the list says so and still lets the operator type a path.
func TestInstallCertPickerInvalidNumberFallsBackToPath(t *testing.T) {
	home := pickerHome(t)
	pickerTwoPEMPairs(t, home)
	cert, key := testCertificate(t, "typed.example.org", []string{"typed.example.org"}, time.Now().Add(-time.Hour), time.Now().Add(24*time.Hour))
	bundle := filepath.Join(t.TempDir(), "fullchain.pem")
	pickerWrite(t, bundle, time.Now(), append(certPEM(t, cert), keyPEM(t, key)...))

	labels := pickerAnswerSequence(t, "99", bundle)

	var args []string
	out := pickerCapture(t, func() { args, _ = askInstallCert(t.TempDir()) })

	if !strings.Contains(out, "not one of the listed numbers") {
		t.Fatalf("invalid number was not reported:\n%s", out)
	}
	if len(args) != 1 || args[0] != bundle {
		t.Fatalf("typed path produced %q, want [%q]", args, bundle)
	}
	if !pickerLabelAsked(*labels, "Certificate file") {
		t.Fatalf("path question was not asked after an invalid number; labels: %q", *labels)
	}
}

// TestInstallCertPickerEmptyHomeFallsThrough: with nothing found the installer
// says so and goes straight to today's path question.
func TestInstallCertPickerEmptyHomeFallsThrough(t *testing.T) {
	pickerHome(t)
	cert, key := testCertificate(t, "picker.example.org", []string{"picker.example.org"}, time.Now().Add(-time.Hour), time.Now().Add(24*time.Hour))
	bundle := filepath.Join(t.TempDir(), "fullchain.pem")
	pickerWrite(t, bundle, time.Now(), append(certPEM(t, cert), keyPEM(t, key)...))

	labels := pickerPrompts(t, map[string]string{"Certificate file": bundle})

	var args []string
	out := pickerCapture(t, func() { args, _ = askInstallCert(t.TempDir()) })

	if strings.Contains(out, "Certificates found:") {
		t.Fatalf("empty home must not render a picker list:\n%s", out)
	}
	if !strings.Contains(out, "No certificate files found under ~.") {
		t.Fatalf("missing not-found notice:\n%s", out)
	}
	if !pickerLabelAsked(*labels, "Certificate file") {
		t.Fatalf("path question was not asked; labels: %q", *labels)
	}
	if len(args) != 1 || args[0] != bundle {
		t.Fatalf("typed path produced %q, want [%q]", args, bundle)
	}
}

// pickerAnswerSequence answers the questionnaire's questions in order, so a
// flow that asks the path question more than once can be exercised. It also
// accepts the initial certificate offer, which every test here answers yes.
func pickerAnswerSequence(t *testing.T, answers ...string) *[]string {
	t.Helper()
	var labels []string
	savedPrompt, savedYesNo := questionnairePrompt, askCertificateYesNo
	questionnairePrompt = func(label, fallback string) string {
		labels = append(labels, label)
		if len(answers) == 0 {
			return fallback
		}
		answer := answers[0]
		answers = answers[1:]
		return answer
	}
	askCertificateYesNo = func(string) bool { return true }
	t.Cleanup(func() { questionnairePrompt, askCertificateYesNo = savedPrompt, savedYesNo })
	return &labels
}

// pickerCountLabels counts how often a question label was asked.
func pickerCountLabels(labels []string, substring string) int {
	count := 0
	for _, label := range labels {
		if strings.Contains(label, substring) {
			count++
		}
	}
	return count
}

// pickerFullchain writes a PEM file holding a certificate and its key and
// returns its path.
func pickerFullchain(t *testing.T, name string) string {
	t.Helper()
	cert, key := testCertificate(t, name, []string{name}, time.Now().Add(-time.Hour), time.Now().Add(24*time.Hour))
	bundle := filepath.Join(t.TempDir(), "fullchain.pem")
	pickerWrite(t, bundle, time.Now(), append(certPEM(t, cert), keyPEM(t, key)...))
	return bundle
}

const pickerRetryHint = "  Try another file or folder, or press Enter to continue without a certificate."

// TestInstallCertPathEmptyFolderThenEnterContinues: a typed folder that holds
// no usable certificate says so and offers another answer; pressing Enter then
// continues without a certificate and says what happens next.
func TestInstallCertPathEmptyFolderThenEnterContinues(t *testing.T) {
	pickerHome(t)
	empty := t.TempDir()

	labels := pickerAnswerSequence(t, empty, "")
	var args []string
	out := pickerCapture(t, func() { args, _ = askInstallCert(t.TempDir()) })

	if args != nil {
		t.Fatalf("continuing without a certificate produced %q", args)
	}
	for _, want := range []string{
		"No usable certificate with a matching private key was found in " + empty + ".",
		pickerRetryHint,
		"Continuing with automatic certificates. Install your own later with: ./sb cert install",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("output is missing %q:\n%s", want, out)
		}
	}
	if got := pickerCountLabels(*labels, "Certificate file or folder"); got != 2 {
		t.Fatalf("path question asked %d times, want 2:\n%s", got, out)
	}
}

// TestInstallCertPathWrongPathThenValidFolder: a wrong path does not end the
// choice; the next answer, a folder holding one usable certificate, installs
// that certificate.
func TestInstallCertPathWrongPathThenValidFolder(t *testing.T) {
	pickerHome(t)
	folder := t.TempDir()
	bundle := pickerFullchain(t, "retry.example.org")
	if err := os.Rename(bundle, filepath.Join(folder, "fullchain.pem")); err != nil {
		t.Fatal(err)
	}
	bundle = filepath.Join(folder, "fullchain.pem")
	stubCertificateDefaultYes(t, true)
	missing := filepath.Join(t.TempDir(), "not-there.pem")

	labels := pickerAnswerSequence(t, missing, folder)
	var args []string
	out := pickerCapture(t, func() { args, _ = askInstallCert(t.TempDir()) })

	if len(args) != 1 || args[0] != bundle {
		t.Fatalf("typed answers produced %q, want [%q]", args, bundle)
	}
	for _, want := range []string{"file not found: " + missing, pickerRetryHint} {
		if !strings.Contains(out, want) {
			t.Fatalf("output is missing %q:\n%s", want, out)
		}
	}
	if got := pickerCountLabels(*labels, "Certificate file or folder"); got != 2 {
		t.Fatalf("path question asked %d times, want 2:\n%s", got, out)
	}
}

// TestInstallCertPathThreeWrongAnswersAsksAgain: the retry is bounded. After
// three unusable answers the installer asks again whether there is a
// certificate (owner, rc.18 manual box: a failed search is not a no); no then
// continues without a certificate and says so.
func TestInstallCertPathThreeWrongAnswersAsksAgain(t *testing.T) {
	pickerHome(t)
	missing := func(name string) string { return filepath.Join(t.TempDir(), name) }
	labels := pickerAnswerSequence(t, missing("one.pem"), missing("two.pem"), missing("three.pem"))
	var asked []string
	askCertificateYesNo = func(label string) bool {
		asked = append(asked, label)
		return len(asked) == 1
	}

	var args []string
	out := pickerCapture(t, func() { args, _ = askInstallCert(t.TempDir()) })

	if args != nil {
		t.Fatalf("three wrong answers and then no produced %q, want no certificate", args)
	}
	want := []string{"  Do you have a certificate to install now?", "  Do you have a certificate to install now?"}
	if strings.Join(asked, "|") != strings.Join(want, "|") {
		t.Fatalf("yes/no questions = %q, want %q:\n%s", asked, want, out)
	}
	if got := strings.Count(out, "Continuing with automatic certificates. Install your own later with: ./sb cert install"); got != 1 {
		t.Fatalf("'Continuing with automatic certificates' printed %d times, want once, after the second no:\n%s", got, out)
	}
	if got := strings.Count(out, pickerRetryHint); got != 2 {
		t.Fatalf("retry hint printed %d times, want 2 (before attempts two and three):\n%s", got, out)
	}
	if got := pickerCountLabels(*labels, "Certificate file or folder"); got != 3 {
		t.Fatalf("path question asked %d times, want 3:\n%s", got, out)
	}
}

// TestInstallCertPathTypedFolderSearchesBelow: the manual-box run on rc.07.
// The home search found nothing, the operator then copied a certificate into
// ~/Documents/certificate-from-it and answered "." (the home). A typed folder
// is searched the way the home is, subfolders included, so the certificate
// copied in the meantime is found and offered.
func TestInstallCertPathTypedFolderSearchesBelow(t *testing.T) {
	home := pickerHome(t)
	stubCertificateDefaultYes(t, true)
	pickerWrite(t, filepath.Join(home, ".bashrc"), time.Now(), []byte("alias ll='ls -l'\n"))

	// The first search (home) runs before the certificate arrives.
	var copied string
	answers := []string{home}
	labels := pickerAnswerSequence(t, answers...)
	savedFind := findCertificateCandidates
	findCertificateCandidates = func(root string) []certCandidateFolder {
		if copied == "" {
			bundle := pickerFullchain(t, "statbus-manual.statbus-test.local")
			copied = filepath.Join(home, "Documents", "certificate-from-it", "fullchain.pem")
			if err := os.MkdirAll(filepath.Dir(copied), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.Rename(bundle, copied); err != nil {
				t.Fatal(err)
			}
			return nil
		}
		return savedFind(root)
	}
	t.Cleanup(func() { findCertificateCandidates = savedFind })

	var args []string
	out := pickerCapture(t, func() { args, _ = askInstallCert(t.TempDir()) })

	if len(args) != 1 || args[0] != copied {
		t.Fatalf("typed home folder produced %q, want [%q]:\n%s", args, copied, out)
	}
	if strings.Contains(out, "No usable certificate") || strings.Contains(out, ".bashrc") {
		t.Fatalf("the found certificate was preceded by a not-found report:\n%s", out)
	}
	if got := pickerCountLabels(*labels, "Certificate file or folder"); got != 1 {
		t.Fatalf("path question asked %d times, want 1:\n%s", got, out)
	}
}

// A single certificate is shown as "  Found: <certificate>" before "Install
// this certificate?", in the indented column of the other certificate lines,
// whether the home search or a typed folder found it, and before as well as
// after the PFX password opened it (the rc.10 box showed both lines flush
// left with no label).
func TestInstallCertSingleFindIsLabelledAndIndented(t *testing.T) {
	home := pickerHome(t)
	stubCertificateDefaultYes(t, true)
	folder := filepath.Join(home, "Documents", "certificate-from-it")
	cert, key := testCertificate(t, "statbus.example.org", []string{"statbus.example.org"}, time.Now().Add(-time.Hour), time.Now().Add(24*time.Hour))
	pfx := filepath.Join(folder, "site.pfx")
	if err := os.MkdirAll(folder, 0o755); err != nil {
		t.Fatal(err)
	}
	writePFX(t, pfx, cert, key, "RightPass")
	pickerAnswerSequence(t)
	stdinReader, stdinWriter, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	originalStdin := os.Stdin
	os.Stdin = stdinReader
	t.Cleanup(func() { os.Stdin = originalStdin })
	if _, err := stdinWriter.WriteString("RightPass\n"); err != nil {
		t.Fatal(err)
	}
	_ = stdinWriter.Close()

	out := pickerCapture(t, func() { _, _ = askInstallCert(t.TempDir()) })
	var found []string
	for _, line := range strings.Split(out, "\n") {
		if strings.Contains(line, pfx) {
			found = append(found, line)
		}
	}
	if len(found) != 2 {
		t.Fatalf("want the certificate shown before and after its password, got:\n%s", out)
	}
	for _, line := range found {
		if !strings.HasPrefix(line, "  Found: "+pfx) {
			t.Fatalf("certificate line %q does not start with \"  Found: \" and the file", line)
		}
	}
}
