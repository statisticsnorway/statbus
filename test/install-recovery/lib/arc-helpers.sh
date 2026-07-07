#!/bin/bash
# arc-helpers.sh — shared helpers for the upgrade-arc scenarios (STATBUS-071).
#
# Both arcs (working-arc.sh = the MANY who succeed → re-stamp; failing-arc.sh =
# the FEW who fail → rollback → fresh fix) drive real upgrades through the Albania
# mechanism (register → schedule → the upgrade SERVICE runs executeUpgrade
# autonomously; NO quiesce, NO ./sb install). This file holds everything they
# share so the two scripts stay thin and can't drift apart.
#
# Relies on (sourced by the caller BEFORE any call): vm-bootstrap.sh (VM_EXEC,
# bootstrap_install_test_vm, install_statbus_at_sha, vm_restart_unit), data-helpers.sh
# (populate_with_demo_data), assertions.sh (assert_health_passes, assert_demo_data_present).
# Reads globals the caller sets: VM_NAME, BASE_SHA, V_VERSION, TICK_WAIT_S,
# UPGRADE_BUDGET_S, SB_ARC_TRUSTED_SIGNER.

# trust_arc_signer — trust the ephemeral arc signing key POST-install. install's
# checkSignersDone (install.go:1592-1650) runs `git verify-commit HEAD` against
# every configured UPGRADE_TRUSTED_SIGNER_* and DELETES them all if HEAD doesn't
# verify; the arc key signs B/C, never HEAD=A (a master commit jhf signed), so a
# pre-install arc key is scrubbed. Adding it AFTER install works: `config generate`
# does NOT run checkSignersDone, so the key survives into .env; restarting the
# upgrade unit makes loadTrustedSigners re-read .env WITH arc → the daemon trusts
# B/C. (After B applies, HEAD becomes arc-signed, so later checkSignersDone passes.)
trust_arc_signer() {
    if [ -z "${SB_ARC_TRUSTED_SIGNER:-}" ]; then
        echo "✗ SB_ARC_TRUSTED_SIGNER not set — cannot trust the arc signer; B/C would fail verification" >&2
        exit 1
    fi
    echo ""
    echo "── trusting ephemeral arc signer (post-install) ──"
    VM_EXEC bash -c "cd ~/statbus && ./sb dotenv -f .env.config set UPGRADE_TRUSTED_SIGNER_arc \"${SB_ARC_TRUSTED_SIGNER}\" && ./sb config generate >/dev/null"
    vm_restart_unit "statbus-upgrade@statbus.service"
    echo "  ✓ arc signer trusted; upgrade unit restarted (loadTrustedSigners re-read .env)"
}

# arc_prepare_box — bring the box to the shared arc starting line: provision →
# install A (base_sha, pinned) → health → assert the upgrade daemon is active →
# trust the arc signer → populate demo data. After this both arcs capture their
# own baseline (working: data snapshot; failing: 3-dim fingerprint) and drive B/C.
arc_prepare_box() {
    bootstrap_install_test_vm "$VM_NAME" ""
    echo ""
    echo "── install A (base_sha ${BASE_SHA:0:8}) ──"
    install_statbus_at_sha "$VM_NAME" "$BASE_SHA"
    assert_health_passes "$VM_NAME"

    # The arc is driven by A's daemon (A=base_sha is post-086 → it HAS
    # register/schedule + executeUpgrade). Confirm the unit is active first.
    local unit_state
    unit_state=$(VM_EXEC systemctl --user is-active "statbus-upgrade@statbus.service" 2>/dev/null | tr -d ' \r\n' || echo "?")
    [ "$unit_state" = "active" ] || { echo "✗ upgrade-service unit not active after install A (state=$unit_state)" >&2; exit 1; }
    echo "  ✓ upgrade-service active (daemon will run the arc)"

    trust_arc_signer

    echo ""
    echo "── populate demo data ──"
    populate_with_demo_data "$VM_NAME"
    assert_demo_data_present "$VM_NAME"
}

