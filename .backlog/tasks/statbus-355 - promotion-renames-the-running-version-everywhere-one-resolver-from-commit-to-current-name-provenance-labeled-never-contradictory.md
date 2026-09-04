---
id: STATBUS-355
title: >-
  promotion renames the running version everywhere: one resolver from commit to current name; provenance labeled, never contradictory
status: To Do
assignee: []
created_date: '2026-09-04 11:07'
updated_date: '2026-09-04 11:07'
labels:
  - upgrade
  - app
  - ux
dependencies: []
priority: high
type: bug
ordinal: 348000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## The observed defect (2026-09-04, real boxes)

Dev installed `v2026.09.0-rc.14` (commit `d53731ec5`) at 08:56. At 10:54 the SAME commit was promoted to stable `v2026.09.0`. After dev's next discovery tick, one page showed two answers:

- Upgrade card title: `v2026.09.0 (d53731ec)` with badge `release` — CORRECT, re-resolved.
- Card grey subtitle: `v2026.09.0-rc.14` — stale.
- Page footer: `Statbus version v2026.09.0-rc.14 (d53731ec)` — stale.

Demo (channel stable, installed AFTER promotion) shows `v2026.09.0` everywhere with the SAME app image, proving the stale values are install-time state, not build-time baking.

Identity is the commit; a tag is a name attached later. A box running a commit that has been promoted IS running the release and must say so. Full investigation with file:line and dev DB evidence: `tmp/promotion-name-investigation.md` (copy into the PR if useful).

## Why one surface already works

Two layers exist and are correct:
1. Discovery enriches completed rows: appends new tags to `commit_tags`, promotes `release_status` (`cli/internal/upgrade/service.go:4987-5005`). Dev's row: `commit_tags={v2026.09.0-rc.14,v2026.09.0}`, `release_status=release`.
2. Read-time resolver `public.display_name(upgrade)`: prefers the tag without `-` (stable), else last tag, else short SHA. The admin card title requests this computed column.

The stale surfaces bypass the resolver:
- Subtitle renders `u.summary` (set to the tag name at registration, never updated) — `page.tsx:1236-1238`, `service.go:4971-4976`.
- `commit_version` is computed as `commit_tags[1]` (first-name-biased) at `service.go:4820-4821,5000-5001`; `./sb upgrade list` displays it raw (`cli/cmd/upgrade.go:219-228`).
- Footer reads `PUBLIC_STATBUS_VERSION` from the app container's environment, injected per request by `layout.tsx:45-60` but fixed when the container started; `.env` `VERSION` comes from `git describe` at config-generate time (`config.go:600-616,768-778`).

## The rule (decided; implement, do not relitigate)

- **Running version** (footer, card title, card version line, `./sb upgrade list`): resolved from the RUNNING COMMIT via the one resolver, `display_name` semantics (stable tag first, then prerelease, then short SHA).
- **Provenance** (binary build label, install-time name, event history): immutable, shown only with an explicit label — `built as v2026.09.0-rc.14`, `installed as ...` — never as a bare contradictory version.
- `./sb --version` stays exactly as built (ldflags): it names the artifact, honestly.
- History is never rewritten: callbacks, progress records, old rows keep their event-time names.

## What to do

1. **Publish running identity** `{commit_sha, resolved_name, release_status, build_name}` through `/rest` (extend `system_info` or a purpose-built view) resolved by the same SQL rule as `public.display_name`, keyed on the installed commit. Discovery already refreshes the ledger it reads from.
2. **Footer** (`footer.tsx` + `layout.tsx` fallback): show the resolved name from (1); fall back to the injected env value plus commit short if REST is unreachable. Optionally `built as <build_name>` in a tooltip or admin-only detail.
3. **Admin card subtitle** (`page.tsx:1236-1238`): stop rendering bare `summary`; render `Installed as <summary>` only when it differs from the title, else nothing.
4. **`./sb upgrade list`** (`upgrade.go:219-228`): display the resolver's name (`display_name` column), keep `commit_version` available as labeled provenance.
5. **Leave alone**: `commit_version` storage semantics (provenance), `summary` storage, `./sb --version`, callback payloads, progress/maintenance JSON.
6. **Do not touch the two safety guards**: same-commit skip at `service.go:4925-4949` (promotion must never schedule an upgrade, take a backup, enter maintenance, or run migrations) and the `apply-latest` convergence guard (`upgrade_apply_latest_decision.go:47-101`, parked is not converged).

## Done when (acceptance, from the investigation's 14-item list, condensed)

- A completed row with `commit_tags={vX-rc.N, vX}` on a box whose installed commit equals that row renders footer and card title `vX` with badge `release`, commit short unchanged, WITHOUT reinstall, container recreate, or any upgrade row change beyond the ledger.
- No surface shows an unlabeled rc name as the current version; rc appears only behind `built as` / `installed as`.
- `./sb upgrade list` shows `vX` for that row.
- `./sb --version` still prints the rc build label.
- Test covers the real sequence: install rc → same-SHA stable tag appears → discovery runs → resolved surfaces change, lifecycle state and timestamps do not, and no upgrade is scheduled (assert zero new rows, no maintenance flag, no backup).
- Resolver-unavailable fallback shows the env name + commit short, never a wrong newer name.
<!-- SECTION:DESCRIPTION:END -->
