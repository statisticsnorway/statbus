package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

// parkedRepairTransactionControl refuses SQL which could escape psql's -1
// transaction. A parked-window repair is one auditable atomic change: either its
// audit row and its SQL commit together, or neither does. PL/pgSQL bodies may
// contain BEGIN/END, so only a top-level transaction-control line is rejected.
var parkedRepairTransactionControl = regexp.MustCompile(`(?im)^\s*(begin|end|commit|rollback|abort|start\s+transaction|prepare\s+transaction|commit\s+prepared(?:\s+[^;]+)?|rollback\s+prepared(?:\s+[^;]+)?)\s*;\s*$`)
var parkedRepairMetaCommand = regexp.MustCompile(`(?m)^\s*\\`)

func parkedRepairSQL(sqlPath, reason, operator string) (string, error) {
	body, err := os.ReadFile(sqlPath)
	if err != nil {
		return "", fmt.Errorf("read repair SQL %q: %w", sqlPath, err)
	}
	if len(strings.TrimSpace(string(body))) == 0 {
		return "", fmt.Errorf("repair SQL %q is empty", sqlPath)
	}
	if parkedRepairTransactionControl.Match(body) {
		return "", fmt.Errorf("repair SQL %q contains top-level transaction control; ./sb upgrade repair owns the single audited transaction", sqlPath)
	}
	if parkedRepairMetaCommand.Match(body) {
		return "", fmt.Errorf("repair SQL %q contains a psql meta-command; ./sb upgrade repair accepts SQL only", sqlPath)
	}
	// psql variables quote values safely. \ir keeps the supplied path relative to
	// the invoking file, never to a shell expansion.
	return fmt.Sprintf(`\set ON_ERROR_STOP on
SELECT set_config('statbus.actor', :'operator', true);
DO $parked_repair$
DECLARE
  _upgrade_id integer;
BEGIN
  SELECT u.id
    INTO _upgrade_id
    FROM public.upgrade AS u
   WHERE u.state = 'in_progress'
     AND u.recovery_parked_at IS NOT NULL
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'parked-window repair requires an in_progress parked upgrade';
  END IF;
  INSERT INTO public.upgrade_state_log (
    upgrade_id, application_name, query, backend_pid, actor, actor_source
  ) VALUES (
    _upgrade_id, current_setting('application_name', true),
    'parked-window repair: ' || :'reason', pg_backend_pid(),
    current_setting('statbus.actor', true), 'self-reported'
  );
END;
$parked_repair$;
\ir %s
`, psqlPathLiteral(sqlPath)), nil
}

func psqlPathLiteral(path string) string {
	// psql's \ir accepts a single-quoted filename. Double quote characters are
	// not special inside it; single quotes are doubled.
	return "'" + strings.ReplaceAll(filepath.Clean(path), "'", "''") + "'"
}

var upgradeRepairCmd = &cobra.Command{
	Use:   "repair --file <sql> --reason <reason> --operator <name>",
	Short: "Apply one audited SQL repair while an upgrade is parked",
	Long: `Applies one SQL file in a single transaction while a parked upgrade keeps
clients frozen. It appends an audit record to public.upgrade_state_log with the
operator and reason before running the file. The repair is deliberately subject
to rollback: if recovery later restores its pre-upgrade snapshot, this change is
forfeited too. This command refuses unless an in_progress upgrade is parked.

It is the only sanctioned write path during a parked read-only window. Use a
reviewed SQL file, name the human operator, and give the operational reason.`,
	Args: cobra.NoArgs,
	RunE: func(cmd *cobra.Command, _ []string) error {
		file, _ := cmd.Flags().GetString("file")
		reason, _ := cmd.Flags().GetString("reason")
		operator, _ := cmd.Flags().GetString("operator")
		sql, err := parkedRepairSQL(file, reason, operator)
		if err != nil {
			return err
		}
		projDir := migrate.PsqlProjectDir()
		psqlPath, prefix, env, err := migrate.PsqlCommand(projDir)
		if err != nil {
			return err
		}
		args := append(prefix, "-1", "-v", "operator="+operator, "-v", "reason="+reason)
		args, env = migrate.PsqlWriteArgs(psqlPath, args, env, "sb upgrade repair")
		child, err := migrate.Command(projDir, psqlPath, args...)
		if err != nil {
			return fmt.Errorf("construct parked repair psql command: %w", err)
		}
		child.Env = env
		child.Stdin = strings.NewReader(sql)
		child.Stdout = cmd.OutOrStdout()
		child.Stderr = cmd.ErrOrStderr()
		return child.Run()
	},
}

func init() {
	upgradeRepairCmd.Flags().String("file", "", "reviewed SQL file to apply")
	upgradeRepairCmd.Flags().String("reason", "", "why this repair is required, recorded in the audit log")
	upgradeRepairCmd.Flags().String("operator", "", "your name, recorded in the audit log")
	_ = upgradeRepairCmd.MarkFlagRequired("file")
	_ = upgradeRepairCmd.MarkFlagRequired("reason")
	_ = upgradeRepairCmd.MarkFlagRequired("operator")
}