# dump_signing_diagnostics <sha> — permanent DIAGNOSTIC (AGENTS.md: build the
# tool). Dumps the trust chain the daemon will use to verify <sha> right before
# scheduling: .env.config signer, .env signer (post config-generate),
# tmp/allowed-signers (what git verify-commit reads), and <sha>'s own signature.
# A mismatch pinpoints where the ephemeral-key trust broke. Best-effort.
dump_signing_diagnostics() {
    local sha="$1"
    echo "  ┌─ signing diagnostics (trust chain for ${sha:0:8}) ─"
    echo "  │ .env.config:    $(VM_EXEC bash -c "cd ~/statbus && grep UPGRADE_TRUSTED_SIGNER .env.config || echo '(none)'" 2>/dev/null | tr '\n' ' ')"
    echo "  │ .env:           $(VM_EXEC bash -c "cd ~/statbus && grep UPGRADE_TRUSTED_SIGNER .env || echo '(none)'" 2>/dev/null | tr '\n' ' ')"
    echo "  │ allowed-signers:$(VM_EXEC bash -c "cd ~/statbus && cat tmp/allowed-signers 2>/dev/null || echo '(no file)'" 2>/dev/null | tr '\n' '|')"
    echo "  │ commit sig:     $(VM_EXEC bash -c "cd ~/statbus && git log -1 --format='%G? key=%GK' $sha 2>/dev/null || echo '(unreadable)'" 2>/dev/null | tr '\n' ' ')"
    echo "  └─"
}

# dump_daemon_state <label> — DIAGNOSTIC (BUG-2): the upgrade unit's is-active,
# whether a backend is LISTENing on upgrade_apply, + the recent journal, right
# before scheduling. Reveals whether the post-B-restart daemon was ready when C
# was scheduled. Best-effort; never fails the arc.
dump_daemon_state() {
    local label="$1" unit="statbus-upgrade@statbus.service"
    echo "  ┌─ daemon state ($label) ─"
    echo "  │ is-active: $(VM_EXEC systemctl --user is-active "$unit" 2>/dev/null | tr -d ' \r\n' || echo '?')"
    echo "  │ LISTEN upgrade_apply backends: $(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM pg_stat_activity WHERE query = 'LISTEN upgrade_apply';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo '?')"
    VM_EXEC bash -c "journalctl --user -u $unit --no-pager -n 6 2>/dev/null | sed 's/^/  | /'" 2>/dev/null || true
    echo "  └─"
}

# arc_to <sha> <branch> <label> [expected_state] — drive ONE upgrade through the
# real register→ready→schedule→service-runs→terminal path (0-happy-upgrade
# phases 4-6, generalized). Pre-fetches the target branch so the daemon's
# executeUpgrade can `git checkout` it. expected_state defaults to 'completed'
# (working/fix legs); the failing leg passes 'rolled_back'. Fails loud otherwise.
arc_to() {
    local sha="$1" branch="$2" label="$3" expected="${4:-completed}"
    echo ""
    echo "── arc → ${label} (${sha:0:8}; expect '${expected}') ──"
    # STATBUS-098: do NOT wait for the daemon here — the arc must keep CATCHING the
    # lost-NOTIFY-during-restart class (a wait would mask the product gap). The
    # product fix (daemon claims pending 'scheduled' rows on startup + every 30s
    # heartbeat tick, not only on a live NOTIFY) makes C get claimed within ≤30s of
    # schedule. dump_daemon_state records the daemon state at schedule time.
    dump_daemon_state "before ${label}"
    VM_EXEC bash -c "cd ~/statbus && git fetch origin $branch && git cat-file -e $sha"

    echo "  register ${label}"
    VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $sha 2>&1 | tail -20"
    echo "  wait for candidate ready"
    wait_for_upgrade_candidate_ready "$VM_NAME" "$sha" "$TICK_WAIT_S"

    dump_signing_diagnostics "$sha"

    echo "  schedule ${label} (DB trigger → daemon claims + runs executeUpgrade)"
    VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $sha 2>&1 | tail -20"

    local start_ts elapsed state final=""
    start_ts=$(date +%s)
    while true; do
        elapsed=$(( $(date +%s) - start_ts ))
        if [ "$elapsed" -ge "$UPGRADE_BUDGET_S" ]; then
            echo "✗ ${label}: no terminal state within ${UPGRADE_BUDGET_S}s" >&2
            VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, commit_sha, error FROM public.upgrade ORDER BY id DESC LIMIT 5;' | ./sb psql" >&2 || true
            exit 1
        fi
        state=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$sha' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
        case "$state" in
            completed|failed|rolled_back) final="$state"; echo "  ${label}: state='$state' (t+${elapsed}s)"; break ;;
        esac
        sleep 5
    done
    if [ "$final" != "$expected" ]; then
        echo "✗ ${label} reached '$final', expected '$expected'" >&2
        VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '$sha' ORDER BY id DESC LIMIT 3;\" | ./sb psql" >&2 || true
        exit 1
    fi
}

