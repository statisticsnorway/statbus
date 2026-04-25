# Install ↔ Service mutex

This doc describes the contract that prevents `./sb install` from corrupting an in-flight upgrade. For the full system context see `upgrade-system.md`.

## What the mutex protects against

The upgrade service and `./sb install` both mutate the same things:
- the `./sb` binary file;
- the git working tree in `~/statbus/`;
- the `public.upgrade` table in the database;
- the database schema via migrations.

Running both concurrently would interleave these mutations unpredictably. The mutex ensures at most one orchestrated actor is modifying state at a time.

## The primitive: `~/statbus/tmp/upgrade-in-progress.json`

Both the upgrade service and `./sb install` write this file via `O_CREATE|O_EXCL` — the kernel guarantees exactly one writer wins when two race. The `Holder` field distinguishes ownership ("service" or "install"). The file's presence means "an orchestrated mutator is either running or crashed pending recovery."

Each holder removes the file on its own normal completion path. The service additionally reconciles any flag found at startup, branching on `Holder` to decide whether DB cleanup is needed. `./sb install` performs the same reconciliation on its crashed-upgrade detection path before re-dispatching.

## Flag schema

```go
type UpgradeFlag struct {
    ID          int       `json:"id"`           // 0 when Holder=="install"
    CommitSHA   string    `json:"commit_sha"`   // "" when Holder=="install"
    DisplayName string    `json:"display_name"` // version OR install description
    PID         int       `json:"pid"`          // os.Getpid() of the writer
    StartedAt   time.Time `json:"started_at"`
    InvokedBy   string    `json:"invoked_by"`   // specific trigger source
    Trigger     string    `json:"trigger"`      // coarse bucket
    Holder      string    `json:"holder"`       // "service" or "install"
}
```

`PID` is used by readers to distinguish "the holder is alive and actively running" from "the holder crashed and recovery is pending". See `pidAlive` in `cli/internal/upgrade/service.go`.

`Holder` drives recovery: a crashed service-held flag triggers `public.upgrade` reconciliation (mark completed if HEAD matches, failed otherwise); a crashed install-held flag is just a stale file to remove (install never writes a `public.upgrade` row).

## Decision tree at `./sb install` entry

`./sb install` first runs `install.Detect` (see `doc/upgrade-system.md` for the state ladder). Dispatch then branches:

- **StateLiveUpgrade** (flag present, PID alive) → refuse without touching state; point at `journalctl --user -u 'statbus-upgrade@*' -f`.
- **StateCrashedUpgrade** (flag present, PID dead) → call `RecoverFromFlag` directly (no install-flag acquire), then re-`Detect` and re-dispatch. Recovery reads `Holder`: `"service"` reconciles the `public.upgrade` row (completed if HEAD matches `flag.CommitSHA`, failed otherwise), `"install"` just removes the file.
- **StateScheduledUpgrade** (pending row) → delegate to `upgrade.Service.ExecuteUpgradeInline`. Install does NOT acquire the flag itself; `executeUpgrade` writes its own `Holder="service"` flag internally via `writeUpgradeFlag`. Ownership transfers cleanly via the filesystem-level O_EXCL handshake.
- **All other states** (Fresh, HalfConfigured, DBUnreachable, NothingScheduled) → run `acquireOrBypass`, then the step-table:

```
Bypass signal set (--inside-active-upgrade or env var)?
│
├── Yes → Verify-only. The upgrade service spawned us as runInstallFixup;
│         the parent already holds the flag. Log "bypass honored, PID X,
│         holder=Y, invoked_by=Z" and proceed without acquiring.
│
└── No → AcquireInstallFlag (writeFlagAtomic via O_CREATE|O_EXCL).
        │
        ├── Success → Proceed; defer ReleaseInstallFlag (removes the file
        │             iff our PID still owns it as Holder="install").
        │
        └── EEXIST → Read the existing flag for diagnostics:
            │
            ├── Live PID, Holder=="service" → "Upgrade in progress: PID X
            │       is running. Wait for it to complete:
            │         journalctl --user -u 'statbus-upgrade@*' -f"
            │
            ├── Live PID, Holder=="install" → "Another ./sb install is
            │       already running: PID X. Wait for it to complete."
            │
            └── Dead PID (any holder) → unreachable from acquireOrBypass.
                    install.Detect returns StateCrashedUpgrade first;
                    RecoverFromFlag reconciles the flag before dispatch.
```

Key invariant: exactly one actor ever holds the flag. The step-table path and the inline-dispatch path are mutually exclusive within a single `./sb install` run, so there is no moment where install holds the flag and then tries to hand off to `executeUpgrade`. Either `acquireOrBypass` runs (step-table) or it doesn't (inline dispatch).

## Bypass signals — use with care

Two signals exist. Either triggers the bypass:

- CLI flag `--inside-active-upgrade` (hidden from `--help`).
- Environment variable `STATBUS_INSIDE_ACTIVE_UPGRADE=1`.

**Only one caller in the codebase sets these: `runInstallFixup` in `cli/internal/upgrade/exec.go`**, called from `executeUpgrade` during the post-migration install step. It sets both redundantly — the flag for audit visibility in `ps`/logs, the env var for robustness through exec chains.

