package upgrade

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func maintenanceFlagHeadline(snapshot upgradeClaimSnapshot) string {
	return fmt.Sprintf("upgrade %d to %s", snapshot.ID, snapshot.CommitVersion)
}

// maintenanceFlagContent renders the three-line maintenance-file contract.
// ImmutableJSON comes from PostgreSQL to_json over the claim UPDATE's RETURNING
// row, so this is the actual database representation in explicit SELECT order.
func maintenanceFlagContent(snapshot upgradeClaimSnapshot) (string, error) {
	immutableJSON := strings.TrimSpace(snapshot.ImmutableJSON)
	if immutableJSON == "" {
		return "", fmt.Errorf("immutable upgrade claim JSON is empty")
	}
	if !json.Valid([]byte(immutableJSON)) {
		return "", fmt.Errorf("immutable upgrade claim JSON is invalid")
	}
	liveStateCommand := fmt.Sprintf(
		`echo "SELECT to_json(t) FROM (SELECT id, state, completed_at, rolled_back_at, error FROM public.upgrade WHERE id = %d) AS t;" | ./sb psql -t -A`,
		snapshot.ID,
	)
	return strings.Join([]string{
		maintenanceFlagHeadline(snapshot),
		immutableJSON,
		liveStateCommand,
	}, "\n") + "\n", nil
}

func homeRelativePath(path string) string {
	home := os.Getenv("HOME")
	if home == "" {
		return filepath.ToSlash(path)
	}
	rel, err := filepath.Rel(home, path)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return filepath.ToSlash(path)
	}
	if rel == "." {
		return "~"
	}
	return "~/" + filepath.ToSlash(rel)
}

func formatProgressDuration(elapsed time.Duration, forceTenths bool) string {
	rounded := elapsed.Round(100 * time.Millisecond)
	if forceTenths || rounded < time.Second || rounded%time.Second != 0 {
		return fmt.Sprintf("%.1fs", rounded.Seconds())
	}
	return fmt.Sprintf("%.0fs", rounded.Seconds())
}

func formatProgressBudget(budget time.Duration) string {
	if budget%time.Minute == 0 {
		return fmt.Sprintf("%dm", int(budget/time.Minute))
	}
	return budget.String()
}

// operatorServiceStateLines keeps the post-handoff narrative focused on the
// four application-facing services. Database state has its own explicit start
// and health line later in the sequence, so repeating its expected stopped
// state here would add a 45th happy-path M line.
func operatorServiceStateLines(mismatched []string) []string {
	lines := make([]string, 0, len(mismatched))
	for _, mismatch := range mismatched {
		if strings.HasPrefix(mismatch, "db: ") {
			continue
		}
		lines = append(lines, mismatch)
	}
	return lines
}

type successfulUpgradeFinishingNarrative struct {
	displayName     string
	maintenancePath string
	lockPath        string
}

type rollbackCompletionErrors struct {
	databaseRestore error
	servicesStart   error
	databaseHealth  error
	reconnect       error
	maintenance     error
	readOnly        error
}

func (e rollbackCompletionErrors) degraded() bool {
	return e.databaseRestore != nil ||
		e.servicesStart != nil ||
		e.databaseHealth != nil ||
		e.reconnect != nil ||
		e.maintenance != nil ||
		e.readOnly != nil
}

func (e rollbackCompletionErrors) details() []string {
	details := make([]string, 0, 6)
	for _, item := range []struct {
		err   error
		label string
	}{
		{e.databaseRestore, "DB snapshot restore failed"},
		{e.servicesStart, "services did not come back up"},
		{e.databaseHealth, "restored database did not become healthy"},
		{e.reconnect, "upgrade service did not reconnect to the restored database"},
		{e.maintenance, "maintenance mode did not lift"},
		{e.readOnly, "SQL writes remained blocked"},
	} {
		if item.err != nil {
			details = append(details, item.label)
		}
	}
	return details
}

func newSuccessfulUpgradeFinishingNarrative(displayName, maintenancePath, lockPath string) successfulUpgradeFinishingNarrative {
	return successfulUpgradeFinishingNarrative{
		displayName:     displayName,
		maintenancePath: homeRelativePath(maintenancePath),
		lockPath:        homeRelativePath(lockPath),
	}
}

func (n successfulUpgradeFinishingNarrative) heading() string {
	return "Finishing:"
}

func (n successfulUpgradeFinishingNarrative) maintenanceLines() []string {
	return []string{
		"  Lifting maintenance mode ... ok",
		fmt.Sprintf("    removed: %s", n.maintenancePath),
	}
}

func (n successfulUpgradeFinishingNarrative) recordedLine() string {
	return "  Recording the successful upgrade in the database ... ok"
}

func (n successfulUpgradeFinishingNarrative) readOnlyLines(statement string) []string {
	return []string{
		"  Unblocking SQL writes ... ok",
		fmt.Sprintf("    ran: %s", statement),
	}
}

func (n successfulUpgradeFinishingNarrative) lockLines() []string {
	return []string{
		"  Releasing upgrade lock ... ok",
		fmt.Sprintf("    removed: %s", n.lockPath),
	}
}

func (n successfulUpgradeFinishingNarrative) fixupLine(elapsed time.Duration) string {
	return fmt.Sprintf("  Applying configuration and service updates ... ok (%s)", formatProgressDuration(elapsed, false))
}

func (n successfulUpgradeFinishingNarrative) completeLine() string {
	return fmt.Sprintf("Upgrade to %s complete.", n.displayName)
}

func (n successfulUpgradeFinishingNarrative) successLines(readOnlyStatement string, fixupElapsed time.Duration) []string {
	lines := []string{n.heading()}
	lines = append(lines, n.maintenanceLines()...)
	lines = append(lines, n.recordedLine())
	lines = append(lines, n.readOnlyLines(readOnlyStatement)...)
	lines = append(lines, n.lockLines()...)
	lines = append(lines, n.fixupLine(fixupElapsed), n.completeLine())
	return lines
}

func writeProgressLines(progress *ProgressLog, lines ...string) {
	for _, line := range lines {
		progress.Write("%s", line)
	}
}
