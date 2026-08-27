---
id: STATBUS-259
title: >-
  sshdoers-ships-as-code: the fleet's inbound-command policy is hand-managed
  root state on niue — the one security surface that does not ship as code
status: In Progress
assignee:
  - engineer
created_date: '2026-08-19 20:06'
updated_date: '2026-08-27 13:05'
labels:
  - ops
  - security
dependencies: []
priority: medium
type: chore
ordinal: 252000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/etc/sshdoers on niue — the byte-pinned allowlist every inbound CI ssh command is checked against — is root-owned, hand-edited host state. The repo carries a copy (ops/niue/sshdoers, whose own header says "Managed by hand"), and nothing syncs or verifies repo↔host: the live policy can drift from the reviewed copy silently, in either direction.

The allowlist SHAPE is correct (least privilege on an inbound credential door). What violates doctrine is the management: every other fix reaches a box through code + the box's own install; the access policy alone reaches it through a person editing a root file over SSH — the exact pattern the fleet-channel correction (STATBUS-254) just removed from configuration.

Surfaced during the King's 2026-08-19 pushback on STATBUS-258 ("an allowlist seems unprincipled"); the architect ruled the diagnosis is precisely this, and that it deserves its own ticket whichever shape 258 takes. Sequencing note: 253/Wave D shrinks this file (deploy entries die with the deploy key); the durable mechanism should land on whatever remains (the notify entrypoints, the pg_regress runner, and any 258 observation door).

WHAT IS ACHIEVED: the live inbound-command policy is provably the reviewed one — drift either fails loudly or is impossible, and the last hand-managed security surface joins the ships-as-code doctrine.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-19 20:37
---
DESIGN — the mechanism already exists; what is missing is that sshdoers never joined it.

## THE LEGO DECOMPOSITION

**General part, already built and already sanctioned:** `ops/setup-ubuntu-lts-24.sh` — a repo-tracked, staged, root-run host provisioning script with a non-interactive mode, fetched over https and run with sudo. That is *how root state on these hosts is established*, by design and by documented usage.

**Our composition:** the specific commands our CI is permitted to run on each slot.

**What is missing is not a mechanism. It is that sshdoers was never made a stage of the one we have.** `grep sshdo ops/setup-ubuntu-lts-24.sh` returns nothing — the allowlist was established by hand, outside the path built for exactly this, and its own header records the consequence: *"Managed by hand."*

So the fix is not to invent a delivery mechanism. **It is to add a stage that renders `/etc/sshdoers` from `ops/<host>/sshdoers`**, which is already the repo layout (`ops/niue/sshdoers`, with standalone hosts free to carry their own).

## WHY NOT PUT IT IN `./sb`

Because that is the STATBUS-258 error again. A statistical office installing StatBus has no CI door and never will; a `./sb` subcommand for rendering a CI allowlist would put our fleet's arrangement into every installation in the world. **The allowlist is ops territory, not product territory**, and `ops/` is where our fleet's compositions belong. I am stating this explicitly because it is the exact trap I fell into yesterday and the King will be reading for it.

## BOOTSTRAP — there is no new hand-touch

The honest question is whether the mechanism's own installation reintroduces the problem. It does not: **`curl … | sudo ./harden.sh` is already the accepted, documented, one-hand-touch for standing up a host.** Adding a stage to it introduces no new class of manual action — it moves the allowlist *into* the action we already accept, and out of the ad-hoc root session we do not.

The stage must be independently runnable (the script is already staged and non-interactive-capable), so an allowlist change does not require re-running host hardening in full on a live box.

## DRIFT DETECTION — publish a checksum, not the file

The live file must be checkable, but `/etc/sshdoers` is root-owned and its contents are a security policy no slot user should read. Both constraints are satisfied by publishing a hash rather than the content:

- The stage writes `/etc/sshdoers` (root, restrictive) **and** a world-readable `/etc/sshdoers.sha256` beside it.
- Anyone — including an unprivileged slot user over the existing read door — can compare that hash to the hash of the repo copy.

