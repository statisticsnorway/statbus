# The only way to know if install and upgrade work is to run them

This is the most important thing to understand before you touch install, upgrade,
or recovery. Read it once; it governs everything in this area.

## The rule

You cannot tell whether a change to install, upgrade, or recovery works by reading
the code or reasoning about it. The problem is too hard. The only way to know is to
run it for real and look at what happened.

"Run it for real" means exactly this, and there is no shortcut:

1. Commit your change.
2. Push to `master`.
3. CI builds a Docker image for that exact commit.
4. The install-recovery tests pull that image onto a fresh VM and run a real
   install or upgrade.
5. You read the result.
6. You almost always learn something you could not have predicted — so you change
   the code and go around again.

That loop — **commit → push → build → run → observe → iterate** — is the whole job.

## Why these tests are not like the others

Every other test, you can run *before* you push:

- the SQL tests (`pg_regress`),
- the Go tests (`go test`),
- the integration tests.

Run them locally, get your answer, then push. Install and upgrade are different.
They need the built per-commit image and a real machine doing a real install or a
real upgrade. There is no local stand-in for "a server reboots mid-migration."

That is the entire reason CI builds an image on every push: **so we can run the
install and upgrade tests against it.** The pipeline exists for this one purpose.
There is no way to get the answer except commit → push → observe.

## What this means when you are working

- **Stalling before you run is not caution — it is zero knowledge.** A confident
  plan that has not been run is worth nothing here. It only consumed the time the
  run would have used.
- **Your uncertainty is the reason to run, not the reason to stop.** The run is the
  only thing that resolves it, and you control it (commit, push, trigger).
- **Nobody can predict the outcome** — not the author, not the reviewer, not the
  person who designed the system. Asking someone to approve "will this work?"
  before the run asks for something no one can give. The test is the only judge.
- **A decision is proven right by a green run and wrong by a red one.** When it is
  red, you read the red, pick the next direction, and drive again. That is the loop;
  there is no step where you wait at a green light for permission to proceed.

The only legitimate reasons to stop and ask a human are a genuine choice about the
*goal* (a direction or values question a result surfaces) or something destructive
in real production. "Will it work" is never one of those. That, you run.

## Why we have the tests *and* the diagrams

Because we cannot theorize reliably, we keep two things and keep them honest:

- **The tests** give ground truth — the real answer from a real run.
- **The diagrams** (`doc/diagrams/install-recovery.plantuml`,
  `upgrade-timeline.plantuml`, `upgrade-lifecycle.plantuml`) let us think clearly
  through every case, *see* that there is a test for each one, and confirm each test
  actually passes. Each failure point in a diagram carries a `TEST <scenario>` note
  naming the guarantee that scenario proves, or `NO TEST (gap)` where coverage is
  missing — so the holes are visible.

The diagram is the map; the test is the territory. The map keeps you from getting
lost in "maybe this, maybe that"; only walking the territory tells you it is really
there. Both must be clear in plain words — a test or a diagram you cannot read at a
glance cannot tell you whether you reached the goal.

## A real example (why we trust the run over the analysis)

The post-swap "convergence canary" was believed to silently mark a half-migrated
database as `completed` (silent corruption). The fix was designed end-to-end, the
analysis was confident, and the predicted result of the reproducer run was a clean
rollback (`state=rolled_back`).

The run (`27674217081`) returned `state=completed` against a database that looked
*consistent* — the migration was applied and recorded. Nobody predicted that. It
means the recovery path may already heal the database on its own, and the "bug" may
not be a bug at all. We only learned this by running it.

That is the rule, demonstrated: the run is the oracle. Drive to it.
