package installinput

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

func TestPromptsAndRequiredKeysAreSameSet(t *testing.T) {
	asked := map[string]bool{}
	content := Ask(func(label, fallback string) string {
		for _, f := range fields {
			if strings.HasSuffix(label, f.prompt) {
				asked[f.prompt] = true
			}
		}
		if strings.HasSuffix(label, "Domain name") {
			return "example.org"
		}
		return fallback
	})
	canonical, err := Validate(content)
	if err != nil {
		t.Fatal(err)
	}
	keys := dotenv.FromString(canonical).Keys()
	if len(keys) != len(asked) || len(keys) != len(fields)-1 {
		t.Fatalf("keys=%v prompts=%v", keys, asked)
	}
	for _, f := range fields {
		if f.installationOnly {
			label, fallback := TrustQuestion()
			if label != f.prompt || fallback != f.fallback {
				t.Fatal("trust question drift")
			}
			err := MissingTrustInConfig("/tmp/install-input.env")
			if !strings.Contains(err.Error(), f.key) || !strings.Contains(err.Error(), f.prompt) {
				t.Fatal(err)
			}
			if strings.Contains(err.Error(), "--trust-github-user") || !strings.Contains(err.Error(), TrustExplanation) {
				t.Fatal(err)
			}
			continue
		}
		if !asked[f.prompt] {
			t.Errorf("key %s has no prompt %q", f.key, f.prompt)
		}
		// Use original lines to remove this key, preserving the exact questionnaire output.
		var lines []string
		for _, line := range strings.Split(content, "\n") {
			if !strings.HasPrefix(line, f.key+"=") {
				lines = append(lines, line)
			}
		}
		_, err := Validate(strings.Join(lines, "\n"))
		if err == nil || !strings.Contains(err.Error(), f.key) || !strings.Contains(err.Error(), f.prompt) {
			t.Errorf("missing %s: %v", f.key, err)
		}
	}
}

func TestExplicitInputRefusals(t *testing.T) {
	content := Ask(func(label, fallback string) string {
		if strings.HasSuffix(label, "Domain name") {
			return "example.org"
		}
		return fallback
	})
	tests := []struct{ name, input, want string }{
		{"extra", content + "DEBUG=false\n", "extra key DEBUG"},
		{"fixed output is not input", content + "DEPLOYMENT_SLOT_PORT_OFFSET=1\n", "extra key DEPLOYMENT_SLOT_PORT_OFFSET"},
		{"duplicate", content + "SITE_DOMAIN=other\n", "duplicate key SITE_DOMAIN"},
		{"malformed", content + "unexpected text\n", "expected KEY=VALUE"},
		{"empty", strings.ReplaceAll(content, "SITE_DOMAIN=example.org", "SITE_DOMAIN="), "SITE_DOMAIN (Domain name)"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Validate(tc.input)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("got %v, want %s", err, tc.want)
			}
		})
	}
	_, err := Read("")
	if err == nil || err.Error() != Requirement() {
		t.Fatalf("missing env: %v", err)
	}
	if !strings.Contains(err.Error(), TrustExplanation) {
		t.Errorf("missing signer trust explanation: %v", err)
	}
	for _, f := range fields {
		fallback := f.fallback
		if f.key == "SITE_DOMAIN" {
			fallback = "example.org"
		}
		if !strings.Contains(err.Error(), f.key+"="+fallback+"  # "+f.prompt) {
			t.Errorf("missing help for %s", f.key)
		}
	}
	_, err = Read(filepath.Join(t.TempDir(), "missing"))
	if err == nil || !strings.Contains(err.Error(), "read STATBUS_ENV_CONFIG") {
		t.Fatalf("missing file: %v", err)
	}
	path := filepath.Join(t.TempDir(), "input with spaces")
	if err := os.WriteFile(path, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
	got, err := Read(path)
	if err != nil || got != content {
		t.Fatalf("read got %q err %v", got, err)
	}
}