# Small psql readers for the arc's observable schema change + V's ledger row.
fixture_row_count() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM public.upgrade_arc_fixture;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "ERR"
}
migration_content_hash() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT content_hash FROM db.migration WHERE version = ${V_VERSION};\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "ERR"
}
migration_row_count() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM db.migration WHERE version = ${V_VERSION};\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "ERR"
}
# migration_max_version — the highest applied migration version (COALESCE 0 if
# none). The CAT-C forward-recovery arcs (mid-migration / between-migrations /
# mid-tx) assert this == V_VERSION_2 for a COMPLETED upgrade — load-bearing proof
# that forward-recovery re-applied BOTH shared working migrations, not just one.
migration_max_version() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(MAX(version), 0) FROM db.migration;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "ERR"
}

# capture_db_fingerprint — the 3-dim clean-slate fingerprint (STATBUS-071 d).
# Echoes "schema_sha ledger_sha data_sha"; each dim is hashed ON the VM.
#   SCHEMA — pg_dump --schema-only inside the db container, comments + blank lines
#            + trailing whitespace stripped (gold standard: catches table / fn /
#            trigger / policy / sequence residue an information_schema digest misses).
#   LEDGER — db.migration (version,content_hash) ordered.
#   DATA   — BASE tables ONLY {legal_unit, establishment}. Derived tables
#            (statistical_unit, statistical_history) are worker-COMPUTED → a
#            re-derivation between rollback and re-capture would falsely mismatch
#            on a CLEAN rollback; base is pure snapshot-restore and derived=f(base),
#            so base SUFFICES to prove the data clean-slate. (Adding derived +
#            a worker-quiescence-wait is a noted later enhancement.)
capture_db_fingerprint() {
    local label="${1:-fp}"
    local schema_sha ledger_sha data_sha fp_db fp_user schema_file
    schema_file="${HARNESS_ROOT}/tmp/arc-schema-${label}.sql"
    mkdir -p "$(dirname "$schema_file")"

    # QUIESCE the worker before capturing (071 AC#2 schema-dim determinism; architect
    # call (b) — NOT a rollback bug: data + ledger dims MATCH, and V_fail only RAISEs).
    # statistical_history is hash-partitioned; the worker creates/manages partition
    # schema objects during derivation. Capturing at different derivation states
    # (baseline post-populate vs post-rollback) makes pg_dump --schema-only differ → a
    # FALSE clean-slate mismatch. Derivation is deterministic (hash_slot from the same
    # restored base data → same partitions), so quiescing to the STABLE FINAL state
    # before BOTH captures makes the partition-schema identical. Quiesce stdout → &2
    # so it can't pollute the captured fingerprint; warn (don't fail) on timeout — the
    # diff instrument in assert_fingerprint_matches surfaces any residual.
    wait_for_worker_quiesce "$VM_NAME" "${FP_QUIESCE_MAX_S:-300}" >&2 \
        || echo "  ⚠ worker did not quiesce before fingerprint ($label) — schema dim may be nondeterministic" >&2

    # Read connection params via SEPARATE SIMPLE one-liner VM_EXEC calls. BUG-1: a
    # GIANT multi-statement `bash -c '…db=$(…);…|…'` does NOT survive VM_EXEC's
    # printf-%q + `sudo -i` re-parse (inner assignments never run). Each working dim
    # is ONE plain pipe, no intermediate assignment.
    fp_db=$(VM_EXEC bash -c "cd ~/statbus && ./sb dotenv -f .env get POSTGRES_APP_DB" 2>/dev/null | tr -d ' \r\n')
    fp_user=$(VM_EXEC bash -c "cd ~/statbus && ./sb dotenv -f .env get POSTGRES_ADMIN_USER" 2>/dev/null | tr -d ' \r\n')
    # SCHEMA dim — VM_EXEC pulls the RAW pg_dump (in the db container via the PROVEN
    # `docker compose exec -T db` pattern, 1-boot-advisory:116 / wedge-helpers:89);
    # ALL text-processing (strip + hash) runs on the RUNNER. Doing the strip
    # runner-side lets the nonce filter be BACKSLASH-ANCHORED (the architect's exact
    # form) WITHOUT fighting VM_EXEC's double-quote + %q + sudo-i backslash mangling
    # (a literal-backslash regex inside the VM_EXEC pipe would be mangled — the BUG-1
    # layer lesson). Strip: (1) pg_dump comment lines (^--); (2) the PG18 `\restrict`
    # / `\unrestrict <random-nonce>` psql-meta wrapper lines — a PER-DUMP random token
    # (restore-hardening), NOT DDL; the diff instrument caught it as the ONLY
    # baseline↔rollback diff. Anchored on the literal leading backslash + the trailing
    # space → matches EXACTLY the 2 wrapper lines (verified vs the real dump: a DDL
    # line containing "restrict" like 'restricted_user' is untouched). (3) blank
    # lines. Two same-box quiesced dumps are then byte-identical.
    local schema_raw="${schema_file}.raw"
    VM_EXEC bash -c "cd ~/statbus && docker compose exec -T db pg_dump --schema-only --no-owner --no-privileges -U ${fp_user} ${fp_db} 2>/dev/null" > "$schema_raw" 2>/dev/null
    grep -v '^--' "$schema_raw" 2>/dev/null | grep -vE '^\\(un)?restrict[[:space:]]' | grep '[^[:space:]]' > "$schema_file"
    schema_sha=$(sha256sum "$schema_file" 2>/dev/null | cut -d' ' -f1)
    rm -f "$schema_raw"
    # CENTERPIECE GUARD: a silently-failed pg_dump → empty schema → sha256("") on
    # BOTH captures → a VACUOUS clean-slate pass. Fail loud + a SIMPLE diagnostic.
    # return 1 → caller's var=$(...) non-zero under set -e → the arc halts.
    local empty_sha="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    if [ -z "$schema_sha" ] || [ "$schema_sha" = "$empty_sha" ]; then
        echo "✗ capture_db_fingerprint($label): SCHEMA dim empty — refusing a vacuous fingerprint." >&2
        echo "    db=[$fp_db] user=[$fp_user] schema_file=[$schema_file] lines=[$(wc -l <"$schema_file" 2>/dev/null | tr -d ' ')]" >&2
        VM_EXEC bash -c "cd ~/statbus && docker compose exec -T db pg_dump --schema-only --no-owner --no-privileges -U ${fp_user} ${fp_db} 2>&1 | head -5" 2>&1 | sed 's/^/    pgdump: /' >&2 || true
        return 1
    fi
    ledger_sha=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT version::text || ',' || content_hash FROM db.migration ORDER BY version;\" | ./sb psql -t -A 2>/dev/null | sha256sum | cut -d' ' -f1" 2>/dev/null | tr -d ' \r\n')
    data_sha=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT md5(coalesce(string_agg(t::text, '|' ORDER BY t::text), '')) FROM public.legal_unit t UNION ALL SELECT md5(coalesce(string_agg(t::text, '|' ORDER BY t::text), '')) FROM public.establishment t;\" | ./sb psql -t -A 2>/dev/null | sha256sum | cut -d' ' -f1" 2>/dev/null | tr -d ' \r\n')
    echo "${schema_sha} ${ledger_sha} ${data_sha}"
}

