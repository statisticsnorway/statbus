package release

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
)

// STATBUS-352 C3: the box-command policy closure.
//
// WHAT IS NAMED, HONESTLY. The closure derived here is the dependency set of
// ORDINARY `./cmd` (the commands that run on a box: install, upgrade,
// migrate, config, ...), NOT the complete `sb` executable. The release
// engine (cmd/release, internal/release) is in the same binary but, since
// the C1/C2 extraction, is provably unreachable from ordinary cmd
// (architecture_test.go pins `go list -deps ./cmd` never contains either).
// A change confined to release tooling therefore cannot change what a box
// executes, and need not invalidate box-behaviour evidence. A change to any
// package ordinary cmd DOES reach is box payload.
//
// This is an OPTIMIZER. Every failure mode (git archive error, old
// toolchain, module cache miss, parse error, missing boundary) returns an
// error, which the coverage evaluator turns into "undecidable": the scenario
// must run and coverage-question-health goes red. It never returns a
// smaller closure than the truth, and never returns covered.

// cliRoot is the module directory the closure is derived for.
const cliRoot = "cli"

// cliBuildInputs are files outside any package directory that still shape
// the binary. Always box payload, at every commit.
var cliBuildInputs = []string{
	"cli/main.go",
	"cli/go.mod",
	"cli/go.sum",
	"cli/Dockerfile",
	"cli/Dockerfile.sb",
	"cli/Makefile",
}

// boxCommandBoundaryMarker is the file whose presence at a commit proves the
// C1 extraction has happened there. Before it, cmd and the release engine
// were one package and the closure is undefined: the whole cli/ tree stays
// box payload, exactly as before this optimizer existed.
const boxCommandBoundaryMarker = "cli/cmd/release/command.go"

// BoxCommandClosure is the derived policy closure at one commit.
type BoxCommandClosure struct {
	Commit string
	// Dirs are repository-relative package directories (no trailing slash)
	// that ordinary cmd reaches, plus cliBuildInputs as exact paths in Files.
	Dirs  []string
	Files []string
	// Broad is true when the boundary did not exist at this commit, so the
	// whole cli/ tree must be treated as payload.
	Broad bool
}

var (
	closureCacheMu sync.Mutex
	closureCache   = map[string]cachedClosure{}
)

type cachedClosure struct {
	closure BoxCommandClosure
	err     error
}

// BoxCommandClosureAt derives (and memoizes per commit) the closure. The
// source tree is materialised with `git archive` into a temp dir that is
// removed before return; the working tree is never read or mutated.
func BoxCommandClosureAt(projDir, commit string) (BoxCommandClosure, error) {
	if commit == "" {
		return BoxCommandClosure{}, fmt.Errorf("box-command closure needs a commit")
	}
	closureCacheMu.Lock()
	if c, ok := closureCache[commit]; ok {
		closureCacheMu.Unlock()
		return c.closure, c.err
	}
	closureCacheMu.Unlock()

	closure, err := deriveBoxCommandClosure(projDir, commit)

	closureCacheMu.Lock()
	closureCache[commit] = cachedClosure{closure, err}
	closureCacheMu.Unlock()
	return closure, err
}

