---
id: doc-013
title: >-
  STATBUS-089 design: maintenance path reconciliation + config self-heal on
  upgrade
type: specification
created_date: '2026-06-18 15:20'
tags:
  - upgrade
  - maintenance
  - standalone
  - config
  - architect-plan
  - root-cause
---
# STATBUS-089 design — maintenance path reconciliation + config self-heal on upgrade

**Audience:** engineer (build), foreman (review). **Status:** root-caused, design ready. **TL;DR:** the task is framed as "upgrade should regenerate config so drift self-heals," but the verified root cause is a **three-way path split** that makes maintenance mode **non-functional on every standalone + private box since 2026-04-14** — regenerating config CANNOT fix it because the regen target (the Caddy template) is itself broken. The real fix is a small clean-break path reconciliation; the config-regen-on-upgrade part is **already implemented** and self-heals the fix on the next upgrade.

## 1. Verified root cause — three inconsistent maintenance paths
The maintenance flag-file is referenced by THREE places that no longer agree:
| Concern | Path | Where (file:line) |
|---|---|---|
| setMaintenance WRITES (host) | `~/maintenance` (=`/home/<user>/maintenance`) | cli/internal/upgrade/exec.go:216 (+ service.go:2846) |
| Caddy template CHECKS (in-container) | `/home/<deployment_user>/maintenance` | cli/src/templates/standalone.caddyfile.ecr:77 ; private.caddyfile.ecr:109 |
| compose MOUNTS (host→container) | `~/statbus-maintenance` → `/statbus-maintenance` | caddy/docker-compose.yml:28 ; dir created by cli/cmd/install.go:1068 |

Caddy runs IN the proxy container; its `file { try_files … }` matcher checks the path **absolutely, in-container**. There is **no mount at `/home/<user>/maintenance`** in any compose file (verified: only maintenance-related mounts are compose:28 `/statbus-maintenance` and compose:30 `/maintenance-page`). So the file setMaintenance writes (`~/maintenance`, a sibling of the mounted `~/statbus-maintenance/`) is never exposed at the path Caddy checks → **the `@maintenance` matcher never fires → maintenance mode never activates.**

### How it broke (git history)
- **2026-03-25 d7f8b1186** ("Add upgrade daemon…") added the compose mount `~/statbus-maintenance:/statbus-maintenance`. Original self-consistent convention = `/statbus-maintenance/active`.
- **2026-04-14 24b0ae771** ("fix(upgrade): align maintenance flag path with Caddy (~/maintenance)") moved setMaintenance + the templates to `/home/<user>/maintenance` **but did not update the compose mount**. It "aligned" the writer and the template to a path the container never mounts → introduced the split.

Both failure modes coexist in the field: a box with the OLD deployed Caddyfile (`file /statbus-maintenance/active`, e.g. rune) fails because setMaintenance writes the NEW path `~/maintenance` (not `~/statbus-maintenance/active`); a box whose Caddyfile was REGENERATED to the new template fails because `/home/<user>/maintenance` isn't mounted. Either way maintenance is dead. (Operator SSH-confirmation of rune's live state pending — confirmatory only; the code + git history are authoritative.)

## 2. PART A — the fix: reconcile to ONE convention (priority; the actual bug)
**Recommended convention = `/statbus-maintenance/active`** (the directory-mount convention the infra ALREADY implements). Tradeoff in one line: the alternative (`/home/<user>/maintenance`) needs a new home-dir/single-file mount — and bind-mounting a sometimes-absent single file makes Docker create a spurious directory at the source on container (re)create — whereas `/statbus-maintenance/` is a stable directory the compose mount + install.go already provide; pick the dir convention.

Exact edits (clean break, all sites in one commit — internal-code discipline):
1. **setMaintenance** (cli/internal/upgrade/exec.go:216) + the duplicate at **service.go:2846**: write/remove `filepath.Join(os.Getenv("HOME"), "statbus-maintenance", "active")` instead of `~/maintenance`. Update the comment exec.go:213-214 (it currently claims `~/maintenance` is "the path Caddy's try_files directive watches" — that claim is the bug).
2. **Templates** standalone.caddyfile.ecr:77 + private.caddyfile.ecr:109: `try_files /statbus-maintenance/active` (the container mount path) instead of `/home/<deployment_user>/maintenance`.
3. **compose:28 mount + install.go:1068**: KEEP as-is (already correct for this convention; `:ro` is fine — the host writes, the container only reads).
4. **SECONDARY — also reconcile the HTML-serving block** (standalone.caddyfile.ecr:82 / private.caddyfile.ecr:114): `handle @maintenance { root * /home/<user>/statbus/app/public; rewrite * /maintenance.html }` references `/home/<user>/statbus/app/public/maintenance.html`, which is ALSO not mounted into the proxy container (the mounted maintenance assets are at `/maintenance-page`, compose:30). Engineer: confirm where maintenance.html actually lives in-container and repoint `root`/rewrite to the mounted path so the 503 page renders once the matcher fires. (The matcher must fire first, so this is second-order — but fix it in the same pass.)

