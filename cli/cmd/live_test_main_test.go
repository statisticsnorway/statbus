//go:build livedb

package cmd

import (
	"fmt"
	"os"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/livedbtest"
)

// TestMain gives the cmd package the same detached scratch worktree, pinned sb
// and throwaway database (statbus_livedb_<pid>, cloned from statbus_seed) as
// internal/upgrade and internal/install, so ./dev.sh test-livedb runs the
// install-path tests here on every push. The unit-test guard in
// test_main_test.go applies only without the livedb tag.
func TestMain(m *testing.M) {
	cleanup, err := livedbtest.Setup("cmd")
	if err != nil {
		fmt.Fprintf(os.Stderr, "set up live-database fixture: %v\n", err)
		os.Exit(1)
	}
	code := m.Run()
	cleanup()
	os.Exit(code)
}
