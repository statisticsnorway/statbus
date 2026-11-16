---
id: doc-033
title: 'The zero-scope green: one defect class, seven costumes in one day'
type: specification
created_date: '2026-08-18 10:52'
updated_date: '2026-08-18 17:26'
tags:
  - quality-gate
  - architecture
  - doctrine
---
# The zero-scope green

Architect note, 2026-08-18, amended twice the same day. Each instance carries its own ticket. **This document has itself been wrong three times — the corrections are kept rather than edited away, at the end, because they are the best evidence the class does not spare whoever names it.**

## WHAT WE RELY ON

Almost everything this project trusts is a green signal from a check: a workflow run concluded success, a release gate passed, a test suite came back clean, a linter reported no issues, a git command answered a question about history. Those signals are what let work move without a human re-reading every line. They only work if a green means the check actually looked at the thing.

## WHAT GOES WRONG

Seven times in one day, a check reported success **having examined nothing, or nothing current, or nothing complete** — and in every case the signal was indistinguishable from a real answer until a person looked closer. None was caught by tooling. All seven were caught by someone noticing.

- **A workflow run concluded SUCCESS with zero scenario jobs.** The matrix never expanded; the run was green because nothing ran. (STATBUS-215)
- **A release gate printed `✓ FULL SUITE green (0/0 arc jobs present)`.** The scenario listing came back empty, so "is every required scenario present?" was asked of an empty list and answered yes. (STATBUS-216)
- **A trigger assertion passed because a COMMENT contained the string it searched for.** The real trigger had been removed; the prose describing its removal satisfied the check. (STATBUS-224)
- **A path-matching feature would have refused every real board commit, while every test passed.** The fixtures used ASCII filenames; the actual ticket files contain em-dashes, which git quotes. The tests examined a world simpler than the one the code runs in. (STATBUS-219)
- **A linter printed `0 issues.` as its final line after failing to resolve the module** — zero issues over zero analysed packages. It exits non-zero, so a scripted gate still fails; what it misleads is the human reading the summary, which is how it was nearly missed. (STATBUS-230)
- **A test suite replayed a cached pass over files it had never re-read.** The pins asserting facts about workflow YAML and checked-in lists live outside the Go module; a cached `ok` could vouch for content that had since changed. (STATBUS-234)
- **A git command answered "this is the root commit" about a clone that could only see 67 commits.** The graph was truncated; every history question asked of it came back confidently wrong. (STATBUS-239)

## THE DETAIL

They look like seven unrelated bugs — a CI condition, a Go helper, a test assertion, a string-matching rule, a tool invocation, a build cache, a shallow clone. They are one shape:

> **A green signal produced by a check that never examined the thing it claims to have examined.**

The reason this class is so easy to ship is that every one of these checks was *correct on its own terms*. Ask "is every required job present?" of an empty set and the honest answer is yes. Search a file for a string and it is there. Replay a cached result and it is the result you cached. Ask a truncated graph for its root and it names the oldest commit it can see. Nothing lied. Each answered the question it was given — and the question had a vacuous case nobody had ruled on.

The reason it is dangerous is that the failure direction is always toward *confident*. A check that examines nothing produces a clean answer, and a clean answer reads as knowledge everywhere downstream: the reviewer, the foreman, the release gate, the operator.

## THE RULE

> **A check must report what it examined, and a zero-scope examination must be a failure rather than a pass.**

Zero jobs. Zero required arcs. Zero code lines behind a matched string. Zero realistic fixtures. Zero analysed packages. Zero fresh reads. Zero visible history. Every fix is that rule applied — a guard that fails a run selecting nothing, an empty domain made an error, a structural parse instead of a substring, a fixture shaped like production, a pinned working directory, a disabled test cache, a shallow-clone refusal.

Two habits follow, and both are cheap:

**When writing a check, ask what its answer is over an empty input.** If the answer is "pass", that is a defect, not an edge case.

**When writing a fixture, ask how it differs from production.** Every simplification is a class the test cannot see.

## WHEN THE INSTRUMENT IS THE PROBLEM

The seventh instance is the one worth studying, because it is the only one where **re-running the check could never have revealed the error**.

Our shared clone was shallow — 67 boundary commits. Asked for the root, git named the oldest commit it could see. Asked whether a May tag was an ancestor, it said no. Both answers were honest about the graph in front of them and false about the repository. From them the team constructed an entire history: a "2026-07-14 rebaseline", a discarded pre-rebaseline lineage, a release gate designed to refuse comparisons across the break, and a bullet in this document. **None of it happened.** The true root is `898d04734`; `v2026.05.5` is a genuine ancestor, 2154 commits behind master.

So the lesson beyond *verify premises at writing time* is: **verify the instrument, not only the premise.** I did verify — I ran the commands, and they answered. What I did not ask was whether the thing answering could see.

**And the anomalies were visible.** `77fa16fb2~1` failed to resolve — the textbook shape of a shallow boundary. A "root commit" whose message reads *"Update task STATBUS-071"* is absurd on its face. I saw both, noted them in passing, and moved on, because each fit a story I had already formed. That is the actual failure mode, and it is worth more here than the git mechanics: **the surprise was delivered and declined.**

Two things caught it, and both are worth keeping. CI runs a full clone, so it saw the true graph. And the check that fired was **STATBUS-233's own canary — a gate designed on the false premise, which then disproved it.** The mechanism was right even though the fact motivating it was wrong. A guard built for the wrong reason still guards.

**STATBUS-233 is therefore retracted from the list above.** It was never an instance of this class; it was a *consequence* of instance seven — a false finding manufactured by a polluted instrument. The gate itself stands: refusing to compare against a predecessor that shares no history is sound, and remains a real hazard we simply do not currently have.

## WHAT THIS DOCUMENT GOT WRONG

Three times, and each correction sharpened the rule rather than weakening it.

**The linter's exit code.** First written as "printed `0 issues.` and exited 0". It exits 7. My reproduction wrapped the command as `( … ; echo "EXIT=${PIPESTATUS[0]}" )`, so the status I read was the trailing `echo`'s; my own output showed a bare `EXIT=` line saying exactly that, and I read past it. I measured a compound command and reported it as the tool — inside the document naming the class. The true finding is smaller and better: a **misleading summary to a human reader**, not a silently passing gate.

**The cache exposure.** First written as though CI had been replaying stale greens. It had not: `setup-go` is configured without `cache-dependency-path` and this repository keeps `go.sum` under `cli/`, so the restore silently no-opped and CI always ran cold. The exposure was **local only** — and the no-op was **accidental**, which is why the guard still mattered: adding `cache-dependency-path` later would have looked like pure improvement and silently re-opened it. *A safety property that holds by accident is not a safety property.*

**The rebaseline.** Described above. The largest, and the one that took a full clone and a canary to disprove.

Each was found by a builder reproducing a claim instead of inheriting it. That is the review direction working upward, and it is the direction that usually does not.

## WHY THIS MATTERS

The project's quality posture is built on verify-what-ran rather than trust-what-is-claimed. This class is that doctrine's blind spot: not a check being *wrong*, but a check being *empty* — and, at its worst, an instrument that cannot see reporting as though it can. Naming it is worth more than the seven tickets, because the eighth will wear a costume none of these wore. The only thing that generalises is the question: **what did this actually examine, this time, and could it see?**
