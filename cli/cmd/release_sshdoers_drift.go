package cmd

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// STATBUS-259: the fleet's inbound-command policy must be provably the reviewed
// one, and the release cut is where that is checked.
//
// /etc/sshdoers on each host is the byte-pinned allowlist every inbound CI ssh
// command is checked against. The repo carries the source (ops/<host>/sshdoers)
// and Stage 8 of ops/setup-ubuntu-lts-24.sh installs it byte for byte, publishing
// a world-readable /etc/sshdoers.sha256 beside it. Nothing else synced the two
// before that stage existed, so the live policy could differ from the reviewed
// copy silently, in either direction.
//
// WHY THE PREFLIGHT AND NOT A CRON. This is the moment the door's correctness
// actually matters, it is a surface somebody reads at every single release, and
// it already refuses on gate failures. A drifted allowlist means the fleet's
// access policy is not what was reviewed — precisely a thing that should stop a
// release rather than be discovered after one.
//
// WHY A HASH AND NOT THE FILE — and NOT for secrecy. The slot users must be
// able to read the policy: sshdo runs as the invoking user and opens it as that
// user. A hash is the right shape because it answers "did this change?" without
// anyone parsing a policy file to find out, and because publishing it records
// exactly which bytes the stage installed.

const (
	// sshdoersReadUserEnv overrides the account used to read the published hash.
	// The default is the ops account Stage 6 creates on every host.
	sshdoersReadUserEnv  = "SSHDOERS_READ_USER"
	sshdoersReadUser     = "devops"
	sshdoersSkipEnv      = "SKIP_SSHDOERS"
	sshdoersLiveHashPath = "/etc/sshdoers.sha256"
	sshdoersSSHTimeout   = 20 * time.Second
)

// sshdoersHost is one repo-declared allowlist and the host it belongs to.
type sshdoersHost struct {
	Name     string // "niue" — the ops/<name>/ directory
	RepoPath string // absolute path to the repo copy
	Address  string // "niue.statbus.org"
}

// discoverSshdoersHosts returns every ops/<host>/sshdoers the repo declares.
//
// Driven by what is on disk rather than by a hard-coded list, so a standalone
// host that grows its own allowlist is covered the moment the file is committed
// — nobody has to remember to add it here, which is the failure this whole
// ticket is about in miniature.
func discoverSshdoersHosts(projDir string) ([]sshdoersHost, error) {
	opsDir := filepath.Join(projDir, "ops")
	entries, err := os.ReadDir(opsDir)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", opsDir, err)
	}
	var out []sshdoersHost
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		p := filepath.Join(opsDir, e.Name(), "sshdoers")
		if st, err := os.Stat(p); err != nil || st.IsDir() {
			continue
		}
		out = append(out, sshdoersHost{
			Name:     e.Name(),
			RepoPath: p,
			Address:  e.Name() + ".statbus.org",
		})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

// fileSHA256 hashes a file exactly as `sha256sum` does, so the two sides of the
// comparison are computed the same way on both ends.
func fileSHA256(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:]), nil
}

// readLiveSshdoersHash reads the published hash over an ordinary ssh session.
//
// BatchMode: a host that prompts must fail rather than hang a release cut behind
// a password prompt nobody is watching.
func readLiveSshdoersHash(host sshdoersHost) (string, error) {
	user := os.Getenv(sshdoersReadUserEnv)
	if user == "" {
		user = sshdoersReadUser
	}
	cmd := exec.Command("ssh",
		"-o", "BatchMode=yes",
		"-o", fmt.Sprintf("ConnectTimeout=%d", int(sshdoersSSHTimeout.Seconds())),
		"-o", "StrictHostKeyChecking=accept-new",
		user+"@"+host.Address,
		"cat "+sshdoersLiveHashPath,
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("%v: %s", err, strings.TrimSpace(string(out)))
	}
	return strings.TrimSpace(string(out)), nil
}