# assert_fingerprint_matches <label> <baseline> — re-capture + compare byte-for-byte;
# report WHICH dim drifted on mismatch (the clean-slate centerpiece, STATBUS-071 d).
assert_fingerprint_matches() {
    local label="$1" baseline="$2" baseline_schema_label="${3:-baseline}" current
    current=$(capture_db_fingerprint "rollback-recheck")
    if [ "$current" != "$baseline" ]; then
        echo "✗ CLEAN-SLATE FINGERPRINT MISMATCH (${label})" >&2
        local b_s b_l b_d c_s c_l c_d
        read -r b_s b_l b_d <<< "$baseline"
        read -r c_s c_l c_d <<< "$current"
        if [ "$b_s" != "$c_s" ]; then
            echo "    SCHEMA differs: ${b_s:0:16}… → ${c_s:0:16}…" >&2
            # INSTRUMENT: diff the two raw schema dumps → NAME the differing objects.
            # worker-created hash-partition/facet residue (statistical_history_*) =
            # residual determinism → quiesce harder; a migration table altered/missing
            # = a real recovery bug. Full dumps upload as artifacts (run-arc globs
            # tmp/arc-schema-*.sql).
            local bf="${HARNESS_ROOT}/tmp/arc-schema-${baseline_schema_label}.sql"
            local cf="${HARNESS_ROOT}/tmp/arc-schema-rollback-recheck.sql"
            echo "    schema diff (${bf} vs ${cf}) — first 60 differing lines:" >&2
            diff "$bf" "$cf" 2>/dev/null | head -60 | sed 's/^/      /' >&2 || true
        fi
        [ "$b_l" = "$c_l" ] || echo "    LEDGER differs: ${b_l:0:16}… → ${c_l:0:16}…" >&2
        [ "$b_d" = "$c_d" ] || echo "    DATA   differs: ${b_d:0:16}… → ${c_d:0:16}…" >&2
        exit 1
    fi
    echo "  ✓ clean-slate fingerprint matches (${label})"
}

