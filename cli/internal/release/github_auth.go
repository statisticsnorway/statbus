package release

import (
	"encoding/base64"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

type GitHubAuthMode string

const (
	GitHubAuthEnv       GitHubAuthMode = "authenticated via GITHUB_TOKEN"
	GitHubAuthCLI       GitHubAuthMode = "authenticated via gh auth"
	GitHubAuthAnonymous GitHubAuthMode = "anonymous, 60/h"
)

type GitHubAuthentication struct {
	Token string
	Mode  GitHubAuthMode
}

// GitHubAuth is the single resolver for release-time GitHub reads.
func GitHubAuth() GitHubAuthentication {
	if token := strings.TrimSpace(os.Getenv("GITHUB_TOKEN")); token != "" {
		return GitHubAuthentication{Token: token, Mode: GitHubAuthEnv}
	}
	out, err := exec.Command("gh", "auth", "token").Output()
	if err == nil {
		if token := strings.TrimSpace(string(out)); token != "" {
			return GitHubAuthentication{Token: token, Mode: GitHubAuthCLI}
		}
	}
	return GitHubAuthentication{Mode: GitHubAuthAnonymous}
}

func githubAuthHeader() string {
	auth := GitHubAuth()
	if auth.Token == "" {
		return ""
	}
	return "Bearer " + auth.Token
}

// GitHubGitEnv carries the same identity into HTTPS git without exposing the
// token in argv. Anonymous mode returns the environment unchanged.
func GitHubGitEnv(base []string) []string {
	auth := GitHubAuth()
	if auth.Token == "" {
		return base
	}
	encoded := base64.StdEncoding.EncodeToString([]byte("x-access-token:" + auth.Token))
	env := append([]string{}, base...)
	index := 0
	for i, item := range env {
		if strings.HasPrefix(item, "GIT_CONFIG_COUNT=") {
			index, _ = strconv.Atoi(strings.TrimPrefix(item, "GIT_CONFIG_COUNT="))
			env[i] = "GIT_CONFIG_COUNT=" + strconv.Itoa(index+1)
			return append(env,
				"GIT_CONFIG_KEY_"+strconv.Itoa(index)+"=http.https://github.com/.extraheader",
				"GIT_CONFIG_VALUE_"+strconv.Itoa(index)+"=AUTHORIZATION: basic "+encoded,
			)
		}
	}
	return append(env,
		"GIT_CONFIG_COUNT=1",
		"GIT_CONFIG_KEY_0=http.https://github.com/.extraheader",
		"GIT_CONFIG_VALUE_0=AUTHORIZATION: basic "+encoded,
	)
}
