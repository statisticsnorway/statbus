---
id: STATBUS-310
title: >-
  fleet-refspec-pollution: five slots still fetch deleted deploy branches — the
  landmine detonates exactly when each box takes the stable
status: To Do
assignee:
  - '@operator'
created_date: '2026-08-28 22:43'
labels:
  - ops
  - cloud
dependencies: []
priority: high
type: bug
ordinal: 303000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: every fleet box's git configuration must be able to fetch the tags its discovery needs. Five production slots cannot: their fetch refspecs still name deploy branches that STATBUS-244's retirement deleted from GitHub, so any git fetch aborts on the missing ref before tags ever arrive.

THE EVIDENCE (operator's read-only audit, 2026-08-28, verbatim table on STATBUS-303's report thread): et, jo, ma, tcc, ug each carry `+refs/heads/ops/cloud/deploy/<slot>:refs/remotes/origin/ops/cloud/deploy/<slot>` alongside the standard wildcard refspec. Demo carried the same and was repaired tonight (before: two refspecs; after: wildcard only) — the repair immediately restored discovery (19 candidates registered on the next check).

WHY IT MATTERS NOW: these five boxes run pre-255 binaries whose discovery is API-based, so the pollution is currently latent — but the moment each takes the stable (post-255 binary, pure git discovery), the stale refspec becomes the exact blocker demo hit: fetch dies on the deleted ref, discovery goes dark, and the box that just upgraded cannot see the next release. The landmine detonates precisely at the moment of success.

THE REPAIR, proven on demo tonight (King-approved config-class, same family as the HTTPS remote switch):
  git config --unset-all remote.origin.fetch
  git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
Two commands per box, no data, no services. Also note each box's remote is still SSH — the HTTPS switch (Ukraine/demo precedent) can ride the same visit if approved.

SEQUENCING: before or with the stable delivery — the King's overnight answer (Q2) decides whether tonight or later; either way this must precede or accompany each box's first post-255 discovery. ALSO RECORD the root cause for the retirement's own ledger: STATBUS-244 deleted the branches on GitHub but never cleaned the boxes' refspecs — retirements that leave client-side state behind detonate later; a future retirement checklist should include the fleet-side sweep.

RELATED, dated evidence, separate defect: the rc.03-era binary's MANUAL `upgrade register <tag>` verb cannot parse annotated tags ('parse committed-at "tag v..." as time'), observed on demo tonight. Fixed eras are unaffected; the fleet's AUTOMATIC path uses API data, not the git parse. No action needed on current code — recorded so the next old-box triage recognizes it.

WHAT IS ACHIEVED: no box discovers its way into darkness at the moment it upgrades; the fleet is git-discovery-ready before the stable arrives.
<!-- SECTION:DESCRIPTION:END -->
