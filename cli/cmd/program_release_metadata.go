package cmd

import (
	"fmt"

	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// Program metadata is not evidence of the separately serving app or source install.
func programReleaseMetadataSQL(sha upgrade.CommitSHA) string {
	if _, err := upgrade.NewCommitSHA(string(sha)); err != nil {
		return `SELECT 'Invoked program (not serving app)' AS identity, 'unknown' AS commit_sha, 'unknown' AS release;`
	}
	return fmt.Sprintf(`SELECT 'Invoked program (not serving app)' AS identity,
 '%s' AS commit_sha,
 COALESCE((SELECT resolved_name FROM public.release_identity('%s')), 'unknown') AS release;`, sha, sha)
}