**Where it must fail loudly: the release preflight.** That is the moment the door's correctness actually matters, it is a surface somebody reads every single release, and it already refuses on gate failures. A drifted allowlist means the fleet's access policy is not what was reviewed — which is precisely a thing that should stop a release rather than be discovered afterwards.

The check reports what it examined: which host, which hash, and — when they differ — that the LIVE file is authoritative for behaviour while the REPO copy is authoritative for intent, so the operator knows which way to reconcile.

## SEQUENCING WITH 253 / WAVE D

This is the payoff and it should be said plainly: once the stage exists, **the file shrinking as deploy entries die becomes a reviewed commit plus a stage re-run, instead of a root session.** The 253 removals and the Wave D deletions stop needing privileged hands at all — they become diffs, which is what "ships as code" means.

259 lands first; 253's removals then ride it.

## TWO FACTS FOUND WHILE VERIFYING

1. **The header is stale about its own location** — it says *"see tmp/niue-sshdoers in the statbus repo for a copy"* while the file lives at `ops/niue/sshdoers`. Fix it in this unit; a pointer to a path that no longer exists is how the repo copy came to be treated as a souvenir rather than a source.
2. **STATBUS-258's entry is already expressible.** The file declares `match hexdigits`, where `#` matches any hex digit at runtime — used today for pg_regress's 40-char SHA. So `upgrade apply <40hex>` needs **no new grammar and no new sshdo capability**, only a line. That de-risks 258 materially and is worth knowing before it is built.

## NOT SPECIFIED

Whether other hand-managed root state on these hosts (unit files, ACLs) should join the same stage. Probably yes, and by the same argument — but each deserves its own evidence rather than being swept in on this one's reasoning.
---

author: foreman
created: 2026-08-20 06:06
---
KING APPROVAL (2026-08-20 morning) — the design in comment #1 is approved as ratified, exactly as written: /etc/sshdoers becomes a stage of ops/setup-ubuntu-lts-24.sh (the existing repo-tracked root provisioning path), independently runnable; a world-readable /etc/sshdoers.sha256 is published beside the root-owned file; drift FAILS THE RELEASE PREFLIGHT; explicitly NOT a ./sb subcommand (the product must not know CI doors). The existing `match hexdigits` grammar means 258's future `upgrade apply <40hex>` entry is one line.

Execution order pinned by the King:
1. Engineer builds the stage + the preflight drift check (this ticket).
2. The FIRST stage run on niue requires the King's root session — the exact command list must be pre-declared per the standing box-access rule.
3. Only after the stage is live does deploy-to-dev's marked block swap apply-latest → upgrade apply "$SHA".

Architect verdict required on the diff before landing, as always.
---

author: architect (relayed by foreman)
created: 2026-08-20 06:15
---
VERDICT on the engineer's plan (2026-08-20): (a) faithful implementation — APPROVED. (b) COMPARE-FIRST first-run protocol — RATIFIED, an improvement on the design: nothing has ever synced repo↔live, so the first root session compares read-only and STOPS on difference; reconciliation is a reviewed commit (live wins on first contact — live is authoritative for behaviour, repo for intent) and the first stage run is byte-wise a no-op. Prove the machinery while changing nothing.

(c1) Preflight read account: devops@<host>, env-overridable. The read needs no privilege (hash file world-readable); unreachable = FAIL with loud SKIP_SSHDOERS=1 bypass — cannot-verify is not verified.

(c2) MODE — REVERSED, hazard not preference: sshdo runs AS THE SLOT USER via command= in authorized_keys and must read /etc/sshdoers as that user (unless setuid). Setting 0600 root:root could deny every CI command fleet-wide in one stroke. The stage PRESERVES the live mode on an existing file — reports it, changes nothing. This also corrects the original design's unverified premise that no slot user should read the policy; the hash file survives on the better justification (drift detection without parsing + recording what was installed). The real mode arrives with step 3 of the first run.

(c3) SSHDOERS_REF — REQUIRED, no default, never master. A security artifact must be commit-addressed (canonical-commit-naming); installing whatever master holds at run time means nobody can name the live policy afterwards.

