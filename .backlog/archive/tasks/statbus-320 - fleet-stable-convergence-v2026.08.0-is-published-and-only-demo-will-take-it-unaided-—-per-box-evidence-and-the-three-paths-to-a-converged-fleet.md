---
id: STATBUS-320
title: >-
  fleet-stable-convergence: v2026.08.0 is published and only demo will take it
  unaided — per-box evidence and the three paths to a converged fleet
status: Done
assignee: []
created_date: '2026-08-30 02:13'
updated_date: '2026-08-31 11:23'
labels:
  - ops
  - release
  - upgrade
dependencies: []
priority: high
type: task
ordinal: 313000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: every box runs the published stable. Overnight reads (2026-08-30 ~02:00, read-only) show the fleet will NOT converge on its own, for three different reasons — none of them a failed upgrade; nothing was attempted anywhere and every box serves normally.

PER-BOX EVIDENCE:
- et (and by era, jo/ma/tcc/ug): v2026.08.0 discovered but carries a DISCOVERY-side error — "CI images absent after 20m0s timeout; gh probe err=exec: 'gh': executable file not found in $PATH". The July binary (v2026.07.0-rc.03) verifies CI images via the gh CLI, absent on the boxes, so docker_images_status never reaches ready and nothing can ever be scheduled. The upgrade list renders these rows as "failed", which is display-alarming but operationally nothing: state=available, scheduled_at/started_at NULL, containers up 6 weeks. CONSEQUENCE FOR STATBUS-254: its resolution path ("the first stable clears the offers") was wrong in mechanism — these boxes cannot verify the stable's artifacts, so waiting does not converge them. The demo-proven canonical escape (dump → git checkout tag → install.sh; refspecs already repaired on all five) is the working path — KING'S CALL to extend it beyond demo to five NSO production boxes.
- ua (Ukraine, rc.10-era binary): v2026.08.0 available, discovered cleanly, NO error — but its era only OFFERS; nothing auto-schedules (discovery has never written state=scheduled). One operator command converges it: ./sb upgrade schedule v2026.08.0 (or ./sb install). KING'S CALL whether we run it or Ukraine's operator does.
- demo (rc.16-era): v2026.08.0 available, clean — and its daily auto-apply-stable workflow (STATBUS-248's first mechanism, cron) will take it unaided within 24h. The one box that converges alone.
- gh (Ghana, rc.16-era standalone): unreadable from the foreman session (host-key not in this environment); by era it should mirror demo's clean discovery, minus any auto-apply workflow. Needs the same schedule decision as Ukraine.
- dev + no (Norway): already at/na the candidate line (dev auto-canary; Norway completed rc.17 and is offered v2026.08.1-rc.01 next).

THE STRUCTURAL FINDING FOR STATBUS-248: channel-following-in-full (a stable-channel box AUTO-INSTALLING the published stable) exists nowhere in the fleet except demo's external cron. If boxes are to follow their channel per the 248 intent, the upgrade service needs the auto-apply arm for role=production — designed deliberately (the same offer-vs-act boundary that protects Norway must not erode).

DECISIONS FOR THE KING (morning, interview-style): (1) extend the canonical reinstall to the five legacy boxes — approve/schedule/who runs; (2) Ukraine + Ghana: one schedule command each — us or their operators; (3) 248's auto-apply arm for production role — build now or after v2026.08.1.

WHAT IS ACHIEVED: the fleet actually converges, each box by its honest path, and 248/254/287 close on observed state instead of assumed mechanism.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**First convergence observed (2026-08-30 ~05:30 read):** demo runs v2026.08.0 COMPLETED — taken unaided overnight by its daily auto-apply-stable workflow (STATBUS-248's cron mechanism, abe93ed49), exactly as designed. The first channel-following convergence in the fleet's history, and the live proof that the 248 shape works where a current-era binary and an apply trigger both exist. The remaining boxes stand as mapped: five legacy (structurally cannot verify artifacts), Ukraine + Ghana (clean offer, need one schedule act), dev/Norway on the candidate line.

**King's rulings (2026-08-31 morning):** (1) UKRAINE IS WIPED FROM THIS TICKET — it self-installs from now on; no pending work, no decision owed, not ours to act on. (2) VOCABULARY CORRECTED: et/jo/ma/tcc/ug are CLOUD SLOTS, not 'legacy' — the word is retired; their binaries are older, the boxes are not a category. (3) The five cloud slots: the King upgrades them himself in one sitting with the cloud tool — `./cloud.sh install <slot> v2026.08.0` per slot (the PINNED form always takes the full bootstrap: stop service, replace binary, re-run install — which bypasses the old binaries' broken artifact verification entirely; the unpinned 'smart' path would try the very upgrade-service machinery that cannot verify). (4) The 248 auto-apply arm is NOT being built on the earlier framing — the King's constraint stands as the north star: an NSO must control WHEN something installs; automatic installation the office cannot control is rejected on sight. Demo's cron is OUR box and OUR explicit choice, outside the product. What 'channel-following' means under NSO-controls-when goes to a deliberate design discussion, not a build.

**CORRECTION + roster fix landed (bf0016503):** Ghana is NOT a standalone host — the earlier note's description was wrong (one failed SSH to the subdomain, no DNS check). Verified: gh.statbus.org is a CNAME to niue and statbus_gh@niue answers; Ghana and Ukraine are both ordinary niue slots born in August from create-new-statbus-installation.sh, invisible to the fleet tool only because cloud.sh's SERVERS was last edited before they existed. Both added to the roster; the comment at the line records the rule (a slot missing from the list is invisible to fleet upgrades — the list gains every new slot the day it is created). King's ruling: NEITHER is special; both converge via the same pinned `./cloud.sh install <slot> v2026.08.0` he is running across the fleet, superseding both the 'Ukraine self-installs' framing and the 'Ghana needs a tool extension' framing.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CONVERGENCE COMPLETE (2026-08-31): every serving box runs its correct version. Closing fleet table — dev: v2026.08.1-rc.01 (canary, correct); demo, et, jo, ma, ug, ua, gh: v2026.08.0 with translation verified per box (role present, channel key gone) and units active; tcc: exempt, retiring (STATBUS-321); Norway: v2026.08.1-rc.01 (human canary). The run's method: King-driven pinned installs (`./cloud.sh install <slot> v2026.08.0`), operator-executed, foreman-gated per slot. Two real defects surfaced and both were converted to tickets with fixes or designs: the install-vs-service fetch race (ma; STATBUS-323, stop-the-unit-first became procedure and the code fix is filed) and the anonymous-HTTPS shared-IP throttle plus gh's refspec pollution (STATBUS-324; refspec repaired on the spot in the approved class). The 248 auto-apply question was reframed by the King's constraint — an NSO controls WHEN; it is a design discussion, not a build. STATBUS-254 and STATBUS-287 close on this event; Malawi's birth (STATBUS-322) is the fleet's next change.
<!-- SECTION:FINAL_SUMMARY:END -->
