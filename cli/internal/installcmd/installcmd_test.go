package installcmd

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLocalNamesTheCheckoutByAbsolutePath(t *testing.T) {
	for dir, want := range map[string]string{
		"/home/statbus/statbus":    "cd /home/statbus/statbus && ./sb install",
		"":                         "cd ~/statbus && ./sb install",
		"/srv/my statbus":          "cd '/srv/my statbus' && ./sb install",
		"/srv/o'neil/statbus":      `cd '/srv/o'\''neil/statbus' && ./sb install`,
		"/home/statbus_no/statbus": "cd /home/statbus_no/statbus && ./sb install",
	} {
		if got := Local(dir); got != want {
			t.Errorf("Local(%q) = %q, want %q", dir, got, want)
		}
	}
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if got, want := Local("relative/checkout"), "cd "+filepath.Join(wd, "relative/checkout")+" && ./sb install"; got != want {
		t.Errorf("a relative checkout must be made absolute: got %q, want %q", got, want)
	}
}

func TestForRunningBinaryNamesACheckout(t *testing.T) {
	// The test binary runs from a temp dir outside any checkout, but the
	// working directory is this package inside the repository, so the rule
	// resolves the repository checkout.
	root, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	if got, want := ForRunningBinary(), Local(root); got != want {
		t.Fatalf("ForRunningBinary() = %q, want %q", got, want)
	}
}
