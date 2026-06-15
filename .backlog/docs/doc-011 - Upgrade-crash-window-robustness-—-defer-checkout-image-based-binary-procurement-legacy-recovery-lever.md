---
id: doc-011
title: >-
  Upgrade crash-window robustness — defer-checkout + image-based binary
  procurement + legacy recovery lever
type: specification
created_date: '2026-06-15 22:24'
tags:
  - upgrade
  - recovery
  - robustness
  - design
  - rc.03
---
# Upgrade crash-window robustness — design of record

**Status:** blessed by the King (2026-06-15) to implement. Forward fix targets rc.03. One open item (install.sh acquisition) being nailed by the architect before the legacy-lever leg is finalized.

## North Star
Unattended upgrades across release boundaries — including boundaries that add a new **mandatory** docker-compose variable — must never wedge, and any crash must be recoverable by the operator's ONLY action: `./sb install`. This is on the critical path to external standalone deployments.

## Root cause (verified this session)
`docker compose` config-load-**parses the WHOLE merged project** before selecting any service. `docker-compose.yml` uses `include:` to merge `docker-compose.rest.yml` (et al.), and that file has `${REST_ADMIN_BIND_ADDRESS:?...}` (mandatory). Empirically, `docker compose config db`, `start db`, and `stop db` ALL exit 1 on the missing var even though only `db` is targeted. `REST_ADMIN_BIND_ADDRESS` was added by 9257eadc7 (unreleased) and is absent from any pre-this-release `.env` (e.g. v2026.05.2 = 50fd4325). `executeUpgrade` does `git checkout <target>` (service.go:~3831) BEFORE the binary swap, so the working tree holds the target's compose while a key-deficient `.env` and possibly the OLD binary are still in control → any compose call dies → upgrade/recovery wedges.

## The three crash windows
1. **post-swap boot** (NEW binary, post_swap flag) — covered by **F1** (commit 87c38c4fb): regenerate config before EnsureDBUp.
2. **binary-swap-kill** (NEW binary on disk, flag still preswap because updateFlagPostSwap stamps post_swap only AFTER replaceBinaryOnDisk) — covered by **F1's widened gate** (any service-held flag).
3. **preswap-checkout-kill** (crash after `git checkout` but before the binary swap → OLD binary restarts) — **NOT covered by F1** (old binary lacks the code; flag is preswap). This is the residual this design closes.

Verified: in window 3 the DB is STOPPED (backup stop, upstream of the checkout). A genuine v2026.05.2 binary's `runCrashRecovery` does config-generate (can't emit the new var) → `EnsureDBReachable` (connect-only) → FAILS on the down DB → returns; it has NO `StartDBForRecovery` fallback → **WEDGE**, before any compose call or rollback. `restoreGitState` itself is fine (`git checkout -f previousVersion`); 026's old RED was a harness pre-upgrade branch-pin bug (fixed ba02e1ed0).

## The fix (3 layers)

### Layer 1 — F1 (DONE, 87c38c4fb)
Regenerate config before EnsureDBUp on any service-held-flag boot. Covers windows 1 & 2.

### Layer 2 — Forward fix (TARGETS rc.03; implementable now, no open crux)
- **Defer the working-tree checkout:** move `git checkout <target>` out of executeUpgrade's pre-swap section INTO applyPostSwap (just before config-generate). The OLD binary then never leaves the tree at target-compose → window 3 cannot arise for any source release that carries this fix.
- **Image-based binary procurement:** replace `buildBinaryOnDisk`'s `make -C cli build` with `docker create ghcr.io/statisticsnorway/statbus-sb:<target_short>` + `docker cp <cid>:/sb ./sb` (keep `./sb.old`), mirroring `./sb db seed fetch` (cli/cmd/seed.go). This makes procurement checkout-independent (prerequisite for the defer) AND kills the host Go/make dependency (also removes the harness "go: not found" friction). Decide: unify `replaceBinaryOnDisk` (tagged path — already downloads a manifest artifact, needs no checkout) onto the same image-extract path, or leave it (justify in the implementation).
- The `statbus-sb:<commit>` image already exists — built by images.yaml on every master push ("a commit is installable iff its images include sb"). So this CONSUMES existing infra; no Images-workflow change expected (engineer to confirm).

### Layer 3 — Legacy lever (already-shipped v2026.05.2 boxes) — OPEN ITEM
A pre-fix binary can't be patched, so windows-3 recovery for a v2026.05.2 SOURCE needs the operator entry to run a NEWER binary. Proposed: on a crashed-upgrade flag, `./sb install` (or the install.sh script) reads `flag.target` → `docker create statbus-sb:<target>` + `docker cp /sb` → runs the TARGET binary's recovery (which emits keys + has StartDBForRecovery). 
**CRUX (architect resolving, with file:line):** does a stranded operator run a FRESH `install.sh` (curl'd latest, so a lever-carrying script reaches them) or the pinned on-disk one? 
- If fresh-curl → put the lever in install.sh; implement.
- If pinned/bundled → the legacy box can't receive the lever; document the residual + exact manual recovery (`git checkout OLD` then `./sb install`). Do NOT fake a solve.

## Scenario fidelity (folds into STATBUS-026)
`2-preswap-checkout-kill.sh:122` PRE-STAGES HEAD's sb and recovers with it → it validates HEAD-recovery (which recovers), MASKING the genuine v2026.05.2-binary wedge. Need a faithful variant that recovers with the GENUINE source binary (no HEAD pre-stage) to expose window 3 + assert the fix.

## Residual after this design
If Layer 3's lever is infeasible (pinned install.sh), upgrades FROM an already-shipped pre-fix release remain wedge-prone in the narrow window-3 timing, operator-recoverable only by documented manual steps. All upgrades FROM a release carrying Layers 1+2 forward are clean in all three windows. (King to accept or direct otherwise.)

## Implementation tasks
- Forward fix (Layer 2): defer-checkout + image-procurement. → new HIGH task.
- Legacy lever (Layer 3): gated on the install.sh-acquisition verdict. → new task.
- Scenario fidelity: genuine-binary variant. → STATBUS-026.
- F1 (Layer 1): done (87c38c4fb), validating via 0-happy run 27578673237 + comprehensive.

## Verification
Each implementation: `go build ./...` + `go vet` + `go test ./internal/upgrade/ ./internal/install/ ./internal/config/`; then the install-recovery harness (0-happy + the preswap-checkout-kill genuine-binary variant). Foreman reviews every diff + pushes; harness validates on Hetzner VMs.
