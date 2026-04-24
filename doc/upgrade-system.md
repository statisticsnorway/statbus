# Upgrade System

The canonical reference for how StatBus upgrades itself. Three orchestration paths exist; they must never fight each other. The mutex contract described here is enforced in code so that running a manual install while the service is mid-upgrade fails loud with a diagnostic, rather than corrupting state.

## Three orchestration paths

| Path | Entry point | Owns | Respects | When to use |
|---|---|---|---|---|
| **Service** (automatic) | `./sb upgrade service` running as systemd user unit `statbus-upgrade@<slot>.service` | End-to-end upgrade lifecycle: discover → schedule → execute → recover | Its own advisory lock, the shared O_EXCL mutex flag | Production norm. Discovers and applies releases on a 6-hour cycle or on NOTIFY. |
| **Unified install** | `./sb install` | Single operator entrypoint — probes state and dispatches: fresh → step-table; scheduled row pending → `executeUpgrade` inline; crashed flag → recover + re-detect; live upgrade → refuse; pre-1.0 → refuse. | The shared O_EXCL mutex flag — step-table path acquires as `Holder="install"`, inline-upgrade path lets `executeUpgrade` write its own `Holder="service"` flag. | First-time install, repair, or dispatching a pending upgrade without waiting for the service tick. |
| **Cloud tool** | `./cloud.sh install <server>` | Fleet-level remote install: SSH + stop_and_unwedge + run `./sb install` + ensure_service_started | Its own fleet semantics; defers to the shared mutex for per-host safety | Operator updating a remote host from their own machine. |

GitHub Actions workflows (`deploy-to-<slot>.yaml`) trigger the service path — they run `./sb upgrade apply-latest` remotely, which sends a NOTIFY that the service picks up. Actions never call `./sb install` directly.

## Install state ladder

`./sb install` runs `install.Detect` (in `cli/internal/install/state.go`) once and dispatches on the result. The 8 states are ordered — detection is a top-down ladder.

| # | State | Probe signal | Dispatch |
|---|---|---|---|
| 1 | `StateFresh` | no `.env.config` | step-table (sets up a clean install) |
| 2 | `StateLiveUpgrade` | flag present, holder PID alive | refuse with diagnostic — point at `journalctl` |
| 3 | `StateCrashedUpgrade` | flag present, holder PID dead | `RecoverFromFlag` → re-`Detect` → re-dispatch (state may have advanced to scheduled-upgrade, nothing-scheduled, etc.) |
| 4 | `StateHalfConfigured` | `.env.config` present, `.env.credentials` missing | step-table |
| 5 | `StateDBUnreachable` | creds present, DB not reachable | step-table (brings services up) |
| 6 | `StateLegacyNoUpgradeTable` | DB up, no `public.upgrade` table | refuse — pre-1.0 install, manual upgrade path documented in `doc/CLOUD.md` |
| 7 | `StateScheduledUpgrade` | pending row in `public.upgrade` (state=`scheduled`, started_at IS NULL) | `executeUpgrade` inline via `upgrade.Service.ExecuteUpgradeInline` |
| 8 | `StateNothingScheduled` | no pending row; everything else healthy | step-table (idempotent config-refresh checkpoint) |

The inline dispatch for state 7 claims the scheduled row atomically (`UPDATE … WHERE state='scheduled' AND started_at IS NULL`) — if a racing service or concurrent install wins first, the losing caller sees `RowsAffected = 0` and bails with a clear diagnostic. After a successful inline upgrade, if the systemd upgrade unit is currently active, install restarts it so the long-running service picks up the new binary and migrations.

## Flag-file state machine

Both the upgrade service and `./sb install` write `~/statbus/tmp/upgrade-in-progress.json` via `O_CREATE|O_EXCL` — the kernel guarantees exactly one writer wins. The `Holder` field records which actor owns the file. The flag is the single source of truth for "is an orchestrated mutator in flight or crashed pending recovery".

Two formal states:

