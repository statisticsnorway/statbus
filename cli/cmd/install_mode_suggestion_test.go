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

// STATBUS-465: the installer ALWAYS suggests standalone, the constant
// installinput.SuggestedMode, on every host. These tests drive the real
// interactive Configuration step and record what each question suggested;
// nothing about the machine running them is read or faked.

type questionnaireRun struct {
	labels    []string
	fallbacks map[string]string
	config    string
}

// runInteractiveConfiguration drives runCreateConfig's interactive branch.
// answers maps a question suffix to the operator's answer; "" means Enter.
func runInteractiveConfiguration(t *testing.T, answers map[string]string) questionnaireRun {
	t.Helper()
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
	run := questionnaireRun{fallbacks: map[string]string{}}
	questionnairePrompt = func(label, fallback string) string {
		run.labels = append(run.labels, label)
		for suffix, answer := range answers {
			if strings.HasSuffix(label, suffix) {
				run.fallbacks[suffix] = fallback
				if answer == "" {
					return fallback
				}
				return answer
			}
		}
		t.Fatalf("unexpected question %q", label)
		return ""
	}
	captureStdout(t, func() {
		if err := runCreateConfig(dir); err != nil {
			t.Fatalf("interactive configuration: %v", err)
		}
	})
	data, err := os.ReadFile(filepath.Join(dir, ".env.config"))
	if err != nil {
		t.Fatal(err)
	}
	run.config = string(data)
	return run
}

const modeQuestion = "Deployment mode (development/standalone/private)"

func pressEnterOnMode() map[string]string {
	return map[string]string{
		modeQuestion:                       "",
		"Domain name":                      "statbus.example.org",
		installinput.DevelopmentNamePrompt: "Example",
		installinput.DevelopmentCodePrompt: "ex",
		installinput.CountryNamePrompt:     "Norway",
		installinput.CountryCodePrompt:     "no",
	}
}

// The mode suggestion IS the constant SuggestedMode, which is standalone:
// both where the questions are defined (installinput.Ask) and where the
// installer asks them (runCreateConfig), and pressing Enter configures it.
func TestModeSuggestionIsTheSuggestedModeConstant(t *testing.T) {
	if installinput.SuggestedMode != "standalone" {
		t.Fatalf("SuggestedMode = %q, want standalone", installinput.SuggestedMode)
	}
	var askFallback string
	installinput.Ask(func(label, fallback string) string {
		if strings.HasSuffix(label, modeQuestion) {
			askFallback = fallback
		}
		if strings.HasSuffix(label, "Domain name") {
			return "example.org"
		}
		if answer, ok := countryAnswer(label); ok {
			return answer
		}
		return fallback
	})
	if askFallback != installinput.SuggestedMode {
		t.Fatalf("installinput.Ask suggests %q, want SuggestedMode %q", askFallback, installinput.SuggestedMode)
	}
	run := runInteractiveConfiguration(t, pressEnterOnMode())
	if got := run.fallbacks[modeQuestion]; got != installinput.SuggestedMode {
		t.Fatalf("installer suggests %q, want SuggestedMode %q", got, installinput.SuggestedMode)
	}
	mode, _ := dotenv.FromString(run.config).Get("CADDY_DEPLOYMENT_MODE")
	if mode != installinput.SuggestedMode {
		t.Fatalf("pressing Enter configured %q, want %q:\n%s", mode, installinput.SuggestedMode, run.config)
	}
}

// development and private stay selectable and explained, and choosing one
// never changes what is suggested.
func TestOtherModesStaySelectableAndExplained(t *testing.T) {
	for _, mode := range []string{"development", "private", "standalone"} {
		t.Run(mode, func(t *testing.T) {
			answers := pressEnterOnMode()
			answers[modeQuestion] = mode
			run := runInteractiveConfiguration(t, answers)
			got, _ := dotenv.FromString(run.config).Get("CADDY_DEPLOYMENT_MODE")
			if got != mode {
				t.Fatalf("chose %s, configured %q", mode, got)
			}
			if run.fallbacks[modeQuestion] != "standalone" {
				t.Fatalf("suggestion %q", run.fallbacks[modeQuestion])
			}
			question := strings.Join(run.labels, "\n")
			for _, explained := range []string{"development: testing on this computer only", "standalone: this computer serves the public website on ports 80 and 443", "private: another web server forwards visitors to StatBus"} {
				if !strings.Contains(question, explained) {
					t.Errorf("mode question lost explanation %q:\n%s", explained, question)
				}
			}
		})
	}
}
