---
id: doc-013
title: >-
  STATBUS-089 design: maintenance path reconciliation + config self-heal on
  upgrade
type: specification
created_date: '2026-06-18 15:20'
updated_date: '2026-06-18 16:58'
tags:
  - upgrade
  - maintenance
  - standalone
  - config
  - architect-plan
  - root-cause
---
# STATBUS-089 design — maintenance flag writer-path fix (config self-heal on upgrade)

> **⚠️ CORRECTION (2026-06-18, architect).** This doc's earlier §1/§2 (the "three-way split" and the "three unmounted `/home/` paths" expansion) analyzed **DEAD templates** — `cli/src/templates/*.caddyfile.ecr` (legacy Crystal, no longer rendered). The **LIVE** templates are `caddy/templates/*.caddyfile.tmpl`, rendered by the Go CLI (config.go:755 `tmplDir=caddy/templates` + :790-797 map; `rg "\.ecr" cli/ -g'*.go'` = zero — nothing in Go reads `.ecr`). The live `.tmpl` templates are **already correct** (no `/home/` paths; all roots map to mounts). So the real bug is **writer-only**: `setMaintenance` wrote `~/maintenance` (outside the mount) while the live template + the compose mount already agree on `/statbus-maintenance/active`. Sections below are corrected. Root error: I trusted the `.ecr` path from AGENTS.md + a stale exec.go comment + the operator report without checking which templates the LIVE code renders. **Dead-`.ecr` cleanup is a separate follow-on.**

**Audience:** engineer (build) / foreman (review). **Status:** root-caused (writer-only), implemented, COMMIT-READY. **TL;DR:** maintenance mode never activated on standalone/private because `setMaintenance` wrote the flag to `~/maintenance`, a path NOT inside the proxy's `~/statbus-maintenance → /statbus-maintenance` bind-mount — while the (live `.tmpl`) Caddy template checks `file /statbus-maintenance/active`. The fix points the writer at `~/statbus-maintenance/active`. The config-regen-on-upgrade machinery (the task's original framing) already exists and self-heals on the next upgrade.

## 1. Verified root cause — writer-only path divergence
- **LIVE render path:** the Go CLI renders `caddy/templates/*.caddyfile.tmpl` (config.go:755 + the :790-797 templates map). `cli/src/templates/*.caddyfile.ecr` is dead legacy (Crystal `manage.cr`, deleted) — referenced only by a stale comment.
- **The live templates are CORRECT** (both modes; no `/home/` paths — verified):
  - maintenance flag matcher: `file /statbus-maintenance/active` (standalone.caddyfile.tmpl:88, private:120)
  - maintenance 503 HTML: `root * /maintenance-page` + `try_files /maintenance.html` (standalone:94-95, private:126-127)
  - upgrade-progress-log: `root * /statbus-tmp` (standalone:73/81, private:105/113)
- **The compose mounts match the templates** (caddy/docker-compose.yml): `/statbus-maintenance ← ~/statbus-maintenance`, `/maintenance-page ← ../ops/maintenance` (where maintenance.html + contact.js actually live — config.go:918), `/statbus-tmp ← ../tmp`.
- **THE BUG (writer):** `setMaintenance` (cli/internal/upgrade/exec.go:216) + the duplicate in service.go:2846 wrote/removed `~/maintenance` — a sibling of, NOT inside, the mounted `~/statbus-maintenance/` dir. So the host flag never appeared at the container path the live template checks (`/statbus-maintenance/active` = host `~/statbus-maintenance/active`) → the `@maintenance` matcher never fired → maintenance mode dead on standalone + private.

### How it broke (git history)
- **2026-03-25 d7f8b1186** added the compose mount `~/statbus-maintenance:/statbus-maintenance` and install.go's `~/statbus-maintenance` dir creation (:1068). Convention: `/statbus-maintenance/active`. The live `.tmpl` template has always matched this.
- **2026-04-14 24b0ae771** ("fix(upgrade): align maintenance flag path with Caddy (~/maintenance)") moved the WRITER (setMaintenance) to `~/maintenance` — which MIS-aligned it against the live template (still `/statbus-maintenance/active`). The commit title is ironic: it de-aligned the writer. The live template was not changed.

(Operator SSH-confirmed rune: deployed Caddyfile `/statbus-maintenance/active`, proxy at the rc.04 image — consistent with "template correct, writer wrong.")

