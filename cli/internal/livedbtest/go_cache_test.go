package livedbtest

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

// 3k0ne3: the fixture moves HOME to a private directory for the maintenance flag.
// Go's caches default under HOME, so without pinning them every `go list` in the
// package (go/packages in TestTypedComposeAuthorityGate) starts from an empty module
// cache and downloads every module again; a network hiccup then fails the gate with
// "golang.org/x/sys/unix imported as upgrade". After pinning, a moved HOME leaves
// `go env` pointing at the caches the package started with.
func TestPinnedGoCachesSurviveAMovedHome_3k0ne3(t *testing.T) {
	before := goEnv(t, "GOMODCACHE", "GOCACHE", "GOPATH")
	t.Setenv("GOMODCACHE", os.Getenv("GOMODCACHE"))
	t.Setenv("GOCACHE", os.Getenv("GOCACHE"))
	t.Setenv("GOPATH", os.Getenv("GOPATH"))
	t.Setenv("HOME", os.Getenv("HOME"))

	if err := pinGoCaches(); err != nil {
		t.Fatalf("pinGoCaches: %v", err)
	}
	if err := os.Setenv("HOME", t.TempDir()); err != nil {
		t.Fatal(err)
	}

	after := goEnv(t, "GOMODCACHE", "GOCACHE", "GOPATH")
	for name, want := range before {
		if got := after[name]; got != want {
			t.Errorf("after moving HOME, go env %s = %q, want the original %q", name, got, want)
		}
	}
}

func goEnv(t *testing.T, names ...string) map[string]string {
	t.Helper()
	out, err := exec.Command("go", append([]string{"env"}, names...)...).Output()
	if err != nil {
		t.Fatalf("go env: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	values := map[string]string{}
	for i, name := range names {
		values[name] = lines[i]
	}
	return values
}
