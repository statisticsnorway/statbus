// Package diskpolicy applies the same persisted space threshold to installation and upgrades.
package diskpolicy

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
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

func RerunCommand() string {
	if command := os.Getenv("STATBUS_INSTALL_RERUN_COMMAND"); command != "" {
		return command
	}
	return "curl -fsSL https://statbus.org/install.sh | bash"
}

// DockerRoot refuses to guess a storage location when Docker cannot report it.
func DockerRoot(ctx context.Context, dir string) (string, error) {
	command, err := compose.DockerCommandContext(ctx, dir, "info", "--format", "{{.DockerRootDir}}")
	if err != nil {
		return "", fmt.Errorf("cannot check disk space at Docker storage: Docker root unavailable")
	}
	output, err := command.Output()
	if err != nil || strings.TrimSpace(string(output)) == "" {
		return "", fmt.Errorf("cannot check disk space at Docker storage: Docker root unavailable")
	}
	return strings.TrimSpace(string(output)), nil
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
