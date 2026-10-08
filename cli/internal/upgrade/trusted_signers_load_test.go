package upgrade

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/testgit"
)

// STATBUS-468: the installer's end-state check proves the signer reaches the
// generated .env through TrustedSignersFromEnv. These tests prove the other
// half: given that .env, the daemon's own start-up load (loadTrustedSigners,
// called from Run and LoadConfigAndConnect) writes the allowed-signers file
// git verifies against, and a commit signed by that key then verifies through
// the daemon's verifyCommitSignature. Before the fix the field box's .env had
// no signer, which is the empty-.env case below: no allowed-signers file and a
// refusal at verification.

// signedFixtureRepo creates a repository whose HEAD is SSH-signed by a fresh
// ed25519 key, and returns the repository and that key's public half.
func signedFixtureRepo(t *testing.T) (dir, publicKey string) {
	t.Helper()
	for _, tool := range []string{"git", "ssh-keygen"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skipf("%s not on PATH", tool)
		}
	}
	dir = t.TempDir()
	keyPath := filepath.Join(t.TempDir(), "signer")
	if out, err := exec.Command("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "fixture", "-f", keyPath).CombinedOutput(); err != nil {
		t.Fatalf("ssh-keygen: %v\n%s", err, out)
	}
	pub, err := os.ReadFile(keyPath + ".pub")
	if err != nil {
		t.Fatal(err)
	}
	// "ssh-ed25519 AAAA... fixture" -> the two-field form GitHub serves and
	// the installer stores in UPGRADE_TRUSTED_SIGNER_<name>.
	fields := strings.Fields(string(pub))
	publicKey = fields[0] + " " + fields[1]
	run := func(args ...string) {
		t.Helper()
		cmd := exec.Command("git", testgit.Args(args...)...)
		cmd.Dir = dir
		cmd.Env = testgit.Env()
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
		}
	}
	run("init", "-q", "-b", "main")
	if err := os.WriteFile(filepath.Join(dir, "README.md"), []byte("signed\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	run("add", "README.md")
	run("-c", "gpg.format=ssh", "-c", "user.signingkey="+keyPath, "commit", "-q", "-S", "-m", "signed release")
	return dir, publicKey
}

func TestDaemonLoadsTheInstalledSignerIntoAllowedSigners(t *testing.T) {
	dir, publicKey := signedFixtureRepo(t)
	// The generated .env exactly as `./sb config generate` renders the
	// installer's approved signer (cli/cmd/install_signer_apply_test.go
	// asserts this line in the real generator's output).
	env := "CADDY_DEPLOYMENT_MODE=development\nUPGRADE_TRUSTED_SIGNER_jhf=" + publicKey + "\n"
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte(env), 0o600); err != nil {
		t.Fatal(err)
	}

	d := &Service{projDir: dir}
	if err := d.loadTrustedSigners(); err != nil {
		t.Fatalf("loadTrustedSigners: %v", err)
	}

	wantPath := filepath.Join(dir, "tmp", "allowed-signers")
	if d.allowedSignersPath != wantPath {
		t.Fatalf("daemon allowedSignersPath = %q, want %q", d.allowedSignersPath, wantPath)
	}
	got, err := os.ReadFile(wantPath)
	if err != nil {
		t.Fatalf("daemon wrote no allowed-signers file: %v", err)
	}
	if want := "jhf " + publicKey + "\n"; string(got) != want {
		t.Fatalf("allowed-signers content:\n got %q\nwant %q", got, want)
	}
	// The file is the one the daemon actually verifies against, not merely
	// written: a commit signed by the installed key verifies.
	if err := d.verifyCommitSignature("HEAD"); err != nil {
		t.Fatalf("commit signed by the installed signer did not verify: %v", err)
	}
}

func TestDaemonWithoutTheSignerInEnvRefusesVerification(t *testing.T) {
	dir, _ := signedFixtureRepo(t)
	// The pre-fix field state: .env generated before the signer was written.
	if err := os.WriteFile(filepath.Join(dir, ".env"), []byte("CADDY_DEPLOYMENT_MODE=development\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	d := &Service{projDir: dir}
	if err := d.loadTrustedSigners(); err != nil {
		t.Fatalf("loadTrustedSigners: %v", err)
	}
	if d.allowedSignersPath != "" {
		t.Fatalf("no signer in .env, yet allowedSignersPath = %q", d.allowedSignersPath)
	}
	if _, err := os.Stat(filepath.Join(dir, "tmp", "allowed-signers")); !os.IsNotExist(err) {
		t.Fatalf("allowed-signers written with no signer configured: %v", err)
	}
	if err := d.verifyCommitSignature("HEAD"); err == nil || !strings.Contains(err.Error(), "no trusted signers configured") {
		t.Fatalf("verification without a loaded signer must refuse, got %v", err)
	}
}
