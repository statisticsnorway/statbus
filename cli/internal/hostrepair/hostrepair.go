// Package hostrepair makes host directories exist and be writable by the
// install/service user, without sudo. Docker's daemon creates a missing
// bind-mount source as ROOT (caddy/docker-compose.yml's mounts are the known
// cases), and the statbus user cannot chown it back — only a root process
// can. The repair therefore runs as root inside one throwaway container with
// the directory's parent bind-mounted, the same escape hatch the installer
// already uses for backup ownership (healBackupOwnership) and STATBUS-429's
// cert install uses for caddy/data/custom-certs.
//
// Generalized for STATBUS-431: the upgrade daemon must be able to write its
// maintenance flag even on boxes installed by v2026.09.x installers, whose
// Settings step was silently skipped on every fresh install since
// 2026-09-24/25 (checkEnvDone became true as soon as Credentials generated
// .env), leaving ~/statbus-maintenance for Docker to create as root.
package hostrepair

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
	"github.com/statisticsnorway/statbus/cli/internal/dotenv"
)

// FallbackImage is the image RepairViaContainer falls back to when the box's
// own proxy image is unavailable locally. Pinned to an exact digest-free tag
// (STATBUS-429 R1) rather than a bare "alpine" so the repair does not depend
// on whatever "latest" resolves to on the day it runs, and matches the same
// alpine release uninstall.sh already pins for its own throwaway containers.
const FallbackImage = "alpine:3.20"

// Writable reports whether the current user can actually create a file in
// dir, by creating and removing one. This is a real write probe, not an
// inference from MkdirAll's return value: MkdirAll succeeds on an existing
// directory regardless of who owns it (STATBUS-429 M2), so it cannot tell
// "already there and mine" apart from "already there, root's, and
// permission-denied on every write inside it".
func Writable(dir string) bool {
	f, err := os.CreateTemp(dir, ".writable-probe-*")
	if err != nil {
		return false
	}
	name := f.Name()
	_ = f.Close()
	_ = os.Remove(name)
	return true
}

// PreferredProxyImage returns the fully-qualified proxy image tag for the
// checkout's currently-installed commit (read from .env's COMMIT_SHORT), or
// "" if .env cannot be read or COMMIT_SHORT is unset. This image is present
// on any box that could possibly need the repair, because a host directory
// only becomes root-owned once a container from this checkout has already
// started against it.
func PreferredProxyImage(projDir string) string {
	f, err := dotenv.Load(filepath.Join(projDir, ".env"))
	if err != nil {
		return ""
	}
	commitShort, _ := f.Get("COMMIT_SHORT")
	if commitShort == "" {
		return ""
	}
	return "ghcr.io/statisticsnorway/statbus-proxy:" + commitShort
}

// dockerRun is the seam the fake-docker PATH tests observe. It runs
// `docker run` with the given image, mounting mountDir at /data, executing
// shellCmd with sh -c. pullNever is set for the preferred (already-local)
// image so a missing image fails fast instead of reaching the network.
var dockerRun = func(mountDir, shellCmd, image string, pullNever bool) ([]byte, error) {
	args := []string{"run", "--rm", "--network", "none"}
	if pullNever {
		args = append(args, "--pull=never")
	}
	args = append(args, "-v", mountDir+":/data", image, "sh", "-c", shellCmd)
	cmd, buildErr := compose.DockerCommandContext(context.Background(), "", args...)
	if buildErr != nil {
		return nil, fmt.Errorf("construct docker ownership repair: %w", buildErr)
	}
	return cmd.CombinedOutput()
}

// shellWord renders s as a shell word: bare when it is a plain portable name
// (the product constants statbus-maintenance, statbus-backups, custom-certs —
// keeping the STATBUS-429 R2 pinned argv byte-identical), single-quoted
// otherwise. Never interpolate an unquoted unsafe name into a root shell.
func shellWord(s string) string {
	if s != "" && strings.IndexFunc(s, func(r rune) bool {
		return !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_' || r == '.')
	}) == -1 {
		return s
	}
	return "'" + strings.ReplaceAll(s, `'`, `'\''`) + `'` // '
}

