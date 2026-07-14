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
#   V_VERSION / V_VERSION_2 / V_VERSION_3 — synthetic migration version numbers
#                                  (14-digit ts+1/+2/+3 from BASE_SHA's latest
#                                  migration; shared across both lineages — the
#                                  same value is produced by both calls for a
#                                  given BASE_SHA, since it is deterministic).
#                                  V_VERSION_3 is healthpark-only (C's fix
#                                  migration); every other spec ignores it.
#   ARC_PUBKEY                   — "<type> <key>" (2 fields, no trailing comment field)
#                                  for the signing key. Exported by the library so
#                                  downstream subshells see it without re-deriving.
#
# The caller (the CI step or a scenario harness) is responsible for:
#   - writing outputs to $GITHUB_OUTPUT (CI)
#   - trusting ARC_PUBKEY via arc-helpers.sh::trust_arc_signer (post-install)
#
# SPEC ∈ {working, failing, oom, ceiling, healthpark, codeonly}
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
#   ceiling  — B: a real, LONG V (`SELECT pg_sleep(3600);`, bare) that OUR OWN
#               internal STATBUS_MIGRATE_UP_TIMEOUT ceiling SIGKILLs mid-sleep
#               (STATBUS-095 piece 2) — contrast oom's EXTERNAL kill: nothing
#               revives this one, so it IS a rollback story. SINGLE-PHASE like
#               oom (no C; identical-to-B, unused). Terminal is rolled_back.
#   healthpark — B: V1 (V_marker, benign fixture-table migration, always
#               succeeds) + V2 (CREATE OR REPLACE FUNCTION public.auth_status()
#               to RAISE — itself a SUCCESSFUL migration, which is what makes
#               the box genuinely AT-TARGET when the postswap-health-park-arc
#               (STATBUS-145, doc-029) parks on the health leg's functional RPC
#               probe failing past the /ready warmup). C: B + V3, a NEW migration
#               that CREATE OR REPLACEs auth_status() back to its original body
#               — NEVER an edit to V2 in place (a release-channel content_hash
#               mismatch on an already-applied version is BLESSED/re-stamped,
#               not re-run — doc-029 Rev 2). V1/V2 stay byte-identical between
#               B and C.
#   codeonly — B: NO migration at all — a single non-migration marker file, so B
#               is a distinct signed commit from A with ZERO migration delta. This
#               is the ONLY no-delta lineage: at the post-swap pre-pull disk
#               pre-check the box is genuinely AT-TARGET, so a resource failure
#               there PARKS (the un-park-to-completion arm-(ii) arc's story) — a
#               delta lineage would ROLL BACK instead (positively-Behind; run
#               29360596950). Represents a code-/app-/CLI-only release. SINGLE-PHASE
#               like oom/ceiling (no C; identical-to-B, unused) — the arc completes
#               B's own row via un-park, there is no separate fix release.
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

# _ut_write_ceiling_v V_UP V_DOWN
# Write the CEILING fixture migration (STATBUS-095 piece 2): a real,
# long-running statement OUR OWN internal STATBUS_MIGRATE_UP_TIMEOUT ceiling
# kills — contrast with the oom spec, which is killed EXTERNALLY (an
# operator/OS action) and completes forward on revival; this one is killed
# INTERNALLY (the product's own ceiling) and is a ROLLBACK story, because
# nothing external ever revives anything — the ceiling's own rollback IS the
# terminal. Bare top-level statement (no BEGIN/END), matching the oom spec's
# own reasoning: must show up as pg_stat_activity's own active query.
# Deliberately LONG (3600s, unlike oom's 60s): with the ceiling armed via a
# short STATBUS_MIGRATE_UP_TIMEOUT (the arc's dropin sets 20s), the migration
# is SIGKILLed by the ceiling long before 3600s could ever elapse — a long
# sleep here does not cost the arc any wall-clock (contrast oom, where NO
# internal ceiling exists and a revived box would actually wait out the
# sleep, which is why oom is short).
_ut_write_ceiling_v() {
    local v_up="$1" v_down="$2"
    {
      echo "-- Upgrade-arc CEILING fixture (STATBUS-095 piece 2): a real migration our"
      echo "-- own STATBUS_MIGRATE_UP_TIMEOUT ceiling kills mid-sleep (SIGKILL at the"
      echo "-- ctx deadline, service.go's applyPostSwap migrate call). Bare statement,"
      echo "-- no BEGIN/END — must appear as pg_stat_activity's own active query."
      echo "SELECT pg_sleep(3600);"
    } > "$v_up"
    echo "SELECT 1;  -- V_sleep commits nothing when killed; rollback is the volume-restore" > "$v_down"
}