// The operator example must be accepted by the same schema, not a second
// handwritten promise that starts drifting as soon as a prompt changes.
func TestDeploymentDocumentationUsesExactQuestionnaire(t *testing.T) {
	data, err := os.ReadFile("../../../doc/DEPLOYMENT.md")
	if err != nil {
		t.Fatal(err)
	}
	doc := string(data)
	section := strings.SplitN(doc, "#### Unattended install", 2)
	if len(section) != 2 {
		t.Fatal("missing unattended section")
	}
	block := strings.SplitN(section[1], "```dotenv\n", 2)
	if len(block) != 2 {
		t.Fatal("missing input example")
	}
	input := strings.SplitN(block[1], "```", 2)[0]
	if _, err := Validate(input); err != nil {
		t.Fatalf("documented input: %v", err)
	}
	for _, f := range fields {
		if !strings.Contains(section[1], "| `"+f.key+"` | "+f.prompt+" |") {
			if f.key != TrustKey || !strings.Contains(section[1], "| `"+f.key+"` | "+f.prompt+".") {
				t.Errorf("missing documented prompt for %s", f.key)
			}
		}
	}
	if !strings.Contains(section[1], TrustExplanation) {
		t.Error("deployment documentation is missing the signer trust explanation")
	}
}

func TestTrustAnswersAndConflicts(t *testing.T) {
	for _, tc := range []struct {
		flag, file, want string
		bad              bool
	}{
		{"", "", "", false}, {"jhf", "", "jhf", false}, {"", "jhf", "jhf", false}, {"jhf", "jhf", "jhf", false},
		{"jhf", "other", "", true}, {"", "not a username", "", true}, {"../jhf", "", "", true},
	} {
		got, err := ResolveTrust(tc.flag, tc.file)
		if (err != nil) != tc.bad || got != tc.want {
			t.Fatalf("%+v: %q %v", tc, got, err)
		}
	}
	content := Ask(func(label, defaultValue string) string {
		if strings.HasSuffix(label, "Domain name") {
			return "example.org"
		}
		return defaultValue
	}) + "TRUST_GITHUB_USER=jhf\n"
	a, err := parse(content, "")
	if err != nil || a.Trust != "jhf" || strings.Contains(a.Config, TrustKey) {
		t.Fatalf("trust input not consumed separately: %+v %v", a, err)
	}
	if _, err := parse(content, "other"); err == nil || !strings.Contains(err.Error(), "conflicts") {
		t.Fatalf("conflict: %v", err)
	}
	help := Requirement()
	for _, text := range []string{"TRUST_GITHUB_USER=jhf", "https://github.com/jhf", "STATBUS_INSTALL_VERSION", "STATBUS_USERS_FILE", "--trust-github-user <github-user>", "re-run the same install command", "never approves"} {
		if !strings.Contains(help, text) {
			t.Errorf("help missing %s", text)
		}
	}
}

func TestSetupChoiceExplanationsAndDefaults(t *testing.T) {
	var labels []string
	var domainDefault, modeDefault, codeDefault string
	Ask(func(label, fallback string) string {
		labels = append(labels, label)
		if strings.HasSuffix(label, "Deployment mode (development/standalone/private)") {
			modeDefault = fallback
		}
		if strings.HasSuffix(label, "Domain name") {
			domainDefault = fallback
			return "finland.example.org"
		}
		if strings.HasSuffix(label, "Deployment code (short, lowercase)") {
			codeDefault = fallback
		}
		return fallback
	})
	if modeDefault != "development" || domainDefault != "" || codeDefault != "finland" {
		t.Fatalf("defaults: %q %q %q", modeDefault, domainDefault, codeDefault)
	}
	for _, choice := range []string{"development: testing on this computer only", "standalone: this computer serves the public website", "private: another web server forwards visitors"} {
		if !strings.Contains(strings.Join(labels, "\n"), choice) {
			t.Errorf("missing choice %q", choice)
		}
	}
}
