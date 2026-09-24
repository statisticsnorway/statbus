package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/spf13/cobra"
)

func TestParkedRepairSQL_AuditsAndKeepsOneTransaction(t *testing.T) {
	path := filepath.Join(t.TempDir(), "repair.sql")
	if err := os.WriteFile(path, []byte("CREATE TABLE public.repair_probe (id integer);\n"), 0600); err != nil {
		t.Fatal(err)
	}
	sql, err := parkedRepairSQL(path, "repair deterministic migration defect", "Ada Operator")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"SET default_transaction_read_only=off", // enforced by the command environment
	} {
		if strings.Contains(sql, want) {
			t.Fatalf("%q belongs to the psql connection environment, not the SQL input", want)
		}
	}
	for _, want := range []string{
		"recovery_parked_at IS NOT NULL", "FOR UPDATE", "public.upgrade_state_log", "INTO _upgrade_id",
		"parked-window repair:", "actor_source", "'self-reported'", "\\ir '" + path + "'",
	} {
		if !strings.Contains(sql, want) {
			t.Errorf("repair SQL missing %q:\n%s", want, sql)
		}
	}
}

func TestParkedRepairSQL_RejectsMetaCommandsAndTransactionVariants(t *testing.T) {
	for _, body := range []string{"\\c otherdb\n", "END;\n", "START TRANSACTION;\n", "COMMIT PREPARED 'x';\n"} {
		path := filepath.Join(t.TempDir(), "repair.sql")
		if err := os.WriteFile(path, []byte(body), 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := parkedRepairSQL(path, "test", "Ada"); err == nil {
			t.Fatalf("expected refusal for %q", body)
		}
	}
}

func TestParkedRepairSQL_RejectsTopLevelTransactionControl(t *testing.T) {
	path := filepath.Join(t.TempDir(), "repair.sql")
	if err := os.WriteFile(path, []byte("BEGIN;\nUPDATE public.upgrade SET error = 'no';\n"), 0600); err != nil {
		t.Fatal(err)
	}
	_, err := parkedRepairSQL(path, "test", "Ada")
	if err == nil || !strings.Contains(err.Error(), "transaction control") {
		t.Fatalf("expected transaction-control refusal, got %v", err)
	}
}

func TestUpgradeRepairRequiresAuditInputs(t *testing.T) {
	for _, name := range []string{"file", "reason", "operator"} {
		flag := upgradeRepairCmd.Flags().Lookup(name)
		if flag == nil || flag.Annotations[cobra.BashCompOneRequiredFlag] == nil {
			t.Errorf("%s must be required so a parked write always has auditable inputs", name)
		}
	}
}
