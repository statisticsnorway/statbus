// Package diskpolicy applies the same persisted space threshold to installation and upgrades.
package diskpolicy

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
	"github.com/statisticsnorway/statbus/cli/internal/installcmd"
)

const MinimumGB uint64 = 20
const RecommendedGB uint64 = 40
const PolicyConfig = "STATBUS_DISK_MIN_GB=20\nSTATBUS_DISK_RECOMMENDED_GB=40\n"

type Measurement struct {
	Path   string
	FreeGB uint64
}
type Policy struct{ MinimumGB, RecommendedGB uint64 }

func Load(dir string) (Policy, error) {
	policy := Policy{MinimumGB, RecommendedGB}
	file, err := dotenv.Load(filepath.Join(dir, ".env.config"))
	if os.IsNotExist(err) {
		return policy, nil
	} // fresh installation, before configuration
	if err != nil {
		return policy, err
	}
	for _, field := range []struct {
		key    string
		target *uint64
	}{{"STATBUS_DISK_MIN_GB", &policy.MinimumGB}, {"STATBUS_DISK_RECOMMENDED_GB", &policy.RecommendedGB}} {
		if raw, ok := file.Get(field.key); ok {
			value, parseErr := strconv.ParseUint(raw, 10, 64)
			if parseErr != nil || value == 0 {
				return policy, fmt.Errorf("invalid saved disk policy %s", field.key)
			}
			*field.target = value
		}
	}
	if policy.RecommendedGB < policy.MinimumGB {
		return policy, fmt.Errorf("disk recommendation must not be below its minimum")
	}
	return policy, nil
}

func Evaluate(m Measurement) (string, bool) { return (Policy{MinimumGB, RecommendedGB}).Evaluate(m) }
func (p Policy) Evaluate(m Measurement) (string, bool) {
	rerun := RerunCommand()
	if m.FreeGB < p.MinimumGB {
		return fmt.Sprintf("Only %d GB free on %s. StatBus needs at least %d GB to install. Free some space, then run the same install command again: %s", m.FreeGB, m.Path, p.MinimumGB, rerun), false
	}
	if m.FreeGB < p.RecommendedGB {
		return fmt.Sprintf("Disk space: %d GB free on %s. %d GB is recommended; this is enough to start, and you can add space later.", m.FreeGB, m.Path, p.RecommendedGB), true
	}
	return fmt.Sprintf("Disk space: %d GB free on %s; the %d GB recommendation is met.", m.FreeGB, m.Path, p.RecommendedGB), true
}

// RerunCommand is the command that repeats this install run. Under install.sh
// it is the saved invocation (STATBUS_INSTALL_RERUN_COMMAND), which keeps the
// operator's channel, version and answers-file options. A direct `./sb
// install` has no saved invocation, so the rerun is the same local program on
// the same checkout: `cd <checkout> && ./sb install`. It is never the public
// curl installer, which would replace ./sb and change the checked-out release.
func RerunCommand() string {
	if command := os.Getenv("STATBUS_INSTALL_RERUN_COMMAND"); command != "" {
		return command
	}
	return installcmd.ForRunningBinary()
}

// STATBUS-487: Docker is a PREREQUISITE, not something StatBus installs.
//
// DECISION: the installer refuses with the specific remedy and points at the
// documented prerequisite (ops/setup-ubuntu-lts.sh, doc/setup-ubuntu-lts.md)
// instead of installing Docker itself. install.sh runs as the unprivileged
// install user, and both installing Docker and joining the docker group need
// root and then a NEW login session, which no single install run can provide;
// the setup script already does it together with the OS hardening StatBus
// expects.
//
// Three causes, three sentences. Each is ONE line that install.sh's exit-78
// allow-list matches FULL-LINE anchored, and install.sh's own pre-download
// preflight prints the identical text (pinned by
// TestInstallShRefusesEachDockerCauseBeforeAnyWork).
const DockerSetupGuide = "https://github.com/statisticsnorway/statbus/blob/master/doc/setup-ubuntu-lts.md"

// dockerDeniedQuote extracts the daemon's own permission sentence, restricted to
// a fixed shape so nothing arbitrary can ride it across the install-log boundary.
var dockerDeniedQuote = regexp.MustCompile(`(?i)permission denied while trying to connect to the docker (?:api|daemon socket) at unix:///[A-Za-z0-9_./-]+`)
var dockerStoppedText = regexp.MustCompile(`(?i)(cannot connect to the docker daemon|is the docker daemon running|docker daemon is not running)`)
var safeUserName = regexp.MustCompile(`^[a-z_][a-z0-9_-]{0,31}$`)

