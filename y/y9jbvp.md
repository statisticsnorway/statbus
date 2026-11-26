---
id: "y9jbvp"
title: "June 2026 release candidate: ship the upgrade crash fix without a buggy add-on"
state: "todo"
assignee: []
labels:
  - upgrade
  - release
  - rc.03
group: ""
rank: "000000000109"
dependencies: []
priority: high
origin: "backlog:STATBUS-550"
aliases: ["STATBUS-550"]
type: "feature"
created: "2026-06-16 08:04"
stage: "ready"
---

## Goal
Decide whether this June 2026 release step still needs anything; everything it waited on was later done another way.

## Purpose
What it was about: in June 2026 an upgrade could crash when the box's configuration had drifted (the owner's charge). That fix was ready and tested (7cc6c1b48, 09ac1f7e4). But release candidate v2026.06.0-rc.03 also carried an unfinished change, 'defer the git checkout to the recovery boot' (2f52f3b7f, bb4848dd4), which had a real bug in recovering from a failed upgrade. The question then: take that change back out and ship only the fix, raise the Hetzner server quota for the full test suite, and allow an image-cleanup fix.

## Principle
Close it if nothing is open: the task exists only to decide those three things, and each was settled by later work.

## Details
What happened since (checked 2026-11-26): the defer-checkout change was not reverted; its recovery bug was fixed properly in gfvfwe (preswap recovery refinement, STATBUS-061, done) and has shipped in every release since v2026.06.0-rc.04. The full test suite's limit was solved in 8jv43w (STATBUS-025 line, done), and the image-cleanup fix in wpz2b6 (STATBUS-057, done). Releases are now at v2026.11.6 stable. Nothing in this task remains.

## Acceptance
- [ ] ~~King ruled on revert / quota / 057~~ (not relevant: settled by later work: gfvfwe (recovery fix, shipped since v2026.06.0-rc.04), 8jv43w (test suite limit), wpz2b6 (image cleanup), rabbit, 2026-11-26)
- [ ] ~~Clean config-drift-only RC cut + 0-happy green on it~~ (not relevant: settled by later work: gfvfwe (recovery fix, shipped since v2026.06.0-rc.04), 8jv43w (test suite limit), wpz2b6 (image cleanup), rabbit, 2026-11-26)
- [ ] ~~defer-checkout/preswap-recovery work tracked in STATBUS-061 (rc.04)~~ (not relevant: settled by later work: gfvfwe (recovery fix, shipped since v2026.06.0-rc.04), 8jv43w (test suite limit), wpz2b6 (image cleanup), rabbit, 2026-11-26)
- [ ] [Owner] confirms nothing remains and the task is dropped as superseded by gfvfwe, 8jv43w and wpz2b6; recorded in Notes

## State
Config-drift upgrade-crash wedge (the King's charge) is SOLVED + validated GREEN on real VMs (0-happy run 27582053054 on the config-drift-only commit 658c34ebd; 27582686118 full stack). rc.03 was cut (tag v2026.06.0-rc.03 on d0992498a) BUT it carries the defer-checkout arc, which testing showed has real PreSwap recovery bugs (not the charge).

## RECOMMENDATION (foreman + architect, source-verified): REVERT → ship clean config-drift RC
- KEEP (the charge, validated green): 7cc6c1b48 (unconditional config-regen) + 09ac1f7e4 (image-extract procurement).
- REVERT from the shippable RC: 2f52f3b7f (defer-checkout) + bb4848dd4 (its guard). They ship a real PreSwap schema/git-mismatch bug (recovery-boot checkout before boot-migrate advances schema→target but empty-backup rollback can't undo) + the pre-existing recoveryRollback prev:=d.version (service.go:2193) tree-restore-to-target.
- f29e03a60 (install.sh edge image-extract): likely INDEPENDENT/keepable — confirm with King.
- Clean state ≈ commit 658c34ebd (already 0-happy green → no re-proving of the charge needed).
- The defer-checkout / preswap-window closure + recovery fixes are REDONE PROPERLY in STATBUS-061 (rc.04).

## 3 KING DECISIONS (pending — get these first)
1. Approve REVERT + cut clean config-drift RC (one word from King: "revert + cut clean").
2. Raise the Hetzner project quota (servers + primary IPs) → unblocks the full comprehensive suite (STATBUS-025; max-parallel:8 > quota, stopgap :3 committed 9b7588596).
3. STATBUS-057 image-cleanup GC fix — green-light (still held).

## MECHANIC (on "revert + cut clean")
git revert 2f52f3b7f + bb4848dd4 (keep f29e03a60 unless King says otherwise) → go build/vet/test → foreman reviews → push origin <sha>:master → cut clean annotated RC tag (next number) on that commit → re-confirm 0-happy (operator, 1 VM); full comprehensive once the quota is raised.


## Questions
- 2026-11-22T23:31 question 1 by hibiscus to jhf:
  This task is the rc.03 finalize step (revert defer-checkout, cut a config-drift-only RC); releases have since moved on to v2026.11.6 stable. Drop it as done by later releases, or is any of its three checks still open?
  answered 2026-11-26T22:57 by jhf:
    I agree, drop this as done


## Requests
- 2026-11-26T22:53 request 1 by jhf:
  Can you just this ticket is not clear to me it's it's too many details and not enough like why are we having this discussion what is this about what's the point of it Yeah, help me here
  resolved 2026-11-26T22:54 by rabbit:
    Rewritten in plain words. Purpose: what it was about (June 2026, an upgrade crash fix was ready but release candidate rc.03 also carried an unfinished 'defer checkout' change with a recovery bug; three decisions were asked: take it out, raise the server quota, allow an image-cleanup fix). Details: what happened since (the change stayed and its bug was fixed properly in gfvfwe, shipped since rc.04; the quota and image cleanup were solved in 8jv43w and wpz2b6). The old checks are struck; one check left: confirm it can be dropped.

## History
- 2026-11-22T23:31 todo -> todo/design (ask)
- 2026-11-26T22:53 request 1 by jhf
- 2026-11-26T22:53 request 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-26T22:53 request 1 acknowledged by rabbit
- 2026-11-26T22:54 request 1 in progress by rabbit: hug task set y9jbvp
- 2026-11-26T22:54 resolved request 1 by rabbit
- 2026-11-26T22:57 answered design, by jhf, for hibiscus (todo/design -> todo/ready):
  > This task is the rc.03 finalize step (revert defer-checkout, cut a config-drift-only RC); releases have since moved on to v2026.11.6 stable. Drop it as done by later releases, or is any of its three checks still open?
  I agree, drop this as done
- 2026-11-26T22:57 answer 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
