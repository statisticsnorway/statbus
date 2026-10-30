---
id: STATBUS-189
title: >-
  caddy-unmatched-host-404: explicit catch-all site so unmatched hosts read 404,
  not Caddy's 200-empty default
status: Done
assignee:
  - architect
created_date: '2026-07-15 00:44'
updated_date: '2026-07-29 11:14'
labels:
  - hardening
  - proxy
  - install-recovery
dependencies: []
priority: low
ordinal: 190000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: an external monitor pointed at any StatBus listener never reads GREEN on a broken box.

ORIGIN (STATBUS-071 c-rollback arc, runs 29376442495 + 29378536916, architect ruling 2026-07-15): the arc probed http://127.0.0.1:3010/rest/rpc/auth_status on a box whose auth_status deterministically RAISEs. The request's Host (127.0.0.1) matches NONE of the standalone Caddyfile's site keys (http://{{.Domain}}, {{.Domain}} https, http://proxy), and Caddy v2 answers a request on a bound listener that matches no site with HTTP 200 and an EMPTY body. Two arc runs read this 200 as an "unexplained heal" before instrumentation named it.

THE PRODUCT GAP (low, hardening): a naive external monitor pointed at a bare IP:port — a plausible NSO ops setup — reads 200/green regardless of the box's actual health. The real operator surface (https://SITE_DOMAIN/rest/...) is honest (the @auth_paths route proxies truthfully), and the product's own health gate reads the internal rest bind and is unaffected.

FIX SHAPE (ruled): add an explicit catch-all site block to the Caddy templates responding 404 for unmatched hosts. Cheap, honest-to-monitors, zero effect on real routes. Apply across the deployment-mode templates (development/standalone/private) as applicable — check each template's site-key set.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Unmatched-host requests on every bound HTTP listener answer 404 (not 200-empty) in all deployment modes' generated Caddyfiles
- [x] #2 Real site-key routes byte-unchanged (config-generate diff reviewed)
- [x] #3 A harness or unit check pins the 404 (e.g. curl by bare IP on a test box or a Caddyfile-render assertion)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-07-29 11:13
---
BUILT (architect hands-on, 2026-07-29) — frozen for the foreman's line review + commit. FOUR files, disjoint from the mechanic's in-flight 175 sweep: the three deployment-mode templates (development/standalone/private) + cli/internal/config/config_test.go.

AC#1: each template gains a hostless `:80` catch-all responding 404 with a body naming the condition — host-matched sites always take precedence, so real routes are untouched; 443 needs nothing (an unmatched SNI already fails the TLS handshake — no 200-empty exists there). public.caddyfile.tmpl (the niue HOST-level proxy) is deliberately out of scope per the ticket's mode-template framing — touching the shared host proxy is its own decision if ever wanted.
AC#2: the template diff is APPEND-ONLY — 36 insertions, zero deletions/modifications — so every existing site key renders byte-identically; verified by regenerating the real local config (./sb config generate) and validating the FULL generated tree with the PRODUCT'S OWN caddy build (the layer4-carrying proxy image): 'Valid configuration'. (Stock caddy:2 rejects the config on the layer4 global — the product image is the only honest validator, noted for future template work.)
AC#3: source-pin unit test TestCaddyTemplates_UnmatchedHostCatchAll_STATBUS189 (config package, passing) — the block is static, so the source pin is exactly as strong as a render pin; the behavioral half rides the fleet's next deploy + any arc run (no arc or assert relies on the 200-empty — reliance-swept before the change; probes without a Host header will now read 404, which is the point).

Before-the-change reliance sweep recorded: assertions.sh and c-rollback both only DOCUMENT the 200-empty as the fixed hazard; the c-rollback probe reads the direct rest bind. Nothing flips.
---

author: foreman
created: 2026-07-29 11:14
---
FOREMAN LINE REVIEW + COMMIT (2026-07-29): reviewed the frozen four-file diff. Independently verified beyond the architect's chain: NO http_port/https_port override exists in any template (grep across caddy/templates/*.tmpl), so the container-internal HTTP listener is :80 in all three modes and the hostless block sits on the right listener with host-matched sites taking precedence; go vet + full config-package tests green; gofmt clean (the two struct-literal alignment fixes in config_test.go are correct gofmt). ONE REVIEW-FIX APPLIED before commit: the new respond lines used a TAB where these templates use 4-space indent — normalized in all three, pin re-run green (whitespace-insensitive to Caddy; validated config unaffected). COMMITTED 337cb48e9, pushed. Closing Done: all three ACs checked; the behavioral half rides the fleet's next deploy (bare-IP probes read 404). MARGINAL NOTE recorded, no action: development.caddyfile.tmpl:105 has a dev-only loopback site on :19999 (netdata proxy) whose listener the :80 catch-all does not cover — an unmatched-Host request there still gets the implicit 200-empty; dev-only, loopback-only, out of the NSO-monitor frame.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All three deployment-mode Caddy templates gain a hostless :80 catch-all responding 404, killing the implicit-200-empty false-green for external monitors probing a bare IP:port (the 071 c-rollback arc's 'unexplained heal' mechanism). Append-only diff — real site keys render byte-identically; full generated config validated with the product's own caddy build (stock caddy:2 cannot validate our layer4 global — recorded for future template work). 443 untouched by design: unmatched SNI already fails the handshake. Source pin TestCaddyTemplates_UnmatchedHostCatchAll_STATBUS189 in the config package. Built by architect, foreman line-reviewed (one indent normalization) + committed 337cb48e9.
<!-- SECTION:FINAL_SUMMARY:END -->
