---
id: STATBUS-307
title: >-
  config-generate-couples-serving-to-policy: a channel refusal prevents database
  restoration — all-or-nothing on the boot path
status: Done
assignee:
  - '@engineer'
created_date: '2026-08-28 21:37'
updated_date: '2026-08-31 15:02'
labels:
  - upgrade
  - cli
  - config
dependencies: []
priority: high
type: bug
ordinal: 300000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a box's ability to serve must never depend on resolving upgrade policy. Today it does, at exactly one joint: config generate is all-or-nothing on the boot path, so a refusal about which release CHANNEL a box follows prevents its DATABASE from being brought back up.

THE CAUSAL CHAIN THAT EXPOSED IT (STATBUS-298's checkpoint read, architect-confirmed): an earlier legitimate teardown leaves the db down, expecting the next boot's EnsureDBUp to restore it. The boot runs config generate first (service.go:2103, structurally before EnsureDBUp at :2113 — correctly so, the config feeds everything after). When config generate REFUSES on the 254 channel-ambiguity guard (both UPGRADE_ROLE and UPGRADE_CHANNEL present — a policy question), the boot returns before :2113 and the database that should have come back never does. The refusal is CORRECT; the channel question is genuinely ambiguous. What is wrong is the blast radius: two keys disagreeing about release policy cost the box its database.

THE DEFECT, precisely: config generate conflates two outputs with different criticality — (a) what the box needs to SERVE (.env, compose config, ports, secrets wiring) and (b) upgrade policy resolution (role→channel). A refusal in (b) currently withholds (a). Under 298's fix the failure is loud, once, exit-78 — strictly better than five futile restarts — but the box still ends db-down over a policy disagreement.

THE SHAPE TO EXPLORE (restructure, deliberately NOT this round — architect's ruling: not a same-day change): separate the serve-critical generation from the policy resolution, so a policy refusal degrades the box to serving-but-not-upgrading (with the refusal loud in the journal and the marker file) instead of not-serving. The 298 marker/exit-78 machinery is the natural integration point: policy-refused becomes a parked-but-serving state, the operator's install.sh run resolves it. Design questions: which config outputs are genuinely policy-dependent; whether a stale-but-valid previous .env can serve while policy is unresolved; how the refusal surfaces without being ignorable forever.

CROSS-REFERENCES: STATBUS-298 (the loud-once fix this coupling survives), STATBUS-254 (the guard, correct), STATBUS-297 (where the chain was first observed live).

WHAT IS ACHIEVED: a policy disagreement can never take a database down; refusals about upgrades park the upgrade, not the box.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SMALL HONEST VERSION LANDED at 3ff11f1d6 (the architect's tonight-shippable design): the refusal branch forks on prior-.env existence — fresh box refuses hard (298's exit-78 unchanged), configured box parks (the marker IS the park at boot time; no db connection exists yet for a row-level park) and falls through to EnsureDBUp so the database returns and the box serves. Structural test pins the fork, the single exit site, and the exit-free fall-through window; red-verified. ONE INTERPRETATION FLAGGED FOR THE ARCHITECT (mechanic's, honest): no explicit downstream guard blocks upgrade scheduling while parked — the block is by absence-of-refresh (config generate failed so nothing new exists to act on; the daemon's loaded config and on-disk .env are unchanged). OPEN QUESTION for his next pass: can a PREVIOUSLY-SCHEDULED pending row still execute against the ambiguous config state, and if so does executeUpgrade's own path handle the refusal acceptably (298's machinery) or does the marker need a discover/executeScheduled check? TICKET STAYS OPEN for that ruling + the full serve-config/policy-config restructure as the complete form.

**Architect ruling (2026-08-29): block-by-absence REJECTED — explicit parked-state execution guard required before rc.17.** The parked box's protection against executing a pre-scheduled public.upgrade row currently holds only because the upgrade path happens to need a fresh config — a property held by accident, unstated, that a refactor tolerating stale config would silently remove with nothing going red. The park exists precisely because channel policy is ambiguous; executing a scheduled row in that state could install a wrong-channel candidate on a production box (the 291 harm). Reachable: row scheduled → unconditional UPGRADE_ROLE write on a pre-254 box → boot. Fix: the execution entry point reads the existing marker (307 already built it) and refuses with the same actionable text as the boot refusal. Assigned: mechanic (holds the 298/307 file region), tonight.

**Execution guard LANDED at 3d102d676** (foreman-reviewed diff): the arriving job's own first act in claimScheduledUpgrade — the one function both dispatch paths share (install verb's inline dispatch + daemon's periodic pickup), so a single change covers both. Marker present → refuse surfacing the original refusal text + timestamp; marker unreadable → refuse (fails closed per the 039/111/159 doctrine); no marker → unchanged fall-through. Deliberately distinct in the comment from the row-level recovery_parked_at park. Structural tests pin guard-before-park-read + both refusal branches + genuine-conditional; red-verified via guard-deleted scratch copy; full internal/upgrade suite green, -race clean. TICKET REMAINS OPEN for the full serve-config/policy-config restructure (the architect's not-same-day complete form); tonight's two landings (boot-time park-and-serve fork + this dispatch guard) close the acute halves.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-31 12:40
---
**FULL RESTRUCTURE DESIGN — for the King's approval.**

