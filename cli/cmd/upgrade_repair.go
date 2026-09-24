package cmd

import (
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/spf13/cobra"
	"github.com/statisticsnorway/statbus/cli/internal/migrate"
)

var parkedRepairTransactionControl = regexp.MustCompile(`(?i)\b(begin|commit|rollback|abort|start\s+transaction|prepare\s+transaction)\b`)
var parkedRepairStandaloneControl = regexp.MustCompile(`(?i)^\s*(end|savepoint|release)\b`)

// validateParkedRepairSQL is deliberately conservative. The operator verb can
// only audit one SQL statement, so anything requiring a SQL parser to prove safe
// is refused rather than guessed at: psql meta syntax, dollar-quoted procedural
// bodies, unterminated quotes/comments, transaction control, and multiple
// top-level statements.
func validateParkedRepairSQL(body string) error {
	if strings.Contains(body, `\`) {
		return fmt.Errorf("contains a psql meta-command or backslash escape")
	}
	var visible strings.Builder
	semicolons := 0
	for i := 0; i < len(body); {
		switch {
		case i+1 < len(body) && body[i:i+2] == "--":
			if end := strings.IndexByte(body[i+2:], '\n'); end >= 0 {
				i += end + 2
			} else {
				i = len(body)
			}
		case i+1 < len(body) && body[i:i+2] == "/*":
			end := strings.Index(body[i+2:], "*/")
			if end < 0 {
				return fmt.Errorf("contains an unterminated block comment")
			}
			i += end + 4
		case body[i] == '\'' || body[i] == '"':
			quote := body[i]
			i++
			for {
				if i >= len(body) {
					return fmt.Errorf("contains an unterminated quoted value")
				}
				if body[i] == quote {
					if i+1 < len(body) && body[i+1] == quote {
						i += 2
						continue
					}
					i++
					break
				}
				i++
			}
		case body[i] == '$':
			return fmt.Errorf("contains dollar quoting; only one directly auditable SQL statement is accepted")
		default:
			if body[i] == ';' {
				semicolons++
			}
			visible.WriteByte(body[i])
			i++
		}
	}
	plain := strings.TrimSpace(visible.String())
	if semicolons > 1 || (semicolons == 1 && !strings.HasSuffix(plain, ";")) {
		return fmt.Errorf("contains multiple SQL statements")
	}
	if parkedRepairTransactionControl.MatchString(plain) || parkedRepairStandaloneControl.MatchString(plain) {
		return fmt.Errorf("contains transaction control")
	}
	return nil
}

func parkedRepairSQL(sqlPath, reason, operator string) (string, error) {
	body, err := os.ReadFile(sqlPath)
	if err != nil {
		return "", fmt.Errorf("read repair SQL %q: %w", sqlPath, err)
	}
	if len(strings.TrimSpace(string(body))) == 0 {
		return "", fmt.Errorf("repair SQL %q is empty", sqlPath)
	}
	if err := validateParkedRepairSQL(string(body)); err != nil {
		return "", fmt.Errorf("repair SQL %q %w; ./sb upgrade repair requires one audited SQL statement", sqlPath, err)
	}
	return fmt.Sprintf(`\set ON_ERROR_STOP on
SELECT set_config('statbus.actor', :'operator', true);
SELECT set_config('statbus.repair_reason', :'reason', true);
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
	    'parked-window repair: ' || current_setting('statbus.repair_reason', true), pg_backend_pid(),
	    current_setting('statbus.actor', true), 'self-reported'
	  );
END;
$parked_repair$;
%s
`, string(body)), nil
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
