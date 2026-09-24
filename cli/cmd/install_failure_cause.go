package cmd

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"sync"
)

// Tee command output to the diagnostic log and retain a bounded copy for
// classification. The copy is never printed as operator guidance.
type installDiagnosticCapture struct {
	sync.Mutex
	text []byte
}

func (c *installDiagnosticCapture) Write(p []byte) (int, error) {
	c.Lock()
	defer c.Unlock()
	if len(p) >= 65536 {
		c.text = append(c.text[:0], p[len(p)-65536:]...)
	} else {
		c.text = append(c.text, p...)
		if len(c.text) > 65536 {
			copy(c.text, c.text[len(c.text)-65536:])
			c.text = c.text[:65536]
		}
	}
	return len(p), nil
}

func runInstallCommandWithDiagnostic(cmd *exec.Cmd) error {
	capture := &installDiagnosticCapture{}
	cmd.Stdout = io.MultiWriter(os.Stdout, capture)
	cmd.Stderr = io.MultiWriter(os.Stderr, capture)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%w: %s", err, capture.text)
	}
	return nil
}

// installFailureCauses is the only diagnostic-to-operator boundary for failed
// steps. Never interpolate an error into an operator sentence.
type installFailureCause struct {
	pattern *regexp.Regexp
	cause   string
	fix     string
}

var installFailureCauses = []installFailureCause{
	{failedPublishedPort, "", ""}, // dynamic port and detected owner via servicePortConflictCause
	{regexp.MustCompile(`(?i)(no space left on device|disk full|not enough disk space)`), "The disk ran out of free space.", "Free space on the installation disk and Docker storage, then retry."},
	{regexp.MustCompile(`(?i)(cannot connect to the docker daemon|docker daemon is not running|is the docker daemon running)`), "Docker is not running.", "Start Docker and then retry."},
	{regexp.MustCompile(`(?i)(permission denied.*docker\.sock|docker\.sock.*permission denied|permission denied while trying to connect to the docker daemon)`), "The installer cannot access Docker.", "Give this user access to the Docker socket, then retry."},
	{regexp.MustCompile(`(?i)(pull access denied|unauthorized: authentication required|image pull failure|failed to (?:pull|resolve) (?:image|reference)|error pulling image|registry.*(?:connection refused|timeout|no such host)|lookup .*registry.*no such host)`), "A required image could not be downloaded.", "Check registry access, DNS and image credentials, then retry."},
	{regexp.MustCompile(`(?i)((?:the )?database(?: \(db\))?.*(?:did not (?:start|become (?:healthy|ready))|not (?:reachable|healthy)|connection refused)|(?:dial|connect).*5432.*connection refused)`), "The database did not become reachable after it started.", "Check Docker and database service health, then retry."},
	{regexp.MustCompile(`(?i)(password authentication failed|invalid password|password.*(?:rejected|does not match))`), "The database rejected its password.", "Check the saved database credentials and synchronize them with the running database, then retry."},
	{regexp.MustCompile(`(?i)(failed to connect to bus|systemd.*user.*(?:unavailable|not running)|no medium found|linger.*(?:disabled|unavailable))`), "The user service manager is unavailable.", "Enable linger for the installation user and start its systemd user manager, then retry."},
	{regexp.MustCompile(`(?i)(git.*(?:fetch|remote).*?(?:failed|fatal:|could not|unable to)|(?:fatal:.*(?:could not read from remote repository|unable to access|couldn't find remote ref)))`), "The source update could not be fetched.", "Check network access and Git repository permissions, then retry."},
	{regexp.MustCompile(`(?i)(signature verification failed|invalid signature|untrusted signer|no valid release signer|trusted release signer.*required|gpg: bad signature|signer approval was declined)`), "The release signature could not be verified.", "Verify the release signer and approve a trusted signer before retrying."},
}

func classifyInstallFailure(step string, err error) (cause, fix string) {
	for _, entry := range installFailureCauses {
		if entry.pattern.MatchString(err.Error()) {
			if entry.pattern == failedPublishedPort {
				return servicePortConflictCause(err), ""
			}
			return entry.cause, entry.fix
		}
	}
	return fmt.Sprintf("The %s step could not finish; the details are in the support file.", strings.ToLower(step)), ""
}
