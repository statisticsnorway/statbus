package upgrade

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
)

// withActorTx runs fn inside ONE explicit transaction, having first set the
// session-local statbus.actor GUC to operator (if non-empty) in that SAME
// transaction (STATBUS-317).
//
// TRAP, architect's own words: "set_config(..., true) is transaction-local.
// SET LOCAL / set_config(..., true) outside a transaction is a no-op with a
// warning. If the CLI writes in autocommit, the setting evaporates and
// every row silently records absent — a feature that appears built and
// records nothing." d.queryConn.Exec calls on the bare connection each run
// in their own autocommit transaction (see runOneShot's own comment: "not
// transactional"), so setting the GUC with one Exec and writing with a
// second would already be too late by the time the second one starts. This
// helper is the ONE place that opens the explicit pgx.Tx both statements
// must share, so every caller gets the property by construction instead of
// by remembering.
//
// fn receives the tx to run its write through — never d.queryConn directly,
// or it would silently escape the transaction this helper just opened.
func (d *Service) withActorTx(ctx context.Context, operator string, fn func(ctx context.Context, tx pgx.Tx) error) error {
	tx, err := d.queryConn.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	// Rollback after a successful Commit is a documented no-op in pgx — safe
	// to defer unconditionally rather than track whether Commit ran.
	defer func() { _ = tx.Rollback(ctx) }()

	if operator != "" {
		if _, err := tx.Exec(ctx, "SELECT set_config('statbus.actor', $1, true)", operator); err != nil {
			return fmt.Errorf("set operator context: %w", err)
		}
	}

	if err := fn(ctx, tx); err != nil {
		return err
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit transaction: %w", err)
	}
	return nil
}
