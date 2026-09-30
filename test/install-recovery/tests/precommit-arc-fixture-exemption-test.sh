#!/usr/bin/env bash
# Offline regression test (STATBUS-425 M3b): the pre-commit hook's
# upgrade-arc fixture exemption (STATBUS-118) must cover every V_N the
# fixture family (construct_upgrade_target, test/install-recovery/lib/
# upgrade-target.sh) actually generates, not just V1/V2. Found live: a real
# local `git commit` inside a healthpark/crollback lineage build was
# REJECTED by this hook because the original regex's `(_2)?` suffix never
# covered `_upgrade_arc_3` (healthpark's fix migration / crollback's failing
# C migration) — CI never caught this because its own checkout has no local
# hooks installed (upgrade-target.sh notes this explicitly), so the gap was
# latent until run-arcs.sh's real local construct phase hit it.
#
# Runs the REAL hook script (not a reimplementation) against a real git repo
# and a real staged commit, so a future edit that narrows the regex again
# fails this test with the hook's own exact rejection output, not a
# description of what should happen.
set -euo pipefail
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/statbus-precommit-arc-fixture.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO/migrations" "$REPO/.githooks"
cp "$ROOT/.githooks/pre-commit" "$REPO/.githooks/pre-commit"
chmod +x "$REPO/.githooks/pre-commit"
git -C "$REPO" init -q
git -C "$REPO" config user.name 'Offline harness selftest'
git -C "$REPO" config user.email 'selftest@example.invalid'
git -C "$REPO" config core.hooksPath .githooks
git -C "$REPO" add .githooks
git -C "$REPO" commit -qm 'seed hooks'

# Every V_N construct_upgrade_target actually writes, across every lineage
# (upgrade-target.sh: _v_up/_v_down = V1 always; _v2_up/_v2_down = V2 for
# working/healthpark/crollback; _v3_up/_v3_down = V3 for healthpark's fix
# and crollback's C) must be exempt — not just V1 and V2.
for suffix in upgrade_arc upgrade_arc_2 upgrade_arc_3 upgrade_arc_4; do
    printf 'BEGIN; SELECT 1; COMMIT;\n' > "$REPO/migrations/20990101000000_${suffix}.up.sql"
    printf 'BEGIN; SELECT 1; COMMIT;\n' > "$REPO/migrations/20990101000000_${suffix}.down.sql"
    git -C "$REPO" add "migrations/20990101000000_${suffix}.up.sql" "migrations/20990101000000_${suffix}.down.sql"
    if ! git -C "$REPO" commit -qm "test(upgrade-arc): fixture ${suffix}" 2>"$TMP/commit-${suffix}.err"; then
        echo "FAIL: fixture migration '${suffix}' was rejected by the pre-commit hook (should be exempt)" >&2
        cat "$TMP/commit-${suffix}.err" >&2
        exit 1
    fi
done
echo "PASS: every upgrade-arc fixture migration suffix (V1..V4) is exempt from doc/db pairing"

# A REAL (non-fixture) migration must still be rejected without a paired
# doc/db/ regen — the exemption must never widen far enough to swallow this.
printf 'CREATE OR REPLACE FUNCTION public.selftest_fn() RETURNS void AS $$ BEGIN END; $$ LANGUAGE plpgsql;\n' > "$REPO/migrations/20990101000001_real_schema_change.up.sql"
printf 'DROP FUNCTION public.selftest_fn();\n' > "$REPO/migrations/20990101000001_real_schema_change.down.sql"
git -C "$REPO" add "migrations/20990101000001_real_schema_change.up.sql" "migrations/20990101000001_real_schema_change.down.sql"
if git -C "$REPO" commit -qm 'a real schema migration with no doc/db regen' 2>"$TMP/real.err"; then
    echo "FAIL: a real (non-fixture) migration committed without a paired doc/db/ regen — the exemption has widened too far" >&2
    exit 1
fi
grep -q 'COMMIT REJECTED' "$TMP/real.err" || { echo 'FAIL: unexpected rejection reason for a real migration' >&2; cat "$TMP/real.err" >&2; exit 1; }
echo "PASS: a real (non-fixture) migration without a doc/db regen is still rejected"

# A mixed commit (one real migration + one fixture migration) must still be
# rejected — the ANY-fixture-present branch must not exempt a real change
# riding alongside a fixture in the same commit.
printf 'CREATE OR REPLACE FUNCTION public.selftest_fn2() RETURNS void AS $$ BEGIN END; $$ LANGUAGE plpgsql;\n' > "$REPO/migrations/20990101000002_real_and_fixture_mixed.up.sql"
printf 'DROP FUNCTION public.selftest_fn2();\n' > "$REPO/migrations/20990101000002_real_and_fixture_mixed.down.sql"
printf 'BEGIN; SELECT 1; COMMIT;\n' > "$REPO/migrations/20990101000002_upgrade_arc.up.sql"
printf 'BEGIN; SELECT 1; COMMIT;\n' > "$REPO/migrations/20990101000002_upgrade_arc.down.sql"
git -C "$REPO" add migrations/
if git -C "$REPO" commit -qm 'mixed real + fixture in one commit' 2>"$TMP/mixed.err"; then
    echo "FAIL: a mixed real+fixture commit was accepted without a doc/db regen" >&2
    exit 1
fi
echo "PASS: a mixed real+fixture commit is still rejected without a doc/db regen"

echo "PASS: pre-commit's upgrade-arc fixture exemption covers V1..V4, never swallows real migrations"
