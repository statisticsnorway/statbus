package upgrade

import (
	"os/exec"
	"strings"
)

// CleanStaleRefspecs removes git remote.origin.fetch entries that point
// to branches no longer in use, specifically the legacy `devops/deploy-to-*`
// layout from before the R1.1 rename to `ops/cloud/deploy/*`.
//
// A stale refspec causes every subsequent `git fetch` to fail with
// "couldn't find remote ref refs/heads/devops/deploy-to-X", blocking
// deploy workflows (deploy-to-dev.yaml, etc.) and any `./sb upgrade
// apply-latest` that starts with a fetch.
//
// Idempotent — safe to call unconditionally before any `git fetch`
// regardless of the current refspec state. Existing install flow invokes
// this via configureDeployFetch on every install; upgrade apply-latest
// invokes it as a self-heal pre-step so a server running an older binary
// can still unblock itself on the next deploy tick.
func CleanStaleRefspecs(projDir string) {
	cmd := exec.Command("git", "config", "--get-all", "remote.origin.fetch")
	cmd.Dir = projDir
	out, err := cmd.Output()
	if err != nil {
		return
	}

	removeRefspec := func(pattern string) {
		rm := exec.Command("git", "config", "--unset", "remote.origin.fetch", pattern)
		rm.Dir = projDir
		rm.Run()
	}

	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		// Match any refspec that references the old devops/ branch naming.
		// We don't narrow to `deploy-to-*` because anything under devops/
		// post-rename is stale by definition.
		if strings.Contains(line, "refs/heads/devops/") {
			// git config --unset takes a regex to identify which value
			// to remove. Escape the value to match literally.
			removeRefspec(regexEscape(line))
		}
	}
}

// regexEscape escapes a literal string so it can be used as a git config
// --unset value-regex.
func regexEscape(s string) string {
	// Characters special to POSIX regex; escape with backslash.
	const specials = `\.+*?()[]{}|^$/`
	var b strings.Builder
	for _, r := range s {
		if strings.ContainsRune(specials, r) {
			b.WriteByte('\\')
		}
		b.WriteRune(r)
	}
	return b.String()
}
