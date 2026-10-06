package cmd

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/statisticsnorway/statbus/cli/internal/upgrade"
)

// This is positive attribution of an overtaken daemon attempt, not a claim about
// historical containers or a unique flagless signature. Released direct install
// INSERT/upserts preserve started_at too, so chronology alone is insufficient.
const overtakenCompletedFieldsSQL = `SELECT r.id, r.commit_sha, r.started_at, r.completed_at,
 r.claim_token::text, r.backup_path, r.log_relative_file_path,
 c.id, c.commit_sha, c.completed_at, c.started_at, c.claim_token::text, c.backup_path, c.log_relative_file_path, c.recovery_parked_at, finish.id, claim.id`
const overtakenCompletedEvidenceSQL = ` FROM public.upgrade AS r
 JOIN public.upgrade AS c ON c.id <> r.id AND c.state='completed'
  AND r.started_at < c.completed_at AND c.completed_at < r.completed_at
 JOIN LATERAL (SELECT l.* FROM public.upgrade_state_log AS l
  WHERE l.upgrade_id=r.id ORDER BY l.id DESC LIMIT 1 FOR SHARE) AS finish ON true
 JOIN LATERAL (SELECT l.* FROM public.upgrade_state_log AS l
  WHERE l.upgrade_id=r.id AND l.id<finish.id ORDER BY l.id DESC LIMIT 1 FOR SHARE) AS claim ON true
 WHERE r.state='completed' AND r.recovery_parked_at IS NULL
  AND finish.old_state='in_progress' AND finish.new_state='completed'
  AND finish.old_parked_at IS NULL AND finish.new_parked_at IS NULL
  AND finish.application_name ~ '^statbus-upgrade-daemon-[0-9]+$'
  AND regexp_replace(finish.query, '[[:space:]]+', ' ', 'g') LIKE
   'UPDATE public.upgrade SET state = ''completed'', completed_at = now(), docker_images_status = ''ready'', failure_code = NULL, error = NULL, log_relative_file_path = COALESCE(%'
  AND claim.old_state='scheduled' AND claim.new_state='in_progress'
  AND claim.old_parked_at IS NULL AND claim.new_parked_at IS NULL
  AND claim.logged_at >= r.started_at AND claim.logged_at < c.completed_at
  AND finish.logged_at >= r.completed_at`

type overtakenCompletion struct {
	id                        int
	sha                       string
	started, completed        time.Time
	claim                     *string
	backup, logPath           sql.NullString
	witnessID                 int
	witnessSHA                string
	witnessCompleted          time.Time
	witnessStarted            *time.Time
	witnessClaim              *string
	witnessBackup, witnessLog sql.NullString
	witnessParked             *time.Time
	finishEvent, claimEvent   int64
}

func readOvertakenCompletions(ctx context.Context, tx pgx.Tx) ([]overtakenCompletion, error) {
	rows, err := tx.Query(ctx, overtakenCompletedFieldsSQL+overtakenCompletedEvidenceSQL)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var candidates []overtakenCompletion
	for rows.Next() {
		var c overtakenCompletion
		if err := rows.Scan(&c.id, &c.sha, &c.started, &c.completed, &c.claim, &c.backup, &c.logPath, &c.witnessID, &c.witnessSHA, &c.witnessCompleted, &c.witnessStarted, &c.witnessClaim, &c.witnessBackup, &c.witnessLog, &c.witnessParked, &c.finishEvent, &c.claimEvent); err != nil {
			return nil, err
		}
		candidates = append(candidates, c)
	}
	return candidates, rows.Err()
}

func installationIncludesCommit(dir, ancestor, descendant string) bool {
	if _, err := upgrade.NewCommitSHA(ancestor); err != nil {
		return false
	}
	if _, err := upgrade.NewCommitSHA(descendant); err != nil {
		return false
	}
	if ancestor == descendant {
		return true
	}
	cmd := exec.Command("git", "-C", dir, "merge-base", "--is-ancestor", ancestor, descendant)
	return cmd.Run() == nil // unresolved/failed ancestry is not positive evidence
}

