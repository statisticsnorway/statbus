---
id: doc-033
title: 'The zero-scope green: five instances of one defect class in one day'
type: specification
created_date: '2026-08-18 10:52'
updated_date: '2026-08-18 15:10'
tags:
  - quality-gate
  - architecture
  - doctrine
---
# The zero-scope green

Architect note, 2026-08-18. Every instance below was found and verified on this date; each carries its own ticket. **One instance was overstated when this was first written and has been corrected — see the correction note at the end, which is itself the sixth instance.**

## WHAT WE RELY ON

Almost everything this project trusts is a green signal from a check: a workflow run concluded success, a release gate passed, a test suite came back clean, a linter reported no issues. Those signals are what let work move without a human re-reading every line. They only work if a green means the check actually looked at the thing.

## WHAT GOES WRONG

Five times in one day, a check reported success **having examined nothing** — and in every case the signal was indistinguishable from a real pass until a person looked closer. None was caught by tooling. All five were caught by someone noticing.

- **A workflow run concluded SUCCESS with zero scenario jobs.** The matrix never expanded; the run was green because nothing ran. (STATBUS-215)
- **A release gate printed `✓ FULL SUITE green (0/0 arc jobs present)`.** The scenario folder listing came back empty, so "is every required scenario present?" was asked of an empty list and answered yes. (STATBUS-216)
- **A trigger assertion passed because a COMMENT contained the string it searched for.** The real trigger had been removed; the prose describing its removal satisfied the check. (STATBUS-224)
- **A path-matching feature would have refused every real board commit, while every test passed.** The fixtures used ASCII filenames; the actual ticket files contain em-dashes, which git quotes. The tests examined a world simpler than the one the code runs in. (STATBUS-219)
- **A linter printed `0 issues.` as its final line after failing to resolve the module** — zero issues over zero analysed packages. It does exit non-zero (7), so a scripted gate still fails; what it misleads is the human reading the summary, which is exactly how it was nearly missed. (STATBUS-230)

## THE DETAIL

They look like five unrelated bugs — a CI condition, a Go helper, a test assertion, a string-matching rule, a tool invocation. They are one shape:

> **A green signal produced by a check that never examined the thing it claims to have examined.**

The reason this class is so easy to ship is that every one of these checks was *correct on its own terms*. Ask "is every required job present?" of an empty set and the honest answer is yes. Search a file for a string and it is there. Run the tests and they pass. Nothing lied. Each check answered the question it was given — and the question it was given had a vacuous case nobody had ruled on.

The reason it is so dangerous is that the failure direction is always toward *pass*. A check that examines nothing produces silence, and silence reads as approval everywhere downstream: the reviewer, the foreman, the release gate, the operator. Four of these five sat directly on the release path.

## THE RULE

One rule catches all five:

> **A check must report what it examined, and a zero-scope examination must be a failure rather than a pass.**

Zero jobs. Zero required arcs. Zero code lines behind a matched string. Zero realistic fixtures. Zero analysed packages. Every instance above is that rule violated in a different costume, and every fix already landed or filed is that rule applied:

- 215's `no-arcs-guard` fails a run that selected nothing.
- 216 makes an empty scenario domain an error instead of a trivially-satisfied requirement.
- 224 parses the trigger structurally so prose cannot satisfy a claim about code.
- 219 adds a fixture shaped like the real world, because a fixture simpler than production tests a world we do not ship to.
- 230 pins the working directory so the zero-scope run cannot happen, and prints the package count so a reader can see what was examined.

Two habits follow, and both are cheap:

**When writing a check, ask what its answer is over an empty input.** If the answer is "pass", that is a defect, not an edge case — decide it deliberately and usually make it fail.

**When writing a fixture, ask how it differs from production.** Every simplification is a class the test cannot see. The em-dash case is the sharpest example available: the tests were thorough, the design was right, the reviewer had ruled on the matching rule twice — and the feature would still have been inert on arrival, because the fixture filenames were tidier than the real ones.

## THE SIXTH INSTANCE, AND IT IS THIS DOCUMENT

The first version of this note said the linter "printed `0 issues.` and exited 0". It does not: it exits 7. The claim came from my own reproduction, which wrapped the command as `( golangci-lint … ; echo "EXIT=${PIPESTATUS[0]}" )` — so the status I read was the trailing `echo`'s, not the linter's, and `PIPESTATUS` was empty in that context. My own output showed a bare `EXIT=` line saying exactly that, and I read past it.

So I measured a compound command and reported it as the tool, inside the document naming the class. The mechanic found it while building the fix, by reproducing the bug rather than inheriting my description of it.

It is left here rather than quietly edited out, for three reasons. It is the most honest possible demonstration that the class does not spare the person who named it. It sharpens the rule — *what did this actually examine?* applies to one's own measurement first. And it changes the finding's substance: the linter's defect is a **misleading summary to a human reader**, not a silently passing scripted gate, which is a smaller claim and the true one.

## WHY THIS MATTERS

The project's whole quality posture is built on verify-what-ran rather than trust-what-is-claimed — that is what STATBUS-199's completeness check exists for, and what the release gates re-derive independently rather than inheriting. This class is that doctrine's blind spot: it is not about a check being *wrong*, it is about a check being *empty*. Naming it is worth more than the six tickets, because the seventh instance will not look like any of these either — it will be a new costume, and the only thing that generalises is the question **what did this actually examine?**
