---
id: STATBUS-060
title: >-
  defer-checkout-procure: move the upgrade git-checkout into applyPostSwap +
  extract the sb binary from its prebuilt image (closes the
  preswap-checkout-kill window for fixed-release-onward sources)
status: To Do
assignee:
  - architect
created_date: '2026-06-15 22:25'
labels:
  - upgrade
  - recovery
  - robustness
  - rc.03
dependencies:
  - STATBUS-058
references:
  - doc-011
  - cli/internal/upgrade/service.go
  - cli/internal/upgrade/exec.go
  - cli/cmd/seed.go
priority: high
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design of record: doc-011 (Layer 2). Blessed by the King (2026-06-15) to implement; targets rc.03.

## Why
`executeUpgrade` does `git checkout <target>` BEFORE the binary swap, leaving the working tree at the target's compose template while the OLD binary + key-deficient `.env` are still in control. A crash there (preswap-checkout-kill, window 3 in doc-011) restarts the OLD binary, whose every `docker compose` call dies on the target's new mandatory var → wedge, not `./sb install`-recoverable. F1 (87c38c4fb) does NOT cover this (old binary, preswap flag). Closing it requires the OLD binary to never see target-compose — i.e. defer the checkout past the binary swap. That is only possible if binary procurement no longer needs the checked-out tree.

## Two coupled changes (both in the upgrade service code = forward fix, effective for any source release carrying them)

### A. Image-based binary procurement (prerequisite)
Replace `buildBinaryOnDisk`'s `make -C cli build` with image extraction: `docker create ghcr.io/statisticsnorway/statbus-sb:<target_short>` → `docker cp <cid>:/sb ./sb` → `docker rm <cid>`, keeping `./sb.old`. Mirror the existing config-free pattern in `cli/cmd/seed.go` (seedFetch: docker create + docker cp /seed.pg_dump). The `statbus-sb:<commit>` image is built by images.yaml on every master push, so this consumes existing infra (engineer to confirm no Images-workflow change). Benefit beyond the defer: kills the host Go/make dependency (and the harness "go: not found" friction).
DECIDE + justify: unify `replaceBinaryOnDisk` (tagged path; already downloads a manifest artifact, needs no checkout) onto the same image-extract path, or leave it.

### B. Defer the working-tree checkout
Move `git checkout <target>` out of executeUpgrade's pre-swap section (service.go:~3831) INTO applyPostSwap, immediately before config-generate (service.go:~4112), on the NEW binary. Preserve: pre-upgrade branch pin + backup still run correctly pre-swap; the target's compose only materializes post-swap under the new binary; F1's regen-before-EnsureDBUp still fires.

## Verification (foreman reviews every diff + pushes; do NOT push yourself)
- `go build ./...` + `go vet ./...` + `go test ./internal/upgrade/ ./internal/install/ ./internal/config/` all green.
- Harness: 0-happy-upgrade green; plus the genuine-source-binary preswap-checkout-kill variant (STATBUS-026) must now RECOVER (window 3 closed) for a source carrying this change.
- Report each commit SHA to the foreman for byte-level review before push.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 buildBinaryOnDisk procures ./sb via docker create+cp from statbus-sb:<target> (no make-build); ./sb.old preserved; replaceBinaryOnDisk unification decision made + justified
- [ ] #2 git checkout <target> deferred into applyPostSwap (pre-config-generate); executeUpgrade pre-swap no longer leaves the working tree at target-compose
- [ ] #3 pre-upgrade branch pin + backup + F1 regen ordering preserved (no regression)
- [ ] #4 go build/vet/test green; reported to foreman before push
- [ ] #5 harness: 0-happy green AND a genuine-source-binary preswap-checkout-kill variant recovers (window 3 closed)
- [ ] #6 doc-011 updated with the final file:line + the replaceBinaryOnDisk decision
<!-- AC:END -->
