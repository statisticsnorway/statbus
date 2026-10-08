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

// STATBUS-465: the installer ALWAYS suggests standalone. The removed battery
// heuristic made a Linux laptop host (the Finland box) suggest development,
// which the operator accepted. No host input is consulted any more, so these
// tests drive the real interactive Configuration step and record what each
// question suggested.

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

// A battery-shaped tree present or absent on disk changes nothing: there is
// no hardware input left for it to influence. The fixture is a temp tree, so
// the suite host's own hardware never matters either.
func TestSuggestedModeIsStandaloneWithOrWithoutBattery(t *testing.T) {
	for _, battery := range []bool{false, true} {
		name := "no battery"
		if battery {
			name = "battery present"
		}
		t.Run(name, func(t *testing.T) {
			powerSupply := filepath.Join(t.TempDir(), "sys", "class", "power_supply")
			if battery {
				if err := os.MkdirAll(filepath.Join(powerSupply, "BAT0"), 0o755); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(filepath.Join(powerSupply, "BAT0", "type"), []byte("Battery\n"), 0o644); err != nil {
					t.Fatal(err)
				}
			}
			run := runInteractiveConfiguration(t, pressEnterOnMode())
			if got := run.fallbacks[modeQuestion]; got != "standalone" {
				t.Fatalf("suggested mode %q, want standalone", got)
			}
			mode, _ := dotenv.FromString(run.config).Get("CADDY_DEPLOYMENT_MODE")
			if mode != "standalone" {
				t.Fatalf("pressing Enter configured %q, want standalone:\n%s", mode, run.config)
			}
		})
	}
}

// development and private stay selectable and explained; private is never the
// suggestion; the field table's own fallback is standalone too.
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
	var tableFallback string
	installinput.Ask(func(label, fallback string) string {
		if strings.HasSuffix(label, modeQuestion) {
			tableFallback = fallback
		}
		if strings.HasSuffix(label, "Domain name") {
			return "example.org"
		}
		if answer, ok := countryAnswer(label); ok {
			return answer
		}
		return fallback
	})
	if tableFallback != "standalone" || installinput.SuggestedMode != "standalone" {
		t.Fatalf("field-table fallback %q / SuggestedMode %q, want standalone", tableFallback, installinput.SuggestedMode)
	}
}
