#!/bin/bash
# upgrade-target.sh — construct the controlled-B branch pair for upgrade-arc tests.
#
# This is the single source of truth for building the synthetic B/C branch pairs used
# by both the CI arc harness (.github/workflows/upgrade-arc-harness.yaml) and the
# install-recovery scenario harness (slices 3+). Extracted from the inline construction
# in upgrade-arc-harness.yaml:120-252 (STATBUS-118, behavior-preserving refactor).
#
# EXPOSES
#   construct_upgrade_target BASE_SHA SPEC
#
#   Branches off BASE_SHA, writes the fixed synthetic migration(s), signs the commits,
#   and pushes both branches to origin (unless ARC_NO_PUSH=1).
#
# INPUTS (env vars the caller sets before calling)
#   ARC_SIGNING_KEY       Path to an existing ed25519 private key for signing B+C
#                         commits. If unset, the FIRST call auto-generates an ephemeral
#                         key at /tmp/arc_signer_$$ and exports ARC_SIGNING_KEY so the
#                         SECOND call inherits it → one key / one ARC_PUBKEY guaranteed
#                         by the code. Callers do NOT need to run ssh-keygen or export
#                         ARC_SIGNING_KEY themselves.
#   RUN_ID                Unique suffix for the test/* branch names. CI sets this to
#                         github.run_id; local runs default to a date+time stamp.
#   ARC_NO_PUSH=1         Skip the 'git push -f origin' step. Set this for local unit
#                         tests that must not push test branches to the real origin.
#                         CI must NOT set this (the push is required for image-wait +
#                         run-arc). Default: push is performed.
#
# OUTPUTS (bash vars set in the caller's scope after the call; no $GITHUB_OUTPUT touch)
#   B_BRANCH / B_FULL / B_SHORT  — B (defect) branch name + full/short SHAs.
#   C_BRANCH / C_FULL / C_SHORT  — C (fix) branch name + full/short SHAs.
#   V_VERSION / V_VERSION_2      — synthetic migration version numbers (14-digit ts+1/+2
#                                  from BASE_SHA's latest migration; shared across both
#                                  lineages — the same value is produced by both calls
#                                  for a given BASE_SHA, since it is deterministic).
#   ARC_PUBKEY                   — "<type> <key>" (2 fields, no trailing comment field)
#                                  for the signing key. Exported by the library so
#                                  downstream subshells see it without re-deriving.
#
# The caller (the CI step or a scenario harness) is responsible for:
#   - writing outputs to $GITHUB_OUTPUT (CI)
#   - trusting ARC_PUBKEY via arc-helpers.sh::trust_arc_signer (post-install)
#
# SPEC ∈ {working, failing, oom}
#   working  — B: genuine migration V that SUCCEEDS (CREATE TABLE upgrade_arc_fixture +
#               upgrade_arc_fixture_2); C: B with V amended in place (prepends a comment
#               → new bytes, same effect; triggers STATBUS-102 channel-bless re-stamp).
#   failing  — B: deterministic V that RAISES EXCEPTION (→ autonomous rollback); C: V
#               replaced with the working migration (applies fresh after rollback).
#   oom      — B: a real V (`SELECT pg_sleep(60);` + a fixture table, bare statement —
#               NOT wrapped in a DO $$ block, so it shows up as pg_stat_activity's own
#               active query) that the postswap-migration-oom arc SIGKILLs via its db
#               container mid-sleep (STATBUS-096, reproducing the OS OOM-killer's effect
#               deterministically). SINGLE-PHASE: no C is built (C is left identical to
#               B, same commit, unused) — this arc has no "fixed" phase. Terminal is
#               completed, NOT rolled_back: Run()'s own boot unconditionally revives the
#               db (EnsureDBUp) before any recovery branch runs, so the killed migration
#               always gets a live DB back within the same crash-resume pass and
#               completes forward on its re-attempt.
#
# Migration content is NON-IDEMPOTENT by design (no IF NOT EXISTS): a re-apply
# CONFLICTS ('already exists') — load-bearing for the after-commit arcs' deterministic
# rollback (doc-017 §3). The arc asserts on the TABLE name, not the filename.
#
# Behavior-preserving: byte-identical to upgrade-arc-harness.yaml:120-252.
# Branch names, migration file names, migration SQL content, signing, and push
# are all identical. Proof: the arc-harness CI run is its own oracle (STATBUS-118 DoD).

