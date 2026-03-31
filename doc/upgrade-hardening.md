# Upgrade System: Hardening + Plan Compaction

## Context

The upgrade system is fully implemented and deployed (Checkpoints 1-9, Steps 10-15 all DONE). Architecture is documented in:
- `doc/upgrades.md` — service operation, lifecycle, rollback, troubleshooting
- `doc/releases.md` — CalVer, release pipeline, CI images, image cleanup
- `doc/DEPLOYMENT.md` — standalone deployment with upgrade service section
- `doc/CLOUD.md` — cloud hybrid transition, deploy-via-NOTIFY
- `AGENTS.md` — full `./sb` and `./dev.sh` CLI reference

This document tracks the remaining hardening work from the overnight code review (2026-03-26).

---

## Fixes Applied

### Critical

1. **FetchManifest + selfupdate.Update bare `http.Get`** — DONE
   - `github.go`: FetchManifest now uses `githubRequest()`/`githubDo()` (auth, 30s timeout, rate-limit retry)
   - `selfupdate.go`: Update now uses `http.Client{Timeout: 120s}`

2. **Rollback `git checkout -f` unchecked** — DONE
   - `service.go`: rollback() now checks error from git checkout and config generate, logs CRITICAL warning

3. **dropCreateSQL identifier validation** — already resolved by Step 11 Fix 1 (commit `db33a6e0a`)

### Medium

4. **upgradeScheduleCmd `fmt.Sprintf` SQL** — DONE
   - `upgrade.go`: now uses psql `-v` variable binding instead of string interpolation

5. **Dead code `confirm()` in install.go** — DONE, deleted

6. **`from("upgrade" as any)` missing types** — DEFERRED
   - Upgrade/system_info tables don't exist in local dev database. Will be resolved when migrations are applied locally or types regenerated on a server with the tables.

7. **syncConfigToSystemInfo silent errors** — DONE
   - `service.go`: now logs warnings to stderr for .env load failures and Exec errors

### Low / Accept As-Is

8. **supersedeOlderReleases `discovered_at` ordering** — accepted (GitHub API returns chronological order)
9. **Health check fetches `/`** — accepted (works fine, not worth changing)
10. **Pre-existing TypeScript errors (18)** — out of scope

---

## Rollback Testing — Sentinel File

Implemented in `service.go`. After health check passes, checks for `tmp/simulate-upgrade-failure`:
- If present: deletes the file, triggers full rollback
- Documented in `doc/upgrades.md` Troubleshooting section

See `doc/upgrades.md` "Testing rollback" section for usage.

---

## UI Changes

### Upgrade button replaces logo badge
- Logo always links to `/` (no more hijacking home navigation)
- Separate dashed-border "Upgrade" button appears to right of logo when pending
- Color-coded: blue=available, yellow=scheduled/in_progress, pulse=in_progress

### Upgrades page: active vs history
- Active upgrades (available, scheduled, in_progress, failed, rolled_back) always visible
- Completed/skipped upgrades collapsed behind "N completed upgrades" trigger

---

## Release Sequence

### Release A: Hardening (RC-13)
Tag and push after all fixes committed. Upgrade service on dev.statbus.org applies it.

### Release B: Rollback test (RC-14)
1. Create sentinel: `touch ~/statbus/tmp/simulate-upgrade-failure`
2. Trigger upgrade to RC-14
3. Verify full rollback to RC-13
4. Upgrade to RC-14 for real (sentinel consumed)

---

## Backlog

| Item | Location | Priority |
|------|----------|----------|
| Port worker to Go | Checkpoint 9 (Phase B) | Future |
| YAML parser hand-rolled | `cli/cmd/users.go:60-126` | Revisit if format grows |
| Integration test on fresh VM | `test/integration/test-upgrade-vm.sh` | Next testing session |
| Generate types for upgrade table | Local dev DB needs migrations | Next recreate-database |