### Structural guard (King: "always add constraints")
Add a unit/integration test asserting the maintenance flag path agrees across the THREE sources (setMaintenance write path ↔ the templates' `try_files` path ↔ the compose mount target), mirroring the existing `TestVersionTrackedAlignedWithUpgradePipeline` invariant (which keeps `step11RestartServices` ↔ `versionTrackedServices` aligned). This makes a future three-way split impossible to merge silently.

## 3. PART B — config self-heal on upgrade (the foreman's framing — already mostly solved)
The "upgrade should regenerate config so drift self-heals" mechanism is ALREADY in place:
- **Regen runs on upgrade:** applyPostSwap step 7 runs `./sb config generate` via the NEW binary, post-checkout (service.go:4487; STATBUS-058, commit 7cc6c1b48). It rewrites `.env` + the Caddyfiles from the new version's templates.
- **The proxy is recreated to read them:** `step11RestartServices = {app,worker,rest,proxy}` (service.go:120) and the proxy is **version-tracked** (`versionTrackedServices`, containers.go:103) — its image tag changes per commit, so step 11's `docker compose up -d --no-build … proxy` (service.go:4711) RECREATES the proxy container. The Caddyfile is **bind-mounted** (`./config:/etc/caddy:ro`, compose:20), so the recreated proxy reads the freshly-generated Caddyfile. (This is the exact path the comment at service.go:4696-4701 restored after the "froze rune's proxy on a stale tag for 18 days" Bug-2.)

⇒ Once PART A ships, the corrected template + setMaintenance are in the new binary, and **the next upgrade self-heals every deployed box**: config-generate emits the corrected Caddyfile, step 11 recreates the proxy to read it. No new upgrade-flow step is needed for the upgrade path.

### Residual hardening (small, optional, not the bug)
A standalone `./sb config generate` (operator edits `.env.config` WITHOUT an upgrade) regenerates the Caddyfile but does NOT reload the running proxy — so a non-upgrade config change isn't applied until the next restart/upgrade. Recommendation: have `./sb config generate` (or a dedicated `./sb config apply`) optionally reload the proxy, reusing the existing Caddy-reload primitive at **cli/cmd/cert.go:145** (cert install already reloads Caddy). Keep it a reload, not a full recreate, when only the bind-mounted config changed.

## 4. The foreman's explicit questions answered
- **Should the upgrade regenerate Caddyfiles/.env from the new template?** It already does (service.go:4487) AND applies them (proxy recreate, service.go:4711). The gap was never regen — it was the broken path convention (PART A).
- **Where in the flow?** config-generate at applyPostSwap step 7 (post-checkout, pre-restart); applied at step 11 (proxy recreate). Correct placement; no change.
- **Idempotent?** Yes — config-generate is a pure render from `.env.config` + `.env.credentials`; re-running is a no-op when inputs are unchanged.
- **Don't clobber operator customizations?** Already satisfied by design: **`.env.config` is the operator's customization surface** (hand-edited); `.env` + the Caddyfiles are **disposable generated derivatives** (AGENTS.md: "`.env` … do not edit directly"). Regen never clobbers customizations because they live UPSTREAM of generation. The only way an operator could be clobbered is hand-editing a generated Caddyfile — which the convention forbids; surface that in the operator docs rather than trying to preserve hand-edits to generated files.

## 5. Verification (the run is the oracle)
1. **Unit:** the PART-A invariant test (paths agree across the three sources) — fast, runs in CI.
2. **End-to-end (real standalone VM, via the STATBUS-071 arc once it exists, or a manual rune-shaped box):** trigger an upgrade, and assert the maintenance 503 page is actually served by the running proxy DURING the upgrade window (curl the site, expect 503 + maintenance.html), then 200 after. This is the behaviour that silently regressed for ~2 months — only a live request proves it.
3. **rune immediate remediation (operator, no SSH writes):** ships via the fix + next upgrade (config-generate + proxy recreate). A one-off `./sb config generate` + proxy reload on rune is the manual stopgap if maintenance is needed before the next upgrade — but per "no manual DB/host writes," prefer driving it through the upgrade.

## 6. Scope note for the foreman
This RE-SCOPES STATBUS-089 from "build a config-regen-on-upgrade mechanism" (already exists) to "reconcile the maintenance path convention (PART A) + add the invariant guard + small standalone-reload hardening (PART B residual)." Smaller and cleaner than the original framing, and it's a self-contained clean-break fix in setMaintenance + 2 templates (+ test) that self-heals on the next upgrade. Sequenceable in Wave-2 via the engineer (touches service.go:2846 + exec.go — single-owner) with the template edits disjoint.
