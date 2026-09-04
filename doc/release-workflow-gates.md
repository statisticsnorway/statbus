# Release workflow gates

This document explains how `./sb release prerelease`, `./sb release stable`, and `.githooks/pre-push` consult GitHub Actions workflow status as pre-flight gates, and how to add a new gate. For what each rung of the release proves, in order, and what a candidate may skip, read [release-ladder.md](release-ladder.md) first.

The layer a gate fires at follows one rule (STATBUS-199 D1, STATBUS-205): a workflow that fires on the COMMIT (master push / PR) gates the RC cut (`release prerelease` pre-flight) — the earliest possible signal; a workflow whose only automatic trigger is the RC TAG push itself cannot exist before the tag and gates `release stable` instead. Gating a tag-fired workflow at the cut is a deadlock: the pre-flight would demand runs that only the tag it refuses to cut can start.

## The pattern

A release gate is a check that a named GitHub Actions workflow has run successfully (or failed, or is pending, or has never run) at a specific commit SHA. The check returns a typed result that a pre-flight or hook step can branch on.

One generic function in `cli/internal/release/workflow_check.go` performs the check:

```go
result := release.CheckWorkflowAtCommit(release.WorkflowImages, sha)
switch result.Status {
case release.WorkflowCheckGreen:    // continue
case release.WorkflowCheckPending:  // tell operator to wait
case release.WorkflowCheckFailed:   // tell operator to fix or retry
case release.WorkflowCheckMissing:  // tell operator how to trigger it
case release.WorkflowCheckUnknown:  // GitHub API error; tell operator to retry
}
```

The generic workflow check has **any-green semantics**. Scenario gates are stricter: each required scenario needs its own successful job mark.

Every VM stage in `release-fleet-orchestrator.yaml` makes its dispatch decision per scenario with the same `release.DecideCoverage` library its promotion gate uses. The smoke stages call `./sb release covered`; the install-recovery and upgrade-arc stages call `./sb release covered-subset` and dispatch only the returned selectors. Both call sites read `ops/release/upgrade-sensitive-paths.txt`, which is the single upgrade/install/recovery sensitivity list. There is no workflow-local second implementation of that rule.

## Naming convention

Every gate uses the same chain of names — workflow filename, Go constant, env-var bypass — derived from one canonical concept. **One concept, one name, consistently everywhere.** There is no "ci-" prefix on anything — the workflow directory already conveys CI, and per-workflow names should not duplicate that scope.

| Workflow file (`.github/workflows/*.yaml`) | Go constant (`release.*`) | Bypass env var | Gate layer |
|---|---|---|---|
| `images.yaml`            | `WorkflowImages`           | (no bypass — checked indirectly via `release.CheckAssets` / `release.CheckManifests` in `ValidateStableTag`) | `release prerelease` pre-flight + `verify-images` |
| `fast-tests.yaml`        | `WorkflowFastTests`        | `SKIP_FAST_TESTS=1`     | `release prerelease` pre-flight |
| `go-test.yaml`           | `WorkflowGoTest`           | `SKIP_GO_TEST=1`        | `release prerelease` pre-flight |
| `app_build_and_lint-workflow.yaml` | `WorkflowAppBuildLint` | `SKIP_APP_BUILD_LINT=1` | `release prerelease` pre-flight |
| `test-hardening.yaml`    | `WorkflowTestHardening`    | `SKIP_TEST_HARDENING=1` | `release stable` pre-flight (tag-fired, STATBUS-205) |
| `test-smoke.yaml`        | `WorkflowTestSmoke`        | `SKIP_TEST_INSTALL=1` (compatibility name) | `release stable` pre-flight, fixed two-scenario coverage domain |
| `install-recovery-harness.yaml` | `WorkflowInstallRecoveryHarness` | `SKIP_INSTALL_RECOVERY=1` | `release stable` pre-flight (tag-fired) |
| `upgrade-arc-harness.yaml` | `WorkflowUpgradeArcHarness` | `SKIP_UPGRADE_ARCS=1` | `release stable` pre-flight (tag-fired; path-sensitive ride, STATBUS-199 D2) |

The Go constant name is `Workflow` + CamelCase of the workflow filename. The env var is `SKIP_` + uppercase-with-underscores of the workflow filename. Both derive mechanically from the workflow's own name; neither encodes a separate concept.

## Where each gate fires