# _ut_write_working_v V_UP V_DOWN V2_UP V2_DOWN
# Write the WORKING fixture migration files (migration 1 + migration 2).
# NON-IDEMPOTENT: CREATE TABLE without IF NOT EXISTS (doc-017 §3).
# Verbatim content from upgrade-arc-harness.yaml:150-177.
_ut_write_working_v() {
    local v_up="$1" v_down="$2" v2_up="$3" v2_down="$4"
    # Migration 1 — upgrade_arc_fixture.
    {
      echo "-- Upgrade-arc fixture migration 1 (STATBUS-071). Observable + reversible;"
      echo "-- the arc asserts public.upgrade_arc_fixture exists with its row."
      echo "CREATE TABLE public.upgrade_arc_fixture ("
      echo "    id integer PRIMARY KEY,"
      echo "    note text NOT NULL"
      echo ");"
      echo "INSERT INTO public.upgrade_arc_fixture (id, note) VALUES (1, 'arc');"
    } > "$v_up"
    echo "DROP TABLE IF EXISTS public.upgrade_arc_fixture;" > "$v_down"
    # Migration 2 — upgrade_arc_fixture_2 (separate table; existing arcs unaffected).
    {
      echo "-- Upgrade-arc fixture migration 2 (STATBUS-071 5d / doc-017 §5)."
      echo "CREATE TABLE public.upgrade_arc_fixture_2 ("
      echo "    id integer PRIMARY KEY,"
      echo "    note text NOT NULL"
      echo ");"
      echo "INSERT INTO public.upgrade_arc_fixture_2 (id, note) VALUES (1, 'arc2');"
    } > "$v2_up"
    echo "DROP TABLE IF EXISTS public.upgrade_arc_fixture_2;" > "$v2_down"
}

# _ut_write_failing_v V_UP V_DOWN
# Write the FAILING fixture migration (RAISE EXCEPTION → autonomous rollback).
# Verbatim content from upgrade-arc-harness.yaml:181-189.
_ut_write_failing_v() {
    local v_up="$1" v_down="$2"
    {
      echo "-- Upgrade-arc FAILING fixture (STATBUS-071 d): deterministic failure → rollback."
      echo "DO \$\$ BEGIN"
      echo "  RAISE EXCEPTION 'upgrade-arc failing fixture: deliberate migration failure (STATBUS-071 d)';"
      echo "END \$\$;"
    } > "$v_up"
    echo "SELECT 1;  -- V_fail commits nothing; rollback is the volume-restore" > "$v_down"
}

# _ut_write_oom_v V_UP V_DOWN
# Write the OOM fixture migration (STATBUS-096): a real statement the
# postswap-migration-oom arc SIGKILLs mid-run via its db container, to
# reproduce the OS OOM-killer's effect on Postgres deterministically.
# Deliberately a BARE top-level SELECT pg_sleep — NOT wrapped in a DO $$
# BEGIN...END $$ block (construction ruling, STATBUS-096 comment #1): a DO
# block would not appear as pg_stat_activity.query the same way, and the
# arc's midpoint poll matches the literal `SELECT pg_sleep(60)%` text.
#
# 60s, NOT 3600s (architect reshape, 2026-07-07, confirmed against shipped
# code): Run()'s own boot ALWAYS runs EnsureDBUp (service.go:1808,
# unconditional on every pass, before any recovery branch) — so the killed
# db is guaranteed to come back within the SAME boot that discovers the
# service-held flag, and the re-attempted migrate always finds a live DB.
# There is no code path where the box waits out a long sleep a second time;
# a 3600s sleep would just re-run for another hour on every revival,
# guaranteed-stall-red, derivable without a run. 60s keeps the arc's own
# wall-clock bounded while still giving the midpoint poll below a comfortable
# window to observe the ACTIVE query before the kill.
#
# The migration ALSO creates an observable fixture table (mirrors
# _ut_write_working_v's own pattern) so the arc can assert the migration
# genuinely completed on its post-revival re-run, not merely that
# db.migration's ledger advanced.
_ut_write_oom_v() {
    local v_up="$1" v_down="$2"
    {
      echo "-- Upgrade-arc OOM fixture (STATBUS-096): a real migration the arc kills"
      echo "-- mid-sleep (docker compose kill -s SIGKILL db) to reproduce the effect"
      echo "-- of an OS OOM-kill of Postgres. Bare statement, no BEGIN/END — must"
      echo "-- appear as pg_stat_activity's own active query for the arc's midpoint poll."
      echo "-- ORDERING IS LOAD-BEARING: sleep BEFORE the DDL — no BEGIN/END means psql"
      echo "-- autocommits per statement, so a committed-early table would turn the"
      echo "-- revival's re-run into a relation-exists failure → rolled_back, the exact"
      echo "-- opposite terminal. Sleep-first commits nothing on a mid-sleep kill."
      echo "SELECT pg_sleep(60);"
      echo "CREATE TABLE public.upgrade_arc_oom_fixture ("
      echo "    id integer PRIMARY KEY,"
      echo "    note text NOT NULL"
      echo ");"
      echo "INSERT INTO public.upgrade_arc_oom_fixture (id, note) VALUES (1, 'oom');"
    } > "$v_up"
    echo "DROP TABLE IF EXISTS public.upgrade_arc_oom_fixture;" > "$v_down"
}