func deriveBoxCommandClosure(projDir, commit string) (BoxCommandClosure, error) {
	closure := BoxCommandClosure{Commit: commit, Files: append([]string(nil), cliBuildInputs...)}

	// Boundary present at this commit? A tree read, cheap, and decisive.
	if _, err := gitShow(projDir, commit, boxCommandBoundaryMarker); err != nil {
		closure.Broad = true
		return closure, nil
	}

	tmp, err := os.MkdirTemp("", "statbus-box-closure-")
	if err != nil {
		return BoxCommandClosure{}, fmt.Errorf("create a disposable extraction dir: %w", err)
	}
	defer func() { _ = os.RemoveAll(tmp) }()

	if err := extractTree(projDir, commit, cliRoot, tmp); err != nil {
		return BoxCommandClosure{}, err
	}

	module, err := goListModulePath(filepath.Join(tmp, cliRoot))
	if err != nil {
		return BoxCommandClosure{}, err
	}

	cmd := exec.Command("go", "list", "-deps", "-f", "{{.ImportPath}}", "./cmd")
	cmd.Dir = filepath.Join(tmp, cliRoot)
	// GOFLAGS=-mod=mod would download; we want the opposite. Fail loudly on
	// a missing module rather than reaching the network from a gate.
	cmd.Env = append(os.Environ(), "GOFLAGS=-mod=readonly", "GOPROXY=off", "GIT_TERMINAL_PROMPT=0")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return BoxCommandClosure{}, fmt.Errorf("go list -deps ./cmd at %s: %w\n%s", shortSHA(commit), err, strings.TrimSpace(stderr.String()))
	}

	prefix := module + "/"
	seen := map[string]bool{}
	for _, line := range strings.Split(strings.TrimSpace(stdout.String()), "\n") {
		ip := strings.TrimSpace(line)
		if ip == "" || !strings.HasPrefix(ip, prefix) {
			continue // stdlib or third-party: covered by go.mod/go.sum
		}
		dir := cliRoot + "/" + strings.TrimPrefix(ip, prefix)
		if !seen[dir] {
			seen[dir] = true
			closure.Dirs = append(closure.Dirs, dir)
		}
	}
	if len(closure.Dirs) == 0 {
		return BoxCommandClosure{}, fmt.Errorf("go list -deps ./cmd at %s reported no module-local packages — refusing an empty closure", shortSHA(commit))
	}
	for _, forbidden := range []string{cliRoot + "/cmd/release", cliRoot + "/internal/release"} {
		if seen[forbidden] {
			return BoxCommandClosure{}, fmt.Errorf("ordinary cmd reaches %s at %s — the policy boundary is broken at that commit; refusing to narrow", forbidden, shortSHA(commit))
		}
	}
	sort.Strings(closure.Dirs)
	return closure, nil
}

func goListModulePath(dir string) (string, error) {
	cmd := exec.Command("go", "list", "-m")
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GOFLAGS=-mod=readonly", "GOPROXY=off")
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("go list -m in %s: %w", dir, err)
	}
	return strings.TrimSpace(string(out)), nil
}

// extractTree materialises commit:<subtree> under dest via git archive|tar.
func extractTree(projDir, commit, subtree, dest string) error {
	archive := exec.Command("git", "archive", "--format=tar", commit, "--", subtree)
	archive.Dir = projDir
	archive.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	var archiveErr bytes.Buffer
	archive.Stderr = &archiveErr
	untar := exec.Command("tar", "-x", "-C", dest)
	var untarErr bytes.Buffer
	untar.Stderr = &untarErr
	pipe, err := archive.StdoutPipe()
	if err != nil {
		return fmt.Errorf("git archive pipe: %w", err)
	}
	untar.Stdin = pipe
	if err := untar.Start(); err != nil {
		return fmt.Errorf("start tar: %w", err)
	}
	if err := archive.Run(); err != nil {
		_ = untar.Wait()
		return fmt.Errorf("git archive %s -- %s: %w: %s", shortSHA(commit), subtree, err, strings.TrimSpace(archiveErr.String()))
	}
	if err := untar.Wait(); err != nil {
		return fmt.Errorf("extract %s -- %s: %w: %s", shortSHA(commit), subtree, err, strings.TrimSpace(untarErr.String()))
	}
	return nil
}

// boxPayloadRulesForRange returns the cli/ payload rules for a coverage
// decision from anchor A to target T: the UNION of both closures, so a
// dependency deleted or renamed between them cannot vanish from
// sensitivity. If either commit predates the boundary the answer is the
// single broad `directory | box payload | cli` rule, which is what the
// checked-in policy expressed before this optimizer.
func boxPayloadRulesForRange(projDir, anchor, target string) ([]sensitivityRule, error) {
	a, err := BoxCommandClosureAt(projDir, anchor)
	if err != nil {
		return nil, fmt.Errorf("box-command closure at anchor %s: %w", shortSHA(anchor), err)
	}
	t, err := BoxCommandClosureAt(projDir, target)
	if err != nil {
		return nil, fmt.Errorf("box-command closure at target %s: %w", shortSHA(target), err)
	}
	if a.Broad || t.Broad {
		return []sensitivityRule{{Kind: matchDirectory, Path: cliRoot, Reason: ReasonBoxPayload}}, nil
	}
	seen := map[sensitivityRule]bool{}
	var rules []sensitivityRule
	add := func(r sensitivityRule) {
		if !seen[r] {
			seen[r] = true
			rules = append(rules, r)
		}
	}
	for _, c := range []BoxCommandClosure{a, t} {
		for _, d := range c.Dirs {
			add(sensitivityRule{Kind: matchDirectory, Path: d, Reason: ReasonBoxPayload})
		}
		for _, f := range c.Files {
			add(sensitivityRule{Kind: matchExact, Path: f, Reason: ReasonBoxPayload})
		}
	}
	return rules, nil
}