# ── KILL-ARC driver (STATBUS-071 §9(5) / doc-016) ────────────────────────────
# The DAEMON-DOWN + `./sb install` inline-dispatch variant — DISTINCT from the
# daemon-RUN working/failing arcs. It replaces fabricate_scheduled_upgrade_row
# (the legacy daemon-down 'scheduled' synth) with the REAL register+schedule; the
# crash itself is ALREADY real (STATBUS_INJECT_AT at the product's inject points).

# arc_schedule_daemon_down <sha> — stop the upgrade daemon, then schedule <sha> so
# the row sits in a persistent daemon-down 'scheduled' state (RunSchedule, 086),
# ready for `./sb install` to inline-dispatch. Mirrors the proven claim-without-
# notify daemon-down→schedule pattern. (register <sha> must have run first, with
# the daemon UP, so verifyArtifacts flipped docker_images_status='ready'.)
arc_schedule_daemon_down() {
    local sha="$1"
    echo ""
    echo "── stop the daemon + schedule ${sha:0:8} → persistent daemon-down 'scheduled' row ──"
    VM_EXEC systemctl --user stop "statbus-upgrade@statbus.service" 2>/dev/null || true
    local s
    s=$(VM_EXEC systemctl --user is-active "statbus-upgrade@statbus.service" 2>/dev/null | tr -d ' \r\n' || echo "inactive")
    [ "$s" != "active" ] || { echo "✗ daemon still active after stop — it could claim the row before ./sb install" >&2; exit 1; }
    VM_EXEC bash -c "cd ~/statbus && ./sb upgrade schedule $sha 2>&1 | tail -20"
    local st
    st=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$sha' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
    [ "$st" = "scheduled" ] || { echo "✗ expected B 'scheduled' (daemon down), got '$st'" >&2; exit 1; }
    echo "  ✓ daemon down + B 'scheduled' — the persistent row ./sb install will inline-dispatch"
}

