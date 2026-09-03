package migrate

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

const (
	PendingCountReportEnv    = "STATBUS_MIGRATE_REPORT_PENDING_COUNT"
	PendingCountReportPrefix = "STATBUS_MIGRATE_PENDING_COUNT="
)

func pendingCountReportLine(count int) string {
	return fmt.Sprintf("%s%d", PendingCountReportPrefix, count)
}

func reportPendingCountIfRequested(count int) {
	if os.Getenv(PendingCountReportEnv) != "1" {
		return
	}
	fmt.Println(pendingCountReportLine(count))
	_ = os.Unsetenv(PendingCountReportEnv)
}

// ParsePendingCountReport parses the upgrade parent's one machine-readable
// migrate-up datum. Ordinary child output is deliberately outside this tiny
// contract and returns ok=false.
func ParsePendingCountReport(line string) (count int, ok bool) {
	value, found := strings.CutPrefix(strings.TrimSpace(line), PendingCountReportPrefix)
	if !found {
		return 0, false
	}
	count, err := strconv.Atoi(value)
	if err != nil || count < 0 {
		return 0, false
	}
	return count, true
}