COMMAND LIST ADDITION: step 7 also proves demo's entry (ssh statbus_demo@niue "cd ~/statbus && ./sb upgrade apply-latest" must be ALLOWED) — the newest entry, the named casualty of a wrong reconcile, and its loss would be silent (the 04:23 UTC scheduled trigger just starts failing). Test the entry most likely to be missing.

Build go approved on the architect's side; command list relayed to the King with these three changes.
---

author: engineer
created: 2026-08-20 06:19
---
**BUILT AND FROZEN — ready for the architect's verdict.** Chain: build OK, `go test ./...` green, `golangci-lint run ./...` 0 issues, gofmt clean, `bash -n` clean, **shellcheck warnings IDENTICAL to HEAD** (3×SC2034 + 3×SC2164, all pre-existing — compared count-by-code against a HEAD extraction, not eyeballed). Files: `ops/setup-ubuntu-lts-24.sh`, `ops/niue/sshdoers`, `cli/cmd/release.go`, plus `cli/cmd/release_sshdoers_drift.go` and its test (new).

## ⚠ SEQUENCING — DECIDE THIS BEFORE LANDING

**The preflight check will FAIL the next cut until the King's root session has run.** `/etc/sshdoers.sha256` does not exist on niue yet, so the read fails — and an unreadable host is a FAILURE by design. Correct behaviour, not a bug, but it means landing this blocks releases until Stage 8 has run once.

The refusal names that exact cause ("has Stage 8 ever run there?") and `SKIP_SSHDOERS=1` exists precisely for this gap, so nobody is stuck. The architect should still choose deliberately: land both now and hold the next cut for the session, or land the stage + header fix now and the preflight check after. **I have not decided this** — it changes when releases are possible.

## Stage 8 — "CI Command Allowlist (sshdo)"

Follows the existing stage shape exactly. Fetches `ops/<host>/sshdoers` from the SAME public raw.githubusercontent origin the script itself comes from — no embedded copy, one source of truth — and installs it **byte for byte**: no envsubst, no comment stripping, no normalisation, because the preflight hashes the repo file and any transformation would make two identical policies look like drift and fail every release.

**Three refusals, each because the failure is otherwise invisible:** sshdo absent (an allowlist without its enforcer looks configured and enforces nothing — worse than an absent file, since its presence reads as evidence the door is closed); an empty fetch; and a fetch missing `match hexdigits`/`syslog` (a truncated file fails CLOSED so it would not open the door, but it would break every CI path while looking like a successful run).

Before installing it SHOWS THE DIFF against the live file and backs that file up — the operator is changing the fleet's access policy, and a line that disappears is a workflow that stops working. `verify` covers both files' modes, that the published hash describes the file actually installed (a stale hash would let real drift pass the preflight — the one failure this exists to prevent), and byte-identity with what was fetched.

**"Independently runnable" needed no new flag** — `--skip-stages` is already honoured in both modes, so `--non-interactive --skip-stages "0 1 2 3 4 5 6 7"` runs this stage alone. That is what the King's command list uses.

## Preflight check 16

Hosts are DISCOVERED from `ops/*/sshdoers`, never hard-coded — a hard-coded list is the same defect one level up: a standalone host growing its own allowlist would be silently unchecked, and nobody would learn they had not added it.

Three named outcomes: MATCH passes; MISMATCH fails printing host, both hashes and the reconciliation direction; **UNREACHABLE FAILS**, with the loud `SKIP_SSHDOERS=1` bypass in the established `SKIP_IMAGES` shape. Unreachable is not a skip — the check examined nothing, and a pass would report a guarantee nobody verified, which is worse than no gate because the release summary would say the policy was confirmed. **Zero hosts also fails**, same reason.

The drift message spends its words on what the operator does next: LIVE authoritative for BEHAVIOUR, REPO for INTENT, and *do not simply re-run the stage to make the red go away* — that erases whatever live has and repo lacks.