# arc_install_dispatch_with_inject <inject_class> [budget_s] — run `./sb install`
# WITH STATBUS_INJECT_AT=<class> so the kill/stall fires at the REAL product inject
# point. Used for BOTH the inline-dispatch of a 'scheduled' row (it detects
# StateScheduledUpgrade → executeUpgrade) AND a recovery dispatch of a crashed-
# upgrade flag (it detects the flag → recoverFromFlag) — the inject fires whenever
# its site is reached on either path. The injected SIGKILL exits ~137; the caller
# asserts the REAL crash state (the flag is written by the real executeUpgrade — no
# synthetic crash-state). Fails loud only on a timeout (the inject never fired).
# Exposes the exit in the global ARC_DISPATCH_RC so a caller can BRANCH on it (e.g.
# rollback-kill's outcome A [forward-recovery completed, exit 0] vs outcome B [the
# rollback inject fired, exit 137]). The single-kill callers ignore it.
ARC_DISPATCH_RC=0
arc_install_dispatch_with_inject() {
    local inject_class="$1" budget="${2:-${INSTALL_BUDGET_S:-900}}" kill_marker="${3:-}"
    # ONE-SHOT file-armed kill (doc-017 §1/§2, for the :389/:912 mid-migrate kills):
    # when a marker path is given, also set STATBUS_INJECT_KILL_AND_REMOVE_FILE so
    # KillHere fires IFF the marker exists, removing it BEFORE os.Exit → fires
    # EXACTLY ONCE. The arc creates the marker before the FIRST (kill) dispatch;
    # the SECOND (recovery) dispatch re-enters the same site with the marker GONE →
    # no re-kill → forward-recovery re-runs migrate → completed. The marker survives
    # ./sb install's internal syscall.Exec re-exec (a filesystem handle, not an
    # in-memory one-shot — inject.go EnvKillAndRemoveFile). Unset → persistent kill.
    local kill_env=""
    [ -z "$kill_marker" ] || kill_env="STATBUS_INJECT_KILL_AND_REMOVE_FILE=${kill_marker} "
    echo ""
    echo "── ./sb install dispatch with STATBUS_INJECT_AT=${inject_class}${kill_marker:+ (one-shot marker ${kill_marker})} (budget ${budget}s) ──"
    local rc=0
    VM_EXEC bash -c "cd ~/statbus && ${kill_env}STATBUS_INJECT_AT=${inject_class} STATBUS_MIN_DISK_GB=5 timeout ${budget} ./sb install --non-interactive --trust-github-user jhf" || rc=$?
    # shellcheck disable=SC2034  # read cross-file by the arc scripts (e.g. rollback-kill)
    ARC_DISPATCH_RC="$rc"
    echo "  ./sb install (injected) exit: $rc (137 = injected SIGKILL semantics)"
    [ "$rc" != "124" ] || { echo "✗ ./sb install timed out (${budget}s) — STATBUS_INJECT_AT=${inject_class} never fired" >&2; exit 1; }
}

# ── STALL-DISPATCH (CAT-B / 5c, doc-016) — the 3rd driver variant ─────────────
# daemon-RUN: the systemd UNIT runs the upgrade under WatchdogSec=120s; a STALL
# (not a kill) is injected via a systemd DROPIN so the upgrade hangs > WatchdogSec.
# The load-bearing check is NRestarts stays bounded (the WATCHDOG=1 ticker keeps
# the unit alive across the stall → the upgrade COMPLETES, never SIGABRT).

ARC_UPGRADE_UNIT="statbus-upgrade@statbus.service"

