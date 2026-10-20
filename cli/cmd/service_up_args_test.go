package cmd

import (
	"bytes"
	"errors"
	"reflect"
	"strings"
	"testing"
)

// STATBUS-392: ./sb start and ./sb restart follow the binary's build identity
// (doc/sb-build-identity.md). A source build runs compose up with --build. A
// release build checks locally (no network) that this version's images exist,
// pulls them only when missing, and starts with --no-build; a failed pull
// stops with the remedy. Docker calls sit behind the dockerImageOps seam.

// fakeDockerImageOps records the docker calls the decision makes.
type fakeDockerImageOps struct {
	images    []string
	present   map[string]bool
	pullErr   error
	pulled    int
	inspected []string
}

func (f *fakeDockerImageOps) Images(dir, profile string) ([]string, error) {
	return f.images, nil
}

func (f *fakeDockerImageOps) Present(dir, image string) (bool, error) {
	f.inspected = append(f.inspected, image)
	return f.present[image], nil
}

func (f *fakeDockerImageOps) Pull(dir, profile string) error {
	f.pulled++
	return f.pullErr
}

var testServiceImages = []string{
	"ghcr.io/statisticsnorway/statbus-app:0fb37f20",
	"ghcr.io/statisticsnorway/statbus-worker:0fb37f20",
	"ghcr.io/statisticsnorway/statbus-db:0fb37f20",
	"ghcr.io/statisticsnorway/statbus-proxy:0fb37f20",
}

func imagesPresent(present ...string) map[string]bool {
	m := map[string]bool{}
	for _, image := range present {
		m[image] = true
	}
	return m
}

// upArgFuncs are the two entry points the decision must agree on.
func upArgFuncs() map[string]func(dir, profile string, release bool, version string, docker dockerImageOps, out *bytes.Buffer) ([]string, error) {
	return map[string]func(dir, profile string, release bool, version string, docker dockerImageOps, out *bytes.Buffer) ([]string, error){
		"start": func(dir, profile string, release bool, version string, docker dockerImageOps, out *bytes.Buffer) ([]string, error) {
			return startUpArgs(dir, profile, release, version, docker, out)
		},
		"restart": func(dir, profile string, release bool, version string, docker dockerImageOps, out *bytes.Buffer) ([]string, error) {
			return restartUpArgs(dir, profile, release, version, docker, out)
		},
	}
}

func TestUpArgsSourceBuild_STATBUS392(t *testing.T) {
	wantBase := map[string][]string{
		"start":   {"--profile", "all", "-d", "--build"},
		"restart": {"--profile", "all", "-d", "--wait", "--wait-timeout", "120", "--build"},
	}
	for name, upArgs := range upArgFuncs() {
		fake := &fakeDockerImageOps{images: testServiceImages, present: imagesPresent()}
		var out bytes.Buffer
		args, err := upArgs(t.TempDir(), "all", false, "v2026.10.3-37-g0fb37f201", fake, &out)
		if err != nil {
			t.Fatalf("%s source build: %v", name, err)
		}
		if !reflect.DeepEqual(args, wantBase[name]) {
			t.Errorf("%s source build args = %q, want %q", name, args, wantBase[name])
		}
		// A source build never pays for the release image check.
		if fake.pulled != 0 || len(fake.inspected) != 0 {
			t.Errorf("%s source build touched the image check: inspected %q, pulled %d", name, fake.inspected, fake.pulled)
		}
	}
	// Profile app addresses the service directly, like the existing up invocations.
	fake := &fakeDockerImageOps{}
	var out bytes.Buffer
	args, err := startUpArgs(t.TempDir(), "app", false, "dev", fake, &out)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"-d", "--build", "app"}; !reflect.DeepEqual(args, want) {
		t.Errorf("start app source build args = %q, want %q", args, want)
	}
}

func TestUpArgsReleaseImagesPresent_STATBUS392(t *testing.T) {
	wantArgs := map[string][]string{
		"start":   {"--profile", "all", "-d", "--no-build"},
		"restart": {"--profile", "all", "-d", "--wait", "--wait-timeout", "120", "--no-build"},
	}
	for name, upArgs := range upArgFuncs() {
		fake := &fakeDockerImageOps{images: testServiceImages, present: imagesPresent(testServiceImages...)}
		var out bytes.Buffer
		args, err := upArgs(t.TempDir(), "all", true, "v2026.10.3", fake, &out)
		if err != nil {
			t.Fatalf("%s release build, images present: %v", name, err)
		}
		if !reflect.DeepEqual(args, wantArgs[name]) {
			t.Errorf("%s release build args = %q, want %q", name, args, wantArgs[name])
		}
		if !reflect.DeepEqual(fake.inspected, testServiceImages) {
			t.Errorf("%s release build inspected %q, want every service image %q", name, fake.inspected, testServiceImages)
		}
		if fake.pulled != 0 {
			t.Errorf("%s pulled %d times with every image present, want 0", name, fake.pulled)
		}
		if out.String() != "" {
			t.Errorf("%s printed %q with every image present, want silence", name, out.String())
		}
	}
}

func TestUpArgsReleaseImagesMissingPulls_STATBUS392(t *testing.T) {
	for name, upArgs := range upArgFuncs() {
		missing := testServiceImages[2]
		present := append([]string{}, testServiceImages[:2]...)
		present = append(present, testServiceImages[3])
		fake := &fakeDockerImageOps{images: testServiceImages, present: imagesPresent(present...)}
		var out bytes.Buffer
		args, err := upArgs(t.TempDir(), "all", true, "v2026.10.3", fake, &out)
		if err != nil {
			t.Fatalf("%s release build, image missing: %v", name, err)
		}
		if fake.pulled != 1 {
			t.Errorf("%s pulled %d times with %s missing, want 1", name, fake.pulled, missing)
		}
		// The operator is told why a start suddenly pulls: the images were
		// missing locally, for example after a prune.
		for _, want := range []string{"v2026.10.3", "missing locally", "prune", "pull"} {
			if !strings.Contains(out.String(), want) {
				t.Errorf("%s missing-image message %q does not name %q", name, out.String(), want)
			}
		}
		if !strings.Contains(strings.Join(args, " "), "--no-build") {
			t.Errorf("%s release build after pull args = %q, want --no-build", name, args)
		}
	}
}

func TestUpArgsReleasePullFailureNamesRemedy_STATBUS392(t *testing.T) {
	for name, upArgs := range upArgFuncs() {
		fake := &fakeDockerImageOps{
			images:  testServiceImages,
			present: imagesPresent(),
			pullErr: errors.New("dial tcp: lookup ghcr.io: no such host"),
		}
		var out bytes.Buffer
		args, err := upArgs(t.TempDir(), "all", true, "v2026.10.3", fake, &out)
		if err == nil {
			t.Fatalf("%s release build with a failed pull returned args %q, want an error", name, args)
		}
		for _, want := range []string{"network", "./sb build"} {
			if !strings.Contains(err.Error(), want) {
				t.Errorf("%s pull failure %q does not name the remedy %q", name, err, want)
			}
		}
	}
}