# _ut_write_healthpark_v1 V_UP V_DOWN
# Write V1 (V_marker) for the healthpark spec (STATBUS-145 postswap-health-
# park-arc, doc-029 Rev 2): a benign real migration, fixture-table pattern —
# proves the delta genuinely applies (anti-vacuity), same shape as the
# working/oom fixtures. This migration ALWAYS succeeds; V2 (below) is the one
# that breaks health.
_ut_write_healthpark_v1() {
    local v_up="$1" v_down="$2"
    {
      echo "-- Upgrade-arc healthpark fixture V1 / V_marker (STATBUS-145 doc-029)."
      echo "-- Benign, always succeeds — proves the delta genuinely applied before"
      echo "-- V2 (below) breaks health past warmup."
      echo "CREATE TABLE public.upgrade_arc_healthpark_fixture ("
      echo "    id integer PRIMARY KEY,"
      echo "    note text NOT NULL"
      echo ");"
      echo "INSERT INTO public.upgrade_arc_healthpark_fixture (id, note) VALUES (1, 'healthpark');"
    } > "$v_up"
    echo "DROP TABLE IF EXISTS public.upgrade_arc_healthpark_fixture;" > "$v_down"
}

# _ut_write_healthpark_break_v2 V_UP V_DOWN
# Write V2 for the healthpark spec: the deterministic health break.
# CREATE OR REPLACE FUNCTION public.auth_status() to RAISE — this migration
# itself SUCCEEDS (a broken function is still a successful DDL statement),
# which is exactly what makes the box genuinely AT-TARGET when the upgrade's
# health leg parks (doc-029 Rev 2: "V2 SUCCEEDS as a migration ... which is
# what makes the box genuinely AT-TARGET when the park fires").
#
# WHY THIS BREAKS HEALTH BUT NOT /ready (doc-029 Rev 2, mechanic trace,
# cli/internal/upgrade/exec.go): the post-swap health leg first waits for
# PostgREST's admin /ready endpoint (waitForRestReady — schema cache +
# connection pool loaded; does NOT execute any function body, so it stays
# green), THEN POSTs to /rpc/auth_status (healthURL, a DIFFERENT bind
# address: REST_BIND_ADDRESS, not REST_ADMIN_BIND_ADDRESS). Once RAISE
# EXCEPTION replaces the body, every call to that RPC 500s — the functional
# probe fails deterministically "past warmup", exactly the reason string
# parkForDeterministicFailure emits (service.go:5578).
#
# Signature preserved EXACTLY from the shipped function (doc/db/function/
# public_auth_status().md) — RETURNS auth.auth_response, SECURITY DEFINER,
# SET search_path — so PostgREST's schema-cache introspection (what /ready
# actually checks) sees no change at all; only the BODY differs.
#
# NEVER "fixed" by editing this file in place — see V3 below and the Rev 2
# note at the top of doc-029: a release-channel content_hash mismatch on an
# ALREADY-APPLIED version is BLESSED (re-stamped, never re-run) by
# migrate.go's channelRelease handler, so an in-place edit here would leave
# auth_status broken forever. The fix ships as V3, a new migration.
_ut_write_healthpark_break_v2() {
    local v_up="$1" v_down="$2"
    {
      echo "-- Upgrade-arc healthpark fixture V2 (STATBUS-145 doc-029): deterministic"
      echo "-- health-check break. Preserves auth_status's exact signature (schema-cache"
      echo "-- introspection / PostgREST /ready is unaffected) but the body now RAISEs on"
      echo "-- every call, so the post-swap health leg's functional RPC probe"
      echo "-- (/rpc/auth_status, after /ready warmup passes) fails deterministically."
      echo "-- This migration itself SUCCEEDS — the box is genuinely at-target when the"
      echo "-- upgrade parks. NEVER fix by editing this file in place (see V3 / doc-029"
      echo "-- Rev 2): a release-channel content_hash mismatch on an already-applied"
      echo "-- version is BLESSED (re-stamped, never re-run), not re-executed."
      echo "CREATE OR REPLACE FUNCTION public.auth_status()"
      echo " RETURNS auth.auth_response"
      echo " LANGUAGE plpgsql"
      echo " SECURITY DEFINER"
      echo " SET search_path TO 'public', 'pg_temp'"
      echo "AS \$function\$"
      echo "BEGIN"
      echo "  RAISE EXCEPTION 'upgrade-arc healthpark fixture (STATBUS-145): deterministic health-check failure — auth_status intentionally broken';"
      echo "END;"
      echo "\$function\$;"
    } > "$v_up"
    echo "SELECT 1;  -- unused (oom/ceiling unused-down precedent, doc-029 Rev 2) — the original body lives in V3" > "$v_down"
}

