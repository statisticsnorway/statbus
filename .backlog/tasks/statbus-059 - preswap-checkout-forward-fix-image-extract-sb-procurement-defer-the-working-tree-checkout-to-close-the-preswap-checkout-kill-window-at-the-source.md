---
id: STATBUS-059
title: >-
  preswap-checkout-forward-fix: APPROVED — image-extract the sb binary + switch
  code files only after the new program is in control (closes the upgrade
  crash-window wedge)
status: In Progress
assignee: []
created_date: '2026-06-15 22:10'
updated_date: '2026-06-15 23:03'
labels:
  - install-recovery
  - upgrade
  - recovery
  - procurement
  - architect-plan
  - king-decision
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - cli/Dockerfile.sb
  - .github/workflows/images.yaml
  - cli/cmd/seed.go
  - install.sh
  - cli/cmd/install_upgrade.go
  - test/install-recovery/scenarios/2-preswap-checkout-kill.sh
priority: high
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**APPROVED by the King 2026-06-15. Implement now (by morning). No open questions — decisions ruled below.**

## North Star (what / why)
If an upgrade crashes halfway, the operator fixes it with ONE command (`./sb install` / `curl install.sh`) — no expert surgery (STATBUS-039).

## What breaks today
Mid-upgrade the code runs `git checkout <new version>` BEFORE swapping the program. For a moment the new code's docker-compose files are on disk while the OLD program + OLD config (.env) are still in charge. Any `docker compose` call then config-parses the whole project and dies on a new required setting (REST_ADMIN_BIND_ADDRESS) the old .env lacks. A crash in that moment strands the box.

## The approved fix — 3 parts
1. **Get the new program from a ready-made image, not by compiling it.**
   - Tagged: `docker create statbus-sb:<commit>` + `docker cp /sb` (env-free; mirrors the seed, seed.go:160).
   - Edge/dev (no prebuilt image): `docker build -f cli/Dockerfile.sb` (builds in a container, no host Go/make), then copy /sb out.
   - DONE: commit 09ac1f7e4 (buildBinaryOnDisk → procureSbFromImage; commit_short from commitSHA, not the tree → checkout-independent). Pending foreman review + push.
