package cmd

import (
	"context"
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSelectedPortsAndOwners(t *testing.T) {
	standalone := selectedInstallPorts("standalone", 1)
	if standalone[0].number != 80 || standalone[1].number != 443 || standalone[4].number != 5431 || standalone[5].number != 5432 {
		t.Fatalf("standalone ports: %+v", standalone)
	}
	private := selectedInstallPorts("private", 2)
	if private[0].number != 3020 || private[4].number != 3024 || private[6].number != 3026 {
		t.Fatalf("private ports: %+v", private)
	}
	if m := listenerProgram.FindStringSubmatch(`users:(("apache2",pid=123,fd=4))`); len(m) != 2 || m[1] != "apache2" {
		t.Fatalf("owner: %v", m)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = listener.Close() }()
	port := listener.Addr().(*net.TCPAddr).Port
	if owner := occupiedPortOwner(installPort{"127.0.0.1", port}); owner == "" {
		t.Fatal("occupied non-80 port was accepted")
	}
}
func TestDomainAssessmentSeparatesDNSFromReachability(t *testing.T) {
	absent := assessInstallDomain("absent.example", func(context.Context, string) ([]net.IP, error) { return nil, errors.New("nxdomain") })
	if !strings.Contains(absent, "not confirmed in public DNS") || strings.Contains(absent, "checked external") {
		t.Fatal(absent)
	}
	present := assessInstallDomain("found.example", func(context.Context, string) ([]net.IP, error) { return []net.IP{net.ParseIP("203.0.113.8")}, nil })
	if !strings.Contains(present, "external access on port 80 has not been checked") {
		t.Fatal(present)
	}
}
func TestPasswordMismatchRetriesWithoutDisclosure(t *testing.T) {
	answers := []string{"first-secret", "different-secret", "matching-secret", "matching-secret"}
	i := 0
	value, err := askAdministratorPassword(func(string) (string, error) { answer := answers[i]; i++; return answer, nil })
	if err != nil || value != "matching-secret" || i != 4 {
		t.Fatalf("retry: %q, %v, %d", value, err, i)
	}
}

func TestLaptopModeDefault(t *testing.T) {
	root := t.TempDir()
	if installIsLaptopAt(root) {
		t.Fatal("server classified as laptop")
	}
	if err := os.Mkdir(filepath.Join(root, "BAT0"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "BAT0", "type"), []byte("Battery\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if !installIsLaptopAt(root) {
		t.Fatal("battery-backed laptop not detected")
	}
}