// RepairViaContainer makes dir exist, owner-writable and owned by the current
// uid:gid, by running one throwaway container as root with dir's PARENT
// bind-mounted at /data. Deliberately NOT recursive over the parent: the
// parent may hold sibling state that must stay exactly as it is (e.g.
// caddy/data/caddy/ holds Caddy's own ACME state).
//
// Prefers the box's own proxy image (present whenever this repair can be
// needed, because the directory is only root-owned BECAUSE a container ran)
// with --pull=never so a missing image fails fast instead of reaching the
// network. Falls back to FallbackImage when the proxy image is unavailable
// locally, mirroring uninstall.sh's preferred-image-with-fallback pattern.
// This matters on boxes whose egress allowlist admits the image registry
// (ghcr.io, where StatBus images already came from) but not Docker Hub.
//
// --network none: the repair never needs the network; keeping it off is
// defense in depth.
func RepairViaContainer(projDir, dir string) ([]byte, error) {
	parent := filepath.Dir(dir)
	base := shellWord(filepath.Base(dir))
	shellCmd := fmt.Sprintf(
		"mkdir -p /data/%[1]s && chmod u+rwx /data/%[1]s && chown %d:%d /data/%[1]s",
		base, os.Getuid(), os.Getgid(),
	)
	if image := PreferredProxyImage(projDir); image != "" {
		if out, err := dockerRun(parent, shellCmd, image, true); err == nil {
			return out, nil
		}
		// Falls through to the alpine fallback — the proxy image name was
		// constructed from .env's COMMIT_SHORT but may not actually be present
		// locally (e.g. pruned, or a fresh checkout whose proxy never started).
	}
	return dockerRun(parent, shellCmd, FallbackImage, false)
}

// EnsureWritable makes dir exist and be writable by the current user WITHOUT
// sudo. Two disjoint triggers, mirroring the STATBUS-429 cert path:
//   - dir (or its parent) does not exist yet: plain os.MkdirAll succeeds,
//     creating it as the current user, and the write probe passes. Docker
//     never rechowns a pre-existing mount source, so this ownership is
//     permanent.
//   - dir already exists but is not writable by us (root-owned from an
//     earlier container start, OR a prior manual `sudo mkdir`): the current
//     user cannot chown it directly, so RepairViaContainer does it as root.
//
// Idempotent: MkdirAll on an existing dir, and chown to the same uid:gid,
// are both no-ops. Never claims success without a post-repair re-probe: the
// repair container itself can exit 0 while still leaving the directory
// unwritable (STATBUS-429 R-b).
func EnsureWritable(projDir, dir string) error {
	mkdirErr := os.MkdirAll(dir, 0o755)
	if mkdirErr != nil && !os.IsPermission(mkdirErr) {
		return fmt.Errorf("create dir %s: %w", dir, mkdirErr)
	}
	if mkdirErr == nil && Writable(dir) {
		return nil
	}
	out, err := RepairViaContainer(projDir, dir)
	if err != nil {
		return &NotWritableError{Dir: dir, Reason: "Docker could not run the repair container", DockerErr: err, DockerOutput: out}
	}
	if !Writable(dir) {
		return &NotWritableError{Dir: dir, Reason: "the repair ran but the directory is still not writable", DockerErr: fmt.Errorf("repair container exited 0 but %s is still not writable", dir), DockerOutput: out}
	}
	return nil
}

// NotWritableError is returned when the Docker ownership repair itself fails
// (Docker unavailable, denied, or the repair container errors). Its Error()
// is a plain operator sentence naming the exact next step (STATBUS-429 M3) —
// never a bare "exit status N" — with the raw Docker output kept as trailing
// detail for support bundles.
type NotWritableError struct {
	Dir          string
	Reason       string // why the automatic repair did not help, in plain words
	DockerErr    error
	DockerOutput []byte
}

// Error puts the fix first: the one administrator command, then the raw
// repair detail for support.
func (e *NotWritableError) Error() string {
	return fmt.Sprintf(
		"%s is not writable by this user, and StatBus could not repair it automatically: %s.\n"+
			"An administrator can fix it once with:\n"+
			"  sudo install -d -o %d -g %d %s\n"+
			"Repair container detail: %v\n%s",
		e.Dir, e.Reason, os.Getuid(), os.Getgid(), e.Dir, e.DockerErr, e.DockerOutput,
	)
}

func (e *NotWritableError) Unwrap() error { return e.DockerErr }