| State | Flag present | Meaning |
|---|---|---|
| **Idle** | no | Nothing orchestrated. Any caller (service, install, cloud.sh) can acquire. |
| **InProgress** | yes | Either a live mutator (Holder=service or install) is running OR a prior one crashed and needs recovery. |

Inside InProgress, the flag carries a PID and `pidAlive(PID)` acts as a **diagnostic subquery** that selects between two messages:
- PID alive → "wait for the running {upgrade|install}"
- PID dead → unreachable from `acquireOrBypass`; install.Detect returns StateCrashedUpgrade first and RecoverFromFlag reconciles the flag before dispatch

This is not a third state: it's an explanation for why the same InProgress state blocks the caller.

### Flag schema (`UpgradeFlag` in `cli/internal/upgrade/service.go`)

```go
type UpgradeFlag struct {
    ID          int       `json:"id"`           // public.upgrade.id (0 when Holder=="install")
    CommitSHA   string    `json:"commit_sha"`   // target commit ("" when Holder=="install")
    DisplayName string    `json:"display_name"` // tag, sha-prefix, or install description
    PID         int       `json:"pid"`          // os.Getpid() at write
    StartedAt   time.Time `json:"started_at"`
    InvokedBy   string    `json:"invoked_by"`   // e.g. "scheduled", "operator:jhf"
    Trigger     string    `json:"trigger"`      // coarse bucket for logs
    Holder      string    `json:"holder"`       // "service" or "install"
}
```

### Cleanup paths (all must remove the flag)

| Path | Location |
|---|---|
| Normal completion | `executeUpgrade` end, `service.go` |
| Rollback on failure | end of `rollback()`, `service.go` |
| Direct failure (e.g., pullImages) | end of `failUpgrade()`, `service.go` |
| Self-update restart recovery (success) | `recoverFromFlag`, `service.go` |
| Crash recovery (failure) | `recoverFromFlag`, `service.go` |
| completeInProgressUpgrade | `service.go` |
| Install-holder release | `ReleaseInstallFlag`, `service.go` (deferred from `runInstall`) |

If any new code path writes the flag, it MUST also remove it on all exit paths. The `rollback()` cleanup was added in Release 1; the `failUpgrade()` cleanup was added in Release 1.1 follow-up after a reviewer found that `pullImages` failure left the flag wedged until the next service restart.

## executeUpgrade pipeline

1. Pre-flight checks: downgrade guard, release-assets manifest, disk space, commit signature.
2. **writeUpgradeFlag** — flag goes on disk; mutex is now held.
3. Maintenance mode on (web UI shows "upgrading").
4. Stop application services; take DB backup.
5. `git checkout` target commit.
6. Docker compose pull new images.
7. Start database; wait for health.
8. `./sb migrate up --verbose` — apply pending migrations.
9. Start application services; wait for health.
10. Post-upgrade install fixup: `runInstallFixup` runs `./sb install --non-interactive --inside-active-upgrade` with `STATBUS_INSIDE_ACTIVE_UPGRADE=1`. The bypass signals are necessary because our flag is still on disk at this point; without them the child install would abort with "upgrade in progress".
11. Self-update binary if newer (`exit 42` → systemd respawn).
12. Mark `completed_at` on the DB row (or inherit the mark from `recoverFromFlag` on exit-42 path).
13. **removeUpgradeFlag** — mutex released.
14. Supersede older available rows; notify UI.

If any step from 4 onward fails, `rollback()` is called. It restores the previous git state, DB backup, and services, then removes the flag.

## Recovery contract (`recoverFromFlag`)

Called once at service startup, before the main loop begins. Also called by `./sb install`'s crashed-upgrade detection path (StateCrashedUpgrade) before re-detecting and re-dispatching. Outcomes:

