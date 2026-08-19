// Package testgit gives every test that builds a throwaway git repository ONE
// definition of how to invoke git safely. It is imported only from _test.go
// files, so it never reaches a shipped binary.
//
// WHY IT EXISTS — a real CI red, not a hypothetical.
// TestFindExemptRide_AddThenRevertRidesTheOlderAncestor failed at commit
// d59f5e06d, and not on any assertion:
//
//	testing.go:1369: TempDir RemoveAll cleanup: unlinkat …: directory not empty
//
// It was green on the next runner. Per the no-flaky-tests rule that is a real
// defect with a real cause, and the error class names the cause exactly: Go's
// RemoveAll walks a directory and then removes it, so "directory not empty" can
// only mean SOMETHING WROTE INTO IT between those two steps. A test whose git
// commands have all returned cannot do that. A background process git spawned
// can.
//
// WHICH spawner cannot be identified from a developer machine — the red is on a
// runner we cannot attach to, and it did not recur on the next one. So this does
// not guess: it closes the whole class of known spawners, because a fix aimed at
// one guess would leave the test able to fail again while looking fixed.
//
//   - auto-gc, which git runs after commits and which DETACHES by default
//     (gc.autoDetach), outliving the command that triggered it;
//   - scheduled background maintenance;
//   - the fsmonitor daemon, which watches the working tree and is enabled by
//     CONFIG — meaning a runner's global git config can switch it on for repos
//     that never asked for it.
//
// That last one is why this also isolates global and system config. A test
// harness that inherits the machine's git configuration is not reproducible: it
// behaves differently on a developer's laptop, on a runner, and on the next
// runner. Isolating it removes an entire class of "green here, red there"
// before anyone has to debug an instance of it.
package testgit

import "os"

// isolation is applied to EVERY git invocation as command-line -c flags rather
// than repo config, because it must also cover `git init` — which runs before
// any repo config exists to be read.
var isolation = []string{
	// No auto-gc. This is the spawner most likely to outlive its command.
	"-c", "gc.auto=0",
	// And if some path runs gc anyway, it must not detach — a foreground gc
	// finishes before the command returns, so it cannot race the cleanup.
	"-c", "gc.autoDetach=false",
	// No scheduled background maintenance.
	"-c", "maintenance.auto=false",
	// No filesystem-watching daemon for a directory that exists for one test.
	"-c", "core.fsmonitor=false",
	// Signing is a host-config leak that fails a fixture for a reason having
	// nothing to do with the test: a developer with commit.gpgsign=true would
	// see every git fixture fail on a missing key.
	"-c", "commit.gpgsign=false",
	"-c", "tag.gpgsign=false",
	// A deterministic branch name. Without this the fixture's branch depends on
	// the machine's init.defaultBranch, which is exactly the kind of ambient
	// difference that makes a test pass locally and fail elsewhere.
	//
	// It is "master" because that is THIS PROJECT's default branch, and fixtures
	// that hardcode a branch name hardcode that one. Pinning "main" here was the
	// first thing tried and it reddened two tests immediately — the isolation
	// should make the project's own convention deterministic, not substitute a
	// different convention for the machine's.
	"-c", "init.defaultBranch=master",
}

// Args prepends the isolation flags to a git argument list.
//
//	exec.Command("git", testgit.Args(args...)...)
func Args(args ...string) []string {
	out := make([]string, 0, len(isolation)+len(args))
	out = append(out, isolation...)
	return append(out, args...)
}

// Env returns the environment for a test git invocation: the host environment,
// a fixed committer identity, and global/system config switched OFF.
//
// The identity is set here rather than left to the machine because a runner
// with no user.email configured fails `git commit` outright — and because a
// fixture's commits should not carry whoever happened to run the suite.
func Env() []string {
	return append(os.Environ(),
		"GIT_AUTHOR_NAME=test", "GIT_AUTHOR_EMAIL=test@example.com",
		"GIT_COMMITTER_NAME=test", "GIT_COMMITTER_EMAIL=test@example.com",
		// /dev/null is a readable, empty config file — git reads it and finds
		// nothing, which is exactly the intent. (Git 2.32+.)
		"GIT_CONFIG_GLOBAL=/dev/null",
		"GIT_CONFIG_SYSTEM=/dev/null",
		// Never block a test on an interactive prompt: a fixture that asks for
		// credentials hangs the suite instead of failing it.
		"GIT_TERMINAL_PROMPT=0",
	)
}