// repairOvertakenCompletion re-reads both rows and the same adjacent retained
// events under row locks. A changed witness, attempt, log/snapshot or event
// revokes the earlier selection. No new retention or ownership protocol.
func repairOvertakenCompletion(ctx context.Context, tx pgx.Tx, c overtakenCompletion, auditLog io.Writer) (bool, error) {
	var backup, logPath any
	if c.backup.Valid {
		backup = c.backup.String
	}
	if c.logPath.Valid {
		logPath = c.logPath.String
	}
	args := []any{c.id, c.witnessID, c.sha, c.started, c.completed, c.claim, backup, logPath, c.witnessSHA, c.witnessCompleted, c.finishEvent, c.claimEvent, c.witnessStarted, c.witnessClaim, c.witnessBackup, c.witnessLog, c.witnessParked}
	var id int
	err := tx.QueryRow(ctx, "SELECT r.id"+overtakenCompletedEvidenceSQL+`
  AND r.id=$1 AND c.id=$2 AND r.commit_sha=$3
  AND r.started_at=$4 AND r.completed_at=$5
  AND r.claim_token::text IS NOT DISTINCT FROM $6::text
  AND r.backup_path IS NOT DISTINCT FROM $7::text
  AND r.log_relative_file_path IS NOT DISTINCT FROM $8::text
  AND c.commit_sha=$9 AND c.completed_at=$10 AND finish.id=$11 AND claim.id=$12
  AND c.started_at IS NOT DISTINCT FROM $13::timestamptz
  AND c.claim_token::text IS NOT DISTINCT FROM $14::text
  AND c.backup_path IS NOT DISTINCT FROM $15::text
  AND c.log_relative_file_path IS NOT DISTINCT FROM $16::text
  AND c.recovery_parked_at IS NOT DISTINCT FROM $17::timestamptz
  FOR UPDATE OF r,c`, args...).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	// Persist attribution in the existing installer log before retracting it.
	if auditLog == nil || auditLog == io.Discard {
		return false, nil
	}
	if _, err := fmt.Fprintf(auditLog, "  Correcting overtaken attempt %d (%s): retract completed_at=%s, witness=%d/%s completed_at=%s, claim_event=%d completion_event=%d\n", c.id, c.sha, c.completed.UTC().Format(time.RFC3339Nano), c.witnessID, c.witnessSHA, c.witnessCompleted.UTC().Format(time.RFC3339Nano), c.claimEvent, c.finishEvent); err != nil {
		return false, nil // no recorded attribution means no correction authority
	}
	tag, err := tx.Exec(ctx, `UPDATE public.upgrade SET state='superseded',superseded_at=clock_timestamp(),completed_at=NULL
  WHERE id=$1 AND commit_sha=$2 AND started_at=$3 AND completed_at=$4
  AND claim_token::text IS NOT DISTINCT FROM $5::text
  AND backup_path IS NOT DISTINCT FROM $6::text
  AND log_relative_file_path IS NOT DISTINCT FROM $7::text
  AND state='completed' AND recovery_parked_at IS NULL`, c.id, c.sha, c.started, c.completed, c.claim, backup, logPath)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

// Called only inside normal successful install bookkeeping, under its existing
// filesystem mutex, before B and ordinary candidate/retention cleanup.
func repairOvertakenCompletedAttempts(ctx context.Context, tx pgx.Tx, dir, installedSHA string, auditLog io.Writer) error {
	candidates, err := readOvertakenCompletions(ctx, tx)
	if err != nil {
		return err
	}
	for _, c := range candidates {
		if c.sha == c.witnessSHA || !installationIncludesCommit(dir, c.sha, c.witnessSHA) || !installationIncludesCommit(dir, c.witnessSHA, installedSHA) {
			continue
		}
		if _, err := repairOvertakenCompletion(ctx, tx, c, auditLog); err != nil {
			return err
		}
	}
	return nil
}
