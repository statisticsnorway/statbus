---
id: STATBUS-089
title: >-
  maintenance-path-split: maintenance mode dead on all standalone+private boxes
  since 2026-04-14 — writer/template/mount 3-way path mismatch (reconcile to
  /statbus-maintenance/active)
status: Done
assignee: []
created_date: '2026-06-18 12:59'
updated_date: '2026-06-18 17:02'
labels:
  - upgrade-ui
  - maintenance
  - standalone
  - post-rc.04
dependencies: []
documentation:
  - doc-013
priority: high
ordinal: 89000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OBSERVED (King, no.statbus.org = standalone/rune box, rc.04 upgrade, 2026-06-18): during the upgrade, https://no.statbus.org/ did NOT redirect to the maintenance page. Users hitting the site mid-upgrade would see errors / a broken site instead of a maintenance notice.

NOTE: not flagged on dev.statbus.org (multi-tenant/private mode) — so this may be STANDALONE-mode-specific. dev (private, behind host proxy) vs no (standalone, public HTTPS via Caddy + Let's Encrypt) have different Caddy configs.

INSPECTION (delegated):
- How is the maintenance page served during an upgrade? (Caddy/proxy-level intercept vs app-level redirect vs a maintenance flag/file the proxy checks.)
- What sets/clears maintenance mode around an upgrade (the upgrade service? a flag file? a Caddy reload?).
- Why did it fail in STANDALONE mode? Compare the standalone Caddy template/maintenance path vs the cloud/private one (cli/src/templates/*.caddyfile.ecr; doc on deployment modes).

Real during-upgrade UX failure (users see errors, not maintenance). Post-rc.04; not a data-loss issue but operator/user-facing during every upgrade.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ROOT CAUSE (mechanic, 2026-06-18) — CONFIG DRIFT on rune, not an rc.04 code bug.
Mechanism: setMaintenance() (cli/.../exec.go:212-236) writes/removes ~/maintenance (=/home/statbus/maintenance). Caddy serves maintenance.html (503) via `try_files /home/statbus/maintenance` (standalone.caddyfile.ecr:75-87, the CURRENT repo template).
Drift: rune's DEPLOYED caddy/config/standalone.caddyfile uses an OLD path — `@maintenance { file /statbus-maintenance/active }` (an older Docker bind-mount convention). The service writes ~/maintenance; Caddy watches /statbus-maintenance/active → mismatch → maintenance never activates. Repo template is correct; the deployed config predates the convention change.

IMMEDIATE FIX (rune): regenerate the Caddyfile from the current template — `./sb config generate` (or re-run the idempotent install) on rune. This is a PRODUCTION change (foreman won't SSH-write; King to run or approve).

DEEPER PRODUCT GAP (Albania-relevant, route to architect): the rc.04 UPGRADE did NOT regenerate the Caddy config from the new version's template, so a template/convention change (here: the maintenance path) does NOT propagate to existing boxes on upgrade. Question: should the upgrade flow regenerate config (Caddyfiles/.env) from the new version's templates so drift self-heals everywhere? If not, every template change is a latent footgun on already-deployed boxes (incl. Albania). Confirm whether the upgrade's install-fixup runs config generate + why it didn't heal this.

ARCHITECT DESIGN + ROOT-CAUSE (2026-06-18) = backlog doc-013. REFRAMES the task: NOT primarily a config-regen gap. Verified root cause = a THREE-WAY maintenance-path split that has made maintenance mode NON-FUNCTIONAL on every standalone+private box since 2026-04-14: setMaintenance writes host ~/maintenance (exec.go:216 + service.go:2846); Caddy template checks in-container /home/<user>/maintenance (standalone.caddyfile.ecr:77, private:109); compose mounts host ~/statbus-maintenance -> container /statbus-maintenance (caddy/docker-compose.yml:28, install.go:1068). Nothing is mounted at /home/<user>/maintenance, so the @maintenance matcher never fires. Regression = commit 24b0ae771 'fix(upgrade): align maintenance flag path with Caddy (~/maintenance)' which moved writer+template but NOT the mount. Config-regen cannot fix it (regenerates the same broken directive).

FIX (PART A, the bug): reconcile to /statbus-maintenance/active (the dir-mount convention the infra already implements) — setMaintenance writes ~/statbus-maintenance/active; templates try_files /statbus-maintenance/active; KEEP the mount+install.go; + a structural invariant test (3 paths agree, like TestVersionTrackedAlignedWithUpgradePipeline); + reconcile the secondary HTML-serving root (standalone:82, also unmounted). PART B (config self-heal): ALREADY EXISTS — config-generate on upgrade (service.go:4487, STATBUS-058) + proxy recreate (step11RestartServices service.go:120, version-tracked containers.go:103, Caddyfile bind-mount compose:20) -> next upgrade self-heals every box after PART A ships. Residual: standalone ./sb config generate should reload the proxy (reuse cert.go:145). Idempotent + don't-clobber already satisfied (.env.config = customization surface; generated files disposable). RE-SCOPE: small clean-break in setMaintenance + 2 templates + guard test, not a new mechanism.

VERIFIED REFRAME (architect doc-013, foreman cross-checked the 3 sources 2026-06-18) — SUPERSEDES the earlier 'config drift on rune / upgrade-should-regen-config' diagnosis, which was WRONG. ALARM-REVERSAL, confirmed in code:
- MOUNT: caddy/docker-compose.yml:28 binds host ~/statbus-maintenance → container /statbus-maintenance (ro).
- WRITER: setMaintenance writes host ~/maintenance (exec.go:216 = filepath.Join(HOME,"maintenance"); also service.go:2846).
- CADDY (in-container) checks: try_files /home/<deployment_user>/maintenance (standalone.caddyfile.ecr:77, private:109).
The container has ONLY /statbus-maintenance mounted; the writer's host ~/maintenance is NOT visible at the in-container /home/<user>/maintenance path → the @maintenance matcher NEVER fires → maintenance mode is non-functional on EVERY standalone+private box since commit 24b0ae771 (2026-04-14, 'align maintenance flag path with Caddy' — it moved writer+template to /home/<user>/maintenance but left the mount at /statbus-maintenance; aligned 2 of 3). rune's 'stale' /statbus-maintenance config was actually the CORRECT convention. The mechanic's first pass compared writer-vs-template (both /home/<user>/maintenance, looked 'aligned') and MISSED the mount.

FIX (PART A — the real bug, clean break, one commit): reconcile all three to /statbus-maintenance/active (the dir-mount the infra already implements): setMaintenance writes ~/statbus-maintenance/active; templates try_files /statbus-maintenance/active; KEEP the mount + install.go's dir creation. PLUS: a structural invariant test (the 3 paths agree, like TestVersionTrackedAligned...) so it can't silently recur; AND reconcile the secondary HTML-serving `root` (standalone:82) which also points at an unmounted path.
FIX (PART B — config-regen, ALREADY SOLVED): upgrade runs config-generate (service.go:4487, STATBUS-058) + recreates the proxy to read the bind-mounted Caddyfile (step11RestartServices). So once PART A ships, the next upgrade self-heals every box — no new flow step. Residual: standalone `./sb config generate` should also reload the proxy (reuse cert.go:145) for non-upgrade edits. Idempotent + don't-clobber already satisfied (config-generate is a pure render; .env.config is the operator surface, .env+Caddyfiles are disposable derivatives).

VERIFY (doc-013 §5): curl the site mid-upgrade → expect 503 maintenance (the behaviour that silently regressed). SEVERITY: real Albania-relevant bug (maintenance never shows during any upgrade on standalone) but NOT a regression from rc.04 (2 months old). RE-SCOPE: Wave-2, small clean-break via engineer (service.go:2846 single-owner + templates disjoint + invariant test). Full detail: doc-013.

CORRECTION (architect, 2026-06-18) — supersedes my earlier 3-way-split / 3-unmounted-/home-paths note: that analysis read DEAD templates (cli/src/templates/*.caddyfile.ecr, legacy Crystal, NOT rendered — `rg "\.ecr" cli/ -g'*.go'` = 0). The LIVE templates are caddy/templates/*.caddyfile.tmpl (Go CLI, config.go:755 + :790-797) and were ALREADY CORRECT (file /statbus-maintenance/active :88/:120, root /maintenance-page :94/:126, root /statbus-tmp :73/:81/:105/:113; no /home/). REAL bug = WRITER-ONLY: setMaintenance (exec.go:216 + service.go:2846) wrote ~/maintenance, outside the ~/statbus-maintenance mount → live template's /statbus-maintenance/active check never saw the flag. FIX (engineer, foreman-committed): setMaintenance/cleanStaleMaintenance → maintenanceFlagHostPath()=~/statbus-maintenance/active (shared constants + MkdirAll); NO template/compose/schema change; + maintenance_path_test.go (reads LIVE .tmpl + compose + Go constants, asserts writer↔template↔mount agree + no unmounted template root). doc-013 reconciled with a correction banner. Caught by the engineer (I'd built on the operator's .ecr report + stale AGENTS.md/exec.go refs without checking the live renderer). Follow-on: delete dead cli/src/templates/*.ecr + the stale exec.go .ecr comment.

DONE 2026-06-18 — committed 52d3e04c6 (3 files, cli/internal/upgrade). CORRECTED DIAGNOSIS (engineer found, foreman+architect verified): the earlier 3-way-split / 3-unmounted-/home-paths analysis targeted DEAD templates (cli/src/templates/*.caddyfile.ecr — legacy Crystal, no longer rendered by any Go code; `rg '\.ecr|src/templates' cli/ -g'*.go'` = ZERO). The LIVE Go-rendered templates are caddy/templates/*.caddyfile.tmpl (config.go:755 + :790-797), and they were ALREADY CORRECT in both modes (file /statbus-maintenance/active :88/:120; root /maintenance-page :94/:126; progress-log root /statbus-tmp :73/:81/:105/:113; NO /home/ anywhere, all mounted). So the LIVE bug was PURELY the WRITER: setMaintenance wrote host ~/maintenance (OUTSIDE the bind-mount) while template+mount already agreed on /statbus-maintenance/active → the container never saw the flag → matcher never fired → maintenance dead on standalone+private.

FIX (writer-only, one atomic commit): exec.go — path-convention constants + maintenanceFlagHostPath() (~/statbus-maintenance/active) + maintenanceFlagContainerPath(); setMaintenance writes the mounted path + MkdirAll; comment corrected (cites the live .tmpl). service.go — cleanStaleMaintenance uses the same helper; progress log fixed. NEW maintenance_path_test.go: TestMaintenancePathAlignment reads the LIVE .tmpl + compose + the Go constants, asserts writer==template `file`==declared bind-mount, AND every template root/try_files is under a compose mount (fails on a reintroduced split or any unmounted path) — PASSES.

PART B (config self-heal on upgrade) already in place → next upgrade self-heals every box. E2E proof (curl 503 mid-upgrade) rides STATBUS-071 / a rune-shaped box. Architect-confirmed + foreman-verified against the live renderer; go build/vet + the upgrade pkg test green.

FOLLOW-ON (separate, mechanic verifying now): delete the dead cli/src/templates/*.caddyfile.ecr (the trap that misled the analysis). PART-B residual (standalone `./sb config generate` proxy-reload via cert.go:145) = orthogonal follow-on. LESSON: verify which artifact the LIVE code renders before analyzing it (foreman + architect both initially grepped the dead .ecr).
<!-- SECTION:NOTES:END -->