func DockerAbsentRefusal(rerun string) string {
	return fmt.Sprintf("Docker is not installed. StatBus needs Docker before it can install: run the server setup script as root, which installs it (%s), then run the same install command again: %s", DockerSetupGuide, rerun)
}

func DockerStoppedRefusal(rerun string) string {
	return fmt.Sprintf("Docker is installed but its service is not running. Start it with sudo systemctl enable --now docker, then run the same install command again: %s", rerun)
}

// DockerDeniedRefusal names both steps IN ORDER: membership, then a new login.
// A stale session and a non-member look identical from `groups` in the current
// shell, so it also says how to tell them apart (getent reads the group file).
func DockerDeniedRefusal(userName, quote, rerun string) string {
	if !safeUserName.MatchString(userName) {
		userName = "$USER"
	}
	if quote == "" {
		quote = "permission denied"
	}
	return fmt.Sprintf("The user %s may not use Docker (Docker said: %s). If getent group docker does not list %s, run sudo usermod -aG docker %s. Then log out and log in again so id -nG lists docker, and run the same install command again: %s", userName, quote, userName, userName, rerun)
}

// DockerAccessRefusal classifies a failed `docker` answer into one of the three
// causes, or "" when it is none of them.
func DockerAccessRefusal(output, userName, rerun string) string {
	if quote := dockerDeniedQuote.FindString(output); quote != "" {
		return DockerDeniedRefusal(userName, quote, rerun)
	}
	if strings.Contains(strings.ToLower(output), "permission denied") && strings.Contains(output, "docker.sock") {
		return DockerDeniedRefusal(userName, "", rerun)
	}
	if dockerStoppedText.MatchString(output) {
		return DockerStoppedRefusal(rerun)
	}
	return ""
}

func currentUserName() string {
	if u, err := user.Current(); err == nil {
		return u.Username
	}
	return os.Getenv("USER")
}

// DockerRoot refuses to guess a storage location when Docker cannot report it.
func DockerRoot(ctx context.Context, dir string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	// STATBUS-487: a Docker cause must be named, never masked by the disk
	// sentence below (the Uganda box saw only "Docker root unavailable").
	if _, lookErr := exec.LookPath("docker"); lookErr != nil {
		return "", fmt.Errorf("%s", DockerAbsentRefusal(RerunCommand()))
	}
	command, err := compose.DockerCommandContext(ctx, dir, "info", "--format", "{{.DockerRootDir}}")
	if err != nil {
		return "", fmt.Errorf("cannot check disk space at Docker storage: Docker root unavailable")
	}
	output, err := command.Output()
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			if refusal := DockerAccessRefusal(string(output)+"\n"+string(exitErr.Stderr), currentUserName(), RerunCommand()); refusal != "" {
				return "", fmt.Errorf("%s", refusal)
			}
		}
		return "", fmt.Errorf("cannot check disk space at Docker storage: Docker root unavailable")
	}
	if strings.TrimSpace(string(output)) == "" {
		return "", fmt.Errorf("cannot check disk space at Docker storage: Docker root unavailable")
	}
	root := strings.TrimSpace(string(output))
	info, statErr := os.Stat(root)
	if statErr != nil || !info.IsDir() {
		return "", fmt.Errorf("cannot check disk space at Docker storage: Docker root unavailable")
	}
	return root, nil
}

// CheckWith is the common decision and measurement path for install, fixup and upgrade.
func CheckWith(dir string, report func(string), paths ...string) error {
	policy, err := Load(dir)
	if err != nil {
		return err
	}
	seen := map[string]bool{}
	var refusal error
	for _, path := range paths {
		if strings.TrimSpace(path) == "" || seen[path] {
			continue
		}
		seen[path] = true
		m, err := Measure(path)
		if err != nil {
			return fmt.Errorf("cannot check disk space at %s: measurement unavailable", path)
		}
		message, ok := policy.Evaluate(m)
		report(message)
		if !ok && refusal == nil {
			refusal = fmt.Errorf("%s", message)
		}
	}
	return refusal
}

func Measure(path string) (Measurement, error) {
	original := path
	for {
		if _, err := os.Stat(path); err == nil {
			break
		}
		parent := filepath.Dir(path)
		if parent == path {
			return Measurement{}, fmt.Errorf("cannot find a filesystem for %s", original)
		}
		path = parent
	}
	var stat syscall.Statfs_t
	err := syscall.Statfs(path, &stat)
	free := stat.Bavail * uint64(stat.Bsize)
	return Measurement{Path: original, FreeGB: free / (1024 * 1024 * 1024)}, err
}

func Check(dir string, paths ...string) error {
	return CheckWith(dir, func(message string) { fmt.Println(message) }, paths...)
}
