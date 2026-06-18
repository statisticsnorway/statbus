---
id: doc-013
title: >-
  STATBUS-089 design: maintenance path reconciliation + config self-heal on
  upgrade
type: specification
created_date: '2026-06-18 15:20'
updated_date: '2026-06-18 16:49'
tags:
  - upgrade
  - maintenance
  - standalone
  - config
  - architect-plan
  - root-cause
---
# STATBUS-089 design — maintenance path reconciliation + config self-heal on upgrade

**Audience:** engineer (build), foreman (review). **Status:** root-caused, design ready (REFINED 2026-06-18: the reconcile is THREE unmounted-path refs, not two — see §1/§2). **TL;DR:** the task is framed as "upgrade should regenerate config so drift self-heals," but the verified root cause is a **class of unmounted-path references in the caddy templates** — the proxy container is told to serve from `/home/<user>/…` paths that are NOT mounted into it. Maintenance mode (the reported symptom) is the most visible instance; there are two more of the same class. Config-regen CANNOT fix it because the regen target (the templates) is itself broken. The real fix is a small clean-break path reconciliation; the config-regen-on-upgrade part is **already implemented** and self-heals the fix on the next upgrade.

## 1. Verified root cause — the proxy serves from paths it doesn't mount
The proxy container (caddy/docker-compose.yml) mounts EXACTLY: `/etc/caddy` (./config), `/data` (./data), `/var/log/caddy`, `/statbus-maintenance` (`~/statbus-maintenance`), `/maintenance-page` (`../ops/maintenance`), `/statbus-tmp` (`../tmp`). Caddy runs IN that container; every `root */try_files` it evaluates is checked against the CONTAINER filesystem. But the templates reference **three `/home/<deployment_user>/…` paths that are NOT mounted**, so all three file-serving routes are broken:

| # | Template route | Current (broken) path | Mounted target it SHOULD use |
|---|---|---|---|
| 1 | upgrade-progress-log root | `/home/<user>/statbus/tmp` (standalone.caddyfile.ecr:67, private:99) | **`/statbus-tmp`** (mount `../tmp:/statbus-tmp`) |
| 2 | maintenance flag matcher | `/home/<user>/maintenance` (standalone:77, private:109) | **`/statbus-maintenance/active`** (mount `~/statbus-maintenance`) |
| 3 | maintenance 503 HTML root | `/home/<user>/statbus/app/public` (standalone:82, private:114) | **`/maintenance-page`** (mount `../ops/maintenance`; maintenance.html + contact.js live in `ops/maintenance/`, VERIFIED — not app/public) |

