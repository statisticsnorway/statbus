package cmd

import (
	"fmt"
	"os"

	"github.com/statisticsnorway/statbus/cli/internal/installcmd"
)

var installExecutable = os.Executable

// resolveInstallDir targets the checkout containing the symlink-resolved running binary;
// only when that binary is outside a checkout does it try the cwd checkout, then
// HOME/statbus. The rule lives in installcmd.Checkout so the operator's
// install command (installcmd.ForRunningBinary) names the same checkout.
func resolveInstallDir(executable, cwd, home string) (string, error) {
	return installcmd.Checkout(executable, cwd, home)
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
