//go:build livedb

package install

import (
	"fmt"
	"os"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/livedbtest"
)

// TestMain creates one detached scratch worktree and pinned sb binary for this
// package. The fixture owns all mutable daemon files while the cross-package
// lock serializes access to the shared local database.
func TestMain(m *testing.M) {
	cleanup, err := livedbtest.Setup("install")
	if err != nil {
		fmt.Fprintf(os.Stderr, "set up live-database fixture: %v\n", err)
		os.Exit(1)
	}
	code := m.Run()
	cleanup()
	os.Exit(code)
}
