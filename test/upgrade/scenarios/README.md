# Upgrade-service scenario scripts

Each file in this directory is a standalone shell script that exercises one named failure or recovery path in the upgrade service.

## Running a scenario

```bash
# Start the sandbox first
./dev.sh upgrade-sandbox up

# Run a scenario (once scripts exist)
bash test/upgrade/scenarios/<name>.sh

# Tear down
./dev.sh upgrade-sandbox down
```

The sandbox exposes:
- PostgreSQL on `127.0.0.1:3094` (user: `postgres`, db: `statbus_sandbox`)
- PostgREST on `127.0.0.1:3093`
- App on `127.0.0.1:3092`

## Scenario contract

A scenario script must:
1. Seed a `public.upgrade` row and/or `tmp/upgrade-in-progress.json` flag in the known fault state.
2. Start the upgrade service binary (compiled locally with a specific `cmd.commit` SHA if needed).
3. Wait for the service to reach a terminal state (poll `public.upgrade.state`).
4. Assert the expected final state — row state, flag file presence, services-up check.
5. Exit 0 on pass, non-zero on fail, with a pointer to the relevant log file on failure.

## Planned scenarios (see `tmp/engineer-upgrade-test-harness-design.md` §6)

| Name | Reproduces | Status |
|------|-----------|--------|
| `post-swap-binary-mismatch` | rune stuck state — stale post_swap flag, binary SHA mismatch, expect `rolled_back` | TODO |
| `ghost-flag-in-progress-row` | ghost flag + `in_progress` row → `recoverFromFlag` → `completeInProgressUpgrade` | TODO |
| `sigterm-mid-fixup` | SIGTERM during `runInstallFixup` → clean shutdown without hung goroutine | TODO |
| `db-restart-mid-scan` | `docker compose restart db` mid-rsync/scan → RST race, expect clean retry or rollback | TODO |
