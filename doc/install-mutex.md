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

The upgrade service writes this file (and only this file-writing code path exists) before any destructive step in `executeUpgrade`. It removes the file on normal completion, on rollback, and during startup recovery. The file's presence means "an orchestrated upgrade is either running or crashed pending recovery."

`./sb install` reads the file. It never writes or removes it.

## Flag schema

```go
type UpgradeFlag struct {
    ID          int       `json:"id"`
    CommitSHA   string    `json:"commit_sha"`
    DisplayName string    `json:"display_name"`
    PID         int       `json:"pid"`         // the service process that wrote the flag
    StartedAt   time.Time `json:"started_at"`
    InvokedBy   string    `json:"invoked_by"`  // specific trigger source
    Trigger     string    `json:"trigger"`     // coarse bucket
}
```

`PID` is used by readers to distinguish "the service is alive and actively upgrading" from "the service crashed and recovery is pending". See `pidAlive` in `cli/internal/upgrade/service.go`.

## Decision tree at `./sb install` entry (`checkUpgradeMutex`)

```
Flag file present?
│
├── No → Idle state. Proceed with install.
│   (If bypass signal is set in this state, log "unexpected bypass" and proceed.)
│
└── Yes → InProgress state.
    │
    ├── Bypass signal set (--inside-active-upgrade or env var)?
    │   │
    │   ├── Yes → Log "bypass honored, PID X, invoked_by=Y" and proceed.
    │   │        (This is the upgrade service calling runInstallFixup.)
    │   │
    │   └── No → Proceed to liveness check.
    │
    ├── pidAlive(flag.PID) == true → An orchestrated upgrade is genuinely in flight.
    │       Abort with: "Upgrade in progress: PID X (<version>, invoked_by=Y) is running.
    │                    Wait for it to complete: journalctl --user -u 'statbus-upgrade@*' -f
    │                    Do NOT pass --inside-active-upgrade — that flag is the upgrade
    │                    service's internal contract with its own post-upgrade install step."
    │
    └── pidAlive(flag.PID) == false → Previous upgrade crashed or service was stopped mid-run.
            Abort with: "Prior upgrade crashed or was stopped mid-run: PID X (<version>) is
                         no longer alive but the flag file remains.
                         Trigger recovery by starting the service:
                           systemctl --user start 'statbus-upgrade@*'
                         The startup handler will clean up the flag."
```

## Bypass signals — use with care

Two signals exist. Either triggers the bypass:

- CLI flag `--inside-active-upgrade` (hidden from `--help`).
- Environment variable `STATBUS_INSIDE_ACTIVE_UPGRADE=1`.

**Only one caller in the codebase sets these: `runInstallFixup` in `cli/internal/upgrade/exec.go`**, called from `executeUpgrade` during the post-migration install step. It sets both redundantly — the flag for audit visibility in `ps`/logs, the env var for robustness through exec chains.

Operators must never set these. An operator who thinks they need to bypass the mutex is almost certainly facing a different problem (stale flag from a crash) and should follow the guidance in the abort message.

## Legacy flag files

Flag files written before Release 1 lack `PID` and `StartedAt`. JSON unmarshal gives `PID=0`. `pidAlive(0)` returns false by design (`pid <= 0` guard). So legacy flags are diagnosed as "crashed — restart service to recover", which is the correct recovery path: the service's `recoverFromFlag` will clean up the old-format flag on startup regardless of missing fields.

## Operator-facing symptoms and recovery

| Symptom | What happened | Recovery |
|---|---|---|
| "Upgrade in progress: PID X is running. Wait for it to complete." | The upgrade service is genuinely executing an upgrade right now. | Wait. Monitor with `journalctl --user -u 'statbus-upgrade@*' -f`. |
| "Prior upgrade crashed … PID X is no longer alive but the flag file remains." | Service process died mid-upgrade (OOM, kill, crash), or was stopped by an operator mid-run. | `systemctl --user start 'statbus-upgrade@*'`. The startup handler reads the flag, checks git HEAD, marks the DB row completed (if HEAD matches) or failed (if it doesn't), removes the flag. Retry install. |
| "Upgrade flag file present but unreadable" | JSON corruption or incompatible schema. | Investigate `~/statbus/tmp/upgrade-in-progress.json` manually. If truly garbage, remove the file and start the service so `recoverFromFlag` can operate cleanly on the next upgrade cycle. |

## What the mutex does NOT cover

- Two operators running `./sb install` on the same server simultaneously with no service in flight. Neither writes the flag; both proceed and race. Expected to be rare; operators coordinate out of band.
- Operator crash mid-install (SSH drop, terminal close). The service was stopped by the prior `systemctl stop`; it stays stopped until an operator runs `systemctl start`. Not kernel-auto-recovering; see the `flock` follow-up proposal at `plans/flock-followup.md` if this becomes a real incident.
- Text-file-busy on the `./sb` binary if the service is still running: avoided by `./cloud.sh install` issuing `systemctl stop` before binary replacement. Direct `curl install.sh | bash` on a live server would hit this; documented as "stop the service first" in `install-statbus.md`.