## Tests — the failure paths, RED-verified in isolation

Three REDs, mutation site asserted, each against a clean file with a verified backup: zero-hosts passing fires; an unreachable host being skipped fires; losing the reconciliation direction fires.

One deserves naming: the hash comparison is checked against the **actual `sha256sum`/`shasum` binary** — not a constant I typed, and not Go hashing twice and agreeing with itself. The stage publishes the host tool's output while the preflight computes its own; if those ever disagreed, every release would fail on a genuinely identical policy. My first draft of that test carried a fabricated expected hash it then discarded unused — decoration, replaced.

Plan and the King's pre-declared root command list: `tmp/259-command-list.md`.
---

author: engineer
created: 2026-08-20 06:21
---
**All three verdict changes applied and re-frozen** — comment #3 arrived while I was building, and (c2) reversed something I had already written. Chain re-run: build OK, `go test ./...` green, lint 0 issues, `bash -n` clean, shellcheck still IDENTICAL to HEAD.

**(c2) THE MODE — the architect is right and my 0600 was a fleet-wide outage waiting to happen.** I verified the mechanism at source rather than taking it on the ruling: `sshdo` is a Python script invoked through `command="/usr/local/bin/sshdo"` in the SLOT USER's `authorized_keys`, and it plain-`open()`s `/etc/sshdoers` at ops/niue/sshdo:299 — as that user, with no setuid anywhere. A `0600 root:root` file would have been unreadable to every slot user and denied EVERY CI command on the fleet, from a stage that printed success and passed its own verifications.

The stage now PRESERVES the live file's mode and ownership, reports them, and changes nothing. Only a first-ever install picks a mode, and it picks a readable one for the same reason. The mode verification changed with it — instead of asserting a chosen `600`, it asserts the file kept the mode it was installed with AND that it is readable by someone other than root, which is the property that must hold whatever the mode turns out to be.

I also removed the premise that justified the tightening. The design said the policy is "a security policy no slot user should read"; that is false — the slot user MUST read it. The hash file survives on the better justification the architect gave: drift detection without anyone parsing the policy, plus a record of exactly which bytes were installed.

**(c3) SSHDOERS_REF is now REQUIRED**, no default, with a refusal that says why: a security artifact installed from a moving ref cannot be named afterwards, so nobody could answer "what policy is live?". The `--help` text says the same.

**(c1)** matches what was already built — `devops@<host>`, env-overridable, unreachable is a FAILURE with the loud `SKIP_SSHDOERS=1` bypass.

**The command list is updated** (tmp/259-command-list.md): demo's entry added to step 7 with the architect's reasoning at the line — newest entry, named casualty of a wrong reconcile, and its loss would be SILENT because the 04:23 UTC scheduled trigger would simply start failing with nobody watching. The compare-first protocol is written up as the session's opening move, `SSHDOERS_REF` is marked required, and step 3 is now explicitly the reading that settles what the real mode has always been.

One note for the verdict: this is the second time this week that a premise stated in a design turned out to be checkable and false (the other was "the original still exists in your frozen state"). Both were a minute's work to verify. I checked this one only because the architect flagged it — I had implemented the design's premise without testing it, which is exactly the habit I am supposed to have.
---

author: engineer
created: 2026-08-20 06:26
---
**Ruling 2's "read sshdo's source, don't infer" carried out properly — and it found more than the ruling assumed.** Three additions since #5; chain green throughout (build, `go test ./...`, lint 0 issues, `bash -n`, shellcheck still identical to HEAD).

**1. The mode hazard is worse than "denies CI commands".** Reading `load_config` rather than reasoning about it: on an IOError — exactly what a `0600 root:root` file gives a slot user — sshdo does NOT fail loudly. It logs `configerror` to syslog and **returns an EMPTY config** (ops/niue/sshdo:477-481). `check_auth` then finds nothing allowed, so every command is refused with the generic *"command not in allowlist"* message. So the tightening would have caused a fleet-wide outage AND disguised its cause, sending whoever debugged it hunting for a missing ENTRY rather than an unreadable FILE.

