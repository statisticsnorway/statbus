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
    local schema_sha ledger_sha data_sha
    # PGPASSWORD is REQUIRED: locally POSTGRES_ADMIN_USER=postgres connects via the
    # container's local-socket trust, but on the VM the admin user/password differ
    # and `docker exec` carries no PG env → pg_dump auth fails → empty output → the
    # guard below halts (correct, but a false failure). Pass the password explicitly.
    schema_sha=$(VM_EXEC bash -c 'cd ~/statbus && db=$(./sb dotenv -f .env get POSTGRES_APP_DB) && user=$(./sb dotenv -f .env get POSTGRES_ADMIN_USER) && pass=$(./sb dotenv -f .env get POSTGRES_ADMIN_PASSWORD) && c=$(docker ps --format "{{.Names}}" | grep -E -- "-db$" | head -1) && docker exec -e PGPASSWORD="$pass" "$c" pg_dump --schema-only --no-owner --no-privileges -U "$user" "$db" 2>/dev/null | grep -v "^--" | sed -e "s/[[:space:]]*$//" -e "/^$/d" | sha256sum | cut -d" " -f1' 2>/dev/null | tr -d ' \r\n')
    # CENTERPIECE GUARD: a silently-failed pg_dump / db-container discovery would
    # make schema_sha = sha256("") on BOTH captures → assert_fingerprint_matches
    # would pass VACUOUSLY (a false-green clean-slate proving nothing). Fail loud.
    # return 1 → the caller's `var=$(capture_db_fingerprint)` is non-zero under
    # set -e → the arc halts. (data-dim is guarded by assert_demo_data_present;
    # ledger always has the base migrations → schema is the only vacuous-risk dim.)
    local empty_sha="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    if [ -z "$schema_sha" ] || [ "$schema_sha" = "$empty_sha" ]; then
        echo "✗ capture_db_fingerprint: SCHEMA dim empty (pg_dump or db-container discovery failed) — refusing a vacuous fingerprint" >&2
        return 1
    fi
    ledger_sha=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT version::text || ',' || content_hash FROM db.migration ORDER BY version;\" | ./sb psql -t -A 2>/dev/null | sha256sum | cut -d' ' -f1" 2>/dev/null | tr -d ' \r\n')
    data_sha=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT md5(coalesce(string_agg(t::text, '|' ORDER BY t::text), '')) FROM public.legal_unit t UNION ALL SELECT md5(coalesce(string_agg(t::text, '|' ORDER BY t::text), '')) FROM public.establishment t;\" | ./sb psql -t -A 2>/dev/null | sha256sum | cut -d' ' -f1" 2>/dev/null | tr -d ' \r\n')
    echo "${schema_sha} ${ledger_sha} ${data_sha}"
}

# assert_fingerprint_matches <label> <baseline> — re-capture + compare byte-for-byte;
# report WHICH dim drifted on mismatch (the clean-slate centerpiece, STATBUS-071 d).
assert_fingerprint_matches() {
    local label="$1" baseline="$2" current
    current=$(capture_db_fingerprint)
    if [ "$current" != "$baseline" ]; then
        echo "✗ CLEAN-SLATE FINGERPRINT MISMATCH (${label})" >&2
        local b_s b_l b_d c_s c_l c_d
        read -r b_s b_l b_d <<< "$baseline"
        read -r c_s c_l c_d <<< "$current"
        [ "$b_s" = "$c_s" ] || echo "    SCHEMA differs: ${b_s:0:16}… → ${c_s:0:16}…" >&2
        [ "$b_l" = "$c_l" ] || echo "    LEDGER differs: ${b_l:0:16}… → ${c_l:0:16}…" >&2
        [ "$b_d" = "$c_d" ] || echo "    DATA   differs: ${b_d:0:16}… → ${c_d:0:16}…" >&2
        exit 1
    fi
    echo "  ✓ clean-slate fingerprint matches (${label})"
}