**Purpose, in two sentences.** A box's ability to serve must never depend on answering which release channel it follows. Today one unanswerable policy question withholds the entire generated configuration, and this design makes the policy answer optional to serving without making it ignorable.

## The finding that makes this SMALL

The restructure sounds like untangling a generator. It is not. **The policy output is exactly two keys.**

`ResolveUpgradeRole` (`cli/internal/config/upgrade_role.go:187`) returns a role and a channel string — nothing else. Everything else `config generate` produces (ports, bind addresses, database credentials, compose wiring, Caddy files) is computed from deployment mode and slot facts that have **nothing to do with release policy**.

**So the coupling is one ABORT, not an interleaving.** The work is to stop one failure from cancelling ~50 unrelated outputs.

## Part 1 — policy resolution becomes a RESULT, not a gate

`config generate` computes every serve-critical output unconditionally. A `ResolveUpgradeRole` failure yields an *unresolved policy* result instead of aborting the run.

**THE RULE THAT MATTERS MOST: the two policy keys are OMITTED, never defaulted.** Absent is the honest representation of unknown. Defaulting to `stable` would be a **fabricated policy**, and a fabricated policy can install a wrong-channel candidate on a production box — the STATBUS-291 harm arriving through a helpful default. **An unresolved question must never acquire an answer by convenience.**

## Part 2 — the blocking half ALREADY EXISTS

Both halves that stop a parked box from upgrading are landed: the marker carrying the refusal text (3ff11f1d6) and the dispatch guard in `claimScheduledUpgrade` that refuses on its presence (3d102d676).

**So this design changes nothing about blocking. It changes only what happens to the OTHER outputs.** Assert the existing behaviour in tests; do not rebuild it.

## Part 3 — visibility, by reuse rather than a new mechanism

The unresolved-policy state is **a state**, and STATBUS-308 already pushes state to `public.system_info` and surfaces it on the upgrade page — including the staleness arm, so a box that stops reporting is visible too.

**Push the policy-unresolved state through 308's existing channel. No second watchdog.** A parked box reads as parked; a silent box reads as stale.

## What the FULL form buys over the small version already landed

Worth stating plainly, or "we already park and serve" looks like enough.

**The landed version serves on the STALE prior `.env` — nothing regenerates.** A port change, a credential rotation, or a Caddy update made while policy is ambiguous does not take effect. **The full form regenerates everything it can**, leaving only the two policy keys unresolved. That is the entire gain, and it is the difference between a box that is frozen and a box that is merely not upgrading.

## THE ONE REAL INTEGRATION RISK

**Omitting a key only helps if no reader invents a value for it.** Every consumer of `UPGRADE_CHANNEL` must tolerate absence and refuse rather than default. **Enumerate the readers before building** — a single reader that falls back to `stable` on absence reintroduces the fabricated policy through the back door, and it would do so silently.

