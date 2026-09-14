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

type field struct {
	key, prompt, fallback string
	installationOnly      bool
}

// One definition drives deployment prompts, input keys and the setup recipe.
// Trust is asked at the signers step, where fingerprints can be displayed.
var fields = []field{
	{"CADDY_DEPLOYMENT_MODE", "Deployment mode (development/standalone/private)", "standalone", false},
	{"SITE_DOMAIN", "Domain name", "statbus.nso.eu", false},
	{"DEPLOYMENT_SLOT_NAME", "Display name", "StatBus", false},
	{"DEPLOYMENT_SLOT_CODE", "Deployment code (short, lowercase)", "local", false},
	{TrustKey, "Release signer to trust (GitHub username)", RecommendedSigner, true},
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

func Requirement() string {
	var b strings.Builder
	b.WriteString("set STATBUS_ENV_CONFIG to a file containing:")
	for _, f := range fields {
		fmt.Fprintf(&b, "\n  %s=%s  # %s", f.key, f.fallback, f.prompt)
	}
	fmt.Fprintf(&b, "\n\nTRUST_GITHUB_USER=%s explicitly approves the recommended release signer\n%s (Jorgen H. Fjeld), https://github.com/%s. Review that trust decision.\n", RecommendedSigner, RecommendedSigner, RecommendedSigner)
	b.WriteString("\nKeep the file outside ~/statbus, protect it with chmod 0600, then set:\n  export STATBUS_ENV_CONFIG=/path/to/install-input.env\n\nOptional:\n  export STATBUS_INSTALL_VERSION='<release-tag>'  # omit for latest stable\n  export STATBUS_USERS_FILE=/path/to/initial-users.yml\n\nRe-run install.sh --non-interactive (or ./sb install --non-interactive if already bootstrapped).\nNon-interactive mode never approves a signer implicitly.")
	return b.String()
}

func Ask(prompt func(label, fallback string) string) string {
	var b strings.Builder
	for _, f := range fields {
		if !f.installationOnly {
			fmt.Fprintf(&b, "%s=%s\n", f.key, prompt("  "+f.prompt, f.fallback))
		}
	}
	return b.String()
}

func TrustQuestion() (string, string) {
	for _, f := range fields {
		if f.key == TrustKey {
			return f.prompt, f.fallback
		}
	}
	panic("trust question missing")
}

func MissingTrust() error {
	for _, f := range fields {
		if f.key == TrustKey {
			return fmt.Errorf("STATBUS_ENV_CONFIG: missing key %s (%s); alternatively supply --trust-github-user.\n\n%s", f.key, f.prompt, Requirement())
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
	var b strings.Builder
	for _, f := range fields {
		if f.installationOnly {
			continue
		}
		value, ok := values[f.key]
		if !ok {
			return Answers{}, fmt.Errorf("STATBUS_ENV_CONFIG: missing key %s (%s)", f.key, f.prompt)
		}
		fmt.Fprintf(&b, "%s=%s\n", f.key, value)
	}
	trust, err := ResolveTrust(trustFlag, values[TrustKey])
	if err != nil {
		return Answers{}, err
	}
	return Answers{Config: b.String(), Trust: trust}, nil
}
