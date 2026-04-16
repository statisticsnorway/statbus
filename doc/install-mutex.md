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

Each holder removes the file on its own normal completion path. The service additionally reconciles any flag found at startup (or on demand via `./sb upgrade recover`), branching on `Holder` to decide whether DB cleanup is needed.

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
            └── Dead PID (any holder) → "Prior {upgrade|install} crashed.
                    Reconcile the stale flag:
                      ./sb upgrade recover
                    Equivalent: systemctl --user start 'statbus-upgrade@*'."
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
| "Prior {upgrade,install} crashed … PID X is no longer alive but the flag file remains." | Holder process died mid-run (OOM, kill, crash), or was stopped by an operator mid-run. | Run `./sb upgrade recover` directly (no service restart needed). It reads the flag, branches on `Holder` (service → mark DB row completed/failed by HEAD; install → just remove file), removes the flag. Retry install. Equivalent: `systemctl --user start 'statbus-upgrade@*'` — the service's startup handler does the same reconciliation. |
| "Upgrade flag file present but unreadable" | JSON corruption or incompatible schema. | Investigate `~/statbus/tmp/upgrade-in-progress.json` manually. If truly garbage, remove the file and start the service so `recoverFromFlag` can operate cleanly on the next cycle. |

## What the mutex does NOT cover

- Operator crash mid-install (SSH drop, terminal close). The flag's `defer release` doesn't fire when the process is killed. The flag persists with a dead PID; the next `./sb install` (or service start) sees it and points the operator at `./sb upgrade recover`. Re-running `./cloud.sh install <server>` is idempotent end-to-end and handles this automatically. Not kernel-auto-recovering: a future iteration could add a `flock` on a shared lock file so the kernel auto-releases on operator process exit. Deferred until observed incidents justify the added complexity.
- Text-file-busy on the `./sb` binary if the service is still running: avoided by `./cloud.sh install` issuing `systemctl stop` before binary replacement. Direct `curl install.sh | bash` on a live server would hit this; documented as "stop the service first" in `install-statbus.md`.
