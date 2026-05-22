#!/bin/bash
# data-helpers.sh — primitives that populate a freshly-installed VM with
# realistic data so failure-injection scenarios have something non-trivial
# to lose. Anchors the R5 catastrophic-loss detector + the R1 worker-
# contention path.
#
# The canonical population path is the demo dataset that ships in
# samples/demo/. Scenarios MUST NOT invent ad-hoc test data — drift
# between the harness dataset and the demo dataset is a maintenance
# trap. If a scenario needs richer data, extend samples/demo/, not the
# harness.
#
# Source order:
#   source lib/vm-bootstrap.sh    # for VM_EXEC + HARNESS_ROOT
#   source lib/data-helpers.sh
#   source lib/wedge-helpers.sh
#   source lib/assertions.sh

# ─────────────────────────────────────────────────────────────────────────
# populate_with_demo_data <vm_name>
#
# Runs samples/demo/import-demo-data.sh against an installed VM and
# blocks until every queued import_job row reaches a terminal state
# (finished or failed). The demo script enqueues four imports — legal
# units, formal establishments, informal establishments, legal
# relationships — and the worker drives them asynchronously.
#
# Operator-email contract: the demo script verifies a user exists in
# public.user before queueing any work. The harness's bootstrap seeds
# `test@statbus.org` via .users.yml; we use that email rather than
# inventing one. If a scenario provisions a different VM shape, override
# via DEMO_USER_EMAIL.
#
# Failure surfacing: any import_job ending in 'failed' is a real harness
# error (the demo dataset is supposed to be a known-good corpus). We
# emit the failed jobs' slugs + errors and return non-zero so the
# scenario's `set -e` bails.
#
# Timeout: imports usually finish in 30-60 s on a cx23. The poll budget
# defaults to 5 min — generous for slower hardware or under contention.
# Override via DEMO_IMPORT_MAX_WAIT_S.
#
# On success: echoes a single line with the resulting row counts so
# scenario logs document the populated state.
populate_with_demo_data() {
    local vm_name="$1"
    local user_email="${DEMO_USER_EMAIL:-test@statbus.org}"
    local max_wait_s="${DEMO_IMPORT_MAX_WAIT_S:-300}"

    echo "  [data] populating $vm_name with samples/demo dataset (USER_EMAIL=$user_email)"

    # Run the demo importer. The script lives at samples/demo/import-
    # demo-data.sh, which is part of the repo cloned into ~/statbus by
    # install_statbus_in_vm; no scp needed.
    if ! VM_EXEC bash -c "cd ~/statbus && USER_EMAIL='$user_email' bash samples/demo/import-demo-data.sh"; then
        echo "  ✗ import-demo-data.sh exited non-zero" >&2
        return 1
    fi

    # Poll for import_job terminal state. The 'state' column transitions
    # from queued/processing/etc to either 'finished' or 'failed'. We
    # block on count of non-terminal rows reaching 0.
    echo "  [data] waiting for import_job rows to reach terminal state (budget ${max_wait_s}s)"
    local elapsed=0
    local poll_s=5
    local non_terminal
    while [ "$elapsed" -lt "$max_wait_s" ]; do
        non_terminal=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM public.import_job WHERE state NOT IN ('finished','failed');\" | ./sb psql -t -A" 2>/dev/null | tr -d ' ' || echo "?")
        if [ "$non_terminal" = "0" ]; then
            break
        fi
        # Periodically surface the in-flight slugs so a stuck import is visible.
        if [ $((elapsed % 30)) -eq 0 ]; then
            local in_flight
            in_flight=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT string_agg(slug || '(' || state || ')', ', ') FROM public.import_job WHERE state NOT IN ('finished','failed');\" | ./sb psql -t -A" 2>/dev/null || echo "?")
            echo "    [data] in-flight (elapsed ${elapsed}s, non_terminal=$non_terminal): $in_flight"
        fi
        sleep "$poll_s"
        elapsed=$((elapsed + poll_s))
    done

    if [ "$non_terminal" != "0" ]; then
        echo "  ✗ import_job rows still non-terminal after ${max_wait_s}s — timeout" >&2
        VM_EXEC bash -c "cd ~/statbus && echo \"SELECT slug, state FROM public.import_job ORDER BY slug;\" | ./sb psql" >&2 || true
        return 1
    fi

    # Surface any 'failed' import_jobs as a real error — the demo dataset
    # is supposed to be a known-good corpus, so 'failed' means something
    # broke and we shouldn't pretend the scenario has clean baseline data.
    local failed
    failed=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM public.import_job WHERE state = 'failed';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' ' || echo "?")
    if [ "$failed" != "0" ]; then
        echo "  ✗ $failed import_job row(s) ended in 'failed' state" >&2
        VM_EXEC bash -c "cd ~/statbus && echo \"SELECT slug, state, error FROM public.import_job WHERE state = 'failed';\" | ./sb psql" >&2 || true
        return 1
    fi

    # Confirm populated and echo a one-line summary for the scenario log.
    local counts
    counts=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT 'statistical_unit=' || (SELECT count(*) FROM public.statistical_unit) || ' legal_unit=' || (SELECT count(*) FROM public.legal_unit) || ' establishment=' || (SELECT count(*) FROM public.establishment);\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r' || echo "?")
    echo "  ✓ demo data populated in ${elapsed}s — $counts"
    return 0
}