Also settled by the same read: **sshdo imposes no mode requirement of its own** — no stat, no permission check, no refusal on a group- or world-readable config anywhere in the file. The only requirement is readability by the invoking user. That is what makes 0644 the right choice for a first-ever install: the least that guarantees what sshdo actually needs, with no stricter rule to satisfy. All of this is now written at the line, with citations, replacing my inference.

**2. The stage now validates with sshdo's OWN parser** (`--check`) before installing, and again after. That catches what a grep cannot: invalid directives, clashing allow/disallow rules, entries naming users that do not exist. The grep stays — the two answer different questions ("is this the file we think it is?" versus "will sshdo accept it?"), and a truncation can be perfectly valid syntax.

**THE EXIT CODE IS NOT THE VERDICT, and testing found that rather than reading.** `sshdo --check` counts "No such user" into its error total and exits non-zero for it — verified: exit 9 against this repo's own allowlist on a machine without the slot accounts. Had I gated on the exit code, a freshly-provisioned host where Stage 8 runs before every slot user exists would have REJECTED a perfectly valid allowlist and stopped provisioning — for a condition of the host, not a fault in the file. The gate now splits on what the parser calls it: `error:` refuses, `warning:` surfaces loudly and continues. Proven on real input both ways — an invalid line produces an `error:` and refuses; the repo's own file with unknown users produces zero `error:` lines and passes.

**3. A wiring pin, in the gate-layer source-scanning shape.** Every other test here exercises `checkSshdoersDrift` directly, so all of them would still pass if the call were deleted from `preflightChecks` — the gate perfectly correct and never running, with the release summary simply no longer mentioning it. A gate nothing calls is indistinguishable from no gate. Pinned both ways: the call must exist AND its result must fold into `allPassed`, since calling it and dropping the answer looks wired up in review and prints a ✗ nobody acts on. Both RED-verified.

**One numbering correction:** the brief called it check 13, but release.go's checks run 1–12 and then "13-15. Commit-scope workflow oracles" (three of them), so this lands as **check 16**. Same position — last, after the network gates — just a different number than the brief anticipated.

The sequencing question from #4 is still open and still not mine: the preflight will fail the next cut until the root session has run.
---

author: foreman
created: 2026-08-20 06:29
---
LANDED at 202ff3511 (master, pushed). Throwaway-worktree build + vet + STATBUS259 tests green from the staged state; bash -n clean. Foreman landing review made two verifications beyond the architect's: sshdo --check is real (ops/niue/sshdo:43) and its error:/warning: prefixes are printed verbatim by errormsg (ops/niue/sshdo:293) so the stage's split greps anchor correctly; FAILED_VERIFICATIONS non-empty exits 1 (setup script:1531-1538) so every refuse-path fails the run loudly. One landing catch fixed before commit: the retracted "no slot user should read it" premise survived in the drift check's header comment — rewritten on the ratified justification; the engineer swept the tree and confirmed it was the last live instance.

REMAINING ON THIS TICKET: (1) the King's pre-declared root session on niue (command list at tmp/259-command-list.md, <COMMIT>=202ff3511, awaiting the King's nod — compare-first, stops on hash difference); (2) after the session: deploy-to-dev's marked block swaps apply-latest → upgrade apply "$SHA" (STATBUS-258's one-line allowlist entry rides the now-landed mechanism). NOTE FOR EVERY CUT UNTIL THE SESSION RUNS: preflight check 16 will fail because /etc/sshdoers.sha256 does not exist on niue yet; the refusal names this cause; SKIP_SSHDOERS=1 is the loud bypass — architect ruled strict-from-day-one (a) deliberately.
---

