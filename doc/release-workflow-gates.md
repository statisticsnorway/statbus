# Release workflow gates

This document explains how `./sb release stable` and `.githooks/pre-push` consult GitHub Actions workflow status as pre-flight gates, and how to add a new gate.

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

The check has **any-green semantics**: one completed/success run for the SHA is authoritative. A later retry queued or failed does not unbuild the artifact (in the case of images) or unrun the test (in the case of test-hardening / test-install). This matters when a transient infra flake causes a retry to fail after an earlier successful run already completed.

## Naming convention

Every gate uses the same chain of names — workflow filename, Go constant, env-var bypass — derived from one canonical concept. **One concept, one name, consistently everywhere.** There is no "ci-" prefix on anything — the workflow directory already conveys CI, and per-workflow names should not duplicate that scope.

| Workflow file (`.github/workflows/*.yaml`) | Go constant (`release.*`) | Bypass env var (`./sb release stable`) | CLI verifier (`./sb release verify-*`) |
|---|---|---|---|
| `images.yaml`            | `WorkflowImages`           | (no bypass — checked indirectly via `release.CheckAssets` / `release.CheckManifests` in `ValidateStableTag`) | `verify-images` |
| `fast-tests.yaml`        | `WorkflowFastTests`        | `SKIP_FAST_TESTS=1`     | (none — fires automatically in `release stable` pre-flight) |
| `test-hardening.yaml`    | `WorkflowTestHardening`    | `SKIP_TEST_HARDENING=1` | (none — fires automatically in `release stable` pre-flight) |
| `test-install.yaml`      | `WorkflowTestInstall`      | `SKIP_TEST_INSTALL=1`   | (none — fires automatically in `release stable` pre-flight) |
| `install-recovery-harness.yaml` | `WorkflowInstallRecoveryHarness` | `SKIP_INSTALL_RECOVERY=1` | (none — fires automatically in `release stable` pre-flight) |

The Go constant name is `Workflow` + CamelCase of the workflow filename. The env var is `SKIP_` + uppercase-with-underscores of the workflow filename. Both derive mechanically from the workflow's own name; neither encodes a separate concept.

## Where each gate fires

- **`images.yaml`** — pre-push hook (`./sb release verify-images <sha>`) gates the prerelease tag push. Also indirectly gates `./sb release stable` via `CheckAssets` / `CheckManifests` against ghcr.io.
- **`fast-tests.yaml`** — gates `./sb release stable` (runs in pre-flight). Triggers on every `master` push plus `pull_request` plus `workflow_dispatch`. Because it runs on master push (not RC-tag push), a run always exists at the RC's commit — the same shape as `images.yaml`. Self-contained on the GHA runner: builds `sb`, brings up the full Docker stack, and runs `./dev.sh migrate-and-test fast` (the pg_regress fast suite, excluding the large 4xx/5xx import tests). Closes the gap where derivation/baseline drift could land silently red on master: `images.yaml` builds artifacts but does not run pg_regress, and `pg_regress.yaml`'s remote SSH suite is complementary (deeper coverage, external-server-dependent).
- **`test-hardening.yaml`** — gates `./sb release stable` (runs in pre-flight). Triggers on prerelease tag push (`v*-rc.*`) plus `workflow_dispatch`.
- **`test-install.yaml`** — gates `./sb release stable` (runs in pre-flight). Triggers on prerelease tag push plus `workflow_dispatch`. Provisions a Hetzner cx23 VM and runs the 0-happy-install scenario of the install-recovery harness on it.
- **`install-recovery-harness.yaml`** — gates `./sb release stable` (runs in pre-flight). Triggers on prerelease tag push plus `workflow_dispatch`. Provisions a Hetzner cx23 VM per scenario and runs the FULL install-recovery suite (every C-class with a paired scenario). Sister to `test-install.yaml`: where `test-install` covers only the happy path (0-happy-install), this workflow covers the recovery surface (every failure-injection class). Much slower (~5-7h sequential vs ~15 min) but ~€0.13/run total. Operator dispatch supports a `scenarios` input for narrowing the suite when debugging a single failure.

The pre-flight in `cli/cmd/release.go` runs each gate independently — each can be SKIP-bypassed individually for surgical operator control.

## Adding a new gate

To add a workflow gate (call it `test-X.yaml`):

1. Create `.github/workflows/test-X.yaml` triggered on `tags: ['v*-rc.*']` + `workflow_dispatch`. Workflow exits 0 on success, non-zero otherwise.
2. Add a constant in `cli/internal/release/workflow_check.go`:
   ```go
   const WorkflowTestX = "test-x.yaml"
   ```
3. Add a pre-flight gate in `releaseStableCmd.RunE` in `cli/cmd/release.go`, parallel to the existing test-hardening / test-install blocks. Include the `SKIP_TEST_X=1` bypass.
4. Update the table in this document.

That is the entire surface. No new functions, no new types, no new error-message catalog — the generic helper provides all of them.

## Why the pre-push hook only checks ci-images

The pre-push hook gates the prerelease *tag push*. `test-hardening.yaml` and `test-install.yaml` only START running once the tag is on origin (their trigger is `push: tags`). Putting them in the pre-push hook would create a chicken-and-egg loop: the hook can't pass until the workflows have completed, but the workflows can't run until the tag has been pushed (which the hook is gating). So:

- **Pre-push hook**: only checks workflows that have already run by the time the tag exists (i.e., master-push-triggered ones — currently just ci-images).
- **`./sb release stable` pre-flight**: checks workflows that run on prerelease tag push. The operator runs `./sb release stable` after the prerelease has had time to complete its workflows; if a workflow is still pending, the gate prints "wait then retry."

## SKIP env vars are not lockable

A SKIP env var is an explicit operator bypass for emergencies (unforeseen circumstances, time pressure, Hetzner outage, etc.). It logs loudly in the pre-flight transcript so the bypass is visible. There is intentionally no way to disable the bypass — when the situation calls for it, the operator needs the escape valve. Each gate has its own SKIP var so a bypass is surgical (one gate, not all of them).
