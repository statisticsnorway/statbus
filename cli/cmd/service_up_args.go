package cmd

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
)

// dockerImageOps is the injectable seam behind the release-build image check
// (STATBUS-392, doc/sb-build-identity.md). Tests substitute a fake; production
// uses liveDockerImageOps.
type dockerImageOps interface {
	// Images lists the image references this version's compose model expects
	// for the profile.
	Images(dir, profile string) ([]string, error)
	// Present reports whether the image exists locally. The check is cheap
	// and never touches the network.
	Present(dir, image string) (bool, error)
	// Pull pulls the profile's images from the registry.
	Pull(dir, profile string) error
}

type liveDockerImageOps struct{}

func (liveDockerImageOps) Images(dir, profile string) ([]string, error) {
	args := []string{}
	if profile != "app" {
		args = append(args, "--profile", profile)
	}
	args = append(args, "config", "--images")
	if profile == "app" {
		args = append(args, "app")
	}
	cmd, err := compose.CommandContext(context.Background(), dir, args...)
	if err != nil {
		return nil, err
	}
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("docker compose config --images: %w (%s)", err, strings.TrimSpace(stderr.String()))
	}
	images := []string{}
	for _, line := range strings.Split(string(out), "\n") {
		if line = strings.TrimSpace(line); line != "" {
			images = append(images, line)
		}
	}
	return images, nil
}

func (liveDockerImageOps) Present(dir, image string) (bool, error) {
	cmd, err := compose.DockerCommandContext(context.Background(), dir, "image", "inspect", image)
	if err != nil {
		return false, err
	}
	if err := cmd.Run(); err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			// docker answered: the image is not on the box.
			return false, nil
		}
		return false, fmt.Errorf("docker image inspect %s: %w", image, err)
	}
	return true, nil
}

func (liveDockerImageOps) Pull(dir, profile string) error {
	args := []string{"pull"}
	if profile == "app" {
		args = append(args, "app")
	} else {
		args = append([]string{"--profile", profile}, args...)
	}
	cmd, err := compose.CommandContext(context.Background(), dir, args...)
	if err != nil {
		return err
	}
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// startUpArgs is the docker compose up invocation for ./sb start.
func startUpArgs(dir, profile string, release bool, version string, docker dockerImageOps, out io.Writer) ([]string, error) {
	return composeUpArgsForBuild(dir, profile, []string{"-d"}, release, version, docker, out)
}

// restartUpArgs is the docker compose up invocation that brings a profile back
// after ./sb restart's stop. It waits for health, unlike ./sb start, and
// follows the same build-identity rule.
func restartUpArgs(dir, profile string, release bool, version string, docker dockerImageOps, out io.Writer) ([]string, error) {
	return composeUpArgsForBuild(dir, profile, []string{"-d", "--wait", "--wait-timeout", "120"}, release, version, docker, out)
}

// composeUpArgsForBuild decides the build flag from the binary's build
// identity (doc/sb-build-identity.md):
//
//   - source build: --build, so a code change shows up after ./sb start.
//   - release build: check locally (no network) that this version's images
//     exist. All present (the normal case): --no-build. Any missing (only
//     after a deliberate prune or disk clean-up): say why, pull, then
//     --no-build. A failed pull stops with the remedy.
func composeUpArgsForBuild(dir, profile string, base []string, release bool, version string, docker dockerImageOps, out io.Writer) ([]string, error) {
	args := append([]string{}, base...)
	if !release {
		args = append(args, "--build")
	} else {
		images, err := docker.Images(dir, profile)
		if err != nil {
			return nil, fmt.Errorf("list the images for %s: %w", version, err)
		}
		missing := []string{}
		for _, image := range images {
			present, err := docker.Present(dir, image)
			if err != nil {
				return nil, err
			}
			if !present {
				missing = append(missing, image)
			}
		}
		if len(missing) > 0 {
			// The message explains why a start suddenly pulls; a failed write
			// must not stop the pull itself.
			_, _ = fmt.Fprintf(out, "Images for %s were missing locally (removed by a prune?); pulling them, then starting.\n", version)
			if err := docker.Pull(dir, profile); err != nil {
				return nil, fmt.Errorf("could not pull the images for %s: %w\n"+
					"Check the network and run the command again, or build locally with ./sb build", version, err)
			}
		}
		args = append(args, "--no-build")
	}
	if profile == "app" {
		return append(args, "app"), nil
	}
	return append([]string{"--profile", profile}, args...), nil
}