author: foreman
created: 2026-08-27 12:33
---
KING APPROVED THE ROOT SESSION (2026-08-27, first act back from the break): the pre-declared command list at tmp/259-command-list.md is the declared session, verbatim, with <COMMIT> = 202ff3511. Verified before relay: no commits landed during the break (origin tip still 99371ab9b), the last change to ops/setup-ubuntu-lts-24.sh and ops/niue/sshdoers is 202ff3511 itself, so the pin is exact. Compare-first stands: steps 1-3 read-only, STOP on hash difference, reconcile as a reviewed commit with live winning on first contact. The King runs steps 1-6 as root on niue; step 7's dev entry is provable through the real CI door via a deploy-to-dev dispatch, demo's at its next scheduled trigger or from a CI-key holder.
---

author: foreman
created: 2026-08-27 12:40
---
FIRST ROOT SESSION RAN AND STOPPED AT THE STOP CONDITION (2026-08-27, operator, root@niue as granted by the King). Step 2: repo@202ff351 = 48a91bc9…, live /etc/sshdoers = f8b66940… — DIFFER; steps 4-6 not executed, zero bytes changed on the box. Step 3's reading settles the mode question: live is 644 root:root, dated Aug 19 11:55 — the architect's preserve-the-mode reversal was correct (0600 would have broken every slot).

HONEST NOTE: the mismatch was GUARANTEED and nobody said so beforehand — the 259 unit rewrote the repo copy's header comment, and byte-for-byte hashing includes comments. The stop still proves the machinery; the substantive question is whether the diff holds anything BEYOND the header (live dated Aug 19 11:55 — hand-edits that day, demo's STATBUS-248 trigger entry the standing suspect).

RECONCILE IN MOTION per the ratified protocol (live wins on first contact): operator fetches the live file content (root read → tmp/259-niue-live-sshdoers); architect diffs against the repo copy and rules which lines belong; the reconcile ships as a reviewed commit to ops/niue/sshdoers; the session re-runs pinned at the NEW commit.
---

author: foreman
created: 2026-08-27 12:44
---
SECOND-SESSION PROTOCOL RATIFIED (architect, 2026-08-27) — the foreman's step-2 reformulation REPLACES the original: after a deliberate reconcile, identity is the wrong question and PROVENANCE is the right one. The second session's step 2 compares live's hash against the CAPTURED BASELINE, not the repo copy: live still at baseline → PROCEED (the only delta is the ruled one); live anything else → STOP, the box moved since the ruling, re-adjudicate. Success criterion moves to step 6: live's post-install hash equals the reconciled repo copy's hash.

LOAD-BEARING BASELINE HASH, recorded verbatim per the architect's addition #1 — the second session's stop condition compares against THIS RECORDED VALUE:

  f8b669402e9c01295de29e30aa676fa65f6ec2f65cd3b62abe314f75aa9ea364  /etc/sshdoers (niue, captured 2026-08-27, mode 644 root:root, dated Aug 19 11:55)

Addition #2: after the install, prove entries-unchanged rather than assert it — diff the non-comment, non-blank lines of the step-4 backup against the new live file; MUST be empty. Pairs with step 7 (door test is behavioural but covers two users; the line diff is exhaustive but cannot prove sshdo parses the result) — both run.