1. **No flag on disk** → Idle; proceed.
2. **Flag on disk, owning PID is alive AND isn't us** → pathological (advisory DB lock should prevent two services coexisting; an install holder would be a surprise concurrent operator). Log an error and refuse to clean up; leave the flag for the operator to investigate.
3. **Flag on disk, owning PID is dead, Holder == "install"** → install crashed or was killed. There is no `public.upgrade` row to reconcile (install doesn't write one). Just remove the flag.
4. **Flag on disk, owning PID is dead, Holder == "service"** (or empty for legacy) → service crashed mid-upgrade. Compare git HEAD to `flag.CommitSHA`:
   - Match → the upgrade has landed at the target commit (either via normal completion, or via self-update + exit 42, or any other path that left HEAD on the target SHA); mark `completed_at`. The recovery code keys on `HEAD == flag.CommitSHA` and is intentionally agnostic about how HEAD got there.
   - Mismatch → real failure; mark `error` + `rolled_back_at`.
   Remove the flag. State is now Idle; main loop proceeds.

This is the ground-truth for "service autocorrects on startup." It is not optional, not a sweep, not belt-and-suspenders — it runs every time the service process starts (including every systemd restart) and must leave the server consistent before the main loop ticks.

## Mutex acquire in `./sb install`

See `cli/cmd/install.go:acquireOrBypass` and `cli/internal/upgrade/service.go:AcquireInstallFlag`. The acquire is gated on dispatch: only the step-table path acquires; the inline-upgrade path delegates mutex ownership to `executeUpgrade`.

**Step-table path** (states 1, 4, 5, 8):
- If the `--inside-active-upgrade` flag is set OR `STATBUS_INSIDE_ACTIVE_UPGRADE=1` env var is set, install does NOT acquire (the parent service already holds the flag). The ONLY legitimate caller that sets these is `runInstallFixup` in the upgrade service. Operators must never pass them.
- Otherwise, install attempts an O_EXCL acquire with `Holder="install"`. On success, defer-release on exit. On contention, abort with a diagnostic that branches on `Holder` and `pidAlive(flag.PID)` — see `install-mutex.md` for the message table.

**Inline-upgrade path** (state 7): install does NOT acquire the install-held flag. `executeUpgrade` writes its own `Holder="service"` flag internally (step 2 of the pipeline below) before any destructive step, serialising against any concurrent install or service via the O_EXCL primitive. This is the same flag the service path uses — two concurrent callers racing into `executeUpgrade` are serialised by the kernel on the flag file; the losing caller sees EEXIST and aborts cleanly.

**Crashed-upgrade path** (state 3): install calls `RecoverFromFlag` directly (via `runCrashRecovery` in `cli/cmd/install_upgrade.go`), which reads the stale flag, branches on `Holder` to reconcile `public.upgrade` if needed, and removes the file. Install then re-runs `Detect` and re-dispatches — recovery may have surfaced a freshly-scheduled row or left the install otherwise healthy.

## Design principle: silent soft-warnings are forbidden

A soft-swallowed warning (a `Note:` or `Notice:` printed to stdout but not acted on) is an operator lie: the system claims partial success while leaving state inconsistent. In the upgrade/install paths, this manifests as a `WARN: state transition matched 0 rows` that does nothing — the operator's admin UI or DB row is then wrong, silently.

Every failure that violates an expected invariant MUST either:
1. Fail fast with a named `INVARIANT <NAME> violated: …` message and (where applicable) write a support bundle so SSB can diagnose the failure remotely, or
2. Propagate the error up the call stack to the operator-facing exit path.

Logging a warning and continuing is never acceptable at a state-transition site. The only acceptable "continue" behaviour is when the failure is explicitly cosmetic (e.g., optional system_info key that is informational only) — and even then, the log line must be a WARN with a clear explanation of why continuation is safe, not a silent swallow.

## Related

- `doc/install-mutex.md` — mutex schema, decision tree, operator guidance.
- `doc/install-statbus.md` — where `install.sh` lives (this repo, served via niue host-Caddy 302-redirect to `raw.githubusercontent.com` on master) and how `--channel <stable|prerelease|edge>` resolves a version.
- `doc/CLOUD.md` — fleet-level deployment flow via GitHub Actions.
- `doc/DEPLOYMENT.md` — single-instance install and service management.
- `doc/upgrades.md` — operator runbook: troubleshooting, log locations, manual triggers.