## Acceptance criteria

1. `config generate` writes a complete serve-critical `.env` when `ResolveUpgradeRole` fails.
2. The two policy keys are **omitted, never defaulted**, when policy is unresolved.
3. A box with ambiguous policy **and a changed port or credential picks up that change on the next boot** — proving fresh generation, not stale reuse.
4. Every reader of `UPGRADE_CHANNEL` is enumerated, and each refuses rather than defaults on absence.
5. The marker and dispatch guard behave exactly as landed (asserted, not rebuilt).
6. The unresolved state appears in `system_info` and on the upgrade page via 308's existing path.
7. A box with **resolved** policy generates byte-identically to today — no regression on the healthy path.
8. Red-verified: reintroducing a default for the channel fails a test.
---

author: foreman
created: 2026-08-31 13:17
---
KING'S PRINCIPLE (2026-08-31, supersedes the pending approval question on the filed design): When an installation runs ./sb config generate, the DEFAULT values shall be those suitable for an NSO STANDALONE installation. Anything else must be specified. Confirmed in discussion: SITE_DOMAIN is the one key with no honest default — and as such it must be specified (standalone mode with an unspecified domain refuses with an actionable message rather than generating a config that cannot serve). Foreman's verified groundwork for the re-derivation: config.go:352 currently defaults CADDY_DEPLOYMENT_MODE to 'development' (the direct inversion of the principle); gen()/f.Generate writes defaults into .env.config on first generate, so every existing box carries the mode key explicitly and a default flip touches only genuinely fresh installations; defaultRoleForMode's equivalence concern dissolves for the same reason; cloud slots set 'private' explicitly (create-new-statbus-installation.sh:361); canary is explicit-only by design. The filed partial-generation design is NOT approved as-is — architect re-derives 307 under this principle (it may shrink to: flip the mode default, add the standalone SITE_DOMAIN refusal, keep fail-fast on incoherent explicit input).
---

author: architect
created: 2026-08-31 13:18
---
**RE-DERIVED DESIGN under the King's principle. This supersedes comment #1, and it is much smaller.**

**Purpose, in two sentences.** A fresh installation must be a working NSO standalone box without anyone configuring it, and the only thing it must be told is the one fact the product cannot know — its domain. Everything the product can honestly decide about itself, it decides.

## The reconciliation that makes the King's principle and the omit-never-default rule BOTH true

My filed design said defaulting the release channel would be a **fabricated policy** that could install a wrong-channel candidate. The King rules that defaults shall be those suitable for an NSO standalone installation. **These do not conflict, and the boundary between them is the load-bearing sentence of this whole entry:**

> **Absent input takes the declared standalone default. Contradictory input refuses. A default answers a question nobody asked; it never settles a question two inputs answered differently.**

Defaulting an **absent** value is the product having a defined identity — legitimate, and exactly what the King is asking for. Defaulting a **contradictory** one is resolving someone's conflict by preference — a guess wearing a default's clothes, and the STATBUS-291 harm arriving by convenience.

**This boundary MUST be written at the code, because the misreading is natural:** *"defaults shall be suitable for standalone, so when the role and channel disagree, just take the standalone default."* That reintroduces exactly what the 254 guard exists to stop.

**And it explains the SITE_DOMAIN carve-out rather than treating it as an exception: a default is honest when the PRODUCT owns the fact, and dishonest when the WORLD owns it.** The product may declare "you are a standalone production installation" — that is a statement about itself. It may not declare "your domain is X" — that is a statement about a world it cannot see. One key, one carve-out, one reason.

## I WITHDRAW the partial-generation restructure. Here is the tension resolved plainly.

Comment #1's argument was the frozen box: while policy is unresolved, the landed behaviour serves on a stale `.env`, so a port change or credential rotation made in that window never takes effect.

**Under the principle that argument no longer pays for itself.** Once absence is answered by the default, the unresolved state arises only from **contradictory explicit input** — an operator's own hand-edit, or our creation script writing `UPGRADE_ROLE` onto a pre-254 box that still seeds `UPGRADE_CHANNEL` (STATBUS-297's path, real but transitional).

