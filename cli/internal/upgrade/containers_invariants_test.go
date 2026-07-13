package upgrade

import "testing"

// TestVersionTrackedAlignedWithUpgradePipeline asserts that every service
// in containers.go's `versionTrackedServices` is actually restarted by
// the upgrade pipeline — either at step 9 (the implicit "db") or at
// step 11 (service.go's `step11RestartServices`).
//
// When this invariant breaks, `containersAtFlagTarget` waits forever
// for a container whose image tag the upgrade pipeline never advances.
// That's the Bug 2 symptom that bit rune.statbus.org: `proxy` was in
// `versionTrackedServices` but missing from step 11's `docker compose
// up -d --no-build app worker rest`, so the canary returned `false`
// indefinitely after any post-swap restart in deployments where proxy
// was on a different tag pre-upgrade.
//
// This test guards against future drift in either direction:
//   - adding a service to `versionTrackedServices` without restarting
//     it in step 11 (the original Bug 2 shape — canary wedges)
//   - removing a service from step 11 without removing it from
//     `versionTrackedServices` (same shape; canary wedges)
//   - removing a service from `versionTrackedServices` without dropping
//     it from step 11 (silent drift; canary fails to verify an updated
//     container's tag)
//
// Source-of-truth references:
//   - containers.go's `versionTrackedServices` var
//   - service.go's `step11RestartServices` var
//   - service.go's step 11 in applyNewSbUpgrading (uses step11RestartServices)
//   - service.go's step 9 in applyNewSbUpgrading (docker compose up -d --no-build db)
//
// "rest" is in step11RestartServices but intentionally absent from
// versionTrackedServices: postgrest's image tag is upstream-pinned
// (postgrest:v12.2.8 in docker-compose.rest.yml), so a tag check
// would never match the post-upgrade SHA. Only the state=="running"
// check applies to rest (evaluateContainersAtFlagTarget special-cases
// this via the `expected` list).
func TestVersionTrackedAlignedWithUpgradePipeline(t *testing.T) {
	pipelineRestarts := map[string]bool{"db": true}
	for _, s := range step11RestartServices {
		pipelineRestarts[s] = true
	}

	for _, svc := range versionTrackedServices {
		if !pipelineRestarts[svc] {
			t.Errorf("INVARIANT VIOLATION: versionTrackedServices includes %q "+
				"but the upgrade pipeline (step 9 + step 11) does not restart %q. "+
				"After a post-swap restart, `containersAtFlagTarget` will wait "+
				"forever for %q's image tag to advance — but step 11's "+
				"`docker compose up -d --no-build %v` never touches it. "+
				"Resolution: either add %q to step11RestartServices (so the "+
				"upgrade pipeline genuinely advances its tag) OR drop %q "+
				"from versionTrackedServices (acknowledge it's not version-"+
				"tracked).",
				svc, svc, svc, step11RestartServices, svc, svc)
		}
	}
}
