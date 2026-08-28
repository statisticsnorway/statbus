package cmd

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// TestNewUpgradeServiceLoadsConfig_STATBUS311 pins that the CLI's service
// constructor actually LOADS the config.
//
// WHY A SOURCE PIN. The bug was never that loading was broken — loadConfig
// worked perfectly for the daemon. It was that nothing on the CLI path CALLED
// it, so d.channel stayed "". A test of the loader alone would have passed
// throughout the entire life of this bug; only "is it reached" catches it.
//
// This is the same hole STATBUS-285's own RED verification exposed a few hours
// earlier: tests that exercised a helper directly while nothing proved the
// caller reached it. Written as a source assertion because the channel is
// unexported in this package's dependency and the alternative — driving a real
// `upgrade check` — needs the network and a database.
func TestNewUpgradeServiceLoadsConfig_STATBUS311(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	src, err := os.ReadFile(filepath.Join(filepath.Dir(thisFile), "upgrade.go"))
	if err != nil {
		t.Fatalf("read upgrade.go: %v", err)
	}

	body, ok := funcBodyFor311(string(src), "func newUpgradeService(")
	if !ok {
		t.Fatal("newUpgradeService not found in upgrade.go — this scan is asserting nothing")
	}
	if !strings.Contains(body, "LoadConfigForCLI()") {
		t.Error(`newUpgradeService does not load this box's config.

Every CLI verb is built here, so without the load d.channel is the zero value "".
` + "`./sb upgrade check`" + ` then filters every release tag against the empty string,
matches nothing, and prints "none matching channel \"\"" while reporting success —
the box is dark for future releases and nothing says so. (STATBUS-311)`)
	}
}

// funcBody returns the text of the top-level function whose declaration starts
// with decl, up to the next top-level declaration.
func funcBodyFor311(src, decl string) (string, bool) {
	i := strings.Index(src, decl)
	if i < 0 {
		return "", false
	}
	rest := src[i+len(decl):]
	if j := strings.Index(rest, "\nfunc "); j >= 0 {
		return rest[:j], true
	}
	return rest, true
}