# arc_install_stall_dropin <inject_class> <release_file> — install a systemd USER
# dropin that arms the StallHere (Environment), then RESTART the unit so the
# already-running daemon PROCESS picks up the env (a daemon-reload alone does NOT
# change a running process's env — the env is read at start; executeUpgrade runs IN
# the daemon → it must have STATBUS_INJECT_AT). Touch the release file (arms the
# stall) before the restart. MUST run BEFORE scheduling B (the restart's startup-
# scan finds nothing → 098 doesn't pre-claim). Heredocs don't survive VM_EXEC's
# %q, so write the dropin script locally + upload + run (the legacy pattern).
arc_install_stall_dropin() {
    local inject_class="$1" release_file="$2"
    echo ""
    echo "── install stall dropin (STATBUS_INJECT_AT=${inject_class}) + RESTART unit (arms env in the daemon process) ──"
    VM_EXEC systemctl --user stop "$ARC_UPGRADE_UNIT" 2>/dev/null || true
    local script
    script=$(mktemp /tmp/arc-stall-dropin-XXXXXX.sh)
    cat > "$script" << SCRIPT_EOF
#!/bin/bash
set -euo pipefail
DROPIN_DIR="\$HOME/.config/systemd/user/${ARC_UPGRADE_UNIT}.d"
mkdir -p "\$DROPIN_DIR"
cat > "\$DROPIN_DIR/inject.conf" << 'DROPIN_EOF'
[Service]
Environment=STATBUS_INJECT_AT=${inject_class}
Environment=STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE=${release_file}
DROPIN_EOF
touch ${release_file}
systemctl --user daemon-reload
SCRIPT_EOF
    chmod 644 "$script"
    upload_install_script_to_vm "$VM_NAME" "$script" /tmp/arc-stall-dropin.sh
    rm -f "$script"
    VM_EXEC bash /tmp/arc-stall-dropin.sh
    vm_start_unit "$ARC_UPGRADE_UNIT"   # RESTART-FOR-ENV: the daemon process now carries STATBUS_INJECT_AT
    echo "  ✓ dropin installed + unit restarted with the stall env (release file armed: ${release_file})"
}

# arc_nrestarts — the unit's systemd NRestarts counter (for the bounded-restart assert).
arc_nrestarts() {
    VM_EXEC systemctl --user show "$ARC_UPGRADE_UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n' || echo "?"
}

# arc_wait_row_state <sha> <want_state> [budget_s] — poll public.upgrade for <sha>
# reaching <want_state>. When waiting for in_progress, a DIFFERENT terminal reached
# first ⟹ fail fast (the dispatch never engaged the stall / went straight through).
arc_wait_row_state() {
    local sha="$1" want="$2" budget="${3:-240}"
    local start now elapsed st
    start=$(date +%s)
    while true; do
        now=$(date +%s); elapsed=$((now - start))
        st=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$sha' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
        if [ "$st" = "$want" ]; then echo "  ✓ row ${sha:0:8} reached '$want' (t+${elapsed}s)"; return 0; fi
        if [ "$want" = "in_progress" ]; then
            case "$st" in
                completed|failed|rolled_back) echo "✗ row reached terminal '$st' before '$want' — dispatch did not engage (stall not armed?)" >&2; return 1 ;;
            esac
        fi
        if [ "$elapsed" -ge "$budget" ]; then
            echo "✗ row ${sha:0:8} did not reach '$want' within ${budget}s (last='$st')" >&2
            VM_EXEC bash -c "cd ~/statbus && echo 'SELECT id, state, error FROM public.upgrade ORDER BY id DESC LIMIT 5;' | ./sb psql" >&2 || true
            return 1
        fi
        sleep 5
    done
}