# construct_upgrade_target BASE_SHA SPEC
# See module header above for full documentation.
construct_upgrade_target() {
    local _base_sha="$1" _spec="$2"

    # ── signing key ──────────────────────────────────────────────────────────
    # If ARC_SIGNING_KEY is unset, generate an ephemeral key and expose it so a
    # subsequent call for the other lineage reuses the same key (one ARC_PUBKEY).
    # ONE code path: generate+export ONLY if unset; second call inherits the first
    # call's key → ONE key / ONE ARC_PUBKEY guaranteed by the code, not the caller.
    # Caller can also pre-set ARC_SIGNING_KEY to a persisted key (e.g. for replay).
    [ -z "${ARC_SIGNING_KEY:-}" ] && {
        local _key_path="/tmp/arc_signer_$$"
        ssh-keygen -t ed25519 -N '' -C 'upgrade-arc-ephemeral' -f "$_key_path" >/dev/null 2>&1
        export ARC_SIGNING_KEY="$_key_path"
    }
    git config gpg.format ssh
    git config user.signingkey "$ARC_SIGNING_KEY"
    git config user.name  "statbus-upgrade-arc[bot]"
    git config user.email "statbus-upgrade-arc@users.noreply.github.com"
    # ARC_PUBKEY: "<type> <key>" (2 fields — no trailing comment; allowed_signers
    # takes "<principal> <type> <key>" and a comment field is not standard there).
    # Exported so downstream subshells (e.g. scenario harnesses) see it without
    # needing to re-derive it.
    export ARC_PUBKEY="$(cut -d' ' -f1-2 "${ARC_SIGNING_KEY}.pub")"

    # ── run_id for branch naming ─────────────────────────────────────────────
    local _run_id="${RUN_ID:-$(date +%Y%m%d%H%M%S)}"

    # ── V versions (deterministic from BASE_SHA's migrations) ────────────────
    # Verbatim from upgrade-arc-harness.yaml:129-141.
    git checkout -q "$_base_sha"
    local _latest
    _latest="$(printf '%s\n' migrations/*.up.sql | sed -E 's#.*/([0-9]{14})_.*#\1#' | sort -n | tail -1)"
    V_VERSION="$((_latest + 1))"
    V_VERSION_2="$((_latest + 2))"
    local _v_up="migrations/${V_VERSION}_upgrade_arc.up.sql"
    local _v_down="migrations/${V_VERSION}_upgrade_arc.down.sql"
    local _v2_up="migrations/${V_VERSION_2}_upgrade_arc_2.up.sql"
    local _v2_down="migrations/${V_VERSION_2}_upgrade_arc_2.down.sql"
    echo "── construct_upgrade_target: spec=${_spec} base=${_base_sha:0:8} V=${V_VERSION} V2=${V_VERSION_2} ──"

    # ── branch names (verbatim pattern from upgrade-arc-harness.yaml:201-202) ─
    local _b_branch="test/upgrade-arc-${_spec}-migration-${_run_id}"
    local _c_branch="test/upgrade-arc-${_spec}-fixed-migration-${_run_id}"
    echo "── building ${_spec} pair: B=${_b_branch} C=${_c_branch} ──"

    # ── build B ──────────────────────────────────────────────────────────────
    git checkout -B "$_b_branch" "$_base_sha"
    case "$_spec" in
        working) _ut_write_working_v "$_v_up" "$_v_down" "$_v2_up" "$_v2_down" ;;
        failing) _ut_write_failing_v "$_v_up" "$_v_down" ;;
        oom)     _ut_write_oom_v "$_v_up" "$_v_down" ;;
        *) echo "construct_upgrade_target: unknown SPEC '${_spec}' (expected: working|failing|oom)" >&2; return 1 ;;
    esac
    git add migrations/
    # The synthetic upgrade-arc fixture migrations are exempted from the doc/db
    # pairing pre-commit hook by a NAMED in-guard rule (.githooks/pre-commit,
    # STATBUS-118 fixture exemption) — so NO call-site --no-verify is needed here.
    # (CI runners have no hooks installed regardless; these branches never merge.)
    git commit -S -q -m "test(upgrade-arc): ${_spec} migration V (B)"
    local _b_short _b_full
    _b_short="$(git rev-parse --short=8 HEAD)"
    _b_full="$(git rev-parse HEAD)"

    # ── build C ──────────────────────────────────────────────────────────────
    git checkout -B "$_c_branch" "$_b_branch"
    case "$_spec" in
        working)
            # C amends V in place: prepend a comment → new bytes, same semantic effect.
            # Triggers STATBUS-102 channel-bless re-stamp on a release-channel box.
            # Verbatim from upgrade-arc-harness.yaml:214-220.
            local _tmp_v
            _tmp_v="$(mktemp)"
            { echo "-- amended in place (STATBUS-102 channel-bless re-stamp; result-preserving)"; cat "$_v_up"; } > "$_tmp_v"
            mv "$_tmp_v" "$_v_up"
            git add migrations/
            git commit -S -q -m "test(upgrade-arc): ${_spec} amend V in place (C)"
            ;;
        failing)
            # C replaces V_fail with the working migration so it applies fresh after rollback.
            # Verbatim from upgrade-arc-harness.yaml:221-224.
            _ut_write_working_v "$_v_up" "$_v_down" "$_v2_up" "$_v2_down"
            git add migrations/
            git commit -S -q -m "test(upgrade-arc): ${_spec} fix V in place (C, applies fresh)"
            ;;
        oom)
            # No "fixed" phase for the OOM arc: it is single-phase (A→B only,
            # terminal is rolled_back — there is nothing to apply afterward).
            # Deliberately NO commit here: C stays identical to B (same
            # commit, different branch name). construct_upgrade_target's
            # caller-scope contract still produces a C_BRANCH/C_FULL output
            # for uniformity across specs; the oom arc's own script simply
            # never references them (it declares only BASE_SHA/B_FULL/B_BRANCH
            # as required, mirroring rollback-kill-arc.sh's own B-only shape).
            ;;
    esac
    local _c_short _c_full
    _c_short="$(git rev-parse --short=8 HEAD)"
    _c_full="$(git rev-parse HEAD)"

    # ── push (unless ARC_NO_PUSH=1) ──────────────────────────────────────────
    if [ "${ARC_NO_PUSH:-0}" != "1" ]; then
        git push -f origin "$_b_branch" "$_c_branch"
    else
        # Loud on skip (architect Q2 refinement): an accidental ARC_NO_PUSH in CI
        # silently produces branches that exist only locally — the remote VM's git
        # fetch will fail opaquely. Make the omission unmissable in the log.
        echo "WARNING: push SKIPPED (ARC_NO_PUSH=1): ${_b_branch} and ${_c_branch}" \
             "exist locally ONLY — NOT fetchable by a remote VM." >&2
        echo "  Set ARC_NO_PUSH=0 or unset it for a real CI/VM run." >&2
    fi

    # ── set caller-scope vars (Q3=B: CI-agnostic, no $GITHUB_OUTPUT touch) ──
    B_BRANCH="$_b_branch"
    B_FULL="$_b_full"
    B_SHORT="$_b_short"
    C_BRANCH="$_c_branch"
    C_FULL="$_c_full"
    C_SHORT="$_c_short"
    # V_VERSION and V_VERSION_2 already set above.
    # ARC_PUBKEY already set above.

    echo "── ${_spec}: B=${_b_branch} (${_b_short}) C=${_c_branch} (${_c_short}) ──"
}