- **`images.yaml`** — pre-push hook (`./sb release verify-images <sha>`) gates the prerelease tag push. Also indirectly gates `./sb release stable` via `CheckAssets` / `CheckManifests` against ghcr.io.
- **`fast-tests.yaml`** — gates `./sb release prerelease` (runs in pre-flight; STATBUS-199 D1). Triggers on every `master` push plus `pull_request` plus `workflow_dispatch`. Because it runs on master push, a run exists for the commit before any tag — the same shape as `images.yaml`. Self-contained on the GHA runner: builds `sb`, brings up the full Docker stack, and runs `./dev.sh migrate-and-test fast` (the pg_regress fast suite, excluding the large 4xx/5xx import tests). Closes the gap where derivation/baseline drift could land silently red on master: `images.yaml` builds artifacts but does not run pg_regress, and `pg_regress.yaml`'s remote SSH suite is complementary (deeper coverage, external-server-dependent).
- **`go-test.yaml`** — gates `./sb release prerelease` (runs in pre-flight; STATBUS-199 D1). Triggers on every `master` push plus `pull_request` plus `workflow_dispatch`. Pure Go, no Docker: runs `go vet ./...` then `go test ./...` in `cli/` (the CLI's ~44 unit-test files across `cli/cmd` + `cli/internal`, including the upgrade/recovery self-heal suite). Closes the gap where a Go-layer regression could land silently red on master: neither `images.yaml` nor `fast-tests.yaml` runs `go test` (`fast-tests` is the pg_regress suite only).
- **`test-hardening.yaml`** — gates `./sb release stable` (runs in pre-flight). Triggers ONLY on prerelease tag push (`v*-rc.*`) plus `workflow_dispatch` — no run can exist before the RC tag, so it cannot gate the cut (STATBUS-205).
- **`test-smoke.yaml`** — dispatch-only two-entry matrix for `0-happy-install` and `0-happy-upgrade`. The orchestrator passes only uncovered selectors, at most once. Stable promotion evaluates both scenario marks independently, including historical marks under the deleted `test-install.yaml` and `test-upgrade.yaml` identities.
- **`install-recovery-harness.yaml`** — gates `./sb release stable` per scenario. It provisions a Hetzner cx23 VM per selected recovery scenario.

## Paid fleet queue operations

The exact paid workflow set is `test-smoke.yaml`, `install-recovery-harness.yaml`, and `upgrade-arc-harness.yaml`. All three use the native `hetzner-vm-fleet` concurrency group with `cancel-in-progress: false` and `queue: max`.

Inspect the ordered owner and waiters with:

```bash
gh api repos/statisticsnorway/statbus/actions/concurrency_groups/hetzner-vm-fleet \
  --jq '.group_members | to_entries[] | {position:(.key + 1),id:.value.run_id,name:.value.run_name,status:.value.status,url:.value.run_html_url}'
```

To remove stale pending work, select one waiter by ID and cancel only that run:

```bash
gh run cancel <pending-id>
```

Never use a bulk-cancel command. Cancelling the running owner is not routine queue maintenance because it can interrupt VM cleanup.

The pre-flight in `cli/cmd/release.go` runs each gate independently — each can be SKIP-bypassed individually for surgical operator control.

## Adding a new gate

To add a workflow gate (call it `test-X.yaml`):

1. Create `.github/workflows/test-X.yaml` triggered on `tags: ['v*-rc.*']` + `workflow_dispatch`. Workflow exits 0 on success, non-zero otherwise.
2. Add a constant in `cli/internal/release/workflow_check.go`:
   ```go
   const WorkflowTestX = "test-x.yaml"
   ```
3. Add a pre-flight gate in `releaseStableCmd.RunE` in `cli/cmd/release.go` at the correct trigger layer. Include the `SKIP_TEST_X=1` bypass when approved.
4. Update the table in this document.

That is the entire surface. No new functions, no new types, no new error-message catalog — the generic helper provides all of them.

## Why the pre-push hook only checks ci-images

The pre-push hook gates the prerelease tag push. Tag-dependent release evidence cannot gate the cut that creates its tag, so it is checked at stable promotion instead.

- **Pre-push hook**: only checks workflows that have already run by the time the tag exists (i.e., master-push-triggered ones — currently just ci-images).
- **`./sb release stable` pre-flight**: checks workflows that run on prerelease tag push. The operator runs `./sb release stable` after the prerelease has had time to complete its workflows; if a workflow is still pending, the gate prints "wait then retry."

## SKIP env vars are not lockable

A SKIP env var is an explicit operator bypass for emergencies (unforeseen circumstances, time pressure, Hetzner outage, etc.). It logs loudly in the pre-flight transcript so the bypass is visible. There is intentionally no way to disable the bypass — when the situation calls for it, the operator needs the escape valve. Each gate has its own SKIP var so a bypass is surgical (one gate, not all of them).
