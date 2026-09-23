package upgrade

import (
	"os"
	"strings"
	"testing"
)

func TestSuccessfulServiceCompletionsClearInstallFailureBanner(t *testing.T) {
	body, err := os.ReadFile("service.go")
	if err != nil {
		t.Fatal(err)
	}
	source := string(body)
	if got := strings.Count(source, "d.clearInstallFailureBanner(ctx)"); got != 3 {
		t.Fatalf("successful service completion writers clearing the banner = %d, want 3", got)
	}
	for _, key := range []string{
		"install_last_error",
		"install_last_error_at",
		"install_last_bundle_path",
	} {
		if !strings.Contains(source, "('"+key+"', '', clock_timestamp())") {
			t.Errorf("clearInstallFailureBanner does not clear %s", key)
		}
	}
}