# _ut_write_healthpark_fix_v3 V_UP V_DOWN
# Write V3 for the healthpark spec's FIX release (C): a NEW, higher-version
# migration that CREATE OR REPLACEs auth_status() back to its original,
# shipped body (doc/db/function/public_auth_status().md, verbatim) — the
# doc-029 Rev 2 correction. V1/V2 stay byte-identical between B and C; this
# is the ONLY migration C adds. Because it is a genuinely NEW version (no
# existing db.migration row), it applies via the normal pending-migrations
# path on C's upgrade — the content_hash/channel-bless machinery is never
# consulted for it at all.
_ut_write_healthpark_fix_v3() {
    local v_up="$1" v_down="$2"
    {
      echo "-- Upgrade-arc healthpark fixture V3 (STATBUS-145 doc-029 Rev 2): THE FIX."
      echo "-- Restores auth_status() to its original, shipped body verbatim (doc/db/"
      echo "-- function/public_auth_status().md). A NEW migration, never an edit to V2 —"
      echo "-- migration immutability + the release-channel bless-not-rerun semantics"
      echo "-- (migrate.go:1662-1685) mean an in-place edit to an already-applied"
      echo "-- version would never actually re-execute."
      echo "CREATE OR REPLACE FUNCTION public.auth_status()"
      echo " RETURNS auth.auth_response"
      echo " LANGUAGE plpgsql"
      echo " SECURITY DEFINER"
      echo " SET search_path TO 'public', 'pg_temp'"
      echo "AS \$function\$"
      echo "DECLARE"
      echo "  access_token_value text;"
      echo "  access_jwt_verify_result auth.jwt_verify_result;"
      echo "  user_record auth.user;"
      echo "  _token_expires_at timestamptz;"
      echo "BEGIN"
      echo "  RAISE DEBUG '[auth_status] Starting. This function can only see the statbus (access) cookie.';"
      echo ""
      echo "  access_token_value := auth.extract_access_token_from_cookies();"
      echo ""
      echo "  IF access_token_value IS NULL THEN"
      echo "    RAISE DEBUG '[auth_status] No access token cookie found. Unauthenticated.';"
      echo "    RETURN auth.build_auth_response();"
      echo "  END IF;"
      echo ""
      echo "  access_jwt_verify_result := auth.jwt_verify(access_token_value);"
      echo ""
      echo "  -- Extract token expiration from claims"
      echo "  _token_expires_at := to_timestamp((access_jwt_verify_result.claims->>'exp')::bigint);"
      echo ""
      echo "  IF access_jwt_verify_result.is_valid AND NOT access_jwt_verify_result.expired THEN"
      echo "    RAISE DEBUG '[auth_status] Access token is valid and not expired.';"
      echo "    SELECT * INTO user_record"
      echo "    FROM auth.user"
      echo "    WHERE sub = (access_jwt_verify_result.claims->>'sub')::uuid AND deleted_at IS NULL;"
      echo ""
      echo "    IF FOUND THEN"
      echo "      RAISE DEBUG '[auth_status] User found. Authenticated.';"
      echo "      RETURN auth.build_auth_response(p_user_record => user_record, p_token_expires_at => _token_expires_at);"
      echo "    ELSE"
      echo "      RAISE DEBUG '[auth_status] User from valid token not found in DB. Unauthenticated.';"
      echo "      PERFORM auth.clear_auth_cookies();"
      echo "      RETURN auth.build_auth_response();"
      echo "    END IF;"
      echo "  END IF;"
      echo ""
      echo "  IF access_jwt_verify_result.is_valid AND access_jwt_verify_result.expired THEN"
      echo "    RAISE DEBUG '[auth_status] Access token is expired but signature is valid. Client should refresh.';"
      echo "    RETURN auth.build_auth_response(p_expired_access_token_call_refresh => true);"
      echo "  END IF;"
      echo ""
      echo "  RAISE DEBUG '[auth_status] Access token is invalid (e.g., bad signature). Unauthenticated.';"
      echo "  RETURN auth.build_auth_response();"
      echo "END;"
      echo "\$function\$;"
    } > "$v_up"
    echo "SELECT 1;  -- unused (oom/ceiling unused-down precedent, doc-029 Rev 2) — C never rolls back within this arc" > "$v_down"
}