// checkSshdoersDrift is preflight check 16. Returns false to fail the cut.
func checkSshdoersDrift(projDir string) bool {
	if os.Getenv(sshdoersSkipEnv) == "1" {
		// Loud bypass, same shape as SKIP_IMAGES: surgical, and it says exactly
		// what is no longer being claimed.
		fmt.Println("  ⚠⚠⚠ CI allowlist drift check BYPASSED (SKIP_SSHDOERS=1)")
		fmt.Println("    The live inbound-command policy on the fleet has NOT been compared")
		fmt.Println("    against the reviewed copy in this repo. This release may be cut against")
		fmt.Println("    an access policy nobody reviewed. Use only when a host is genuinely")
		fmt.Println("    unreachable and the release cannot wait.")
		return true
	}

	hosts, err := discoverSshdoersHosts(projDir)
	if err != nil {
		fmt.Printf("  ✗ CI allowlist drift check could not read ops/: %v\n", err)
		return false
	}
	if len(hosts) == 0 {
		// A check that examines nothing must fail, not pass. If the repo declares
		// no allowlist at all, either the layout moved or the copies were deleted
		// — and silently reporting success would be the exact zero-scope shape
		// this gate exists to avoid.
		fmt.Println("  ✗ CI allowlist drift check found no ops/<host>/sshdoers to compare")
		fmt.Println("    The repo declares no allowlist, so this check examined nothing.")
		fmt.Println("    Fix: restore the reviewed copy, or remove this gate deliberately if")
		fmt.Println("      the fleet genuinely no longer has an inbound CI door.")
		return false
	}

	allPassed := true
	for _, h := range hosts {
		repoHash, err := fileSHA256(h.RepoPath)
		if err != nil {
			fmt.Printf("  ✗ CI allowlist for %s could not be hashed: %v\n", h.Name, err)
			allPassed = false
			continue
		}

		liveHash, err := readLiveSshdoersHash(h)
		if err != nil {
			// UNREACHABLE IS A FAILURE, NOT A SKIP. The check examined nothing,
			// and a pass here would report a guarantee nobody verified — which
			// is worse than no gate, because the release summary would say the
			// policy was confirmed.
			fmt.Printf("  ✗ CI allowlist on %s could not be read\n", h.Name)
			fmt.Printf("    Host:   %s\n", h.Address)
			fmt.Printf("    Read:   %s (as %s)\n", sshdoersLiveHashPath, sshdoersReadUserFor())
			fmt.Printf("    Detail: %v\n", err)
			fmt.Println("    This is not a pass: nothing was compared, so the live access policy")
			fmt.Println("    is unverified for this release.")
			fmt.Println("    Fix, in the order most likely to resolve it:")
			fmt.Printf("      - is %s reachable, and does your key let you in as %s?\n", h.Address, sshdoersReadUserFor())
			fmt.Printf("      - has Stage 8 ever run there? %s only exists after it has\n", sshdoersLiveHashPath)
			fmt.Println("        (ops/setup-ubuntu-lts-24.sh, stage 8 — STATBUS-259)")
			fmt.Printf("      - override the account with %s=<user> if devops is not the right one\n", sshdoersReadUserEnv)
			fmt.Printf("      - genuinely unreachable and the release cannot wait: %s=1 (bypass, prints loudly)\n", sshdoersSkipEnv)
			allPassed = false
			continue
		}

		if !strings.EqualFold(liveHash, repoHash) {
			fmt.Printf("  ✗ CI allowlist on %s DIFFERS from the reviewed copy\n", h.Name)
			fmt.Printf("    Host: %s\n", h.Address)
			fmt.Printf("    live (%s): %s\n", sshdoersLiveHashPath, liveHash)
			fmt.Printf("    repo (%s):  %s\n", relOrAbs(projDir, h.RepoPath), repoHash)
			fmt.Println("    The fleet's inbound-command policy is not the one under review.")
			fmt.Println("")
			fmt.Println("    WHICH WAY TO RECONCILE — they are authoritative for different things:")
			fmt.Println("      LIVE is authoritative for BEHAVIOUR. It is what the door actually")
			fmt.Println("        enforces right now; a CI path working today depends on it.")
			fmt.Println("      REPO is authoritative for INTENT. It is what was reviewed and")
			fmt.Println("        agreed; it is what the next stage run will install.")
			fmt.Println("    So: read the live file, decide deliberately which entries belong,")
			fmt.Println("    commit that to the repo copy, and re-run Stage 8 so the two agree.")
			fmt.Println("    Do NOT simply re-run the stage to make this pass — that would erase")
			fmt.Println("    whatever the live file has that the repo lacks, and an entry that")
			fmt.Println("    disappears is a workflow that stops working.")
			allPassed = false
			continue
		}

		fmt.Printf("  ✓ CI allowlist on %s matches the reviewed copy (%s…)\n", h.Name, shortHash(repoHash))
	}
	return allPassed
}

func sshdoersReadUserFor() string {
	if u := os.Getenv(sshdoersReadUserEnv); u != "" {
		return u
	}
	return sshdoersReadUser
}

func shortHash(h string) string {
	if len(h) > 12 {
		return h[:12]
	}
	return h
}

func relOrAbs(projDir, path string) string {
	if rel, err := filepath.Rel(projDir, path); err == nil {
		return rel
	}
	return path
}
