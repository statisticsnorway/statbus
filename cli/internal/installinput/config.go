// Package installinput defines the single configuration questionnaire used by
// interactive and unattended first installs. This is not the full .env.config
// schema: operator tuning belongs to the installed configuration, not this input.
package installinput

import (
	"fmt"
	"os"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

const EnvConfig = "STATBUS_ENV_CONFIG"
const UsersFile = "STATBUS_USERS_FILE"

type field struct{ key, prompt, fallback string }

// Both asking and validation iterate this table. Never maintain a second list
// of unattended keys or a separately formatted interactive configuration.
var fields = []field{
	{"CADDY_DEPLOYMENT_MODE", "Deployment mode (development/standalone/private)", "standalone"},
	{"SITE_DOMAIN", "Domain name", "statbus.nso.eu"},
	{"DEPLOYMENT_SLOT_NAME", "Display name", "StatBus"},
	{"DEPLOYMENT_SLOT_CODE", "Deployment code (short, lowercase)", "local"},
}

func Requirement() string {
	var b strings.Builder
	b.WriteString("set STATBUS_ENV_CONFIG to a file containing:")
	for _, f := range fields {
		fmt.Fprintf(&b, "\n  %s=<%s>", f.key, f.prompt)
	}
	return b.String()
}

func Ask(prompt func(label, fallback string) string) string {
	var b strings.Builder
	for _, f := range fields {
		fmt.Fprintf(&b, "%s=%s\n", f.key, prompt("  "+f.prompt, f.fallback))
	}
	return b.String()
}

// Read validates the explicit file, including malformed/duplicate declarations,
// before returning canonical configuration. It never sources shell code.
func Read(path string) (string, error) {
	if path == "" {
		return "", fmt.Errorf("%s", Requirement())
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read STATBUS_ENV_CONFIG %q: %w", path, err)
	}
	return Validate(string(data))
}

func Validate(content string) (string, error) {
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
			return "", fmt.Errorf("STATBUS_ENV_CONFIG line %d: expected KEY=VALUE", i+1)
		}
		key := keys[0]
		f, ok := allowed[key]
		if !ok {
			return "", fmt.Errorf("STATBUS_ENV_CONFIG: extra key %s", key)
		}
		if _, exists := values[key]; exists {
			return "", fmt.Errorf("STATBUS_ENV_CONFIG: duplicate key %s", key)
		}
		value, _ := parsed.Get(key)
		if strings.TrimSpace(value) == "" {
			return "", fmt.Errorf("STATBUS_ENV_CONFIG: missing value for %s (%s)", key, f.prompt)
		}
		values[key] = value
	}
	var b strings.Builder
	for _, f := range fields {
		value, ok := values[f.key]
		if !ok {
			return "", fmt.Errorf("STATBUS_ENV_CONFIG: missing key %s (%s)", f.key, f.prompt)
		}
		fmt.Fprintf(&b, "%s=%s\n", f.key, value)
	}
	return b.String(), nil
}
