package release

import (
	"encoding/base64"
	"fmt"
	"os"
	"os/exec"
	"regexp"
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

func redactCommandStderr(text string) string {
	redacted := authorizationHeaderPattern.ReplaceAllString(text, "${1}[REDACTED]")
	if token := strings.TrimSpace(os.Getenv("GITHUB_TOKEN")); token != "" {
		for _, secret := range []string{token, base64.StdEncoding.EncodeToString([]byte(token)), base64.StdEncoding.EncodeToString([]byte("x-access-token:" + token))} {
			redacted = strings.ReplaceAll(redacted, secret, "[REDACTED]")
		}
	}
	return redacted
}

func commandOutput(cmd *exec.Cmd) ([]byte, error) {
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		message := strings.TrimSpace(redactCommandStderr(stderr.String()))
		if message != "" {
			return out, fmt.Errorf("%w: %s", err, message)
		}
	}
	return out, err
}

var authorizationHeaderPattern = regexp.MustCompile(`(?i)(authorization\s*[:=]\s*)[^\r\n]+`)

// GitHubAuth is the single resolver for release-time GitHub reads.
func GitHubAuth() GitHubAuthentication {
	if token := strings.TrimSpace(os.Getenv("GITHUB_TOKEN")); token != "" {
		return GitHubAuthentication{Token: token, Mode: GitHubAuthEnv}
	}
	out, err := commandOutput(exec.Command("gh", "auth", "token"))
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
	// An empty extraheader resets values inherited from lower-priority config.
	// actions/checkout persists its own Authorization extraheader locally; without
	// this reset Git sends both credentials and GitHub rejects the duplicate header.
	index := 0
	for i, item := range env {
		if strings.HasPrefix(item, "GIT_CONFIG_COUNT=") {
			index, _ = strconv.Atoi(strings.TrimPrefix(item, "GIT_CONFIG_COUNT="))
			env[i] = "GIT_CONFIG_COUNT=" + strconv.Itoa(index+2)
			return append(env,
				"GIT_CONFIG_KEY_"+strconv.Itoa(index)+"=http.https://github.com/.extraheader",
				"GIT_CONFIG_VALUE_"+strconv.Itoa(index)+"=",
				"GIT_CONFIG_KEY_"+strconv.Itoa(index+1)+"=http.https://github.com/.extraheader",
				"GIT_CONFIG_VALUE_"+strconv.Itoa(index+1)+"=AUTHORIZATION: basic "+encoded,
			)
		}
	}
	return append(env,
		"GIT_CONFIG_COUNT=2",
		"GIT_CONFIG_KEY_0=http.https://github.com/.extraheader",
		"GIT_CONFIG_VALUE_0=",
		"GIT_CONFIG_KEY_1=http.https://github.com/.extraheader",
		"GIT_CONFIG_VALUE_1=AUTHORIZATION: basic "+encoded,
	)
}

// RedactGitHubCredentials removes every representation of the resolved GitHub
// credential before captured Git or HTTP output can be wrapped, printed, or
// retained in diagnostics. Header values are redacted even when they do not
// match the current token, because transports may normalize or replace them.
func RedactGitHubCredentials(text string) string {
	auth := GitHubAuth()
	redacted := redactCommandStderr(text)
	if auth.Token == "" {
		return redacted
	}
	for _, secret := range []string{auth.Token, base64.StdEncoding.EncodeToString([]byte(auth.Token)), base64.StdEncoding.EncodeToString([]byte("x-access-token:" + auth.Token))} {
		redacted = strings.ReplaceAll(redacted, secret, "[REDACTED]")
	}
	return redacted
}