2. **Switch the code files only after the new program is in control** — move the `git checkout` OUT of executeUpgrade (pre-swap) into the NEW binary's recovery boot, BEFORE boot-migrate, then config-generate. Mirror in runCrashRecovery.
3. **Refresh config on EVERY startup before the database** (not only when a flag is set). Fixes 0-happy (run 27578673237 FAILED: F1's regen was flag-gated; the scenario restarts onto the new binary with no flag → regen skipped → EnsureDBUp died). Parts 2+3 merge into ONE Service.Run change.
4. **install.sh edge image-extract** so recovery is toolchain-free on all channels. (Tagged ALREADY recovers via install.sh's existing re-stage — verified install.sh:203/209/269; only edge-on-a-bare-box was open. This closes it.)

## Correctness fix the team caught (incorporated — NOT a question)
First draft put the deferred checkout in applyPostSwap (after recoverFromFlag). BROKEN: boot-migrate-up (service.go:1612) runs BEFORE recoverFromFlag (1660) and needs the new code's migrations (schema-skew guard); a later checkout leaves schema old → recoverFromFlag hits SQLSTATE 42703 (renamed column) → boot-loop. CORRECT: checkout in the recovery boot BEFORE boot-migrate, then config-generate. Same end-state, correct order.

## Implementation (file:line)
Service.Run startup — recovery boot = service-held flag present:
1. if flag present: `git checkout flag.CommitSHA` (restore target tree)
2. config generate — UNCONDITIONAL (every boot)
3. EnsureDBUp
4. boot-migrate-up (target tree on recovery boot → no skew)
5. recoverFromFlag
runCrashRecovery (~install_upgrade.go:164): same checkout(flag.CommitSHA)+config-generate before DB bring-up.
executeUpgrade: REMOVE the pre-swap `git checkout`.
buildBinaryOnDisk: image-extract (DONE 09ac1f7e4). replaceBinaryOnDisk: LEAVE — downloads a verified manifest, needs no checkout; unifying would change the release trust model (separate concern).
install.sh: image-extract for edge binary acquisition.

## Decisions — RULED (no questions)
- D1 procurement scope: image-extract everywhere (edge build + recovery); leave replaceBinaryOnDisk. — KING: YES.
- D2 legacy wedge: SOLVED by D1 + install.sh's existing re-stage (tagged recovers today; edge closed by install.sh image-extract). Only residual = running the on-disk OLD `./sb install` directly (non-canonical); canonical action is `curl install.sh|bash`, which recovers. — ruled (per King approval).
- D3 test fidelity: YES — add a genuine-pre-fix-binary recovery variant (STATBUS-026) so the harness stops masking the real path. — ruled.

## Verification
Each commit: go build + vet + `go test ./internal/upgrade/ ./internal/install/ ./internal/config/`. Harness: 0-happy green + genuine-binary preswap-checkout-kill variant recovers. Foreman reviews every diff + pushes; cut rc.03 + run the comprehensive suite on it. Validation results by morning.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A toolchain-free host (no Go/make) completes both an edge-commit and a tagged-release upgrade end-to-end (sb procured by image-extract)
- [ ] #2 No git checkout of the target leaves the working tree at the target's compose while a pre-target binary remains systemd's restart target (verified by harness)
- [x] #3 The post-swap config-regen fix (STATBUS-058) is preserved and shown complementary to the deferred checkout
- [x] #4 King ruling D1 (procurement scope: unify vs narrower) recorded before implementation
- [x] #5 King ruling D2 (legacy v2026.05.2 wedge: accept vs mitigate via the legacy lever) recorded
- [x] #6 King ruling D3 (026 genuine-pre-fix recovery variant: yes/no) recorded
- [ ] #7 If D2=mitigate: operator `./sb install` on a crashed preswap-checkout flag recovers with no custom commands, by re-staging the target binary from the image
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
D1 RULING (King, 2026-06-15): YES — unify ALL binary procurement to image-extract. Mechanism = mirror the SEED (verified seed.go:160 uses plain `docker create` + `docker cp`, env-free, NO compose file): tagged → docker create statbus-sb:<commit> + docker cp /sb; edge/no-image → docker build -f cli/Dockerfile.sb (builds in a Go container, no host toolchain) then cp /sb. Env-free + toolchain-free. King's bootstrap ordering: env-free binary acquisition → binary runs `config generate` → regular env-requiring compose. NOTE: foreman recommended raw-docker (seed precedent) over a new compose file; flagged to King, awaiting only an objection (default = seed way). This also closes the edge-on-bare-box gap (the install.sh legacy-lever residual).

IMPLEMENTED (all parts, local; build + full-module `go vet` + `go test ./internal/upgrade/ ./internal/install/ ./internal/config/` green). Commits — 09ac1f7e4 + 7cc6c1b48 already pushed by foreman; 2f52f3b7f + f29e03a60 PENDING foreman review+push:
- Part 1 (image-extract procurement): 09ac1f7e4 — buildBinaryOnDisk `make` → procureSbFromImage (docker create statbus-sb:<short> + docker cp /sb; commit_short from `git rev-parse --short=8 commitSHA`, not the tree → checkout-independent; pre-staged skip + ./sb.old preserved).
- Part 3 (unconditional config-regen, every boot): 7cc6c1b48 — Service.Run regenerates config before EnsureDBUp UNconditionally (was flag-gated; 0-happy run 27578673237 restarts onto the new binary with no flag → regen skipped → death). Flag read kept only for the diagnostic log.
- Part 2 (defer the checkout — CORRECTED flag-gated-boot placement, NOT applyPostSwap): 2f52f3b7f — executeUpgrade drops `git checkout` (keeps fetch); Service.Run + runCrashRecovery `git checkout flag.CommitSHA` BEFORE config-generate AND before boot-migrate-up. Order now: [flag→checkout target] → config-gen → EnsureDBUp → boot-migrate (target tree → no skew) → recoverFromFlag.
- Part 4 (install.sh edge image-extract): f29e03a60 — edge channel procures sb via docker pull statbus-sb:<short> + create + cp /sb (fallback docker build -f cli/Dockerfile.sb, golang in-container); removed the `requires go` gate + `./dev.sh build-sb`. bash -n clean.

ENTANGLEMENT handled (flag for foreman review, security-adjacent): removing executeUpgrade's checkout broke the manifest tag-tampering verify, which relied on `git rev-parse HEAD` == target post-checkout. Changed it to compare commitSHA (the upgrade target) directly to manifest.CommitSHA — same anti-tampering property; the deferred `git checkout` errors on a bad ref.

AC status: #3 (F1/STATBUS-058 preserved + complementary) ✓ — the unconditional regen and the flag-gated checkout compose cleanly (checkout BEFORE regen on a recovery boot; regen unconditional on every boot). #1/#2/#7 are harness-gated (foreman validates: toolchain-free edge+tagged upgrade; window-3 closed; genuine-binary recovery via ./sb install) — leaving unchecked until 0-happy + the STATBUS-026 genuine-binary variant pass. STATBUS-026 NOTE: the 2-preswap-checkout-kill inject site's RED assertion ('working tree at target') is now stale (the tree stays at the source = the fix); inline comment updated; scenario assertion change is the 026 mechanic work.
<!-- SECTION:NOTES:END -->
