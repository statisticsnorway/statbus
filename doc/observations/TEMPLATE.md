# Norway Observation Card — <CANDIDATE_TAG>

STATBUS-247. Promoted from the King-approved draft (`.backlog/docs/doc-035`).

**HOW TO USE THIS TEMPLATE:** copy this file to `doc/observations/<CANDIDATE_TAG>.md`
(the exact release-candidate tag, e.g. `v2026.08.0-rc.17`) and replace every
`<CANDIDATE_TAG>` placeholder below with that same tag before you start. The
stable-release gate (`checkOneCanary`, `cli/cmd/release_canary.go`) refuses to
treat Norway's canary as complete unless a card exists at that exact path AND
names the candidate in its body — a card copied from the previous candidate
and never updated is the realistic mistake this check guards against, not
fraud. Filling in the tag first is not busywork; it is the one thing that
makes this card provably about THIS candidate rather than the last one.

**Candidate:** <CANDIDATE_TAG>
**Date:**

## What this card is for

You are installing a release candidate on Norway by hand. **The software is not the thing being tested — the experience is.** Automated checks already proved the candidate installs; only a person can notice that a message is confusing, that a step took twenty minutes with no sign of life, or that what the screen said did not match what happened.

**A deviation is a ticket, not your mistake.** If something is unclear, slow, or wrong, that is the finding — do not work around it silently and do not tidy it up in your head. Working around a bad message is the one thing that destroys this card's entire value, because the next person to meet that message will be a statistical office with no one to ask.

**Taking your time is correct.** There is no clock on this. The gate will wait, and it will say it is waiting for you.

## Before you start

- [ ] The candidate is a release candidate tag (never a bare commit): **<CANDIDATE_TAG>**.
- [ ] Smoke and the fleets are green. You should have been given their run links — **if you were not, that is a deviation: record it.** The gate is required to name what it is waiting for and where to look.
- [ ] Write down the candidate tag and today's date. You will need both when filing anything.

## Step 1 — The offer

The box should already know about the candidate on its own. Nobody pushes anything to Norway.

Run: `./sb upgrade list`

**Expect:** a row for the candidate tag with status **`available`**, and a discovered date (cli/cmd/upgrade.go:97-110 — the status column renders `available` when a candidate has been discovered but not scheduled).

- If the candidate is **absent**: the box has not discovered it yet. `./sb upgrade check` asks now rather than waiting for the next poll. **Record how long after the tag you looked** — a long gap is worth knowing about.
- If the status is anything other than `available`: stop and record it.

*What I actually saw:*

## Step 2 — The decision

This is the step that only exists because a person is here.

Run: `./sb upgrade schedule <CANDIDATE_TAG>`

**Expect:** the command to accept the tag and hand off to the upgrade service, which the database trigger notifies (cli/cmd/upgrade.go:121-123).

Before you press return, answer these — they are the real test:

- Did anything tell you **what you are about to do**, in words you would be comfortable seeing on a stranger's system?
- Did anything tell you **what happens if it fails**? (A backup is taken and the previous version is restored automatically — did the software say so, or do you only know because you were told?)
- Did anything tell you **how long this will take**, or **where to watch**?

**If the answer to any of these is no, that is the finding.** It is the most likely thing this card will catch, and it is exactly the gap an unattended statistical office falls into.

*What I actually saw:*

## Step 3 — Watching it run

Watch: `sudo journalctl -u statbus-upgrade@statbus_no -f` (doc/upgrades.md:104)

**Expect** to see, in order: the service picking up the scheduled row and naming the version (`Executing upgrade to <version>...`, service.go:5302), then progress through its steps, then either `Upgrade to <version> completed successfully` (service.go:6885) or `Upgrade to <version> failed: …` (service.go:5308).

The questions that matter here:

- Was there ever a stretch where **nothing was printed for long enough that you wondered whether it had hung**? Write down how long. "It was fine, I just waited" is a finding if you had to decide it was fine.
- Could you tell **which step of how many** you were on, or only that something was happening?
- If you had walked away and come back, could you tell **whether it was still working or had stopped**?

*What I actually saw:*

## Step 4 — Where you land

**Expect:** `./sb upgrade list` shows the candidate as **`completed`**, and the running system is on the new version and serving.

- Did anything **tell you it was finished**, or did you have to go and check?
- Is the site up, and did you have to be told how to confirm that?
- If you had to explain to a colleague what state this box is now in, could you — using only what the software showed you?

*What I actually saw:*

## Step 5 — If it fails

A failure is a **valid outcome of this exercise**, not a wasted afternoon. The recovery machinery is supposed to return the box to the previous version by itself.

- Did the failure message tell you **what state the system is in now**?
- Did it tell you **whether your data was affected**?
- Did it tell you **what to do next**, in a step you could actually perform?
- Did it send you to support for something you could have fixed yourself? **That one is always a ticket** (this is the STATBUS-240 class).

*What I actually saw:*

## Finishing

1. File a ticket for every deviation. Quote what you saw, verbatim, and what you expected instead.
2. **Promotion does not proceed until those tickets are triaged** (STATBUS-247 AC#7).
3. If nothing deviated, say so explicitly and record the candidate tag and the date — "nothing to report" is a result, and it is the one that lets the release move.

## A note on what this card cannot do

This card checks the path a candidate takes on a healthy, well-known box, run by someone who built the software. A real operator has none of that context. So when a message seems fine to you **only because you already know what it means**, that is a deviation too — and it is the hardest one to notice, which is why it is written down here at the end where you will read it after seeing everything.
