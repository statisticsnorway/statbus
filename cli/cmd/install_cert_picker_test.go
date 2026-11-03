// install_cert_picker_test.go: the name-only certificate picker that runs
// after "Do you have a certificate to install now? y" (tmp/picker-proto/
// PROPOSAL.md). The tests keep the search inside a temporary HOME so they
// describe the operator's list, not the machine running them.
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

// TestInstallCertPickerListsFoldersNewestFirst: the rendered list names the
// folders that hold candidates, newest first, and leaves out the install
// directory, the noise folders, oversized files and non-certificate names.
func TestInstallCertPickerListsFoldersNewestFirst(t *testing.T) {
	home := pickerHome(t)
	now := time.Now()
	pickerWrite(t, filepath.Join(home, "Downloads", "old.crt"), now.Add(-48*time.Hour), []byte("old"))
	pickerWrite(t, filepath.Join(home, "Documents", "x", "cert.pfx"), now, []byte("new"))
	pickerWrite(t, filepath.Join(home, "statbus", "certs", "skip.pem"), now, []byte("skip"))
	pickerWrite(t, filepath.Join(home, ".git", "objects", "hidden.pem"), now, []byte("skip"))
	pickerWrite(t, filepath.Join(home, ".cache", "cached.pem"), now, []byte("skip"))
	pickerWrite(t, filepath.Join(home, "node_modules", "pkg", "cert.p12"), now, []byte("skip"))
	pickerWrite(t, filepath.Join(home, "Documents", "big.pfx"), now, make([]byte, certCandidateMaxSize))
	pickerWrite(t, filepath.Join(home, "Documents", "notes.txt"), now, []byte("notes"))

	labels := pickerPrompts(t, map[string]string{"Use which": "1"})
	var chosen string
	chooseCertFolder = func(folder, dir string) ([]string, *string) {
		chosen = folder
		return nil, nil
	}

	out := pickerCapture(t, func() { askInstallCert(t.TempDir()) })

	documents := "~/Documents/x"
	downloads := "~/Downloads"
	if !strings.Contains(out, "Certificates found:") {
		t.Fatalf("no picker list in output:\n%s", out)
	}
	for _, want := range []string{documents, "cert.pfx", downloads, "old.crt", "Another file or folder (type a path)"} {
		if !strings.Contains(out, want) {
			t.Fatalf("list is missing %q:\n%s", want, out)
		}
	}
	for _, unwanted := range []string{"statbus", "skip.pem", "big.pfx", "notes.txt", ".git", ".cache", "node_modules"} {
		if strings.Contains(out, unwanted) {
			t.Fatalf("list must not mention %q:\n%s", unwanted, out)
		}
	}
	if strings.Index(out, documents) > strings.Index(out, downloads) {
		t.Fatalf("newest folder must come first:\n%s", out)
	}
	if !pickerLabelAsked(*labels, "Use which") {
		t.Fatalf("picker did not ask 'Use which'; labels: %q", *labels)
	}
	if chosen != filepath.Join(home, "Documents", "x") {
		t.Fatalf("choosing 1 handed %q to the folder chooser, want %q", chosen, filepath.Join(home, "Documents", "x"))
	}
	if pickerLabelAsked(*labels, "Certificate file") {
		t.Fatalf("choosing a listed folder must not ask for a path again; labels: %q", *labels)
	}
}

// TestInstallCertPickerAnotherFileOrFolder: the last option is today's path
// question, unchanged.
func TestInstallCertPickerAnotherFileOrFolder(t *testing.T) {
	home := pickerHome(t)
	cert, key := testCertificate(t, "picker.example.org", []string{"picker.example.org"}, time.Now().Add(-time.Hour), time.Now().Add(24*time.Hour))
	bundle := filepath.Join(t.TempDir(), "fullchain.pem")
	pickerWrite(t, bundle, time.Now(), append(certPEM(t, cert), keyPEM(t, key)...))
	pickerWrite(t, filepath.Join(home, "Downloads", "old.crt"), time.Now(), []byte("old"))

	labels := pickerPrompts(t, map[string]string{"Use which": "2", "Certificate file": bundle})
	chooseCertFolder = func(folder, dir string) ([]string, *string) {
		t.Fatalf("typing a path must not call the folder chooser with %q", folder)
		return nil, nil
	}

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
	cert, key := testCertificate(t, "picker.example.org", []string{"picker.example.org"}, time.Now().Add(-time.Hour), time.Now().Add(24*time.Hour))
	bundle := filepath.Join(t.TempDir(), "fullchain.pem")
	pickerWrite(t, bundle, time.Now(), append(certPEM(t, cert), keyPEM(t, key)...))
	pickerWrite(t, filepath.Join(home, "Downloads", "old.crt"), time.Now(), []byte("old"))

	labels := pickerPrompts(t, map[string]string{"Use which": "99", "Certificate file": bundle})

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

// TestInstallCertPathThreeWrongAnswersContinues: the retry is bounded. After
// three unusable answers the install continues without a certificate and says
// so.
func TestInstallCertPathThreeWrongAnswersContinues(t *testing.T) {
	pickerHome(t)
	missing := func(name string) string { return filepath.Join(t.TempDir(), name) }
	labels := pickerAnswerSequence(t, missing("one.pem"), missing("two.pem"), missing("three.pem"))

	var args []string
	out := pickerCapture(t, func() { args, _ = askInstallCert(t.TempDir()) })

	if args != nil {
		t.Fatalf("three wrong answers produced %q, want no certificate", args)
	}
	if !strings.Contains(out, "Continuing with automatic certificates. Install your own later with: ./sb cert install") {
		t.Fatalf("output does not say what happens next:\n%s", out)
	}
	if got := strings.Count(out, pickerRetryHint); got != 2 {
		t.Fatalf("retry hint printed %d times, want 2 (before attempts two and three):\n%s", got, out)
	}
	if got := pickerCountLabels(*labels, "Certificate file or folder"); got != 3 {
		t.Fatalf("path question asked %d times, want 3:\n%s", got, out)
	}
}
