package cmd

import (
	"context"
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/installinput"
)

// The owner mistyped an answer and had no way to correct it. After the last
// question the installer now shows the answers and asks "Use these answers?
// [Y/n]"; n runs the questions again with the previous answers as the
// defaults, and nothing is written before acceptance.
func TestInteractiveReviewCorrectsATypoBeforeWriting(t *testing.T) {
	oldHostTimeZone := installinput.HostTimeZone
	installinput.HostTimeZone = func() (string, string) { return "", "" }
	t.Cleanup(func() { installinput.HostTimeZone = oldHostTimeZone })

	dir := t.TempDir()
	t.Setenv("HOME", t.TempDir())
	t.Setenv(installinput.EnvConfig, "")
	t.Setenv(installinput.UsersFile, "")
	oldNonInteractive, oldPrompt, oldLookup := nonInteractive, questionnairePrompt, installDomainLookup
	t.Cleanup(func() {
		nonInteractive, questionnairePrompt, installDomainLookup = oldNonInteractive, oldPrompt, oldLookup
	})
	nonInteractive = false
	installDomainLookup = func(context.Context, string) ([]net.IP, error) { return nil, errors.New("offline test") }

	// Pass one has the typo ("exmaple"); pass two presses Enter everywhere
	// except the one answer being corrected.
	steps := []struct{ suffix, answer string }{
		{modeQuestion, ""},
		{"Domain name", "statbus.exmaple.org"},
		{installinput.CountryNamePrompt, "Norway"},
		{installinput.CountryCodePrompt, "no"},
		{modeQuestion, ""},
		{"Domain name", "statbus.example.org"},
		{installinput.CountryNamePrompt, ""},
		{installinput.CountryCodePrompt, ""},
	}
	secondPass := map[string]string{}
	index := 0
	questionnairePrompt = func(label, fallback string) string {
		if index >= len(steps) {
			t.Fatalf("question %d (%q): the review asked more than two passes of questions", index+1, label)
			return ""
		}
		step := steps[index]
		if !strings.HasSuffix(label, step.suffix) {
			t.Fatalf("question %d is %q, want one ending in %q", index+1, label, step.suffix)
		}
		if index == len(steps)/2 {
			// The review was rejected: answering again must not have written
			// anything yet.
			if _, err := os.Stat(filepath.Join(dir, ".env.config")); !os.IsNotExist(err) {
				t.Fatalf(".env.config exists before the answers were accepted: %v", err)
			}
		}
		if index >= len(steps)/2 {
			secondPass[step.suffix] = fallback
		}
		index++
		if step.answer == "" {
			return fallback
		}
		return step.answer
	}

	// The review prompt itself reads stdin: reject the first summary, accept
	// the second with Enter.
	answers, answersW, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	oldStdin := os.Stdin
	os.Stdin = answers
	t.Cleanup(func() {
		os.Stdin = oldStdin
		answers.Close()
	})
	if _, err := answersW.WriteString("n\n\n"); err != nil {
		t.Fatal(err)
	}
	if err := answersW.Close(); err != nil {
		t.Fatal(err)
	}

	output := captureStdout(t, func() {
		if err := runCreateConfig(dir); err != nil {
			t.Fatalf("interactive configuration: %v", err)
		}
	})

	if index != len(steps) {
		t.Fatalf("asked %d questions, want %d (the review must ask them all again)", index, len(steps))
	}
	for suffix, want := range map[string]string{
		modeQuestion:                   "standalone",
		"Domain name":                  "statbus.exmaple.org",
		installinput.CountryNamePrompt: "Norway",
		installinput.CountryCodePrompt: "no",
	} {
		if got := secondPass[suffix]; got != want {
			t.Errorf("second pass offered %q as the default for %q, want %q", got, suffix, want)
		}
	}

	data, err := os.ReadFile(filepath.Join(dir, ".env.config"))
	if err != nil {
		t.Fatal(err)
	}
	values := dotenv.FromString(string(data))
	for key, want := range map[string]string{
		"CADDY_DEPLOYMENT_MODE": "standalone",
		"SITE_DOMAIN":           "statbus.example.org",
		"DEPLOYMENT_SLOT_NAME":  "Norway",
		"DEPLOYMENT_SLOT_CODE":  "no",
	} {
		if got, _ := values.Get(key); got != want {
			t.Errorf("%s=%q, want %q (only the typo may change):\n%s", key, got, want, data)
		}
	}

	if got := strings.Count(output, "Use these answers? [Y/n]"); got != 2 {
		t.Fatalf("the review prompt was shown %d times, want 2 (once per pass):\n%s", got, output)
	}
	for _, line := range []string{
		"Deployment mode: standalone",
		"Domain name: statbus.exmaple.org",
		"Country name: Norway",
		"Country code: no",
		"Domain name: statbus.example.org",
	} {
		if !strings.Contains(output, line) {
			t.Errorf("the review summary does not show %q:\n%s", line, output)
		}
	}
}
