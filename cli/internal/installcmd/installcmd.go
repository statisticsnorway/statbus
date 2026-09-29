// Package installcmd names the one local, version-preserving operator
// command: `cd <checkout> && ./sb install`.
//
// Every recovery, un-park, restore and repair hint uses it. It keeps the
// box's own ./sb binary, its checked-out tree and its UPGRADE_CHANNEL, and it
// works from any directory because it names the checkout by absolute path.
// The public `curl ... | bash` installer is NOT a substitute: it replaces ./sb
// and checks out the latest release of its channel (stable by default), which
// on a prerelease or pinned box changes the version under recovery.
//
// The package is a leaf (standard library only) so diskpolicy, config,
// freshness and upgrade can all import it.
package installcmd

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// DefaultCheckout is where install.sh always puts the checkout. It is used
// only when the running binary's checkout cannot be found.
const DefaultCheckout = "~/statbus"

var plainPath = regexp.MustCompile(`^[A-Za-z0-9_./~+-]+$`)

// Local is the operator command for the checkout at dir. An empty dir names
// install.sh's DefaultCheckout. A relative dir is made absolute.
func Local(dir string) string {
	if dir == "" {
		dir = DefaultCheckout
	} else if !strings.HasPrefix(dir, "~") {
		if abs, err := filepath.Abs(dir); err == nil {
			dir = abs
		}
	}
	return "cd " + shellWord(dir) + " && ./sb install"
}

// ForRunningBinary is Local for the checkout that contains the running ./sb,
// falling back to the current directory's checkout, then HOME/statbus, then
// DefaultCheckout.
func ForRunningBinary() string {
	dir, err := RunningCheckout()
	if err != nil {
		return Local("")
	}
	return Local(dir)
}

// RunningCheckout resolves Checkout for this process.
func RunningCheckout() (string, error) {
	executable, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("cannot locate running StatBus binary: %w", err)
	}
	cwd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("cannot determine current directory: %w", err)
	}
	home, _ := os.UserHomeDir()
	return Checkout(executable, cwd, home)
}

// Checkout targets the checkout containing the symlink-resolved running
// binary; only when that binary is outside a checkout does it try the cwd
// checkout, then HOME/statbus. A checkout has .git, docker-compose.yml and
// cli/; never use an arbitrary directory as an install target.
func Checkout(executable, cwd, home string) (string, error) {
	if executable != "" {
		if real, err := filepath.EvalSymlinks(executable); err == nil {
			if dir := checkoutAncestor(filepath.Dir(real)); dir != "" {
				return dir, nil
			}
		} else {
			return "", fmt.Errorf("cannot resolve running StatBus binary %q: %w", executable, err)
		}
	}
	if dir := checkoutAncestor(cwd); dir != "" {
		return dir, nil
	}
	if home != "" {
		dir := filepath.Join(home, "statbus")
		if IsCheckout(dir) {
			return dir, nil
		}
	}
	return "", fmt.Errorf("cannot find a StatBus checkout for install (binary, current directory, or HOME/statbus)")
}

func checkoutAncestor(start string) string {
	if start == "" {
		return ""
	}
	dir, err := filepath.Abs(start)
	if err != nil {
		return ""
	}
	for {
		if IsCheckout(dir) {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return ""
		}
		dir = parent
	}
}

// IsCheckout reports whether dir looks like a StatBus checkout.
func IsCheckout(dir string) bool {
	if _, err := os.Stat(filepath.Join(dir, ".git")); err != nil {
		return false
	}
	if info, err := os.Stat(filepath.Join(dir, "docker-compose.yml")); err != nil || info.IsDir() {
		return false
	}
	info, err := os.Stat(filepath.Join(dir, "cli"))
	return err == nil && info.IsDir()
}

// shellWord quotes dir only when it needs it, so the common path prints
// exactly as the operator would type it.
func shellWord(dir string) string {
	if plainPath.MatchString(dir) {
		return dir
	}
	return "'" + strings.ReplaceAll(dir, "'", `'\''`) + "'"
}