**In both surviving cases the box is already serving**, and the only extra gain is that unrelated config changes made inside that same window take effect. **That gain is narrow and shrinking; the cost — every reader of the policy keys tolerating absence, forever — is broad and permanent.**

**So the accepted cost is: the operator fixes their own contradiction, and the tooling-induced case resolves when the box upgrades.** The refusal names the two keys and the edit. That is the right trade, and it is a smaller system.

## The design

1. **`CADDY_DEPLOYMENT_MODE` defaults to `standalone`** (`config.go:352`, currently `development` — the direct inversion of the principle).
2. **Standalone with unspecified `SITE_DOMAIN` REFUSES, actionably** — naming the key and how to set it. It never generates a configuration that cannot serve.
3. **Absent `UPGRADE_ROLE` takes the standalone default**, so a fresh NSO box follows `stable` without being told to.
4. **Contradictory policy input still refuses**, unchanged — the 254 guard is correct and untouched.
5. **The landed park-and-serve fork (3ff11f1d6) and dispatch guard (3d102d676) become the final form**, asserted in tests, not rebuilt.

## Acceptance criteria

1. A fresh box with only `SITE_DOMAIN` specified generates a complete, serving standalone configuration.
2. A fresh box with **no** `SITE_DOMAIN` refuses, naming the key and the edit — never emitting a config that cannot serve.
3. Absent `UPGRADE_ROLE` yields production/`stable`; no upgrade-policy configuration is required for correct behaviour.
4. **Contradictory** role/channel input still refuses. **Red-verified: making the default resolve a contradiction FAILS a test.**
5. Existing installations are unaffected — `gen()`/`f.Generate` already wrote the mode key explicitly, so the flip reaches only genuinely fresh installs. Proven by test, not asserted.
6. Cloud slots (explicit `private`) and the canary (explicit-only) are unchanged.
7. The absent-versus-contradictory boundary is stated in the code at the default site.

## What is achieved

An NSO installs StatBus by supplying one fact — its domain — and gets a correct production box; every other default is the product declaring what it is, and no default ever answers a question the operator already answered two different ways.
---

author: architect
created: 2026-08-31 14:09
---
**AUTHORITATIVE DESIGN, part 1 of 2 — supersedes comments #1 and #3. Two variables, not three.**

**Purpose, in two sentences.** A box declares WHAT IT IS, and that alone decides what it follows unless someone writes otherwise. The second variable exists only to record exceptions, so an unremarkable installation stores nothing about upgrade policy at all.

## The table

| `CADDY_DEPLOYMENT_MODE` (what the box IS) | derived `UPGRADE_CHANNEL` (what it FOLLOWS) |
|---|---|
| `development` | `local` |
| `private` | `stable` |
| `standalone` (the default) | `stable` |

**A written `UPGRADE_CHANNEL` always wins.** Topology never implies purpose — leading is a written choice. Our niue slots write `prerelease` (their purpose is to test and show before others); rune writes `prerelease`.

## Derivation is LIVE. Seeding stops.

`.env.config` holds only what is **specified**. `config generate` derives the channel from the mode and writes it to the generated `.env` — **never back into `.env.config`**. The derived value is recomputed on every generate, so a mode change moves it.

**This explicitly overrules the existing rationale** *"a box that changes mode does not silently change what it follows"*. **It is safe for a reason worth stating: only a box that NEVER STATED a channel follows the mode — and for such a box, the mode IS its statement.** Any box with an opinion has written it down, and a written value is untouched by a mode change.

## Why STATBUS-254 cannot recur

254 was two keys disagreeing. **One of them no longer exists**, so the disagreement has no second party.

The seeding change closes the other half: **an unspecified box stores NOTHING**, so there is no previously-seeded value for a later hand-edit to contradict. Only exceptions carry the key, and a single key cannot contradict itself.

