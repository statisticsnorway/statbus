package gitexec

import (
	"bytes"
	"fmt"
	"io"
	"os/exec"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/release"
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
	redactedStdout := release.RedactGitHubCredentials(stdoutCapture.String())
	redactedStderr := release.RedactGitHubCredentials(stderrCapture.String())
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
