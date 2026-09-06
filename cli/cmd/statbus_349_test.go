package cmd

import (
	"errors"
	"testing"

	"software.sslmate.com/src/go-pkcs12"
)

func TestPFXPasswordClassificationUsesSentinelOnly(t *testing.T) {
	if !isPFXPasswordError(pkcs12.ErrDecryption) {
		t.Fatal("pkcs12 decryption sentinel must classify as an invalid password")
	}
	if isPFXPasswordError(errors.New("unrelated decryption failure")) {
		t.Fatal("upstream prose must not classify an error as an invalid password")
	}
}

func TestComposeServicesHaveImagesRequiresEachNamedService(t *testing.T) {
	images := []byte(`[{"Container":"db","ID":"sha256:db"},{"Container":"app","ID":"sha256:app"}]`)
	if !composeServicesHaveImages("db\napp\n", images) {
		t.Fatal("all required services with IDs must be ready")
	}
	if composeServicesHaveImages("db\napp\nworker\n", images) {
		t.Fatal("four arbitrary/countable lines must not hide a missing required service image")
	}
}

func TestLatestTagForPrereleaseSkipsMalformedNewestTag(t *testing.T) {
	got := latestTagForChannel("v2026.09.1-beta.1\nv2026.09.1-rc.4\nv2026.09.0\n", "prerelease")
	if got != "v2026.09.1-rc.4" {
		t.Fatalf("got %q, want newest valid prerelease", got)
	}
}
