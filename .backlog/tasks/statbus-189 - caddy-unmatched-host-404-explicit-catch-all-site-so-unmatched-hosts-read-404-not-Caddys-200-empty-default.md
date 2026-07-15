---
id: STATBUS-189
title: >-
  caddy-unmatched-host-404: explicit catch-all site so unmatched hosts read 404,
  not Caddy's 200-empty default
status: To Do
assignee: []
created_date: '2026-07-15 00:44'
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
- [ ] #1 Unmatched-host requests on every bound HTTP listener answer 404 (not 200-empty) in all deployment modes' generated Caddyfiles
- [ ] #2 Real site-key routes byte-unchanged (config-generate diff reviewed)
- [ ] #3 A harness or unit check pins the 404 (e.g. curl by bare IP on a test box or a Caddyfile-render assertion)
<!-- AC:END -->