# _ut_write_codeonly_change MARKER
# Write the CODE-ONLY (no-delta) fixture: a single non-migration marker file,
# and NO migration at all. STATBUS-071 arm (ii): B = A + code change, no V.
#
# WHY NO MIGRATION IS THE LOAD-BEARING PROPERTY (architect law, STATBUS-071 #22,
# 145 atomicity): at the post-swap pre-pull disk pre-check the ledger's max
# version == the on-disk max and the binary is already the target — the box is
# genuinely AT-TARGET (ObservedAlreadyAtNew, service.go newSbUpgradingFailure).
# A deterministic resource failure there therefore PARKS (restore forbidden —
# forward remains possible), it does NOT roll back. A delta-carrying lineage
# (working/etc.) is positively BEHIND at that same check, so its resource
# failure ROLLS BACK instead (proven by run 29360596950). The resource PARK
# genuinely lives only on no-migration upgrades — a normal fleet reality
# (app-/CLI-only RCs). The marker's CONTENT is irrelevant to the running box:
# unlike working's fixture table, the arm-(ii) arc asserts on the park + un-park
# + zero-restore, never on this file. It exists only so B is a distinct signed
# commit from A with NO migration delta.
_ut_write_codeonly_change() {
    local _marker="$1"
    mkdir -p "$(dirname "$_marker")"
    {
      echo "Upgrade-arc CODE-ONLY (no-delta) fixture (STATBUS-071 arm ii)."
      echo "B = A + this non-migration change; NO migration is written, so B is"
      echo "AT-TARGET at the post-swap pre-pull disk pre-check → a resource failure"
      echo "there PARKS (forward possible) rather than rolling back (which needs a"
      echo "positively-Behind ledger). Represents a normal code-only / app-or-CLI-only"
      echo "release. This file's content is never asserted by the running box."
    } > "$_marker"
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
    # V_VERSION_3 — healthpark-only (C's fix migration, doc-029 Rev 2). Computed
    # unconditionally for every spec, mirroring V_VERSION_2's own pattern (cheap;
    # unused specs just ignore it).
    V_VERSION_3="$((_latest + 3))"
    local _v_up="migrations/${V_VERSION}_upgrade_arc.up.sql"
    local _v_down="migrations/${V_VERSION}_upgrade_arc.down.sql"
    local _v2_up="migrations/${V_VERSION_2}_upgrade_arc_2.up.sql"
    local _v2_down="migrations/${V_VERSION_2}_upgrade_arc_2.down.sql"
    local _v3_up="migrations/${V_VERSION_3}_upgrade_arc_3.up.sql"
    local _v3_down="migrations/${V_VERSION_3}_upgrade_arc_3.down.sql"
    # codeonly (no-delta) marker — a non-migration file so B is a distinct
    # signed commit from A with NO migration V (STATBUS-071 arm ii).
    local _marker="test/install-recovery/fixtures/upgrade-arc-codeonly.marker"
    echo "── construct_upgrade_target: spec=${_spec} base=${_base_sha:0:8} V=${V_VERSION} V2=${V_VERSION_2} V3=${V_VERSION_3} ──"

    # ── branch names (verbatim pattern from upgrade-arc-harness.yaml:201-202) ─
    local _b_branch="test/upgrade-arc-${_spec}-migration-${_run_id}"
    local _c_branch="test/upgrade-arc-${_spec}-fixed-migration-${_run_id}"
    echo "── building ${_spec} pair: B=${_b_branch} C=${_c_branch} ──"

    # ── build B ──────────────────────────────────────────────────────────────
    git checkout -B "$_b_branch" "$_base_sha"
    case "$_spec" in
        working)    _ut_write_working_v "$_v_up" "$_v_down" "$_v2_up" "$_v2_down" ;;
        failing)    _ut_write_failing_v "$_v_up" "$_v_down" ;;
        oom)        _ut_write_oom_v "$_v_up" "$_v_down" ;;
        ceiling)    _ut_write_ceiling_v "$_v_up" "$_v_down" ;;
        healthpark)
            _ut_write_healthpark_v1 "$_v_up" "$_v_down"
            _ut_write_healthpark_break_v2 "$_v2_up" "$_v2_down"
            ;;
        codeonly)
            # No migration — a non-migration marker only. Stage it here (the
            # shared `git add migrations/` below adds nothing for this spec).
            _ut_write_codeonly_change "$_marker"
            git add "$_marker"
            ;;
        *) echo "construct_upgrade_target: unknown SPEC '${_spec}' (expected: working|failing|oom|ceiling|healthpark|codeonly)" >&2; return 1 ;;
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
            # terminal is completed — the box's own boot revives the db and
            # re-runs V forward; there is nothing to apply afterward).
            # Deliberately NO commit here: C stays identical to B (same
            # commit, different branch name). construct_upgrade_target's
            # caller-scope contract still produces a C_BRANCH/C_FULL output
            # for uniformity across specs; the oom arc's own script simply
            # never references them (it declares only BASE_SHA/B_FULL/B_BRANCH
            # as required, mirroring rollback-kill-arc.sh's own B-only shape).
            ;;
        ceiling)
            # No "fixed" phase for the ceiling arc either: single-phase
            # (A→B only), terminal is rolled_back — the ceiling's own
            # in-process rollback IS the terminal, nothing to apply
            # afterward. Same no-commit shape as oom's C (unused, identical
            # to B); the ceiling arc's own script declares only
            # BASE_SHA/B_FULL/B_BRANCH as required.
            ;;
        healthpark)
            # C's fix: a NEW migration (V3), never an edit to V2 (doc-029 Rev 2 —
            # the release-channel content_hash handler blesses an in-place edit to
            # an already-applied version instead of re-running it; see
            # _ut_write_healthpark_break_v2's doc comment). V1/V2 stay byte-
            # identical to B — untouched here.
            _ut_write_healthpark_fix_v3 "$_v3_up" "$_v3_down"
            git add migrations/
            git commit -S -q -m "test(upgrade-arc): ${_spec} fix auth_status via NEW migration V3 (C)"
            ;;
        codeonly)
            # No "fixed" phase: single-phase (A→B only). The un-park-to-completion
            # arm-(ii) arc completes B's OWN row (park → un-park → same row
            # completes); there is no separate fix release. Same no-commit shape as
            # oom/ceiling — C stays identical to B (unused); the arc declares only
            # BASE_SHA/B_FULL/B_BRANCH as required.
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

