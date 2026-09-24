package livedbtest

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

const (
	projectDirEnv = "STATBUS_LIVEDB_PROJECT_DIR"
	pinnedSBEnv   = "STATBUS_LIVEDB_PINNED_SB"
)

// Setup creates one detached scratch worktree and one identity-bearing sb binary
// for a live-database test package. Helper subprocesses inherit the two env vars
// and reuse the exact same fixture without reacquiring the cross-package lock.
func Setup(packageName string) (cleanup func(), err error) {
	if os.Getenv(projectDirEnv) != "" && os.Getenv(pinnedSBEnv) != "" {
		return func() {}, nil
	}

	realRoot, err := findProjectRoot()
	if err != nil {
		return nil, err
	}
	lockPath := filepath.Join(realRoot, "tmp", "live-database-tests.lock")
	if err := os.MkdirAll(filepath.Dir(lockPath), 0o755); err != nil {
		return nil, fmt.Errorf("create live-database lock directory: %w", err)
	}
	lock, err := os.OpenFile(lockPath, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, fmt.Errorf("open live-database package lock: %w", err)
	}
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		_ = lock.Close()
		return nil, fmt.Errorf("lock live-database package fixture: %w", err)
	}

	fixtureRoot, err := os.MkdirTemp("", "statbus-livedb-"+packageName+"-")
	if err != nil {
		_ = lock.Close()
		return nil, fmt.Errorf("create live-database fixture root: %w", err)
	}
	projectDir := filepath.Join(fixtureRoot, "project")
	// pg_regress provisions statbus_seed, not POSTGRES_APP_DB. On CI the app
	// database lacks public.upgrade, while local app databases may contain
	// unrelated upgrade state. Clone the migrated seed for this package.
	fixtureDB := "statbus_livedb_" + strconv.Itoa(os.Getpid())
	createdDB := false
	cleanup = func() {
		if createdDB {
			_, _ = run(projectDir, filepath.Join(projectDir, "sb"), "psql", "-d", "postgres", "-c", "DROP DATABASE "+fixtureDB+" WITH (FORCE)")
		}
		cmd := exec.Command("git", "-C", realRoot, "worktree", "remove", "--force", projectDir)
		_ = cmd.Run()
		_ = os.RemoveAll(fixtureRoot)
		_ = lock.Close()
	}
	fail := func(format string, args ...any) (func(), error) {
		cleanup()
		return nil, fmt.Errorf(format, args...)
	}

	if out, cmdErr := run(realRoot, "git", "worktree", "add", "--detach", projectDir, "HEAD"); cmdErr != nil {
		return fail("create detached live-database worktree: %v: %s", cmdErr, out)
	}
	configRoot := realRoot
	if _, statErr := os.Stat(filepath.Join(configRoot, ".env.config")); os.IsNotExist(statErr) {
		worktrees, listErr := run(realRoot, "git", "worktree", "list", "--porcelain")
		if listErr != nil {
			return fail("list worktrees for local config: %v: %s", listErr, worktrees)
		}
		var candidate string
		for _, line := range strings.Split(worktrees, "\n") {
			if strings.HasPrefix(line, "worktree ") {
				candidate = strings.TrimPrefix(line, "worktree ")
				continue
			}
			if line == "branch refs/heads/master" && candidate != "" {
				configRoot = candidate
				break
			}
		}
	}
	for _, name := range []string{".env.config", ".env.credentials"} {
		source := filepath.Join(configRoot, name)
		if _, statErr := os.Stat(source); statErr == nil {
			mode := os.FileMode(0o600)
			if name == ".env.config" {
				mode = 0o644
			}
			if copyErr := copyFile(source, filepath.Join(projectDir, name), mode); copyErr != nil {
				return fail("copy %s: %v", name, copyErr)
			}
		} else if !os.IsNotExist(statErr) {
			return fail("stat %s: %v", name, statErr)
		}
	}

	versionOut, cmdErr := run(projectDir, "git", "describe", "--tags", "--always", "--match", "v[0-9]*")
	if cmdErr != nil {
		versionOut = "dev"
	}
	commitOut, cmdErr := run(projectDir, "git", "rev-parse", "HEAD")
	if cmdErr != nil {
		return fail("resolve fixture commit: %v: %s", cmdErr, commitOut)
	}
	pinnedSB := filepath.Join(fixtureRoot, "pinned-sb")
	ldflags := fmt.Sprintf("-X 'github.com/statisticsnorway/statbus/cli/cmd.version=%s' -X 'github.com/statisticsnorway/statbus/cli/cmd.commit=%s'", strings.TrimSpace(versionOut), strings.TrimSpace(commitOut))
	if out, cmdErr := run(filepath.Join(projectDir, "cli"), "go", "build", "-ldflags", ldflags, "-o", pinnedSB, "."); cmdErr != nil {
		return fail("build pinned live-database sb: %v: %s", cmdErr, out)
	}
	if copyErr := copyFile(pinnedSB, filepath.Join(projectDir, "sb"), 0o755); copyErr != nil {
		return fail("install fixture sb: %v", copyErr)
	}
	if out, cmdErr := run(projectDir, filepath.Join(projectDir, "sb"), "config", "generate"); cmdErr != nil {
		return fail("generate fixture config: %v: %s", cmdErr, out)
	}
	if out, cmdErr := run(projectDir, filepath.Join(projectDir, "sb"), "psql", "-d", "postgres", "-c", "CREATE DATABASE "+fixtureDB+" TEMPLATE statbus_seed"); cmdErr != nil {
		return fail("clone migrated statbus_seed for live-database tests (run ./dev.sh migrate-and-test fast first): %v: %s", cmdErr, out)
	}
	createdDB = true
	if out, cmdErr := run(projectDir, filepath.Join(projectDir, "sb"), "dotenv", "-f", ".env", "set", "POSTGRES_APP_DB", fixtureDB); cmdErr != nil {
		return fail("point fixture at dedicated test database: %v: %s", cmdErr, out)
	}
	if out, cmdErr := run(projectDir, filepath.Join(projectDir, "sb"), "psql", "-d", fixtureDB, "-t", "-A", "-c", "SELECT to_regclass('public.upgrade'), max(version) FROM db.migration"); cmdErr != nil || !strings.HasPrefix(strings.TrimSpace(out), "upgrade|") {
		return fail("dedicated live-database fixture is not migrated: %v: %s", cmdErr, out)
	}

	if err := os.Setenv(projectDirEnv, projectDir); err != nil {
		return fail("set fixture project env: %v", err)
	}
	if err := os.Setenv(pinnedSBEnv, pinnedSB); err != nil {
		return fail("set pinned sb env: %v", err)
	}
	return cleanup, nil
}

func ProjectDir() string { return os.Getenv(projectDirEnv) }
func PinnedSB() string   { return os.Getenv(pinnedSBEnv) }

func findProjectRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "dev.sh")); err == nil {
			if _, err := os.Stat(filepath.Join(dir, "cli", "go.mod")); err == nil {
				return dir, nil
			}
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("project root not found above %s", dir)
		}
		dir = parent
	}
}

func run(dir, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

func copyFile(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer func() { _ = in.Close() }()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		_ = out.Close()
		return err
	}
	return out.Close()
}