**The maintenance flag (#2) is a THREE-WAY split** (the reported bug): setMaintenance WRITES host `~/maintenance` (cli/internal/upgrade/exec.go:216 + service.go:2846); the template CHECKS in-container `/home/<user>/maintenance` (#2); the compose MOUNTS host `~/statbus-maintenance` → container `/statbus-maintenance` (caddy/docker-compose.yml:28; dir created by cli/cmd/install.go:1068). Nothing is mounted at `/home/<user>/maintenance`, AND the file setMaintenance writes (`~/maintenance`) is not inside the mounted dir → the `@maintenance` matcher never fires → maintenance mode never activates.

### How it broke (git history)
- **2026-03-25 d7f8b1186** added the compose mount `~/statbus-maintenance:/statbus-maintenance`. Original self-consistent convention = `/statbus-maintenance/active`.
- **2026-04-14 24b0ae771** ("fix(upgrade): align maintenance flag path with Caddy (~/maintenance)") moved setMaintenance + the templates to `/home/<user>/…` paths **but did not update the compose mounts** → introduced the split (and the same-class progress-log/html-root breaks).

(Operator SSH-confirmed rune's live state: deployed Caddyfile still `/statbus-maintenance/active`, proxy at the rc.04 image — confirmatory; the code + git history are authoritative.)

## 2. PART-A — the fix: reconcile ALL THREE template paths to their container mounts
Clean break, all sites in one atomic commit (internal-code discipline). The principle: **the proxy serves ONLY from its mounts; no `/home/<user>/…` paths in the templates.**
1. **setMaintenance** (cli/internal/upgrade/exec.go:216) + the duplicate at **service.go:2846**: write/remove `filepath.Join(os.Getenv("HOME"), "statbus-maintenance", "active")` instead of `~/maintenance`. Update the comment exec.go:213-214 (it currently claims `~/maintenance` is "the path Caddy's try_files directive watches" — that claim is the bug).
2. **Templates** — fix all THREE roots in BOTH standalone.caddyfile.ecr AND private.caddyfile.ecr:
   - progress-log root :67/:99 → `root * /statbus-tmp` (confirm the progress log is written to `tmp/upgrade-progress.log` so `/statbus-tmp/upgrade-progress.log` resolves).
   - maintenance matcher :77/:109 → `try_files /statbus-maintenance/active`.
   - maintenance 503 root :82/:114 → `root * /maintenance-page` (the `rewrite * /maintenance.html` line is unchanged; contact.js is served from the same `/maintenance-page`).
3. **compose mounts (caddy/docker-compose.yml) + install.go:1068**: KEEP as-is — they are already the correct convention; the templates were the drift. (`:ro` is fine — the host writes the flag, the container only reads.)

### Recommended convention + tradeoff (one line)
Standardize the maintenance flag on the directory-mount convention `/statbus-maintenance/active` (already implemented by compose:28 + install.go:1068). The alternative (mount the home dir / a single `~/maintenance` file) is fragile — bind-mounting a sometimes-absent single file makes Docker create a spurious directory at the source on container (re)create; the stable directory whose contents toggle is robust. Pick the dir convention.

### Structural invariant test (King: "always add constraints") — broadened to the whole class
Add a unit test that **fails if any caddy template references a `/home/` path**, AND asserts every absolute `root */try_files` path in the templates is a declared mount target in caddy/docker-compose.yml. This single invariant catches all three refs above, keeps setMaintenance's write-path ↔ the matcher path ↔ the mount in agreement, and makes a future "serve from an unmounted host path" merge impossible (mirrors the existing `TestVersionTrackedAlignedWithUpgradePipeline` invariant pattern). Stronger than asserting only the flag-path 3-way agreement.

## 3. PART-B — config self-heal on upgrade (the foreman's framing — already mostly solved)
The "upgrade should regenerate config so drift self-heals" mechanism is ALREADY in place:
- **Regen runs on upgrade:** applyPostSwap step 7 runs `./sb config generate` via the NEW binary, post-checkout (service.go:4487; STATBUS-058, commit 7cc6c1b48). It rewrites `.env` + the Caddyfiles from the new version's templates.
- **The proxy is recreated to read them:** `step11RestartServices = {app,worker,rest,proxy}` (service.go:120) and the proxy is **version-tracked** (`versionTrackedServices`, containers.go:103) — its image tag changes per commit, so step 11's `docker compose up -d --no-build … proxy` (service.go:4711) RECREATES the proxy container. The Caddyfile is **bind-mounted** (`./config:/etc/caddy:ro`, compose:20), so the recreated proxy reads the freshly-generated Caddyfile. (This is the exact path the comment at service.go:4696-4701 restored after the "froze rune's proxy on a stale tag for 18 days" Bug-2.)

⇒ Once PART-A ships, the corrected templates are in the new binary, and **the next upgrade self-heals every deployed box**: config-generate emits the corrected Caddyfiles, step 11 recreates the proxy to read them. No new upgrade-flow step is needed for the upgrade path.

### Residual hardening (small, optional, not the bug)
A standalone `./sb config generate` (operator edits `.env.config` WITHOUT an upgrade) regenerates the Caddyfiles but does NOT reload the running proxy — so a non-upgrade config change isn't applied until the next restart/upgrade. Recommendation: have `./sb config generate` (or a dedicated `./sb config apply`) optionally reload the proxy, reusing the existing Caddy-reload primitive at **cli/cmd/cert.go:145** (cert install already reloads Caddy). Keep it a reload, not a full recreate, when only the bind-mounted config changed.

## 4. The foreman's explicit questions answered
- **Should the upgrade regenerate Caddyfiles/.env from the new template?** It already does (service.go:4487) AND applies them (proxy recreate, service.go:4711). The gap was never regen — it was the broken template paths (PART-A).
- **Where in the flow?** config-generate at applyPostSwap step 7 (post-checkout, pre-restart); applied at step 11 (proxy recreate). Correct placement; no change.
- **Idempotent?** Yes — config-generate is a pure render from `.env.config` + `.env.credentials`; re-running is a no-op when inputs are unchanged.
- **Don't clobber operator customizations?** Already satisfied by design: **`.env.config` is the operator's customization surface** (hand-edited); `.env` + the Caddyfiles are **disposable generated derivatives** (AGENTS.md: "`.env` … do not edit directly"). Regen never clobbers customizations because they live UPSTREAM of generation. The only way an operator could be clobbered is hand-editing a generated Caddyfile — which the convention forbids; surface that in the operator docs rather than trying to preserve hand-edits to generated files.

## 5. Verification (the run is the oracle)
1. **Unit:** the PART-A invariant test (no `/home/` in templates; every template root/try_files path ⊆ compose mounts) — fast, runs in CI.
2. **End-to-end (real standalone VM, via the STATBUS-071 arc once it exists, or a manual rune-shaped box):** trigger an upgrade, and assert the maintenance 503 page is actually served by the running proxy DURING the upgrade window (curl the site, expect 503 + maintenance.html), then 200 after; AND that `/upgrade-progress.log` is fetchable during the upgrade (the progress-log route, fix #1). These are the behaviours that silently regressed for ~2 months — only a live request proves them.
3. **rune immediate remediation (operator, no SSH writes):** ships via the fix + next upgrade (config-generate + proxy recreate). A one-off `./sb config generate` + proxy reload on rune is the manual stopgap if maintenance is needed before the next upgrade — but per "no manual DB/host writes," prefer driving it through the upgrade.

## 6. Scope note for the foreman
This RE-SCOPES STATBUS-089 from "build a config-regen-on-upgrade mechanism" (already exists) to "reconcile the THREE unmounted-path template refs (PART-A) + add the invariant guard + small standalone-reload hardening (PART-B residual)." Smaller and cleaner than the original framing, and it's a self-contained clean-break fix in setMaintenance + the 2 templates (+ test) that self-heals on the next upgrade. Sequenceable in Wave-2 via the engineer (touches service.go:2846 + exec.go — single-owner) with the template edits disjoint. The 3-path scope is the whole same-class fix in one commit — do not fix 2 of 3 and leave the progress-log break latent.