# delete_throwaway_branches SPEC [RUN_ID] — STATBUS-165 AC#4, the LOCAL half of
# end-of-run branch self-delete. CI's own teardown (upgrade-arc-harness.yaml
# :572-596, `if: always()`) already does this for the working+failing lineage
# it drives; this is the SAME recompute-from-run-id shape, generalized to any
# SPEC construct_upgrade_target supports (working|failing|oom|ceiling|
# healthpark), for callers that push their OWN B/C pair directly (the "install-
# recovery scenario harness" this file's own header describes) rather than
# consuming the shared CI construct job's outputs.
#
# RECOMPUTES the two branch names from SPEC + RUN_ID — never reads B_BRANCH/
# C_BRANCH — so it still works if construct_upgrade_target died partway (a
# push that succeeded but a later step failed leaves the branches nameable
# even though the caller-scope vars this function does not touch may be
# unset). Both names are ALWAYS produced by construct_upgrade_target
# regardless of spec (oom/ceiling push a C branch too — same commit as B,
# no separate commit, but still its own pushed ref; see the spec case
# statement above), so no spec-specific branch-count logic is needed here.
#
# ARC_NO_PUSH-GUARDED, SYMMETRICALLY with the :483 push: when ARC_NO_PUSH=1
# nothing was ever pushed (the push step above is skipped identically), so
# there is nothing to delete — this function must not attempt to reach
# origin for state a local unit test deliberately kept local-only.
#
# BEST-EFFORT, ALWAYS RETURNS 0 (mirrors CI teardown's own philosophy: a
# missing/already-deleted branch, or a delete that fails, must never fail the
# caller's exit trap — the weekly image-cleanup.yaml branch-gc step, STATBUS-
# 165 AC#4's other half, is the backstop for anything this misses).
#
# WIRING (the caller's responsibility — this function does not register its
# own trap, to avoid clobbering a caller's existing `trap ... EXIT`, e.g. the
# cleanup_vm pattern every arcs/*.sh already uses): compose it into the SAME
# trap string, called before the exit:
#   trap 'rc=$?; delete_throwaway_branches "$SPEC" "$RUN_ID"; cleanup_vm "$VM_NAME"; exit $rc' EXIT
delete_throwaway_branches() {
    local _spec="$1"
    local _run_id="${2:-${RUN_ID:-}}"

    if [ -z "$_spec" ]; then
        echo "delete_throwaway_branches: SPEC required (working|failing|oom|ceiling|healthpark|codeonly) — skipping" >&2
        return 0
    fi
    if [ -z "$_run_id" ]; then
        echo "delete_throwaway_branches: no RUN_ID given or exported — cannot recompute branch names; skipping" >&2
        return 0
    fi
    if [ "${ARC_NO_PUSH:-0}" = "1" ]; then
        echo "delete_throwaway_branches: ARC_NO_PUSH=1 — nothing was pushed, nothing to delete." >&2
        return 0
    fi

    local _b_branch="test/upgrade-arc-${_spec}-migration-${_run_id}"
    local _c_branch="test/upgrade-arc-${_spec}-fixed-migration-${_run_id}"
    local _br
    for _br in "$_b_branch" "$_c_branch"; do
        if git ls-remote --exit-code --heads origin "$_br" >/dev/null 2>&1; then
            echo "delete_throwaway_branches: deleting ${_br}"
            git push origin --delete "$_br" \
                || echo "  (delete failed — best-effort; the weekly image-cleanup.yaml branch-gc sweep is the backstop)" >&2
        else
            echo "delete_throwaway_branches: ${_br} not present (already gone / never pushed) — nothing to delete."
        fi
    done
    return 0
}
