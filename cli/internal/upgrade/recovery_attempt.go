package upgrade

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os/exec"

	"github.com/jackc/pgx/v5"
)

// recoveryAttempt is the durable identity of one interrupted attempt, not merely
// a release row. A legacy daemon may still write SQL despite losing the flock.
type recoveryAttempt struct {
	id          int
	sha         string
	started     sql.NullTime
	claim       *string
	backup      sql.NullString
	convergence bool
}

const recoveryAttemptPredicate = `id = $1 AND commit_sha = $2
 AND started_at IS NOT DISTINCT FROM $3::timestamptz
 AND claim_token::text IS NOT DISTINCT FROM $4::text
 AND backup_path IS NOT DISTINCT FROM $5::text
 AND state = 'in_progress' AND recovery_parked_at IS NULL
 AND tree_convergence_required = $6`

func (a recoveryAttempt) args() []any {
	var started, backup any
	if a.started.Valid {
		started = a.started.Time
	}
	if a.backup.Valid {
		backup = a.backup.String
	}
	return []any{a.id, a.sha, started, a.claim, backup, a.convergence}
}

// authorizeRecoveryAttempt re-reads the exact attempt on the real teardown-safe
// connection. A completed executable-matching strict descendant is positive
// evidence of an independent install, unlike ancestry by itself. Lock both rows
// until the disposition commits so retention or a late SQL writer cannot change
// the evidence between observation and retirement.
func (d *Service) authorizeRecoveryAttempt(a recoveryAttempt) (authorized, overtaken bool, err error) {
	if _, err = NewCommitSHA(a.sha); err != nil {
		return false, false, err
	}
	if _, err = NewCommitSHA(d.binaryCommit); err != nil {
		return false, false, fmt.Errorf("executable identity is unknown: %w", err)
	}
	err = d.terminalConnDo(func(ctx context.Context, conn *pgx.Conn) error {
		authorized, overtaken = false, false
		tx, e := conn.Begin(ctx)
		if e != nil {
			return e
		}
		defer func() { _ = tx.Rollback(ctx) }()
		var id int
		if e = tx.QueryRow(ctx, "SELECT id FROM public.upgrade WHERE "+recoveryAttemptPredicate+" FOR UPDATE", a.args()...).Scan(&id); errors.Is(e, pgx.ErrNoRows) {
			return nil
		} else if e != nil {
			return e
		}
		if !a.started.Valid {
			return fmt.Errorf("upgrade %d has no attempt start chronology", a.id)
		}
		if d.binaryCommit != a.sha {
			var witness int
			e = tx.QueryRow(ctx, `SELECT id FROM public.upgrade WHERE id <> $1 AND commit_sha=$2 AND state='completed' AND completed_at > $3 FOR UPDATE`, a.id, d.binaryCommit, a.started.Time).Scan(&witness)
			if e != nil && !errors.Is(e, pgx.ErrNoRows) {
				return e
			}
			if e == nil {
				_, ancestryErr := runCommandOutput(d.projDir, "git", "merge-base", "--is-ancestor", a.sha, d.binaryCommit)
				var exitErr *exec.ExitError
				if ancestryErr != nil && (!errors.As(ancestryErr, &exitErr) || exitErr.ExitCode() != 1) {
					return fmt.Errorf("verify intervening installation ancestry: %w", ancestryErr)
				}
				if ancestryErr == nil {
					tag, e := tx.Exec(ctx, "UPDATE public.upgrade SET state='superseded', superseded_at=clock_timestamp() WHERE "+recoveryAttemptPredicate, a.args()...)
					if e != nil {
						return e
					}
					if tag.RowsAffected() != 1 {
						return nil
					}
					if e = tx.Commit(ctx); e != nil {
						return e
					}
					overtaken = true
					return nil
				}
			}
		}
		if e = tx.Commit(ctx); e != nil {
			return e
		}
		authorized = true
		return nil
	})
	return
}

func (d *Service) completeRecoveryAttempt(a recoveryAttempt, logPath string) (string, error) {
	args := append(a.args(), logPath)
	return d.terminalUpdate(`UPDATE public.upgrade SET state='completed', completed_at=now(), docker_images_status='ready', failure_code=NULL, error=NULL, log_relative_file_path=COALESCE(log_relative_file_path,$7) WHERE `+recoveryAttemptPredicate+upgradeRowReturning, args...)
}