**So the 254 guard inverts — from "UPGRADE_CHANNEL is never a setting" to "UPGRADE_CHANNEL is THE setting, visible exactly where someone chose it."** One refusal survives: an unknown channel VALUE. Specified-but-incoherent still fails fast; ordinary doctrine, unchanged.

## Kept from comment #3

- **`CADDY_DEPLOYMENT_MODE` defaults to `standalone`** (`config.go:352`, currently `development`).
- **Standalone with unspecified `SITE_DOMAIN` refuses actionably** — a default is honest when the PRODUCT owns the fact, dishonest when the WORLD owns it. The product may declare what the box is; it may not invent the box's domain.
- **The absent-versus-contradiction boundary**, now simplified: role-versus-channel contradiction is structurally impossible, and what remains is an unknown VALUE — which refuses.
- **The landed park-and-serve fork (3ff11f1d6) and dispatch guard (3d102d676) stand as final**, asserted rather than rebuilt.

*(Consumer enumeration, fleet transition, STATBUS-328 verdict and acceptance criteria follow in part 2.)*
---

author: architect
created: 2026-08-31 14:10
---
**AUTHORITATIVE DESIGN, part 2 of 2 — the deletion, the transition, and STATBUS-328.**

## `UPGRADE_ROLE` deletion — enumerated consumers (9 files, 59 refs; tests/docs/backlog excluded)

| File | What it does | Becomes |
|---|---|---|
| `config/upgrade_role.go` (37) | the whole mechanism | **deleted**; the mode→channel table replaces it |
| `config/config.go` (8) | resolves and writes the role | derives channel from mode; writes to `.env` only |
| `cmd/upgrade.go:718-747` (5) | **a CLI verb that SETS the role** | **user-facing change** — becomes a channel verb or is removed in favour of editing `.env.config`. Decide deliberately; do not drop it silently. |
| `upgrade/service.go:3818,3828` | operator message text | reworded to the mode→channel story |
| `dotenv/dotenv.go:235` | comment | reworded |
| `ops/statbus-upgrade.service:52` | comment naming the 254 retriable refusal | that refusal no longer exists; rewrite |
| `ops/create-new-statbus-installation.sh:139,371` | writes the role unconditionally | writes `UPGRADE_CHANNEL` **only for exceptions**; nothing for an NSO box |
| `test/install-recovery/lib/vm-bootstrap.sh:429,452` | declares `UPGRADE_ROLE=production` | era-accuracy note below |
| `test/install-recovery/arcs/postswap-health-park-arc.sh:31` | comment relying on it | reworded |

**HONEST GAP, stated rather than papered over:** the migration-fix behaviour said to key on `RoleDevelopment` did **not** appear outside `upgrade_role.go`/`config.go` in my sweep. **The builder must find its real decision site and re-key it on `mode == development`.** I am not claiming to have found it — an enumeration presented as complete when it is not is the defect this project keeps catching. *(My first sweep was silently mangled by `rg -r`, which is `--replace`; re-run clean. Recorded because it is exactly why enumerations get verified.)*

