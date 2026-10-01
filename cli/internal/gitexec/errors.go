package gitexec

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/redact"
)

// Run executes Git while ensuring that only redacted output reaches operator
// surfaces. The same shared redactor protects terminal output, install logs,
// returned errors, and any later diagnostic derived from those errors.
func Run(cmd *exec.Cmd, stdout, stderr io.Writer) error {
	var stdoutCapture bytes.Buffer
	var stderrCapture bytes.Buffer
	cmd.Stdout = &stdoutCapture
	cmd.Stderr = &stderrCapture

	err := cmd.Run()
	redactedStdout := redact.GitHubCredentials(stdoutCapture.String(), os.Getenv("GITHUB_TOKEN"))
	redactedStderr := redact.GitHubCredentials(stderrCapture.String(), os.Getenv("GITHUB_TOKEN"))
	if stdout != nil && redactedStdout != "" {
		_, _ = io.WriteString(stdout, redactedStdout)
	}
	if stderr != nil && redactedStderr != "" {
		_, _ = io.WriteString(stderr, redactedStderr)
	}
	if err == nil {
		return nil
	}

	diagnostic := strings.TrimSpace(redactedStderr)
	if diagnostic == "" {
		diagnostic = strings.TrimSpace(redactedStdout)
	}
	if diagnostic == "" {
		return err
	}
	return fmt.Errorf("%w: %s", err, diagnostic)
}
