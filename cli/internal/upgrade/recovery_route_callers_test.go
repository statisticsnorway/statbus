package upgrade

import (
	"os"
	"strings"
	"testing"
)

// The four recovery-route callers serve two incompatible contracts. Pin the
// routing as a 2/2 split so the held-closed verifier cannot leak back into the
// operator/ABORT paths, and cannot disappear from either schema-era guard.
func TestRecoveryRouteCallersSplitByContract(t *testing.T) {
	serviceSourceBytes, err := os.ReadFile(thisRepoFile(t, "cli/internal/upgrade/service.go"))
	if err != nil {
		t.Fatal(err)
	}
	installSourceBytes, err := os.ReadFile(thisRepoFile(t, "cli/cmd/install_upgrade.go"))
	if err != nil {
		t.Fatal(err)
	}
	serviceSource := string(serviceSourceBytes)
	installSource := string(installSourceBytes)

	park := extractFuncBody(t, serviceSource, "func (d *Service) parkEraVerdict(")
	rollbackDB := extractFuncBody(t, serviceSource, "func (d *Service) startRollbackDatabaseOnly(")
	rollback := extractFuncBody(t, serviceSource, "func (d *Service) rollback(")
	install := extractFuncBody(t, installSource, "func runCrashRecovery(")

	if !strings.Contains(park, "d.StartDBRouteClientsMustBeStopped(ctx)") {
		t.Error("parkEraVerdict must use the held-closed route while comparing source and database schema eras")
	}
	if !strings.Contains(rollbackDB, "d.StartDBRouteClientsMustBeStopped(ctx)") {
		t.Error("startRollbackDatabaseOnly must use the held-closed route before schema-floor replay")
	}
	if !strings.Contains(install, "svc.StartDBRouteClientsMayRun(ctx)") {
		t.Error("install.runCrashRecovery must use route-only startup because app/rest/worker may legitimately be live")
	}
	if !strings.Contains(rollback, "d.StartDBRouteClientsMayRun(ctx)") {
		t.Error("rollback stop-verification ABORT must use route-only startup because its defining state includes possibly-live clients")
	}

	if got := strings.Count(serviceSource, "d.StartDBRouteClientsMustBeStopped(ctx)"); got != 2 {
		t.Fatalf("held-closed startup must have exactly the two audited production callers; got %d", got)
	}
	if got := strings.Count(serviceSource, "d.StartDBRouteClientsMayRun(ctx)"); got != 1 {
		t.Fatalf("service.go route-only startup must appear only in the rollback ABORT writer; got %d", got)
	}
	if got := strings.Count(installSource, "svc.StartDBRouteClientsMayRun(ctx)"); got != 1 {
		t.Fatalf("install route-only startup must appear only in runCrashRecovery; got %d", got)
	}
}