# ── arc_kill_confirmed <vm> <mode> [poll_budget_s] ───────────────────────────
# SIGKILL a target captured FRESH at kill time, then POLL until it is CONFIRMED
# gone. Returns 0 iff every targeted PID is dead; on a MISS (no live target at kill
# time, or still alive after the budget) it prints a loud diagnostic and returns 1.
#
# WHY THIS EXISTS (STATBUS-021 bug class — the U1 stale-PID kill miss). The old
# arcs captured the target PID into a variable EARLY (at stall-detection), but the
# exit-42 binary-swap handoff RESPAWNS the daemon (systemd restart → new MainPID)
# between capture and kill. The late SIGKILL then hit a dead PID ('No such process')
# → the kill was MISSED → and because the arc went on to RELEASE the stall anyway,
# the un-killed process finished the upgrade → a FALSE 'completed'. Capturing the
# PID FRESH here — inside this helper, at kill time — closes that window.
#
# Modes (each captures FRESH; that is the whole point — never a stale variable):
#   daemon-mainpid      the upgrade daemon's CURRENT systemd MainPID (authoritative
#                       post-handoff PID — a stale variable is exactly the U1 bug).
#   install-parent      the `./sb install` process (foreground or background).
#   migrate-subprocess  the `/sb migrate up` child only (leaves the parent alive).
#   install-tree        install-parent + migrate-subprocess together.
#
# ★★ IRON RULE — EVERY CALLER MUST HONOUR THIS ★★
#   Never remove a release file / release a stall unless this returned 0. A missed
#   kill means the target respawned or vanished before we could confirm; releasing
#   after a miss lets the still-live process finish and manufactures a FALSE terminal
#   (the 'completed' that isn't — the exact U1 failure). The call site is ALWAYS:
#
#       arc_kill_confirmed "$VM_NAME" <mode> || exit 1     # aborts loudly on a miss
#       remove_release_file_in_vm "$VM_NAME" "$RELEASE_FILE"   # ONLY reached on a confirmed kill
#
arc_kill_confirmed() {
    # shellcheck disable=SC2034  # vm kept for call-site signature parity (like pgrep_upgrade_service_parent); VM_EXEC targets the global VM_NAME
    local vm="$1" mode="$2" budget="${3:-30}"
    local pids=""
    case "$mode" in
        daemon-mainpid)
            local mp
            mp=$(VM_EXEC systemctl --user show "$ARC_UPGRADE_UNIT" --property=MainPID --value 2>/dev/null | tr -d ' \r\n' || echo "0")
            { [ -n "$mp" ] && [ "$mp" != "0" ]; } && pids="$mp"
            ;;
        install-parent)
            pids=$(VM_EXEC bash -c "pgrep -nf '[/]sb install' 2>/dev/null | head -1 || true" 2>/dev/null | tr -d ' \r\n')
            ;;
        migrate-subprocess)
            pids=$(VM_EXEC bash -c "pgrep -nf '[/]sb migrate up' 2>/dev/null | head -1 || true" 2>/dev/null | tr -d ' \r\n')
            ;;
        install-tree)
            local ip mp
            ip=$(VM_EXEC bash -c "pgrep -nf '[/]sb install' 2>/dev/null | head -1 || true" 2>/dev/null | tr -d ' \r\n')
            mp=$(VM_EXEC bash -c "pgrep -nf '[/]sb migrate up' 2>/dev/null | head -1 || true" 2>/dev/null | tr -d ' \r\n')
            pids=$(printf '%s\n%s\n' "$ip" "$mp" | grep -E '^[0-9]+$' | sort -u | tr '\n' ' ')
            ;;
        *)
            echo "✗ arc_kill_confirmed: unknown mode '$mode' (want daemon-mainpid|install-parent|migrate-subprocess|install-tree)" >&2
            return 1 ;;
    esac
    pids=$(echo "$pids" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')
    if [ -z "$pids" ]; then
        echo "✗ arc_kill_confirmed($mode): NO live target PID at kill time — the kill window was MISSED (target respawned/vanished). ABORT: releasing now would manufacture a false terminal (STATBUS-021)." >&2
        return 1
    fi
    echo "  arc_kill_confirmed($mode): SIGKILL fresh PID(s): $pids"
    VM_EXEC bash -c "kill -9 $pids 2>/dev/null || true"
    local start elapsed alive
    start=$(date +%s)
    while true; do
        alive=$(VM_EXEC bash -c "for p in $pids; do kill -0 \$p 2>/dev/null && printf '%s ' \$p; done" 2>/dev/null | tr -d '\r' | sed 's/ *$//')
        [ -z "$alive" ] && { echo "  ✓ kill CONFIRMED — target PID(s) gone: $pids"; return 0; }
        elapsed=$(( $(date +%s) - start ))
        if [ "$elapsed" -ge "$budget" ]; then
            echo "✗ arc_kill_confirmed($mode): PID(s) STILL ALIVE after ${budget}s: $alive — kill NOT confirmed. ABORT." >&2
            return 1
        fi
        sleep 2
    done
}

