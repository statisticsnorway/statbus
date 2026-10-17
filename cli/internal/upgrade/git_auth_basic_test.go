package upgrade

import (
	"encoding/base64"
	"strings"
	"testing"
)

// STATBUS-515: GitHub's git-over-HTTPS endpoint refuses a personal access
// token sent as Bearer (401) and accepts it as Basic auth with the token as
// the password. The git environment carries exactly that header.
func TestGitFetchEnvSendsTokenAsBasicAuth_STATBUS515(t *testing.T) {
	t.Setenv("GITHUB_TOKEN", "github_pat_test")
	want := "GIT_CONFIG_VALUE_0=Authorization: Basic " +
		base64.StdEncoding.EncodeToString([]byte("x-access-token:github_pat_test"))
	env := gitFetchEnv()
	got := ""
	for _, e := range env {
		if strings.HasPrefix(e, "GIT_CONFIG_VALUE_0=") {
			got = e
		}
	}
	if got != want {
		t.Fatalf("git auth header = %q, want %q", got, want)
	}
}
