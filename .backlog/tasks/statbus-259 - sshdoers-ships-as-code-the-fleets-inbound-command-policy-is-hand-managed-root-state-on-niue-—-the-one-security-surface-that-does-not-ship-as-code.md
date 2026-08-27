---
id: STATBUS-259
title: >-
  sshdoers-ships-as-code: the fleet's inbound-command policy is hand-managed
  root state on niue — the one security surface that does not ship as code
status: In Progress
assignee:
  - engineer
created_date: '2026-08-19 20:06'
updated_date: '2026-08-27 12:33'
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
<!-- COMMENTS:END -->
