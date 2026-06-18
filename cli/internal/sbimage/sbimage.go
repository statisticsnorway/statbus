// Package sbimage procures the `sb` binary for a given commit from the
// commit-tagged statbus-sb container image — TOOLCHAIN-FREE. It is the single
// shared primitive behind every place that needs to materialise ./sb without a
// host Go/make toolchain:
//
//   - install.sh --channel edge (bash; the behavioural reference, install.sh:198-211)
//   - upgrade.Service.procureSbFromImage (the upgrade pipeline's binary swap)
//   - freshness.RebuildAndReexec (the stalenessGuard self-heal)
//
// Before this package the self-heal path shelled out to `make -C cli build`
// (host `go build`), which fails on a no-host-Go box — the production shape of
// SSB's standalone deployments (e.g. Albania) and every install-recovery VM —
// with `make: go: command not found` → exit 2. Procurement via Docker removes
// the host-toolchain assumption entirely: golang runs INSIDE the container.
//
// Procurement strategy (mirrors install.sh edge + procureSbFromImage):
//  1. `docker pull ghcr.io/statisticsnorway/statbus-sb:<commit_short>` — every
//     master push builds and pushes this image (.github/workflows/images.yaml);
//     image-cleanup.yaml keeps tagged versions, so it persists.
//  2. On a pull MISS (an UNPUSHED local commit) → build it in-container via
//     cli/Dockerfile.sb. This is GATED: we build only when the working tree is
//     already AT the target commit, so the build context (./cli) is the target's
//     source. Otherwise we refuse rather than stamp the target identity onto a
//     binary compiled from a different commit's source.
//  3. `docker create` + `docker cp <cid>:/sb <sbPath>` + `docker rm` + chmod.
package sbimage

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"
)

// ImageRepo is the GHCR repository carrying the commit-tagged sb binary images.
const ImageRepo = "ghcr.io/statisticsnorway/statbus-sb"

// perCommandTimeout bounds each docker/git subprocess. A cold-cache in-container
// build is the slowest step (~minutes on first build, seconds cached); a pull is
// network-bound. 10m is generous headroom while still guaranteeing forward
// progress instead of a hang. Replaces the 5-minute budget the old `make`
// self-heal carried (freshness/rebuild.go).
const perCommandTimeout = 10 * time.Minute

// Procure replaces the binary at sbPath with the statbus-sb binary for
// commitSHA. commitSHA is a real (full or unambiguous) commit ref resolvable by
// `git rev-parse`; the commit_short image tag is derived from it. This is the
// entrypoint for the freshness self-heal, where commitSHA is the worktree HEAD
// (the commit the stale binary must match).
func Procure(projDir, commitSHA, sbPath string) error {
	if strings.TrimSpace(commitSHA) == "" {
		return fmt.Errorf("sbimage.Procure: empty commitSHA — no image tag to resolve")
	}
	short, err := capture(projDir, "git", "rev-parse", "--short=8", commitSHA)
	if err != nil {
		return fmt.Errorf("resolve commit_short for %q: %w (%s)", commitSHA, err, short)
	}
	return ProcureShort(projDir, strings.TrimSpace(short), commitSHA, sbPath)
}

// ProcureShort is the core procurement step. `short` is the 8-char commit_short
// used as the image tag; `commitSHA` (full, MAY be empty) feeds the in-container
// build's COMMIT build-arg when the pull misses. Exposed directly so the upgrade
// service can keep its own commit_short resolution (which also accepts an 8-char
// displayName when no full SHA is available) and still share this body.
func ProcureShort(projDir, short, commitSHA, sbPath string) error {
	short = strings.TrimSpace(strings.ToLower(short))
	if short == "" {
		return fmt.Errorf("sbimage.ProcureShort: empty commit_short — cannot resolve the statbus-sb image tag")
	}
	imageRef := ImageRepo + ":" + short
	if err := pullOrBuild(projDir, imageRef, short, commitSHA); err != nil {
		return err
	}
	return extract(projDir, imageRef, sbPath)
}

