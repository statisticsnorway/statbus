package unitfloor

import (
	"os"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/testguard"
)

func TestMain(m *testing.M) {
	if err := os.Setenv("STATBUS_CLI_UNIT_TEST_GUARD", "1"); err != nil {
		panic(err)
	}
	cleanup, err := testguard.Install()
	if err != nil {
		panic(err)
	}
	code := m.Run()
	cleanup()
	os.Exit(code)
}