**Era-accuracy consequence (297's rule): the rule INVERTS.** The fixtures declare a role because that is what their era's box carried. After deletion a **new**-era box has none and an **old**-era box does — so the harness must stay era-accurate in the new direction, not merely drop the line, which would construct a state its own era could not produce.

## Fleet transition — a discriminator, so no per-box judgement is needed

> **If the written role equals the default for that box's mode, it was SEEDED — delete it; the derived channel gives the identical answer. If it differs, it was DECLARED — write the matching `UPGRADE_CHANNEL`.**

Safe both ways: deleting a seeded value changes nothing, and a differing value is by definition someone's choice.

- **niue slots (all):** write `UPGRADE_CHANNEL=prerelease`.
- **rune:** write `UPGRADE_CHANNEL=prerelease`.
- **True NSO boxes:** write nothing — they derive `stable` from `standalone`.
- **Through config + install. No manual DB writes**, per standing doctrine.

## STATBUS-328 — split verdict

- **Cloud role-correction arm: ABSORBED.** It becomes the channel-override write above.
- **Ledger-hygiene arm: PREREQUISITE, not companion.** Switching the niue slots to `prerelease` makes every stable row already registered there **off-channel** — and **nothing retracts off-channel rows** (verified: every retirement path keys on version ordering; `d.channel` appears only at intake and announce, never in a retirement predicate). **This transition would MANUFACTURE the exact stale-offer residue already confirmed live on et, jo and ug.** Land the hygiene arm first, or the switch creates the problem it sits beside.

## Acceptance criteria

1. A fresh box with only `SITE_DOMAIN` set generates a complete, serving **standalone** config following `stable`.
2. A fresh box with **no** `SITE_DOMAIN` refuses actionably in standalone — never a config that cannot serve.
3. `config generate` **never writes `UPGRADE_CHANNEL` into `.env.config`**; the derived value appears only in generated `.env`. **Red-verified: reintroducing the seed fails.**
4. Changing the mode moves the derived channel on a box with **no** written channel, and does **not** on a box with one. Both tested.
5. An unknown `UPGRADE_CHANNEL` value refuses, naming the accepted values.
6. `UPGRADE_ROLE` appears **nowhere** outside historical migrations and era-accurate fixtures. **Red-verified by a grep-based test**, so a reintroduction fails rather than lingers.
7. The transition discriminator is implemented and tested both ways.
8. Every existing installation keeps its current effective channel — proven per box shape (development, private slot, standalone), not asserted.

## What is achieved

An installation says what it is, and the product decides what that means. Upgrade policy stops being configuration an ordinary NSO ever sees, and the only boxes carrying a channel are the ones deliberately leading — where the choice is visible on the line that makes it.
---

author: architect
created: 2026-08-31 14:19
---
**AMENDMENT to the authoritative design (#4/#5) — the King's superset model. My 328-prerequisite claim is WITHDRAWN, and replaced by a different one.**

**His model is right and it is grounded in how we actually cut releases:** v2026.08.1 and v2026.08.1-rc.01 are two names for **one commit** (0da0f202dcf3). A release is the final gated prerelease, promoted. So the channels are **nested, not sibling** — prerelease ⊇ stable — and a prerelease box legitimately runs everything.

## The code contradicts the model — that is the bug

`TagMatchesChannel` (`github.go:557-563`) treats them as disjoint: the `prerelease` channel admits `ShapePrerelease` only, so a **stable tag fails it**. Under the model that is simply wrong.

**Fix: `prerelease` admits BOTH shapes; `stable` stays restrictive (release only).** One site carries it — `FilterTagsByChannel` delegates to `TagMatchesChannel`, so discovery is fixed by the same change, and `scheduleStep`'s announce (`:5570`) correctly stops warning a prerelease box about a stable row, because that row is no longer an exception.

## WITHDRAWN: the 328 ordering. But a real prerequisite remains — a different one.

My claim was **conditionally** true: under *today's* disjoint code, switching the niue slots to `prerelease` genuinely does make their stable rows off-channel. The King's refutation removes the condition rather than the reasoning.

**So the replacement is precise: the `TagMatchesChannel` fix must land WITH or BEFORE the channel switch.** Ship the switch against unfixed semantics and the residue I described appears exactly as described. **328 is not the prerequisite; the semantics fix is.**

## The direction asymmetry, which the model implies and nobody has stated

Because the sets are nested, **the two directions are not symmetric**:

- **stable → prerelease WIDENS** what a box accepts. Every existing row stays valid. **No residue. Safe.**
- **prerelease → stable NARROWS** it. Previously-valid rc rows become off-channel, and nothing retracts them. **That direction DOES create residue.**

Record it now, because someone will eventually move a box back and the safety of this transition will be cited as precedent for a transition that is not safe.

## Offer selection: the same-commit short-circuit SURVIVES — and becomes MORE necessary

Widening membership makes the dual-tagged case **more** common, not less. Previously a prerelease box would not register a stable tag at all; now it registers both names for one commit, and `CompareVersions` correctly ranks the release above its own prerelease — so the box is offered the stable name **for the commit it already runs**.

**So the widened membership strengthens the case for the short-circuit rather than obsoleting it.** Keep it, and keep the rule that decides it: **an "upgrade" that changes no code is not an upgrade** — candidate `commit_sha` == installed commit → never an offer.

Ordering across shapes needs no change: an rc for a later patch outranks the current stable (correct — it *is* newer code), and a release already outranks its own prerelease.

## STATBUS-328 — final disposition, with one correction

- **Role-correction arm: ABSORBED**, unchanged.
- **Ledger-hygiene arm: OPEN and INDEPENDENT** — downgraded from prerequisite, **not** to a rare-future case.

**The correction: its subject is live today, not hypothetical.** Under the corrected semantics `stable` stays restrictive, so the **rc rows confirmed on et, jo and ug are genuinely off-channel and genuinely unretracted** — the pre-filter residue we verified by timestamp read. That is a present condition on three production boxes, and the only thing that changed is that it no longer blocks this transition.

Its scope narrows usefully, though: **only the rc-on-stable direction needs retraction now**, because stable-on-prerelease has become a legitimate offer.
---

author: foreman
created: 2026-08-31 14:33
---
KING'S APPROVAL (2026-08-31): the authoritative design (comments #4–#6) is APPROVED with one amendment — no internal ordering dance: IT LANDS IN ONE GO. One coherent landing on master carrying everything: the mode→channel derivation (live, no seeding), UPGRADE_ROLE deletion incl. the CLI verb, the re-keyed role-dependent logic, the TagMatchesChannel superset fix (prerelease admits both shapes), the same-commit short-circuit, and the mechanical fleet-transition logic (seeded role → delete; declared role → write the matching channel) in install's config work. Once landed, the King cuts the prerelease himself — the release IS the deployment vehicle; no box is touched by hand. Build: engineer (architectural multi-file lane), architect reviews the frozen diff hands-on before the foreman commits.
---

author: foreman
created: 2026-08-31 14:35
---
Architect's CLI-verb ruling (2026-08-31, proactive): REMOVE the role-setting verb at cmd/upgrade.go:718-747 — clean break, no shim (verb is 12 days old, arrived with the 2026-08-19 work, no installed base). Deciding reason: the validation a verb adds exists downstream and better — the unknown-channel refusal at generate covers EVERY writer, a verb only its own users; and under this design upgrade policy is not a routine knob — an exception should require opening .env.config and writing the line. Folded into the unit: doc sweep for the removed verb in the same landing.
---

author: foreman
created: 2026-08-31 14:53
---
ARCHITECT'S SUPERSEDING RULING (2026-08-31, replaces comment #8 — appended verbatim by foreman):

1. THE VERB IS KEPT, converted from a role verb to a channel verb. Exact shape: ./sb upgrade channel <local|stable|prerelease> — validate against the closed set and refuse an unknown value, write UPGRADE_CHANNEL into .env.config, run config generate, then restart the upgrade service. All three steps, because all three are what the existing verb does. Its --help must say plainly that an ordinary installation needs no channel and that this records a deliberate exception — that is where a casual adopter meets the command, so that is where the sentence does its work. A follow-up is filed and must not be folded into this landing: the regenerate-and-restart gap is general rather than channel-specific — every .env.config key leaves file and behaviour disagreeing until someone regenerates and restarts — so the right long-term home is ./sb install applying config changes, at which point this verb becomes redundant and can go for the reason originally given.

2. THE PREMISE GOT WRONG: comment #5's table described cmd/upgrade.go:718-747 as 'a CLI verb that SETS the role' — written from a grep hit on f.Set(...) at :732 without reading :699-760. It is not a setter — it is a three-step operator workflow, and step three is a service restart. The daemon loads its config only at startup, so a hand edit changes nothing observable until the operator also regenerates and restarts. Removing the verb would have relocated that work into the operator's memory; the failure mode is a box whose file and behaviour disagree — this ticket's own failure class. Caught by the engineer reading the function.

3. TWO FURTHER CLAIMS CORRECTED, BOTH ACCEPTED: (a) comment #6's 'one site' claim for the superset fix — the FilterTagsByChannel→TagMatchesChannel delegation is real, but selectLatestTagFromNames carries its own PRIVATE COPY of the membership rule and would have survived the fix untouched; the 'surface is small' sentence is precisely what would have made a builder stop looking. (b) comment #5's instruction to re-key the RoleDevelopment behaviour on mode == development — the engineer found the real decision site and it keys on the CHANNEL deliberately, so the instruction would break a stated property. Accepted pending one review condition: the property and where it is stated must be named, so it is verified rather than accepted as a summary.
---

author: foreman
created: 2026-08-31 14:59
---
ARCHITECT'S REVIEW VERDICT (2026-08-31): APPROVE with one required one-line amendment, one HIGH record-correction, and the two requested verifications done. (1) AMENDMENT: vm-bootstrap.sh:479 — empty BASE_SHA routes to the 254-era branch, writing the retired role key; right-by-accident today via the legacy translator, silently disarms the arcs' release-bless when the translator is deleted (upgrade_channel.go:264-269 schedules exactly that). Fix: empty BASE_SHA → current-era branch. (2) RECORD-CORRECTION (HIGH, no code defect): the niue slots do NOT get prerelease from the discriminator — their role=production EQUALS private mode's legacy default → seeded → deleted → derive stable; only rune's canary differs and is preserved. The discriminator is correct as designed; the freeze report's coverage claim was half wrong. THE EXPLICIT PRERELEASE WRITES ON THE NIUE SLOTS ARE A DELIBERATE POST-LANDING FLEET ACTION (comment #5's transition list), King-gated — and ORDERED: the key may only be written to a box ALREADY RUNNING the new code, because the old binary's 254 guard refuses a present UPGRADE_CHANNEL and would park the box. Consistent with AC8: the transition itself changes no box's effective channel; the slots leading is a separate act. (3) VERIFIED: migrate.go:2018's channel-axis property confirmed at the site (the comment-#5 re-key instruction was wrong; engineer's refusal correct); the era-probe design ruled sound (file-existence probe = era detection by the thing defining the era; the third branch is the era-accuracy rule applied). Also noted: seed-build exclusion anticipated at upgrade_channel.go:102-103; the translator's one-time-deletion note is the no-standing-self-heal rule applied unprompted.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LANDED IN ONE GO at 7816a7654, per the King's approval (comments #4–#7): 24 files, +1053/−766. The two-variable model is live: CADDY_DEPLOYMENT_MODE (default standalone — unspecified means an NSO production box) derives UPGRADE_CHANNEL live on every generate; a written channel always wins; UPGRADE_ROLE deleted (mechanism, verb, 59 refs across 9 files) with a grep guard red-verified twice (engineer's build; foreman's redo with a tracked probe after the engineer's index-rule self-report). SITE_DOMAIN refuses actionably in standalone. Channels nested (prerelease ⊇ stable) at TagMatchesChannel AND the private copy in selectLatestTagFromNames the one-site claim missed. Same-commit short-circuit compares by binary ldflags commit — deliberately not git rev-parse HEAD, which diverges from the running binary exactly mid-upgrade (engineer's improvement over the brief). One-time fleet translator with the seeded-vs-declared discriminator, self-scheduled for deletion once the fleet runs it. The channel verb KEPT as ./sb upgrade channel after the architect's ruling reversed on reading the function (three-step workflow, not a setter); config-apply generalization filed as STATBUS-332. Era gate probes upgrade_channel.go existence at BASE_SHA, three eras, empty base = current era (the architect's one required amendment — the old routing was correct only while the deletable translator existed). Review chain: architect hands-on approve; foreman line review + independent full-suite runs (14 packages, twice) + red-verification redo. AC8 holds: no box's effective channel changed at landing — the niue slots leading (explicit prerelease writes, only onto boxes running this code) is a separate King-gated act, on record in comment #10. NEXT: the King cuts the prerelease; the release is the deployment vehicle.
<!-- SECTION:FINAL_SUMMARY:END -->
