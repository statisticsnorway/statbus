---
id: STATBUS-269
title: >-
  sshdoers-host-validate: Stage 8 should refuse when ops/<host>/ does not exist
  — a typo'd SSHDOERS_HOST currently sends the operator chasing a missing file
status: Done
assignee: []
created_date: '2026-08-27 12:58'
updated_date: '2026-08-27 16:53'
labels:
  - ops
dependencies: []
priority: low
type: enhancement
ordinal: 262000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Deferred refinement from STATBUS-259's preamble-fix review (architect, 2026-08-27). Stage 8 derives the host from hostname --fqdn (short name) or SSHDOERS_HOST, then fetches ops/<host>/sshdoers. A mistyped SSHDOERS_HOST — or a container identity — produces an error message naming ops/<typo>/sshdo as "holding the canonical copy" when no such directory exists, sending the operator chasing a missing file instead of the typo.

The fix, as ruled: validate that ops/<host>/ EXISTS (in the repo tree at SSHDOERS_REF) before using the derived name, and refuse with "no reviewed policy directory for host X — is SSHDOERS_HOST correct?" One check covers containers and typos alike.

WHAT IS ACHIEVED: a wrong host name is reported as a wrong host name, not as a missing canonical file.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Landed in two commits (339fd3120 the check, da7caecfc the ruled amendment). Stage 8 refuses a wrong host name AS a wrong host name: the probe hits the exact raw URL the stage fetches (a pass guarantees the real fetch), a 404 names BOTH indistinguishable causes (host or ref — raw returns 404 for either, discovered empirically) with an action line covering both variables, and any other status honestly says could-not-verify while still failing closed. Two standing lessons from the review cycle: the headline is what people act on — when a signal cannot distinguish two causes, name both rather than pick the likelier; and when you sharpen a check, everything feeding it that was close-enough for the coarse version becomes load-bearing (the -f/-w curl interaction was harmless under any-non-200 and fatal under 404-vs-other — found by the live run, invisible on the page).
<!-- SECTION:FINAL_SUMMARY:END -->