RECONCILE DIFF (architect's ruling, summary): live carries SEVEN grants the reviewed copy never had — ci-deploy-status.sh for statbus_tcc/dev/ma/ug/et/jo and github-runner's statbus-runner-health — a naive install would have revoked all seven. Repo wins on comments; live wins on entries, captured verbatim; the live block's "all seven" comment is corrected to SIX with demo's absence explained (deploy-to-demo.yaml deleted, 244a — adding a poll entry for demo would be a grant ADDITION, separate reviewed decision); the five Wave-D-condemned entries are captured AND marked, never deleted in a reconcile. Mechanic building; architect reviews the diff before landing.
---

author: foreman
created: 2026-08-27 12:47
---
RECONCILE LANDED at eff9b42efbbcc1091449598f70defd059912d686 (architect verdict: LAND — both anchors verified independently: 25 insertions 0 deletions one hunk, comments untouched proven by absence of deletion lines; sshdo emits No-such-user as warning: at :332/:393 so the stage tolerates github-runner on hosts without that user). STATBUS259 preflight tests green in the throwaway worktree.

ARCHITECT'S GUARANTEE NOTE, recorded so nobody mistakes the parser for it: sshdo --check CANNOT catch a misspelled username (unknown user = warning, validates cleanly, silently grants nothing). The protection is the SET-EQUALITY CHECK — comment-stripped, sorted, byte-identical to the live capture — which is the strongest evidence in this unit and the guarantee the parser structurally cannot give.

SECOND SESSION NEXT (operator, root@niue): provenance protocol as ratified in comment #10 — step 2 compares live against the RECORDED baseline f8b669402e9c01295de29e30aa676fa65f6ec2f65cd3b62abe314f75aa9ea364 (proceed only if unchanged); SSHDOERS_REF=eff9b42efbbcc1091449598f70defd059912d686; step 6 success = live hash equals the reconciled repo copy's hash; post-install entry-line diff of backup vs new live MUST be empty.
---

author: foreman
created: 2026-08-27 12:50
---
SECOND SESSION STOPPED CLEANLY AT STEP 4 (2026-08-27): provenance check PASSED (live still at the recorded baseline f8b66940… — the new step 2 worked as ratified), backup taken (/root/sshdoers.pre-259.20260827T124818Z), then the stage run REFUSED: ops/setup-ubuntu-lts-24.sh --non-interactive demands /root/.setup-ubuntu.env (ADMIN_EMAIL, GITHUB_USERS, …) — values Stage 8 never consumes. Nothing was installed; zero bytes changed on the box.

THE FINDING: "independently runnable" was verified by READING (--skip-stages exists, comment #4) and never RUN — the run was the only oracle, again. The env requirement lives in the script preamble, not in the stages that consume it, so running ONLY Stage 8 still demands a config it never reads. Hand-writing a dummy env on niue is out (NO WORKAROUNDS, King's standing ruling). Architect is ruling the fix shape: per-stage config requirement (general, honest — the requirement belongs to the stages) vs a narrow only-Stage-8 exemption (surgical, special-case smell). Fix lands as a reviewed commit; THIRD session runs pinned at that commit — same provenance protocol, baseline unchanged (the box did not move).
---

author: architect (pinned by foreman)
created: 2026-08-27 12:51
---
FIX RULING for the step-4 refusal (2026-08-27), with the error owned first: "independently-runnable is satisfied by SKIP_STAGES" was ruled from reading that the flag EXISTS — the presence of a mechanism is not the mechanism working; the run was the only oracle again and it cost the King a session.

THE RULING: shape (a), done a specific way. (b) — encoding "Stage 8 is special" in the preamble — is disqualified: right exactly once, wrong from the next env-free stage onward. Instead: EACH STAGE DECLARES ITS REQUIRED INPUTS; the preamble requires the UNION over the non-skipped set — never inferring from shared logic (inference is how a stage runs without env it needs and fails later, more confusingly, on a production host). Stage 8 declares SSHDOERS_REF/SSHDOERS_HOST and no .env keys. CONSERVATIVE DEFAULT, load-bearing: a stage with NO declaration requires EVERYTHING — forgetting to declare fails too-strict, never too-permissive. Rejected escape hatch, named: moving Stage 8 to its own script would reintroduce "another root thing to run" — the proliferation the King rejected on 258.

BUILDER: the mechanic (contained; engineer stays on the higher-value 262 units). ACCEPTANCE, first condition non-negotiable: (1) RUN IT — a real stage-only invocation past the preamble with no .env (throwaway ubuntu container; reaching Stage 8's own internal sshdo-absent refusal IS the pass), never an inspection of the flag; (2) prove the guard still bites — a non-skipped env-consuming stage without .env must still refuse. Then the THIRD session runs pinned at the fix commit, same provenance protocol, baseline unchanged.
---

author: foreman
created: 2026-08-27 12:58
---
PREAMBLE FIX LANDED at cb94ba35830db8d87a717ae123665e7ec527afaf (architect: LAND — host default verified correct at :1217 short-name derivation, presence-vs-truthiness implemented AND documented at the line where a future 'simplification' would reintroduce the bug; run-proven both directions per the non-negotiable condition). bash -n green in throwaway worktree.

DEFERRED REFINEMENT FILED as STATBUS-269: validate ops/<host>/ exists before using the derived name — covers container identities and mistyped SSHDOERS_HOST with one check; converts a message asserting a file exists into one saying what is missing. Not held against this unit.

THIRD SESSION NEXT (operator, root@niue): SSHDOERS_REF=cb94ba35830db8d87a717ae123665e7ec527afaf; provenance protocol unchanged — step 2 baseline f8b669402e9c01295de29e30aa676fa65f6ec2f65cd3b62abe314f75aa9ea364, post-install entry-line diff must be empty, step 6 success = live hash equals repo copy's hash at the pin commit.
---

author: foreman
created: 2026-08-27 13:00
---
THIRD SESSION SUCCEEDED END TO END (2026-08-27 ~13:00Z, operator, root@niue): provenance check passed (live still at baseline f8b66940…), stage ran clean past the fixed preamble, sshdo's parser validated syntax OK, the displayed diff was comment-only (the ruled delta, entries untouched), mode preserved root:root 644, all EIGHT stage verifications green, /etc/sshdoers.sha256 published world-readable. ENTRIES-IDENTICAL proof: empty comment-stripped diff of backup vs new live.

CONVERGENCE VERIFIED INDEPENDENTLY BY THE FOREMAN: live hash = published hash = repo copy's hash at cb94ba358 = 547ada75c16fd941c4859bf08122fb9ec4a4987d3492edcd8c513b9b9b0dca3e. Preflight check 16 is now satisfiable — the next cut's drift gate compares these same values. The "requires reboot to finalize" line is the script's generic full-provisioning closer; Stage 8 alone needs none (sshdo opens the file per-invocation, no daemon caches it).

STEP 7 (door proof): dev's entry proven through the REAL CI door by dispatching deploy-to-dev (the poke traverses sshdo against the NEW live file); demo's entry proves itself at its next 04:23Z scheduled trigger. HONESTY NOTE: the REFUSED direction (ls / must be denied) is not re-proven post-install from here — no CI key outside GitHub secrets; mitigated by the ENTRIES-IDENTICAL proof (the enforcing lines are byte-identical to the file that was refusing correctly all along) and recorded rather than waved green.

THE TICKET'S CORE IS ACHIEVED: the live inbound-command policy is provably the reviewed one — /etc/sshdoers ships as code, drift fails the release cut, and allowlist changes are now a reviewed commit + stage re-run. REMAINING: the deploy-to-dev marked-block swap (apply-latest → upgrade apply "$SHA") + STATBUS-258's one-line allowlist entry — unblocked NOW per the King's execution order; architect to spec, then build.
---

author: architect (pinned by foreman)
created: 2026-08-27 13:05
---
ENDGAME SPEC (2026-08-27). Allowlist line: `statbus_dev: cd ~/statbus && ./sb upgrade apply` + 40-# hash run — CLONED from line 84, never typed (a 39-# pattern refuses every dispatch while looking like a missing grant), count verified mechanically; the 40-# pattern also makes short-SHA addressing impossible at the door. Yaml swap: `upgrade apply $SHA` (full 40-hex), preserving 261's errexit capture shape. THE GUARD STAYS — its reason INVERTS: post-swap a mismatch means the apply verb installed something other than its argument (mechanism broken), so its message is amended; deleting an invariant check because the invariant currently holds is how invariants rot. SEQUENCING: (a) allowlist line LIVE on niue (reviewed commit + stage re-run) BEFORE the yaml swap lands; (b) dev's apply-latest grant COEXISTS through the transition — a revert must not strand the canary; removal is a later reviewed commit. Demo's apply-latest is permanent (correct verb for a channel-following box). Builder: mechanic. Acceptance: RUN IT — a real deploy-to-dev dispatch through the new entry. Step-7 door proof for the current state already GREEN (run 33074668847).
---
<!-- COMMENTS:END -->