Operators must never set these. An operator who thinks they need to bypass the mutex is almost certainly facing a different problem (stale flag from a crash) and should follow the guidance in the abort message.

## Legacy flag files

Flag files written before Release 1 lack `PID` and `StartedAt`. JSON unmarshal gives `PID=0`. `pidAlive(0)` returns false by design (`pid <= 0` guard). So legacy flags are diagnosed as "crashed — recovery required", which is the correct recovery path.

Flag files written before Release 1.1 lack `Holder`. The empty default is treated as `"service"` everywhere it matters (`recoverFromFlag` and `formatContentionError`), preserving prior semantics for in-flight upgrades while the new install acquire path takes effect.

## Operator-facing symptoms and recovery

| Symptom | What happened | Recovery |
|---|---|---|
| "Upgrade in progress: PID X is running. Wait for it to complete." | The upgrade service is genuinely executing an upgrade right now. | Wait. Monitor with `journalctl --user -u 'statbus-upgrade@*' -f`. |
| "Another ./sb install is already running: PID X." | A second operator (or a script) started install while another install was still going. | Wait for the other invocation to finish, then retry. |
| "Prior {upgrade,install} crashed … PID X is no longer alive but the flag file remains." | Holder process died mid-run (OOM, kill, crash), or was stopped by an operator mid-run. | Re-run `./sb install` — it detects the stale flag automatically (StateCrashedUpgrade), calls RecoverFromFlag (service → mark DB row completed/failed by HEAD; install → just remove file), and continues. No separate recovery command needed. |
| "Upgrade flag file present but unreadable" | JSON corruption or incompatible schema. | Investigate `~/statbus/tmp/upgrade-in-progress.json` manually. If truly garbage, remove the file and start the service so `recoverFromFlag` can operate cleanly on the next cycle. |

## What the mutex does NOT cover

- Operator crash mid-install (SSH drop, terminal close). The flag's `defer release` doesn't fire when the process is killed. The flag persists with a dead PID; re-running `./sb install` (or `./cloud.sh install <server>`, which is idempotent end-to-end) detects it as StateCrashedUpgrade and reconciles automatically. Not kernel-auto-recovering: a future iteration could add a `flock` on a shared lock file so the kernel auto-releases on operator process exit. Deferred until observed incidents justify the added complexity.
- Text-file-busy on the `./sb` binary if the service is still running: avoided by `./cloud.sh install` issuing `systemctl stop` before binary replacement. Direct `curl install.sh | bash` on a live server would hit this; documented as "stop the service first" in `install-statbus.md`.

## Git branch pointers maintained by install/upgrade

The install/upgrade machinery keeps two local-only git branches under the `statbus/` namespace as per-host state pointers — neither is pushed to origin. They are complementary: `statbus/current` is **time-anchored** ("what is checked out right now"), while `statbus/pre-upgrade` is **event-anchored** ("what was checked out before the most recent upgrade started").

- **`statbus/current`** — written by `install.sh` at every checkout (idempotent via `git checkout -B`). Replaces detached-HEAD checkouts on tags so `git status` shows a real branch and `git reflog statbus/current` records the install history on this host. Semantic: "what install.sh last checked out" — the time-anchored pointer always reflects the latest install action (in-progress or completed; the canonical "currently running" answer comes from `./sb --version` or `public.upgrade.state='completed'`).
- **`statbus/pre-upgrade`** — written by `executeUpgrade` in `cli/internal/upgrade/service.go` before destructive steps. The event-anchored pointer freezes "the version BEFORE the upgrade started" and stays put through the upgrade, then advances on the next upgrade. Acts as the rollback fallback ref when the explicit `previousVersion` doesn't resolve (e.g., upstream tag pruning). See `restoreGitStateFn`.

Both branches are slot-implicit: each multi-tenant slot on niue has its own `~/statbus/.git`, so the same name on two slots refers to two independent pointers. Origin's deployment branches (`ops/cloud/deploy/<slot>`, `ops/standalone/deploy/<host>-<slot>`) are CI-driven and unrelated — they may diverge briefly from `statbus/current` during install, which is expected.

## Design principle: silent soft-warnings are forbidden

A soft-swallowed warning (a `Note:` or `Notice:` printed to stdout but not acted on) is an operator lie: the system claims partial success while leaving state inconsistent. In the upgrade/install paths, this manifests as a `WARN: state transition matched 0 rows` that does nothing — the operator's admin UI or DB row is then wrong, silently.

Every failure that violates an expected invariant MUST either:
1. Fail fast with a named `INVARIANT <NAME> violated: …` message and (where applicable) write a support bundle so SSB can diagnose the failure remotely, or
2. Propagate the error up the call stack to the operator-facing exit path.

Logging a warning and continuing is never acceptable at a state-transition site. The only acceptable "continue" behaviour is when the failure is explicitly cosmetic (e.g., optional system_info key that is informational only) — and even then, the log line must be a WARN with a clear explanation of why continuation is safe, not a silent swallow.
