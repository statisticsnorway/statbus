package upgrade

import (
	"os"
	"strings"
	"testing"
)

// Recovery-route callers serve two incompatible contracts. Position is established
// once, then selects the route contract: deterministic parks with unreadable position
// may inspect through the route-only contract, while source-restoration and rollback
// schema-floor work retain the held-closed contract.
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

	deterministicPark := extractFuncBody(t, serviceSource, "func (d *Service) parkForDeterministicFailure(")
	parkRecovery := extractFuncBody(t, serviceSource, "func (d *Service) parkServiceRecovery(")
	park := extractFuncBody(t, serviceSource, "func (d *Service) parkEraVerdict(")
	rollbackDB := extractFuncBody(t, serviceSource, "func (d *Service) startRollbackDatabaseOnly(")
	rollback := extractFuncBody(t, serviceSource, "func (d *Service) rollback(")
	install := extractFuncBody(t, installSource, "func runCrashRecovery(")

	if !strings.Contains(deterministicPark, "d.StartDatabaseRouteServingMayRun") {
		t.Error("unreadable-position deterministic park must use route-only startup because serving clients may legitimately be live")
	}
	if strings.Contains(deterministicPark, "d.StartDatabaseRouteServingMustBeStopped") {
		t.Error("held-closed startup must not be reachable from parkForDeterministicFailure after its observed-position verdict")
	}
	if !strings.Contains(parkRecovery, "startDatabaseRoute") || !strings.Contains(park, "startDatabaseRoute(ctx)") {
		t.Error("park service recovery must receive the already-selected route contract instead of re-deriving position")
	}
	if !strings.Contains(rollbackDB, "d.StartDatabaseRouteServingMustBeStopped(ctx)") {
		t.Error("startRollbackDatabaseOnly must use the held-closed route before schema-floor replay")
	}
	if !strings.Contains(install, "svc.StartDatabaseRouteServingMayRun(ctx)") {
		t.Error("install.runCrashRecovery must use route-only startup because the serving tier may legitimately be live")
	}
	if !strings.Contains(rollback, "d.StartDatabaseRouteServingMayRun(ctx)") {
		t.Error("rollback stop-verification ABORT must use route-only startup because its defining state includes a possibly-live serving tier")
	}

	if got := strings.Count(serviceSource, "d.StartDatabaseRouteServingMustBeStopped"); got != 3 {
		t.Fatalf("held-closed startup must have exactly the two park source-restoration selections plus rollback schema-floor replay; got %d", got)
	}
	if got := strings.Count(serviceSource, "d.StartDatabaseRouteServingMayRun"); got != 2 {
		t.Fatalf("service.go route-only startup must appear only in unreadable-position deterministic park and rollback ABORT; got %d", got)
	}
	if got := strings.Count(installSource, "svc.StartDatabaseRouteServingMayRun(ctx)"); got != 1 {
		t.Fatalf("install route-only startup must appear only in runCrashRecovery; got %d", got)
	}
}
