// Package installinput owns the installation questions and their unattended
// answers. Installation-only answers are consumed, not copied into .env.config.
package installinput

import (
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

const EnvConfig = "STATBUS_ENV_CONFIG"
const UsersFile = "STATBUS_USERS_FILE"
const TrustKey = "TRUST_GITHUB_USER"
const RecommendedSigner = "jhf"
const TrustExplanation = "Releases are signed; this names the GitHub user whose published signing key the installer verifies release tags against; jhf is the SSB release signer."

const StdinNotTerminalMessage = "stdin is not a terminal (running under a pipe?). Run interactively with a terminal on stdin, or provide STATBUS_ENV_CONFIG for unattended install."

type field struct {
	key, prompt, fallback string
	installationOnly      bool
	// optional keys are accepted in the answer file and emitted when present,
	// but never required and never prompted for interactively.
	optional bool
}

// One definition drives deployment prompts, input keys and the setup recipe.
// Trust is asked at the signers step, where fingerprints can be displayed.
var fields = []field{
	// SuggestedMode, never a machine-derived value (STATBUS-465).
	{"CADDY_DEPLOYMENT_MODE", "Deployment mode (development/standalone/private)", SuggestedMode, false, false},
	{"SITE_DOMAIN", "Domain name", "", false, false},
	// A country installation's name and code (STATBUS-466). No fallback: the
	// interactive default comes from a real signal (SuggestCountry), and the
	// recipe example from RecipeExample, never the development StatBus/local.
	{"DEPLOYMENT_SLOT_NAME", CountryNamePrompt, "", false, false},
	{"DEPLOYMENT_SLOT_CODE", CountryCodePrompt, "", false, false},
	{TrustKey, "Release signer to trust (GitHub username)", RecommendedSigner, true, false},
	// Custom-certificate answers (doc/DEPLOYMENT.md): an NSO on a private
	// network installs standalone with its own certificate; the unattended
	// answer file is how those keys reach .env.config. Not prompted — the
	// interactive certificate choice is STATBUS-399's design.
	{"TLS_CERT_FILE", "TLS certificate fullchain file (custom certificate)", "", false, true},
	{"TLS_KEY_FILE", "TLS certificate private key file (custom certificate)", "", false, true},
}

var githubUsername = regexp.MustCompile(`^[a-zA-Z0-9]([a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?$`)

// ResolveTrust reconciles explicit answers. Neither a default nor unattended
// mode grants trust. The legacy flag and answer file must agree if both are set.
func ResolveTrust(flag, fileAnswer string) (string, error) {
	if flag != "" && fileAnswer != "" && flag != fileAnswer {
		return "", fmt.Errorf("--trust-github-user %q conflicts with TRUST_GITHUB_USER=%q in STATBUS_ENV_CONFIG; supply one answer or matching values", flag, fileAnswer)
	}
	answer := flag
	if answer == "" {
		answer = fileAnswer
	}
	if answer != "" && !githubUsername.MatchString(answer) {
		return "", fmt.Errorf("invalid GitHub username %q for release-signer trust", answer)
	}
	return answer, nil
}

// RecipeExample is the value shown for a key in the unattended recipe. The
// recipe describes a standalone (country) installation, so its domain, name
// and code are a country's, never the development values StatBus and local.
func RecipeExample(key string) string {
	switch key {
	case "SITE_DOMAIN":
		return "example.org"
	case "DEPLOYMENT_SLOT_NAME":
		return "Norway"
	case "DEPLOYMENT_SLOT_CODE":
		return "no"
	}
	for _, f := range fields {
		if f.key == key {
			return f.fallback
		}
	}
	return ""
}

func Requirement() string {
	var b strings.Builder
	b.WriteString("set STATBUS_ENV_CONFIG to a file containing:")
	for _, f := range fields {
		fmt.Fprintf(&b, "\n  %s=%s  # %s", f.key, RecipeExample(f.key), f.prompt)
	}
	fmt.Fprintf(&b, "\n\n%s\nTRUST_GITHUB_USER=%s explicitly approves the recommended release signer\n%s (Jorgen H. Fjeld), https://github.com/%s. Review that trust decision.\n", TrustExplanation, RecommendedSigner, RecommendedSigner, RecommendedSigner)
	b.WriteString("\nKeep the file outside ~/statbus, protect it with chmod 0600, then set:\n  export STATBUS_ENV_CONFIG=/path/to/install-input.env\n\nOptional:\n  export STATBUS_INSTALL_VERSION='<release-tag>'  # omit for latest stable\n  export STATBUS_USERS_FILE=/path/to/initial-users.yml\n\nBecause this run used --non-interactive, signer trust may instead be supplied with:\n  --trust-github-user <github-user>\n\nAfter exporting STATBUS_ENV_CONFIG, re-run the same install command.\nNon-interactive mode never approves a signer implicitly.")
	return b.String()
}

// SuggestedMode is the ONE deployment-mode suggestion, for every run and every
// machine (owner decision, STATBUS-465): running the installer IS a
// standalone installation. development and private remain selectable and are
// explained in the question, but are chosen on purpose, never suggested.
// Nothing about the host (battery, hostname, checkout) changes this. Checkout
// detection cannot work anyway: install.sh always creates ~/statbus by git
// clone, so every real install already runs inside a checkout.
const SuggestedMode = "standalone"

// The questions' own words. The field table carries the country questions
// because a country installation is what the recipe and the documentation
// describe; development asks the same keys with permissive wording.
const (
	CountryNamePrompt     = "Country name"
	CountryCodePrompt     = "Country code"
	DevelopmentNamePrompt = "Display name"
	DevelopmentCodePrompt = "Deployment code (short, lowercase)"
	// askAttempts bounds re-asking so a closed stdin cannot loop forever; an
	// answer still empty or malformed then fails validation, naming the key.
	askAttempts = 3
)

var deploymentModes = map[string]bool{"development": true, "standalone": true, "private": true}

// Ask runs the deployment questions. Every question explains itself and
// offers a default where a useful one exists (STATBUS-400). A standalone or
// private installation serves a country, so it asks for the country name and
// country code (STATBUS-466); development may invent both.
func Ask(prompt func(label, fallback string) string) string {
	var b strings.Builder
	var mode, domain, name string
	for _, f := range fields {
		if f.installationOnly || f.optional {
			continue
		}
		var answer string
		switch f.key {
		case "CADDY_DEPLOYMENT_MODE":
			mode = askMode(prompt, f)
			answer = mode
		case "SITE_DOMAIN":
			domain = prompt("  The web address people will use. For local testing, use local.statbus.org.\n  "+f.prompt, f.fallback)
			answer = domain
		case "DEPLOYMENT_SLOT_NAME":
			if mode == "development" {
				name = prompt("  A name people will recognize in the web interface. A development installation may invent one.\n  "+DevelopmentNamePrompt, "StatBus")
			} else {
				name = askCountryName(prompt, domain)
			}
			answer = name
		case "DEPLOYMENT_SLOT_CODE":
			if mode == "development" {
				answer = askDevelopmentCode(prompt, domain)
			} else {
				answer = askCountryCode(prompt, name, domain)
			}
		}
		fmt.Fprintf(&b, "%s=%s\n", f.key, answer)
	}
	return b.String()
}

func askMode(prompt func(label, fallback string) string, f field) string {
	label := "  How will people reach StatBus?\n    development: testing on this computer only\n    standalone: this computer serves the public website on ports 80 and 443\n    private: another web server forwards visitors to StatBus\n  " + f.prompt
	answer := ""
	for attempt := 0; attempt < askAttempts; attempt++ {
		answer = strings.ToLower(strings.TrimSpace(prompt(label, f.fallback)))
		if deploymentModes[answer] {
			return answer
		}
		label = "  Please answer development, standalone or private. Press Enter for " + f.fallback + ".\n  " + f.prompt
	}
	return answer
}

func askCountryName(prompt func(label, fallback string) string, domain string) string {
	suggestion, reason := SuggestCountry(domain)
	intro := "  Which country does this installation serve? Its name is shown in the web interface, for example Norway."
	if suggestion != "" {
		intro += "\n  Suggested " + reason + "; press Enter to accept it."
	}
	label := intro + "\n  " + CountryNamePrompt
	answer := ""
	for attempt := 0; attempt < askAttempts && answer == ""; attempt++ {
		answer = strings.TrimSpace(prompt(label, suggestion))
		label = "  Please type the country name people will see, for example Norway.\n  " + CountryNamePrompt
	}
	return answer
}

func askCountryCode(prompt func(label, fallback string) string, countryName, domain string) string {
	suggestion := SuggestCountryCode(countryName, domain)
	label := "  The country's code: two or three lowercase letters, used in container names and the subdomain, for example no for Norway."
	if suggestion != "" {
		label += "\n  Suggested from " + countryName + "; press Enter to accept it."
	}
	label += "\n  " + CountryCodePrompt
	answer := ""
	for attempt := 0; attempt < askAttempts; attempt++ {
		answer = strings.ToLower(strings.TrimSpace(prompt(label, suggestion)))
		switch {
		case answer == "":
			label = "  Please type the country code, for example no.\n  " + CountryCodePrompt
			continue
		case !slotCode.MatchString(answer):
			label = "  " + answer + " cannot be used: the code must be " + slotCodeShape + ", for example no.\n  " + CountryCodePrompt
			continue
		}
		advice := CountryCodeAdvice(answer, countryName)
		if advice == "" {
			return answer
		}
		// Warn, never block: a deliberate test installation keeps its code
		// by pressing Enter, and the reason is on screen, not hidden.
		confirmed := strings.ToLower(strings.TrimSpace(prompt("  "+advice+"\n  For a deliberate test installation, press Enter to keep "+answer+". Otherwise type the country code.\n  "+CountryCodePrompt, answer)))
		if confirmed == "" || confirmed == answer {
			return answer
		}
		suggestion, answer = confirmed, confirmed
		if slotCode.MatchString(confirmed) && CountryCodeAdvice(confirmed, countryName) == "" {
			return confirmed
		}
		label = "  Check the code " + confirmed + ", or press Enter to keep it.\n  " + CountryCodePrompt
	}
	return answer
}

// askDevelopmentCode keeps development permissive: the first domain label
// when it is a usable code (local for local.statbus.org), else local.
func askDevelopmentCode(prompt func(label, fallback string) string, domain string) string {
	suggestion := strings.ToLower(strings.Split(domain, ".")[0])
	if !slotCode.MatchString(suggestion) {
		suggestion = "local"
	}
	label := "  A short lowercase name for this installation, used in container names. A development installation may invent one.\n  " + DevelopmentCodePrompt
	answer := ""
	for attempt := 0; attempt < askAttempts; attempt++ {
		answer = strings.ToLower(strings.TrimSpace(prompt(label, suggestion)))
		if slotCode.MatchString(answer) {
			return answer
		}
		label = "  The code must be " + slotCodeShape + ". Press Enter for " + suggestion + ".\n  " + DevelopmentCodePrompt
	}
	return answer
}

func TrustQuestion() (string, string) {
	for _, f := range fields {
		if f.key == TrustKey {
			return f.prompt, f.fallback
		}
	}
	panic("trust question missing")
}

func MissingTrustInConfig(path string) error {
	for _, f := range fields {
		if f.key == TrustKey {
			return fmt.Errorf("STATBUS_ENV_CONFIG %q: missing key %s (%s).\nAdd %s=<github-user> to the config file at %q.\n%s", path, f.key, f.prompt, f.key, path, TrustExplanation)
		}
	}
	panic("trust question missing")
}

type Answers struct{ Config, Trust string }

// ReadAnswers validates file inputs without sourcing shell code. The trust
// answer may be absent for interactive prompting or the compatible CLI flag.
func ReadAnswers(path, trustFlag string) (Answers, error) {
	if path == "" {
		return Answers{}, fmt.Errorf("%s", Requirement())
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return Answers{}, fmt.Errorf("read STATBUS_ENV_CONFIG %q: %w", path, err)
	}
	return parse(string(data), trustFlag)
}

func Read(path string) (string, error)        { a, err := ReadAnswers(path, ""); return a.Config, err }
func Validate(content string) (string, error) { a, err := parse(content, ""); return a.Config, err }

func parse(content, trustFlag string) (Answers, error) {
	allowed := make(map[string]field, len(fields))
	for _, f := range fields {
		allowed[f.key] = f
	}
	values := make(map[string]string, len(fields))
	for i, line := range strings.Split(content, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parsed := dotenv.FromString(line)
		keys := parsed.Keys()
		if len(keys) != 1 {
			return Answers{}, fmt.Errorf("STATBUS_ENV_CONFIG line %d: expected KEY=VALUE", i+1)
		}
		key := keys[0]
		f, ok := allowed[key]
		if !ok {
			return Answers{}, fmt.Errorf("STATBUS_ENV_CONFIG: extra key %s", key)
		}
		if _, exists := values[key]; exists {
			return Answers{}, fmt.Errorf("STATBUS_ENV_CONFIG: duplicate key %s", key)
		}
		value, _ := parsed.Get(key)
		if strings.TrimSpace(value) == "" {
			return Answers{}, fmt.Errorf("STATBUS_ENV_CONFIG: missing value for %s (%s)", key, f.prompt)
		}
		values[key] = value
	}
	if mode, ok := values["CADDY_DEPLOYMENT_MODE"]; ok && !deploymentModes[mode] {
		return Answers{}, fmt.Errorf("STATBUS_ENV_CONFIG: CADDY_DEPLOYMENT_MODE=%s is not development, standalone or private", mode)
	}
	if code, ok := values["DEPLOYMENT_SLOT_CODE"]; ok && !slotCode.MatchString(code) {
		return Answers{}, fmt.Errorf("STATBUS_ENV_CONFIG: DEPLOYMENT_SLOT_CODE=%s must be %s (%s)", code, slotCodeShape, CountryCodePrompt)
	}
	var b strings.Builder
	for _, f := range fields {
		if f.installationOnly {
			continue
		}
		value, ok := values[f.key]
		if !ok {
			if f.optional {
				continue
			}
			return Answers{}, fmt.Errorf("STATBUS_ENV_CONFIG: missing key %s (%s)", f.key, f.prompt)
		}
		fmt.Fprintf(&b, "%s=%s\n", f.key, value)
	}
	// The custom-certificate pair is both-or-neither.
	_, certOK := values["TLS_CERT_FILE"]
	_, keyOK := values["TLS_KEY_FILE"]
	if certOK != keyOK {
		return Answers{}, fmt.Errorf("STATBUS_ENV_CONFIG: TLS_CERT_FILE and TLS_KEY_FILE must be given together (a certificate needs both parts)")
	}
	trust, err := ResolveTrust(trustFlag, values[TrustKey])
	if err != nil {
		return Answers{}, err
	}
	return Answers{Config: b.String(), Trust: trust}, nil
}
