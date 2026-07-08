package upgrade

import (
	"strings"
	"testing"
)

// TestRecoveryDSNTagsApplicationName pins STATBUS-149: the daemon's connect DSN
// (recoveryDSN, feeding both d.queryConn and d.listenConn via connect()) must
// carry application_name=statbus-upgrade-daemon-<pid>. Without the tag,
// install.classifyAdvisoryHolder reads the daemon's own live advisory-lock
// connection as an unidentified zombie and kills it every sessions-step pass —
// the self-regenerating "zombie" this ticket closes. This is a source-level pin
// so a future DSN rewrite cannot silently drop the tag; it must stay paired with
// the classifier's statbus-upgrade-daemon- arm (install.go classifyAdvisoryHolder).
func TestRecoveryDSNTagsApplicationName(t *testing.T) {
	body := mustRead(t, thisRepoFile(t, "cli/internal/upgrade/service.go"))
	// The literal the DSN must build. os.Getpid() supplies the trailing %d.
	const want = "application_name=statbus-upgrade-daemon-%d"
	if !strings.Contains(body, want) {
		t.Errorf("STATBUS-149: recoveryDSN must tag the session with %q so the "+
			"daemon's own advisory-lock connection is not misclassified as a zombie", want)
	}
}
