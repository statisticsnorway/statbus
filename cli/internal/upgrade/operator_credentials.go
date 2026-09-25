package upgrade

import (
	"os"
	"path/filepath"

	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// loadOperatorCredentials supplies optional operator tokens to the daemon and
// its subprocesses. Explicit nonempty process environment values take precedence.
// Never include token values in errors or logs.
func loadOperatorCredentials(projDir string) error {
	f, err := dotenv.Load(filepath.Join(projDir, ".env.credentials"))
	if err != nil {
		return err
	}
	for _, key := range []string{"GITHUB_TOKEN", "SLACK_TOKEN", "SEQ_API_KEY"} {
		if os.Getenv(key) != "" {
			continue
		}
		if value, ok := f.Get(key); ok && value != "" {
			if err := os.Setenv(key, value); err != nil {
				return err
			}
		}
	}
	return nil
}
