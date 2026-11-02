package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func withRuntimeBase(t *testing.T) string {
	t.Helper()
	base := t.TempDir()
	saved := userRuntimeDirBase
	userRuntimeDirBase = base
	t.Cleanup(func() { userRuntimeDirBase = saved })
	return base
}

// sudo -iu statbus leaves XDG_RUNTIME_DIR unset although the user's manager
// runs; sb supplies the user's own /run/user/<uid>.
func TestEnsureUserRuntimeDirSuppliesTheUsersOwnDirectory(t *testing.T) {
	base := withRuntimeBase(t)
	own := filepath.Join(base, fmt.Sprint(os.Getuid()))
	if err := os.Mkdir(own, 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XDG_RUNTIME_DIR", "")
	ensureUserRuntimeDir()
	if got := os.Getenv("XDG_RUNTIME_DIR"); got != own {
		t.Fatalf("XDG_RUNTIME_DIR = %q, want %q", got, own)
	}
}

// A login that set it keeps its own value.
func TestEnsureUserRuntimeDirKeepsALoginValue(t *testing.T) {
	base := withRuntimeBase(t)
	if err := os.Mkdir(filepath.Join(base, fmt.Sprint(os.Getuid())), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("XDG_RUNTIME_DIR", "/run/user/elsewhere")
	ensureUserRuntimeDir()
	if got := os.Getenv("XDG_RUNTIME_DIR"); got != "/run/user/elsewhere" {
		t.Fatalf("XDG_RUNTIME_DIR = %q, want the login's value", got)
	}
}

// No running user manager (no directory): nothing is invented, so systemctl
// reports the real cause.
func TestEnsureUserRuntimeDirInventsNothingWithoutAManager(t *testing.T) {
	withRuntimeBase(t)
	t.Setenv("XDG_RUNTIME_DIR", "")
	ensureUserRuntimeDir()
	if got := os.Getenv("XDG_RUNTIME_DIR"); got != "" {
		t.Fatalf("XDG_RUNTIME_DIR = %q, want unset", got)
	}
}
