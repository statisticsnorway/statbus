package upgrade

// installedCommitSHA is the commit this binary was built from — the identity of
// what is actually RUNNING (STATBUS-307's same-commit short-circuit).
//
// WHY NOT `git rev-parse HEAD`, which the brief suggested as the cheap source:
// HEAD is the WORKING TREE's commit, and the two diverge in exactly the
// situations this check matters. Mid-upgrade the tree is checked out to the
// target while the running binary is still the old one; after a swap-and-exit
// the reverse holds briefly. service.go's own manifest-resolution path warns
// against HEAD for this same reason. binaryCommit is set from ldflags at build
// time and cannot drift from the process that is asking.
//
// Empty when the build carried no ldflags (local `go run` paths, where
// binaryCommit is "unknown"). The caller treats empty as "cannot tell" and
// offers the candidate — degrading to today's behaviour rather than suppressing
// an offer on a guess.
func (d *Service) installedCommitSHA() string {
	if d.binaryCommit == "" || d.binaryCommit == "unknown" {
		return ""
	}
	return d.binaryCommit
}
