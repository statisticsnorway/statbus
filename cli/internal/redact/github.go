package redact

import (
	"encoding/base64"
	"regexp"
	"strings"
)

var authorizationHeaderPattern = regexp.MustCompile(`(?i)(authorization\s*[:=]\s*)[^\r\n]+`)
var credentialURLPattern = regexp.MustCompile(`(?i)([a-z][a-z0-9+.-]*://)[^/@\s]+@`)

// GitHubCredentials removes credential-bearing headers and URLs, plus every
// representation of token, from command diagnostics.
func GitHubCredentials(text, token string) string {
	redacted := authorizationHeaderPattern.ReplaceAllString(text, "${1}[REDACTED]")
	redacted = credentialURLPattern.ReplaceAllString(redacted, "${1}[REDACTED]@")
	token = strings.TrimSpace(token)
	if token == "" {
		return redacted
	}
	for _, secret := range []string{
		token,
		base64.StdEncoding.EncodeToString([]byte(token)),
		base64.StdEncoding.EncodeToString([]byte("x-access-token:" + token)),
	} {
		redacted = strings.ReplaceAll(redacted, secret, "[REDACTED]")
	}
	return redacted
}
