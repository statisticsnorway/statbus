---
id: STATBUS-251
title: >-
  new-instance-script-drift: the country-instance installer still generates the
  retired push-to-install workflows — and the new-box channel default needs a
  ruling
status: Done
assignee: []
created_date: '2026-08-19 09:54'
updated_date: '2026-08-19 10:27'
labels:
  - ops
  - release
dependencies: []
references:
  - ops/create-new-statbus-installation.sh
  - doc/CLOUD.md
priority: medium
type: chore
ordinal: 244000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
STATBUS-244a retired the master-to-X and per-slot push-deploy workflows — but the script that creates a NEW country instance still generates exactly those files, so the next instance created would resurrect the retired mechanism one box at a time.

WHAT THE EVIDENCE SHOWS (mechanic, during the 244a sweep): ops/create-new-statbus-installation.sh generates master-to-<slot>.yaml and deploy-to-<slot>.yaml for each new instance. Under the approved topology (STATBUS-248 + the King's opt-in amendment), a new country instance needs NEITHER: it sits on the stable channel, is offered each promoted release, and a human performs the upgrade — zero deploy workflows, zero deploy branches.

THE FIX: the script stops generating the retired files and instead configures the new instance per its role (stable channel, opt-in). The doc/CLOUD.md runbook already carries the mechanic's inline flag at the affected steps.

SECOND ITEM, RULING NEEDED (architect or King): the new-STANDALONE-box default of UPGRADE_CHANNEL=prerelease (doc/CLOUD.md authoring) predates Norway being named the sole human canary. By 248's logic a future non-canary standalone belongs on STABLE; prerelease-by-default would silently put a customer-shaped box on candidates. Rule the default (likely: stable for everything, prerelease only by explicit canary designation) before the next standalone is created.

WHAT IS ACHIEVED: creating a new instance produces a box that matches the approved topology by construction — no retired machinery resurrected, no channel accidents.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 create-new-statbus-installation.sh no longer generates master-to-X or deploy-to-X files for new instances and instead configures the role-correct channel
- [x] #2 The new-box channel default is ruled and encoded: stable unless explicitly designated a canary
- [x] #3 The doc/CLOUD.md runbook steps match the script's actual behavior
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (pinned by foreman)
created: 2026-08-19 09:56
---
CHANNEL-DEFAULT RULED (architect, during the A2 review — folds into this entry's item 2, no King time needed as it directly applies his approved 248/250 rulings): the standalone default becomes STABLE. Under 248 only a role-assigned canary runs candidates — Norway is an exception to be CONFIGURED, never defaulted into. This matters more than it looks: standalone is the shape external customers install, and a prerelease default means a statistical office runs release candidates by default — the opposite of the channel's purpose. INTERIM EDGE (same as the King's 250 ruling): until a stable exists in the current line, prerelease remains the fallback — which is almost certainly why the default reads as it does today.

ALSO FROM THE A2 REVIEW, the finding that reshapes 244's tail: deploy-to-{et,jo,ma,tcc,ug} still exist as live push paths to real NSO installations — the architect's own AC#4 enumerated only demo/no ("an enumeration is a premise, not a fact — including my own", third instance this week). Their deletion is CORRECT but MUST FOLLOW Wave D1's channel confirmation — deleting a live NSO box's only receive-path before proving its channel works could strand it, and a box on a wrong channel looks identical to a box with nothing to do. Filed as a Wave D unit dependent on D1; the A2 landing carries a transitional doc paragraph naming this explicitly.
---

author: architect
created: 2026-08-19 10:20
---
BUILD DESIGN, part 1 of 2 — a defect found while designing, and the script edit list. Every claim verified at source; no decision is left to the builder.

## LEAD FINDING — every instance this script creates is probably left on the `local` channel, and would never upgrade

This is not the AC#1 work; it surfaced while establishing how the channel is consumed, and it is more serious than the thing the ticket was filed for.

1. The script NEVER sets `UPGRADE_CHANNEL`. It relies on `./sb config generate` applying the mode-aware default.
2. It runs `./sb config generate` at **line 294**, while `.env.config` still says `CADDY_DEPLOYMENT_MODE=development` — proven by line 350, whose sed pattern matches that literal string in order to change it to `private`. The development default is **`local`** (cli/internal/config/config.go:403-406).
3. `gen()` uses `f.Generate`, which **returns the existing value and only writes when the key is absent** (cli/internal/dotenv/dotenv.go:223-225).
4. So the second `./sb config generate` at **line 419** — which now runs under `private`, where the default would be `stable` — finds `UPGRADE_CHANNEL=local` already present and PRESERVES it.

**Result: the box sits on `local` forever.** A `local`-channel box discovers no releases at all, so it looks exactly like a box with nothing to do — the precise failure STATBUS-248 warns about, sitting in the creation path rather than in an operator's edit.

**CONFIDENCE, stated honestly:** the mechanism is verified in code; the outcome on a live box is NOT — I have not read one. Have the operator run `ssh statbus_ug 'grep UPGRADE_CHANNEL statbus/.env.config'` (and the same for et, jo, ma, tcc) before the edit. That is a read, it is one command, and it converts a strong prediction into the fact 248 requires — confirmed on the box, never inferred. If they come back `local`, that is also STATBUS-248's D1 work landing early and for free.

## EDIT LIST — ops/create-new-statbus-installation.sh

**EDIT 1 — DELETE lines 101-113** (the `master-to-<slot>.yaml` generation block, `if [ ! -f ... ]` through its closing `fi`).

**EDIT 2 — DELETE lines 115-126** (the `deploy-to-<slot>.yaml` generation block, same shape).

Both blocks template from `.github/workflows/master-to-demo.yaml` and `deploy-to-demo.yaml` — **which STATBUS-244a deleted**. So today both blocks already fall into their `else` arms and print `Warning: Could not find template workflow file`, then continue. The script is therefore already broken in the warn-and-continue shape the King rejects: it does not reach its goal and does not stop. Deleting the blocks is what makes the script correct, not merely current.

**EDIT 3 — ADD an explicit channel write** inside the existing `UPDATE_SETTINGS` heredoc, alongside its siblings (the `DEPLOYMENT_SLOT_CODE` block at :362-364 is the pattern to copy), and therefore BEFORE the final `config generate` at :419.

It must **overwrite**, not set-if-missing — the whole point of the lead finding is that a wrong value is already there:

```sh
current_channel=$(grep '^UPGRADE_CHANNEL=' .env.config | cut -d'=' -f2)
if [ "$current_channel" != "$TARGET_CHANNEL" ]; then
    sed -i "s/UPGRADE_CHANNEL=.*/UPGRADE_CHANNEL=$TARGET_CHANNEL/" .env.config
    echo "Set UPGRADE_CHANNEL=$TARGET_CHANNEL (was: ${current_channel:-unset})"
fi
```

The `(was: ...)` clause is deliberate: on every existing-instance re-run it prints the old value, which is how we find out whether the lead finding bit any box we have already built.
---

author: architect
created: 2026-08-19 10:20
---
BUILD DESIGN, part 2 of 2 — the interim-edge conditional, the doc changes, and the orphan check.

## THE INTERIM EDGE — where the conditional lives and what it reads

`TARGET_CHANNEL` from EDIT 3 is computed ONCE near the top of the script, next to the other derived values, and printed in the settings echo block (:79-86) so the choice is visible before anything is configured:

```sh
git fetch --tags --quiet
if git tag -l 'v*' --sort=-version:refname | grep -qv -- '-rc\.'; then
    TARGET_CHANNEL=stable
else
    TARGET_CHANNEL=prerelease
    echo "NOTE: no stable release exists yet in this line, so this instance starts on the"
    echo "      prerelease channel. It must move to stable once the first stable ships."
    echo "      STATBUS-248's role-correct-channel check is what will catch it if nobody does."
fi
```

**Why it reads git tags rather than the GitHub API:** the script already runs inside a checkout, tags are the same source of truth the upgrade service's own discovery uses (`DiscoverTagsViaGit`), and it needs no token. The `git fetch --tags` is required — without it the answer depends on how stale the operator's clone is, which is exactly the instrument error to avoid.

**Why the note is loud and names its own expiry:** a box parked on prerelease "temporarily" is a standing wrong-channel hazard nobody revisits. Per the no-standing-self-heal rule this must not quietly self-correct later; it announces itself once, and STATBUS-248's recurring role-correct-channel verification is the mechanism that catches it if the human forgets. The two compose — say so in the brief so the mechanic does not invent a third.

**Note the grep is `-qv`, not `-q`:** we are asking whether any tag exists that is NOT an `-rc.` prerelease. Getting this inverted would put every new box on the wrong channel while looking correct, so it is worth the mechanic re-reading that one character.

## DOC — doc/CLOUD.md

**Step 2 of the runbook (line 220)** currently reads *"Generate GitHub workflow files (master-to-pk.yaml, deploy-to-pk.yaml)"* followed by the mechanic's inline STALE flag naming this ticket. **Replace the whole step**, flag included, with what the script will then actually do:

> 2. Set the instance's upgrade channel (`stable`; `prerelease` only until the first stable release exists). A new country instance is an ordinary production slot — it follows releases on its own and gets no push-triggered workflow and no deploy branch.

The flag text must go, not stay as history: it says "filed as STATBUS-251", and once 251 has landed a reader following it would be chasing a closed ticket to explain behaviour that no longer exists.

**Also check while in the file:** the numbered list continues to 13; the step numbering stays intact because step 2 is replaced rather than removed. If the mechanic finds any other step referring to generated workflows or deploy branches for a new instance, it is in scope for this unit — that is the same doc-and-mechanism-move-together rule A2 established.

## ORPHANS — CHECKED, NONE

Verified by grep over the whole script: **zero** occurrences of `gh api`, `gh secret`, `gh workflow`, `git push`, `git branch`, or any `curl` against api.github.com, and **zero** references to `ops/cloud/deploy`. The script writes workflow FILES into the local checkout and nothing else on the GitHub side — it creates no secret, no branch, no branch protection and no webhook, so the deletion orphans nothing.

One thing that LOOKS like a counterexample and is not: `GITHUB_DEPLOY_KEYS` (:31, :49, :169). It is not a secret the script creates — it names public-key SOURCES (`<org>/<repo>.keys`) that get fetched and written into the box's `authorized_keys`. Untouched by this unit.

## SEQUENCING

No dependency on Wave D. This unit only edits a script and a doc — it changes nothing about a live box — so it can land whenever the mechanic is free. The channel READ named in part 1 should go out sooner than that, because it is one command and it may promote a prediction into a live-fleet defect.
---

author: foreman
created: 2026-08-19 10:22
---
CHANNEL READS COMPLETE (operator, read-only, all seven boxes): et/jo/ma/tcc/ug/demo ALL read UPGRADE_CHANNEL=prerelease; dev reads edge. The architect's local-channel hypothesis is NOT confirmed by the live reads — but the fleet is NOT healthy either, and the operator's 'configuration is correct' conclusion is wrong against the ruled topology: under the King's 248 rulings the five country boxes and demo belong on STABLE (candidates must never be offered to NSO production boxes; demo auto-applies stable), and dev belongs on prerelease, not edge. So EVERY box deviates from the ruled topology — the deviation is just a different one than predicted. TWO QUESTIONS routed to the architect: (1) reconcile the code-derivation (which says the creation path yields local) with the observed prerelease — both cannot be true of the same mechanism; something else set these channels, and what that something is determines whether the script fix as designed suffices; (2) whether the fleet's channel correction (all-country + demo → stable, dev → prerelease) folds into Wave D1 as already planned or needs its own unit — no manual writes; the correction ships via the ruled mechanism. Note the silver lining: prerelease boxes CAN receive releases (stable releases appear on the prerelease channel too, once one exists), so the 'boxes can never upgrade' severity does not hold — the real exposure is NSO boxes being OFFERED release candidates.
---

author: mechanic (pinned by foreman)
created: 2026-08-19 10:25
---
BUILD FROZEN, executed exactly per comments #2-3 (design followed to the letter; zero design decisions taken). Files: ops/create-new-statbus-installation.sh (28+/29-), doc/CLOUD.md (1 line, step 2 replaced + STALE flag removed). ONE MECHANICAL DISCREPANCY reported rather than filled: EDIT 2's stated range (115-126) ended one line short of the balanced if/else/fi — the closing fi is :127; deleting to :126 would have left a dangling fi (bash -n confirmed). The full balanced block was deleted; boundary unambiguous from code structure. TARGET_CHANNEL computed once at the top (the -qv character re-read and confirmed); channel overwrite inside UPDATE_SETTINGS with sibling-matched escaping; echo prints 'Set UPGRADE_CHANNEL=<target> (was: <old>)', silent when already correct; interim NOTE verbatim. Validation: bash -n clean; shellcheck findings identical to HEAD baseline (zero new). Post-edit grep of CLOUD.md: no other step references generated workflows/deploy branches for a new instance. Awaiting architect review.
---

author: foreman
created: 2026-08-19 10:27
---
LANDED as 10e5ab2c4 (architect APPROVED; his one amendment — the stale GITHUB_DEPLOY_KEYS comment — folded and re-frozen first). The two already-broken generation blocks are gone; TARGET_CHANNEL computed once with the stable-unless-no-stable-exists interim; the channel write OVERWRITES with a '(was: <old>)' echo; doc/CLOUD.md step 2 matches the script. All three ACs closed — AC#2's ruling was comment #1, now encoded. FOLLOW-UPS CARRIED ELSEWHERE: the fleet's live channel correction (six boxes prerelease→stable, dev edge→prerelease) is its own entry being drafted by the architect for the King; the deploy-key consumer question is STATBUS-253. The design's off-by-one and the wrong-question orphan check are both on the record in comments #5 and the review — the reporting-not-absorbing behavior this board keeps rewarding.
---
<!-- COMMENTS:END -->
