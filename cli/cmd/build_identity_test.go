package cmd

import "testing"

// STATBUS-392: one function answers "release build or source build" from the
// binary's version stamp, and start, restart and command visibility all use
// it (doc/sb-build-identity.md). A tag is a release build; a git-describe
// suffix, "dev" or empty is a source build.
func TestBuildIdentityDecision_STATBUS392(t *testing.T) {
	for _, v := range []string{
		"v2026.10.3",
		"v2026.10.3-rc.01",
		"v2026.9.12-rc.1",
	} {
		if !isReleaseBuildVersion(v) {
			t.Errorf("isReleaseBuildVersion(%q) = false, want a release build", v)
		}
	}
	for _, v := range []string{
		"v2026.10.3-37-g0fb37f201", // git describe between tags
		"v2026.10.3-1-g1234567",
		"dev",
		"",
		"local",
		"v2026.10.3-dirty",
	} {
		if isReleaseBuildVersion(v) {
			t.Errorf("isReleaseBuildVersion(%q) = true, want a source build", v)
		}
	}
}
