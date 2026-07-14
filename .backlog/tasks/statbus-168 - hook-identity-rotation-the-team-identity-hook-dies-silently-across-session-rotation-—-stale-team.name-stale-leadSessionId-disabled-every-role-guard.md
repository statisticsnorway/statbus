---
id: STATBUS-168
title: >-
  hook-identity-rotation: the team identity hook dies silently across session
  rotation — stale team.name + stale leadSessionId disabled every role guard
status: To Do
assignee: []
created_date: '2026-07-12 22:14'
updated_date: '2026-07-14 09:53'
labels:
  - tooling
  - team
  - not-install-upgrade
dependencies: []
priority: medium
ordinal: 169000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the role guards (operator/tester cannot commit or push; only the foreman cuts releases) hold on EVERY session, including post-restart/compaction continuations — and when identity is unknowable, the hook behaves per its own documented intent instead of silently disarming.
> FOUND: 2026-07-13 ~00:10, night shift — the foreman's authorized RC cut was denied as "unidentified caller"; investigation showed the guards had been silently OFF for everyone all along.
> COMPLEXITY: architect ruling + small hook change; the King should bless the final shape (it is permission machinery).

WHAT BROKE, three stacked stale facts (.claude/hooks/restrict-agent-spawn.sh):
1. `.claude/team.name` (the hook's per-checkout team pointer) was git-tracked with value "statbus" — but the harness moved to SESSION-SCOPED teams (`teams/session-<id>/`); `teams/statbus/` no longer exists. The hook resolved a nonexistent config → `lead_session_id=""` → every caller unidentified → ALL identity rules silently disabled (operator/tester commit blocks included). A guard that dies silently is worse than no guard — nothing failed loudly.
2. Even pointed at the live config, `leadSessionId` records the foreman session that CREATED the team; session ids rotate on restart/clear/continuation, so a legitimate continuation-foreman never matches. This is the same class STATBUS-118 fixed for spawns and the retired test-identity rule ("broke on every clear/crash/compaction").
3. The transcript-grep fallback identifies teammates by `agentName` — which never appears in the LEAD's own transcript (verified: zero roster-name matches in the live foreman transcript). So the lead has NO working fallback identification.

NIGHT-SHIFT REPAIRS (data fixes only, rule untouched; commit 701477b3a):
- `.claude/team.name` untracked + gitignored (per-checkout state by its own design), local copy now names the live session-team.
- The live team config's `leadSessionId` corrected to the current foreman session.
Both re-armed the hook; the authorized RC cut then passed identification legitimately.

DURABLE FIX for the architect to rule (the repairs are one-time; recurrence must fail loudly, never be quietly repaired — no-standing-self-heal):
- How the hook should identify the lead across rotation (e.g. the harness updates leadSessionId on continuation; or identify the lead as "the session that is not any roster member's" — careful, that grants by exclusion; or read the team dir freshest-inbox ownership).
- Whether `release prerelease`'s deny-on-unknown should stand given the file header's own documented principle is "unidentifiable → permissive fallback (never hard-break legitimate work)" — the two contradict; pick one and write it down.
- A loud self-check: if the resolved team config does not exist, the hook must SAY so on every gated call, not silently disable all rules.
- Map the vocabulary drift: the roster name is "team-lead" but the rules test for "foreman" — the header notes the equivalence, the code does not implement it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect rules the lead-identification mechanism across session rotation and the deny-vs-permissive contradiction for release commands; King blesses the shape (permission machinery)
- [ ] #2 The hook fails LOUDLY when its resolved team config does not exist — silent disarm is impossible
- [ ] #3 The ruled fix is implemented with the hook's test file extended to cover: continuation-foreman identification, missing-config loudness, and team-lead↔foreman vocabulary
- [ ] #4 The night-shift data repairs (701477b3a + config leadSessionId) are superseded by the mechanism — nothing depends on hand-maintained session ids
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-13 09:09
---
CARRY-OVER from STATBUS-122 (merged here on the 2026-07-13 triage): the cross-clone concurrent-team scenario — two checkouts on one machine, each with its own live team — becomes an explicit TEST FIXTURE for the ruled identity mechanism (AC#3's test file gains it). 122's original collision mechanism (shared global team name) died with the harness's move to session-scoped teams; what survived is exactly this ticket's scope.
---

author: foreman
created: 2026-07-13 14:56
---
RECURRENCE (2026-07-13 ~14:40, night shift resume after /clear): the hook denied `./sb release prerelease` from the foreman — caller unidentifiable. Anatomy this time: `.claude/team.name` pointed at team `session-7719192b` whose leadSessionId was the PRE-/clear session (5e89a6d0-…); the new session (0409b59d-…) matched nothing, and the transcript roster-grep found no member name in a fresh post-/clear transcript. Workaround applied: jq-edit the team config's leadSessionId to the current session id (verified by newest transcript filename), after which the release gate passed. Note the failure was at least LOUD here (release path denies unknown callers) — the silent half of this ticket is the permissive fallback on other paths. Fix design should cover the /clear rotation case explicitly: the lead's identity must survive session-id rotation or be re-derivable without hand-editing config.json.
---

author: architect
created: 2026-07-14 09:53
---
RULING part 1/2 (architect, 2026-07-14) — AC#1 first half: lead identification across rotation + the release deny-vs-permissive contradiction. King blesses before build (permission machinery). All premises verified live this session.

VERIFIED FACTS:
1. Teammate sessions are SEPARATE PROCESSES spawned with explicit identity argv (`--agent-id <name>@<team> --agent-name <name> --team-name <team> --parent-session-id <id>` — observed on live teammates of another session-team via ps, 2026-07-14) and carry env `CLAUDE_CODE_CHILD_SESSION=1` (verified in my own architect session). Lead sessions run bare (`claude --effort max [--resume]`) — no agent flags. Hooks inherit the session process env; restrict-agent-spawn.sh already depends on env there (`CLAUDE_CONFIG_DIR`, line 77).
2. The lead's roster entry is name="team-lead", agentType="team-lead" (live config.json); the code only ever sets/tests caller=="foreman" (lines 131-132, 224-227, 341-342, 363) — gap (d) is real in code. Worse: the deny messages advise `SendMessage({to: 'foreman'})` (lines 351, 372, 383) — NOT a routable roster name; those hints are broken today.
3. `leadSessionId` in the live config is still the 2026-07-13 hand-edit; nothing updates it on rotation (two incidents prove it).

(a) LEAD IDENTIFICATION — DERIVE, DON'T RECORD. Identity comes from live process lineage, never from a stored session id:
- Step 1 (unchanged): transcript roster-grep (STATBUS-118 most-count match) → positively identifies teammates. A hit whose member agentType=="team-lead" normalizes to foreman.
- Step 2: no roster hit AND `CLAUDE_CODE_CHILD_SESSION` unset → ROOT session → caller="foreman". A root session in this checkout is by definition user-driven (the lead, or the King's own shell) — the guard's threat model is confused spawned teammates, never the user.
- Step 3: no roster hit AND child marker set → unknown-child.
`leadSessionId` is REMOVED from the hook entirely (clean break — it IS the stale-data vector behind both incidents). AC#4 satisfied: nothing hand-maintained remains. Rotation-proof: /clear rotates session_id but never changes root-ness.

Rejected alternatives: freshest-inbox ownership (lag-prone — a fresh post-/clear foreman has touched no inbox at exactly the moment it cuts a release; that is the incident timing, twice); harness-updates-leadSessionId (not ours to control; observed NOT happening, twice); lead-by-exclusion without the child marker (grants root status to unidentified children).

BOUNDED RESIDUAL + BUILD PROBES (the run is the oracle): if the harness merely INHERITS env rather than injecting it per session, an in-process non-roster subagent inherits the lead's env and classifies foreman (today it classifies unknown→permissive, so the delta is only on the release gate). Build MUST probe: (P1) foreman runs `env | grep CHILD_SESSION` → expect absent; (P2) an in-process background subagent runs the same → record set/absent. If P2 shows absent, the residual stands and is documented in the hook header (accepted: in-process subagents are foreman-spawned and instruction-scoped; every small-model teammate is a separate process carrying both the marker and a roster name).

(b) RELEASE deny-vs-permissive — KEEP THE DENY; the contradiction dissolves. Two-tier policy, written into the header: Tier 1, ordinary ops: unknown → permissive (never hard-break legitimate work). Tier 2, authority-gated ops (`./sb release prerelease`): caller must be positively "foreman"; unknown-child → DENY. The contradiction's precondition is gone — the legitimate foreman can no longer land in "unknown" (root-ness survives rotation) — so fail-closed on release costs nothing legitimate and still blocks confused children. The header's blanket "unidentifiable → permissive fallback" sentence is rewritten to name the release exception explicitly.
---

author: architect
created: 2026-07-14 09:53
---
RULING part 2/2 (architect, 2026-07-14):

(c) MISSING CONFIG = LOUD ON EVERY GATED CALL. If the resolved TEAM_CONFIG does not exist, every allow on a gated path emits BOTH the allow-note AND a top-level `systemMessage`: "restrict-agent-spawn: team config NOT FOUND at <path> (resolved via CLAUDE_TEAM_NAME | .claude/team.name | default); teammate role guards INACTIVE — fix .claude/team.name". NOT a deny: a missing config is legitimate in solo sessions, and the root foreman must never be bricked by a stale pointer (root identification is config-independent — this alone would have prevented both incidents). Child sessions with no config remain unknown → the release gate stays fail-closed. Build must verify `systemMessage` visibility EMPIRICALLY; if it does not surface in the transcript/UI, escalate the channel — do not ship a silent "loud".

(d) VOCABULARY — ONE NORMALIZATION BOUNDARY. Caller resolution returns the ROLE vocabulary ("foreman") plus, separately, the ROUTABLE lead name read from config (the leadAgentId member's `name`, e.g. "team-lead"). Role tests keep "foreman" internally (matches all docs and messages); every emitted SendMessage hint interpolates the routable name (fixes the currently-broken `to: 'foreman'` hints, lines 351/372/383). Lead recognition keys on `agentType == "team-lead"`, never on a hardcoded display name.

AC#3 TEST ADDITIONS (for the build): continuation-foreman (root env, fresh transcript, no session-id match anywhere) → foreman; child+roster hit → that teammate, including team-lead→foreman normalization; child+no-roster → unknown (release DENIED, git ops allowed); missing config → loud output shape asserted (allow-note + systemMessage); cross-clone two-checkout fixture (comment #1) — each checkout resolves only its own cwd-scoped config; existing heredoc-strip and commit-msg-strip cases unchanged.

KING BLESS POINTS (the three judgment calls in this shape):
1. Root-session ⇒ foreman-equivalence: ANY user-driven session in this checkout passes foreman gates (release included). Rationale: the guard constrains spawned agents, not the King.
2. Fail-closed release for unknown children (Tier 2 deny stands).
3. The accepted residual if probe P2 shows env is inherited (in-process non-roster subagents would pass the release gate; all real teammates remain covered).

Nothing checked on the ACs — AC#1 completes only with the King's bless of this shape.
---
<!-- COMMENTS:END -->