## 2. The fix (writer-only) — IMPLEMENTED
Clean break in cli/internal/upgrade (single-owner; engineer, reviewed):
1. **setMaintenance + cleanStaleMaintenance → `maintenanceFlagHostPath()`** = `~/statbus-maintenance/active`, via shared constants (`maintenanceFlagDir` / `maintenanceFlagName`) + `MkdirAll` of the dir; the stale comment (exec.go:213-214 claiming `~/maintenance` is what Caddy watches) is fixed to cite the live `.tmpl`. The service.go:2846 duplicate uses the same helper.
2. **Templates + compose + install.go: NO CHANGE** — the live `.tmpl` already checks `/statbus-maintenance/active`, serves `/maintenance-page` + `/statbus-tmp`; the mounts already provide them. (Earlier drafts proposed template edits — those targeted the dead `.ecr`; the live `.tmpl` needs none.)
3. **Structural invariant test** `maintenance_path_test.go` (cli/internal/upgrade): reads the LIVE `caddy/templates/*.caddyfile.tmpl` + `caddy/docker-compose.yml` + the Go constants, and asserts (a) the template's `file` directive == `maintenanceFlagHostPath()`'s container path AND the host path is a declared bind-mount (writer↔template↔mount agree); (b) every template `root`/`try_files` path is under a declared compose mount ("unmounted path is dead in-container"). Reintroducing the writer↔template split fails (a); any unmounted template path fails (b). This is the "always add constraints" guard, on the live files — it makes the original (writer-vs-template) divergence un-mergeable.

## 3. PART-B — config self-heal on upgrade (the task's original framing — already solved)
Already in place; no work needed:
- config-generate runs on upgrade: applyPostSwap step 7 (`./sb config generate` via the new binary, post-checkout — service.go:4487; STATBUS-058). It re-renders the Caddyfiles from the new version's `.tmpl` templates.
- the proxy is recreated to read them: `step11RestartServices = {app,worker,rest,proxy}` (service.go:120), proxy version-tracked (containers.go:103), Caddyfile bind-mounted (`./config:/etc/caddy`, compose:20). So the next upgrade re-renders + reloads.
⇒ Once the writer fix ships, the next upgrade carries the corrected binary to every host; maintenance works thereafter with no per-host action. (The templates needed no fix, so even the regen is moot for THIS bug — but it's the mechanism that would have conveyed a template fix had one been needed.)

### Residual hardening (optional, not the bug)
A standalone `./sb config generate` (operator edits `.env.config` without an upgrade) re-renders config but doesn't reload the running proxy — a non-upgrade config change isn't applied until the next restart. Optional: have `./sb config generate` reload the proxy, reusing the Caddy-reload primitive at cli/cmd/cert.go:145.

## 4. The task's explicit questions answered
- **Should the upgrade regenerate Caddyfiles/.env from the new template?** It already does (service.go:4487) AND applies them (proxy recreate, service.go:4711). For THIS bug it was moot (the templates were already correct; the defect was the writer).
- **Idempotent / don't-clobber?** config-generate is a pure render from `.env.config` + `.env.credentials` (re-run = no-op on unchanged inputs); `.env.config` is the operator's customization surface, `.env` + Caddyfiles are disposable derivatives — regen never clobbers customizations.

## 5. Verification
1. **Unit:** `maintenance_path_test.go` (writer↔live-template↔mount alignment + no unmounted template path) — fast, CI.
2. **End-to-end (standalone VM, via the STATBUS-071 arc or a rune-shaped box):** trigger an upgrade; assert the maintenance 503 page IS served during the upgrade window (curl → 503 + maintenance.html), then 200 after. The behaviour that silently regressed for ~2 months; only a live request proves it.
3. **rune:** heals on the next upgrade (corrected writer ships in the binary). One-off `./sb config generate` is NOT sufficient for rune (the templates were already correct there; rune's issue is the running binary's writer path — fixed by the upgrade).

## 6. Scope note
STATBUS-089 reduces to a **writer-only** clean-break fix in cli/internal/upgrade (setMaintenance/cleanStaleMaintenance → maintenanceFlagHostPath) + the live-files invariant test. No template/compose/schema change. The original "config-regen mechanism" framing was already solved; the "3-path template reconcile" expansion was an analysis error on dead `.ecr` files (corrected above). FOLLOW-ON (separate, low-priority): delete the dead `cli/src/templates/*.ecr` + the stale exec.go `.ecr` comment so no future reader is misled (the very trap that caught this analysis).
