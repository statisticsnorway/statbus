package cmd

import (
	"fmt"
	"os"
	"path/filepath"
)

var installExecutable = os.Executable

// resolveInstallDir targets the checkout containing the symlink-resolved running binary;
// only when that binary is outside a checkout does it try the cwd checkout, then
// HOME/statbus. A checkout has .git, docker-compose.yml and cli/; never use an
// arbitrary directory as an install target.
func resolveInstallDir(executable, cwd, home string) (string, error) {
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
		if isStatbusCheckout(dir) {
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
		if isStatbusCheckout(dir) {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return ""
		}
		dir = parent
	}
}

func isStatbusCheckout(dir string) bool {
	if _, err := os.Stat(filepath.Join(dir, ".git")); err != nil {
		return false
	}
	if info, err := os.Stat(filepath.Join(dir, "docker-compose.yml")); err != nil || info.IsDir() {
		return false
	}
	info, err := os.Stat(filepath.Join(dir, "cli"))
	return err == nil && info.IsDir()
}

func installProjectDir() (string, error) {
	executable, err := installExecutable()
	if err != nil {
		return "", fmt.Errorf("cannot locate running StatBus binary: %w", err)
	}
	cwd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("cannot determine current directory: %w", err)
	}
	home, _ := os.UserHomeDir()
	return resolveInstallDir(executable, cwd, home)
}