// pullOrBuild pulls imageRef; on a miss it falls back to an in-container build
// via cli/Dockerfile.sb. The fallback is GATED on the working tree being AT the
// target commit (HEAD short == `short`): the build context is the current ./cli
// tree, so building when the tree is at a DIFFERENT commit would compile the
// wrong source while stamping the target's identity via build-args. In the
// upgrade pipeline this guard means a pre-checkout call simply errors out (same
// outcome as the old pull-only path); the self-heal path always satisfies it
// because its target IS the worktree HEAD.
func pullOrBuild(projDir, imageRef, short, commitSHA string) error {
	fmt.Fprintf(os.Stderr, "Pulling sb image %s...\n", imageRef)
	pullOut, pullErr := stream(projDir, "docker", "pull", imageRef)
	if pullErr == nil {
		return nil
	}

	// Pull miss → consider the in-container build fallback.
	headFull, headErr := capture(projDir, "git", "rev-parse", "HEAD")
	headShort, headShortErr := capture(projDir, "git", "rev-parse", "--short=8", "HEAD")
	if headErr != nil || headShortErr != nil {
		return fmt.Errorf("pull sb image %s failed (%v: %s) and cannot resolve worktree HEAD to attempt an in-container build: head=%v headShort=%v",
			imageRef, pullErr, strings.TrimSpace(pullOut), headErr, headShortErr)
	}
	if strings.TrimSpace(strings.ToLower(headShort)) != short {
		return fmt.Errorf("no published image %s and the working tree is at %s, not %s — "+
			"refusing to build a mislabeled binary from non-target source; "+
			"publish the image, or check out %s before procuring",
			imageRef, strings.TrimSpace(headShort), short, short)
	}

	full := strings.TrimSpace(commitSHA)
	if full == "" {
		full = strings.TrimSpace(headFull)
	}
	fmt.Fprintf(os.Stderr, "  no published image for %s — building locally via cli/Dockerfile.sb (golang runs in-container; no host Go)...\n", short)
	if buildOut, buildErr := stream(projDir, "docker", "build",
		"-f", "cli/Dockerfile.sb",
		"--build-arg", "VERSION="+short,
		"--build-arg", "COMMIT="+full,
		"-t", imageRef,
		"./cli",
	); buildErr != nil {
		return fmt.Errorf("pull sb image %s failed (%v: %s) AND in-container build failed: %w (%s)",
			imageRef, pullErr, strings.TrimSpace(pullOut), buildErr, strings.TrimSpace(buildOut))
	}
	return nil
}

// extract records the image's ENTRYPOINT into a stopped container (docker
// create runs nothing), copies /sb out, removes the container, and makes the
// binary executable. Mirrors `./sb db seed fetch` (cli/cmd/seed.go) and the
// original procureSbFromImage.
func extract(projDir, imageRef, sbPath string) error {
	out, err := capture(projDir, "docker", "create", imageRef)
	if err != nil {
		return fmt.Errorf("docker create %s: %w (%s)", imageRef, err, strings.TrimSpace(out))
	}
	cid := strings.TrimSpace(out)
	if cid == "" {
		return fmt.Errorf("docker create %s returned an empty container id", imageRef)
	}
	defer func() {
		if rmOut, rmErr := capture(projDir, "docker", "rm", cid); rmErr != nil {
			fmt.Fprintf(os.Stderr, "WARN: docker rm %s (sb extraction container) failed: %v (%s)\n", cid, rmErr, strings.TrimSpace(rmOut))
		}
	}()

	if cpOut, cpErr := capture(projDir, "docker", "cp", cid+":/sb", sbPath); cpErr != nil {
		return fmt.Errorf("docker cp %s:/sb -> %s: %w (%s)", cid, sbPath, cpErr, strings.TrimSpace(cpOut))
	}
	if err := os.Chmod(sbPath, 0o755); err != nil {
		return fmt.Errorf("chmod +x %s after image extraction: %w", sbPath, err)
	}
	return nil
}

// capture runs a short command quietly and returns its combined output. Used
// for git rev-parse and docker create/cp/rm, whose output is small and only
// surfaced in error messages.
func capture(dir, name string, args ...string) (string, error) {
	return run(dir, false, name, args...)
}

// stream runs a long command (docker pull/build), tee-ing its output to
// os.Stderr so the operator sees progress during a self-heal AND the daemon
// journal captures it, while still returning the captured output for error
// tails. Replaces the streamed `make` build output of the old self-heal.
func stream(dir, name string, args ...string) (string, error) {
	return run(dir, true, name, args...)
}

// run executes name+args in dir with a per-command timeout. When toStderr is
// true the child's stdout/stderr also stream to os.Stderr. Mirrors the upgrade
// package's gitArgs (disable log.showSignature so a globally-configured
// commit-signature banner cannot corrupt parsed git output) and prepareCmd
// (own process group + SIGKILL-on-cancel so docker's children die on timeout
// rather than holding pipes open — Go issue #59055).
func run(dir string, toStderr bool, name string, args ...string) (string, error) {
	if name == "git" {
		args = append([]string{"-c", "log.showSignature=false"}, args...)
	}
	ctx, cancel := context.WithTimeout(context.Background(), perCommandTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir = dir

	var buf bytes.Buffer
	if toStderr {
		cmd.Stdout = io.MultiWriter(os.Stderr, &buf)
		cmd.Stderr = io.MultiWriter(os.Stderr, &buf)
	} else {
		cmd.Stdout = &buf
		cmd.Stderr = &buf
	}

	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.WaitDelay = 10 * time.Second
	cmd.Cancel = func() error {
		if cmd.Process != nil {
			return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		}
		return nil
	}

	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return buf.String(), fmt.Errorf("%s %v timed out after %s", name, args, perCommandTimeout)
	}
	return buf.String(), err
}
