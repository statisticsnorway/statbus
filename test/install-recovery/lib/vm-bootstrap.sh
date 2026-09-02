#!/bin/bash
# vm-bootstrap.sh — Hetzner Cloud bootstrap helper for install recovery tests.
#
# Provisions ephemeral Hetzner Cloud VMs (CX23, IPv4, hel1) for the per-scenario
# harness. Replaces the previous Multipass-on-macOS implementation, which kept
# breaking on vmnet bridge state (no recovery without `sudo reboot`).
#
# Sourced by test/install-recovery/scenarios/*.sh. Provides:
#
#   bootstrap_install_test_vm <vm_name> [install_version]
#       Provision a fresh Hetzner CX23 VM, run the project hardening script,
#       create the statbus user, set up linger so systemctl --user works.
#       Sets globals VM_IP, VM_EXEC, STATBUS_UID.
#
#       install_version: empty → uses locally-built `sb` binary
#                        v2026.05.0-rc.X → downloaded inside the VM
#
#   install_statbus_in_vm <vm_name> [install_version]
#       Run `./sb install` inside an already-bootstrapped VM. Returns the
#       install command's exit status.
#
#   reset_vm_state <vm_name>
#       Reimage the existing VM via `hcloud server rebuild` (~30s, same IP)
#       and re-run hardening. Use between scenarios in approach-B to amortise
#       a single 1-hour billing window across the whole harness run. State
#       reset is at the OS-disk level — no leftover postgres/docker state.
#
#   cleanup_vm <vm_name>
#       Delete the VM. KEEP_VM=1 leaves it running (€0.0072/hr) for debugging.
#       STATBUS-207: refuses to delete unless THIS run actually created the
#       VM (VM_OWNED_BY_THIS_RUN) — a cross-run name collision (two
#       workflows deriving the same VM name from the same scenario slug,
#       STATBUS-208) must never let one job's cleanup delete another job's
#       live VM. A caller whose bootstrap hit the refuse-on-existing check
#       never sets the flag, so its EXIT-trap cleanup_vm call becomes a
#       no-op that logs the foreign ownership instead of deleting.
#
#   $VM_EXEC            ssh prefix to run as the statbus user inside the VM.
#                       Sources .profile so XDG_RUNTIME_DIR is set for
#                       systemctl --user.
#   $VM_IP              VM's public IPv4 address.
#   $STATBUS_UID        Numeric UID of the statbus user inside the VM.
#   $VM_OWNED_BY_THIS_RUN  Set to 1 by bootstrap_install_test_vm immediately
#                       after `hcloud server create` succeeds. cleanup_vm's
#                       ownership guard (STATBUS-207).
#
# Cost model: one CX23 in hel1 = €0.0064/hr + €0.0008/hr for primary IPv4 =
# €0.0072/hr. Hetzner bills hourly with 1-hour minimum (no per-minute), so
# the cost-optimal pattern is one VM per harness run with reset_vm_state
# between scenarios. KEEP_VM=1 charges €0.17/day if you forget to clean up.
#
# Safety: all VM operations refuse names not starting with $HCLOUD_NAME_PREFIX
# (default "statbus-recovery-"). This protects the production niue VM, which
# lives in the same Hetzner project as the test VMs.

set -euo pipefail
# Propagate ERR trap into functions and subshells sourced from this lib.
set -E
# Emit a one-line diagnostic whenever set -e fires so failure logs are
# self-explaining.  $LINENO and $BASH_COMMAND are correct in ERR context;
# they would be wrong inside the EXIT trap (which would report the trap's
# own line, not the failing command's line).
trap 'rc=$?; echo "✗ harness failure: rc=$rc at ${BASH_SOURCE[0]##*/}:${LINENO}: ${BASH_COMMAND}" >&2' ERR

HARNESS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$HARNESS_LIB_DIR/../../.." && pwd)"
source "$HARNESS_LIB_DIR/watch-decisions.sh"

# Load HCLOUD_TOKEN from .env.credentials if not in env.
if [ -z "${HCLOUD_TOKEN:-}" ]; then
    if [ -f "$HARNESS_ROOT/.env.credentials" ]; then
        # shellcheck disable=SC2046
        export $(grep '^HCLOUD_TOKEN=' "$HARNESS_ROOT/.env.credentials" | awk 'NR==1')
    fi
fi
if [ -z "${HCLOUD_TOKEN:-}" ]; then
    echo "ERROR: HCLOUD_TOKEN not set; expected in env or .env.credentials" >&2
    return 1 2>/dev/null || exit 1
fi

HCLOUD_SERVER_TYPE="${HCLOUD_SERVER_TYPE:-cx23}"
HCLOUD_LOCATION="${HCLOUD_LOCATION:-hel1}"
HCLOUD_IMAGE="${HCLOUD_IMAGE:-ubuntu-24.04}"
HCLOUD_SSH_KEY="${HCLOUD_SSH_KEY:-jorgen@veridit.no}"
HCLOUD_NAME_PREFIX="${HCLOUD_NAME_PREFIX:-statbus-recovery-}"

mkdir -p "$HARNESS_ROOT/tmp"

# Shared ssh options for ephemeral test VMs. Host-key verification is
# explicitly OFF — these VMs live for minutes and Hetzner recycles IPv4s
# across instances, so accept-new fails the first time an IP gets reused.
# Threat model: MITM on first connect to a freshly-provisioned Hetzner VM
# inside Hetzner's hel1 datacenter. Negligible for a test harness whose
# secrets are confined to a throwaway VM that gets deleted on completion.
#
# Keepalives matter: `./sb install` can pull GB of docker images with no
# stdout for minutes at a time. Without keepalives, intermediate NAT /
# firewall middleboxes drop the TCP connection, sshd back-end keeps
# running on the VM, and we get exit 255 with a partial transcript.
SSH_OPTS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=10
    -o LogLevel=ERROR
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=10
    -o ControlMaster=no
    -o ControlPath=none
)

_check_name_safety() {
    local name="$1"
    case "$name" in
        "$HCLOUD_NAME_PREFIX"*) return 0 ;;
        *)
            echo "REFUSE: VM name '$name' does not start with prefix '$HCLOUD_NAME_PREFIX'." >&2
            echo "       Safety guard prevents accidental deletion of production VMs (niue etc) in the same Hetzner project." >&2
            return 1
            ;;
    esac
}

# _run_suffix prints a short (<=8 char) string that's unique per concurrent
# invocation — STATBUS-208 defect A: run-scoped VM names. CI: the last 8
# characters of GITHUB_RUN_ID, exported by GitHub Actions to every job step
# and distinct per workflow RUN (two runs of the SAME workflow, or two
# DIFFERENT workflows firing off the same tag push, never share one — this
# is what makes statbus-recovery-0-happy-install collide today between
# test-install.yaml and install-recovery-harness.yaml). Local (no
# GITHUB_RUN_ID): this process's PID — unique per concurrently-running
# dev.sh invocation on one machine, which is the only local collision that
# matters (a single developer isn't racing a concurrent CI fleet).
_run_suffix() {
    if [ -n "${GITHUB_RUN_ID:-}" ]; then
        printf '%s' "${GITHUB_RUN_ID: -8}"
    else
        printf '%s' "$$"
    fi
}

# _suffixed_vm_name prints "<base_name>-<suffix>", truncating the MIDDLE of
# base_name (never its statbus-recovery-/statbus-arc- prefix, never the
# suffix) if the combined length would exceed Hetzner's 63-char server-name
# limit. Today's longest real slugs (34 chars, arcs/; 33 chars,
# scenarios/) plus an 8-char suffix never actually trip this (max 55/59
# chars observed) — the guard exists so a FUTURE longer scenario/arc name
# fails safely (a valid, if less descriptive, truncated name) instead of
# hcloud silently rejecting or mangling an over-length name in a way this
# harness's own bookkeeping (VM_NAME, the refuse-on-existing check,
# cleanup) would then disagree with.
_suffixed_vm_name() {
    local base_name="$1" suffix="$2"
    local full="${base_name}-${suffix}"
    local limit=63
    if [ "${#full}" -le "$limit" ]; then
        printf '%s' "$full"
        return 0
    fi
    local budget=$(( limit - ${#suffix} - 1 ))
    local head_len=$(( (budget + 1) / 2 ))
    local tail_len=$(( budget - head_len ))
    printf '%s%s-%s' "${base_name:0:head_len}" "${base_name: -tail_len}" "$suffix"
}

# _hcloud_server_ip prints vm_name's public IPv4 on success. On failure it
# prints an explicit diagnostic naming hcloud's OWN error text and returns
# non-zero — STATBUS-207: hcloud's stderr already reaches the raw CI log
# unredirected today, but unlabeled and disconnected from the harness's own
# "✗ harness failure: rc=N at FILE:LINE: COMMAND" ERR-trap line; a reader
# scanning only the harness-failure lines (or a filtered/truncated log
# view) can miss it entirely. Every authoritative (non-best-effort) caller
# of `hcloud server ip` goes through this so a failure is self-explaining
# without needing the full raw log — the probe-shape discipline the
# architect's ruling names (README §probes): capture the reason, never
# swallow it. Best-effort cleanup/probe call sites that deliberately
# discard hcloud's stderr (2>/dev/null, optional VM existence checks) are
# a different, intentionally-silent use case and are NOT routed through
# this helper.
_hcloud_server_ip() {
    local vm_name="$1"
    local ip stderr_file rc
    stderr_file=$(mktemp)
    # $? must be captured as the FIRST statement of the else branch, not
    # after the if/fi construct — POSIX defines an if/then with no else
    # branch taken as exiting 0 regardless of the tested command's real
    # status (verified empirically; a genuine gotcha, not an assumption).
    if ip=$(hcloud server ip "$vm_name" 2>"$stderr_file"); then
        rm -f "$stderr_file"
        echo "$ip"
        return 0
    else
        rc=$?
        echo "ERROR: hcloud server ip failed for VM '$vm_name' (rc=$rc): $(cat "$stderr_file")" >&2
        rm -f "$stderr_file"
        return "$rc"
    fi
}

# _assert_head_still_on_origin — STATBUS-184: re-verify HEAD is STILL on origin
# immediately before it is captured for the VM's --commit pin. run.sh's own
# preflight_head_on_origin checks this ONCE at the very top of a run, before
# any VM is provisioned — but VM provisioning + any earlier scenarios in a
# multi-scenario run take many minutes, during which a busy team session's
# Backlog.md auto-commits (every board edit creates one) can advance local
# HEAD past what that top-level check saw (the exact race two burned VM runs
# demonstrated on 4-flagless-selfheal-at-target: run 1's local HEAD was a
# just-landed board-edit commit; run 2's local HEAD moved again between the
# push and this capture point). This is the SAME check, repeated at the
# actual point of no return — right before `git rev-parse HEAD` gets baked
# into what the VM checks out. Deliberately NOT shared code with run.sh's own
# copy: run.sh has zero lib dependencies by design (kept lightweight for
# --list/--print-selected), so duplicating this ~20-line check here is
# cheaper than introducing a new source dependency into the dispatcher for it.
_assert_head_still_on_origin() {
    local sha
    sha="$(git -C "$HARNESS_ROOT" rev-parse HEAD 2>/dev/null)" || {
        echo "WARN: could not resolve HEAD (git rev-parse) — skipping the origin re-check" >&2
        return 0
    }
    if git -C "$HARNESS_ROOT" branch -r --contains "$sha" 2>/dev/null | grep '^ *origin/' >/dev/null; then
        return 0
    fi
    local remote_refs
    if remote_refs="$(GIT_TERMINAL_PROMPT=0 git -C "$HARNESS_ROOT" ls-remote origin 2>/dev/null)"; then
        if printf '%s\n' "$remote_refs" | grep "^${sha}[[:space:]]" >/dev/null; then
            return 0
        fi
    else
        echo "WARN: could not reach origin (git ls-remote) to verify HEAD is pushed — proceeding; a genuinely-unpushed commit still fails VM-side as before." >&2
        return 0
    fi
    echo "" >&2
    echo "════════════════════════════════════════════════════════════════" >&2
    echo "  REFUSING: HEAD ($sha) is not on origin — the VM cannot resolve it." >&2
    echo "════════════════════════════════════════════════════════════════" >&2
    echo "  HEAD moved past what run.sh's top-level preflight checked (STATBUS-184 —" >&2
    echo "  a busy session's Backlog.md auto-commits can land during VM provisioning" >&2
    echo "  or an earlier scenario's run time). Push, then re-run:" >&2
    echo "      git push" >&2
    echo "════════════════════════════════════════════════════════════════" >&2
    exit 3
}

_wait_for_ssh() {
    local ip="$1" max="${2:-90}"
    local i
    for i in $(seq 1 "$max"); do
        if ssh "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=2 root@"$ip" echo ok 2>/dev/null | grep "^ok$" >/dev/null; then
            echo "  SSH up after ${i}s"
            return 0
        fi
        sleep 1
    done
    echo "  SSH did not come up within ${max}s" >&2
    return 1
}

# _watch_provider_state VM_NAME [DEADLINE_EPOCH]
# Prints alive, missing, or unknown. Provider reads are retried so a transient
# hcloud/API failure is never mislabeled as a deleted VM.
_watch_provider_state() {
    local vm_name="$1" deadline_epoch="${2:-0}" attempt output rc
    local now remaining describe_timeout sleep_secs
    if [ -z "$vm_name" ]; then
        printf '%s\n' unknown
        return 0
    fi
    for attempt in 1 2 3; do
        describe_timeout=15
        if [ "$deadline_epoch" -gt 0 ]; then
            now=$(date +%s)
            remaining=$((deadline_epoch - now))
            if [ "$remaining" -le 0 ]; then
                printf '%s\n' unknown
                return 0
            fi
            [ "$remaining" -lt "$describe_timeout" ] && describe_timeout="$remaining"
        fi
        if output=$(timeout "$describe_timeout" hcloud server describe "$vm_name" -o format='{{.Status}}' 2>&1); then
            printf '%s\n' alive
            return 0
        else
            rc=$?
        fi
        if printf '%s\n' "$output" | grep -Eqi 'not found|does not exist'; then
            printf '%s\n' missing
            return 0
        fi
        echo "  provider retry ${attempt}/3 for '$vm_name' after rc=$rc: $output" >&2
        if [ "$attempt" -lt 3 ]; then
            sleep_secs=5
            if [ "$deadline_epoch" -gt 0 ]; then
                now=$(date +%s)
                remaining=$((deadline_epoch - now))
                [ "$remaining" -le 0 ] && continue
                [ "$remaining" -lt "$sleep_secs" ] && sleep_secs="$remaining"
            fi
            sleep "$sleep_secs"
        fi
    done
    printf '%s\n' unknown
}

# _watch_ssh_probe IP VM_NAME STAGE REMOTE_COMMAND [DEADLINE_EPOCH]
#
# Runs one controller read with a hard wall-clock bound. OpenSSH rc=255 and
# GNU timeout rc=124 reconnect to the SAME tmux session/log position. Output is
# returned through WATCH_SSH_OUTPUT so callers do not put a potentially wedged
# ssh process inside an unbounded command substitution.
_watch_ssh_probe() {
    local ip="$1" vm_name="$2" stage="$3" remote_command="$4" deadline_epoch="${5:-0}"
    local max_attempts="${LONG_CMD_SSH_RECONNECT_ATTEMPTS:-5}"
    local retry_secs="${LONG_CMD_SSH_RECONNECT_DELAY_S:-30}"
    local probe_timeout="${LONG_CMD_SSH_PROBE_TIMEOUT_S:-20}"
    local attempt rc class provider_state decision output_file error_file
    local now remaining effective_timeout sleep_secs
    output_file=$(mktemp)
    error_file=$(mktemp)
    WATCH_SSH_OUTPUT=""

    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        now=$(date +%s)
        if [ "$deadline_epoch" -gt 0 ] && [ "$now" -ge "$deadline_epoch" ]; then
            echo "  controller watch deadline reached while reconnecting [$stage]" >&2
            rm -f "$output_file" "$error_file"
            return 252
        fi
        effective_timeout="$probe_timeout"
        if [ "$deadline_epoch" -gt 0 ]; then
            remaining=$((deadline_epoch - now))
            [ "$remaining" -lt "$effective_timeout" ] && effective_timeout="$remaining"
        fi
        : > "$output_file"
        : > "$error_file"
        if timeout "$effective_timeout" ssh "${SSH_OPTS[@]}" root@"$ip" "$remote_command" \
            >"$output_file" 2>"$error_file"
        then
            WATCH_SSH_OUTPUT=$(cat "$output_file")
            rm -f "$output_file" "$error_file"
            return 0
        else
            rc=$?
        fi

        class=$(watch_ssh_rc_class "$rc")
        if [ "$class" = fatal ]; then
            echo "  FAILURE CLASS: controller-probe-failed[$stage] rc=$rc" >&2
            sed 's/^/    /' "$error_file" >&2 || true
            rm -f "$output_file" "$error_file"
            return 250
        fi

        provider_state=unknown
        if [ "$attempt" -eq "$max_attempts" ]; then
            now=$(date +%s)
            if [ "$deadline_epoch" -gt 0 ] && [ "$now" -ge "$deadline_epoch" ]; then
                echo "  controller watch deadline reached after SSH reconnect [$stage]" >&2
                rm -f "$output_file" "$error_file"
                return 252
            fi
            provider_state=$(_watch_provider_state "$vm_name" "$deadline_epoch")
        fi
        decision=$(watch_reconnect_decision "$rc" "$attempt" "$max_attempts" "$provider_state")
        echo "  SSH reconnect [$stage] attempt ${attempt}/${max_attempts}: rc=$rc; detached tmux survives; log offset preserved" >&2
        case "$decision" in
            retry)
                sleep_secs="$retry_secs"
                if [ "$deadline_epoch" -gt 0 ]; then
                    now=$(date +%s)
                    remaining=$((deadline_epoch - now))
                    if [ "$remaining" -le 0 ]; then
                        echo "  controller watch deadline reached before SSH reconnect [$stage]" >&2
                        rm -f "$output_file" "$error_file"
                        return 252
                    fi
                    [ "$remaining" -lt "$sleep_secs" ] && sleep_secs="$remaining"
                fi
                sleep "$sleep_secs"
                ;;
            resume)
                echo "  SSH reconnect window exhausted for [$stage], but provider state is $provider_state; resuming the outer watch without losing position" >&2
                sed 's/^/    /' "$error_file" >&2 || true
                rm -f "$output_file" "$error_file"
                return 75
                ;;
            vm-gone)
                echo "  FAILURE CLASS: vm-gone[$stage] — hcloud confirms '$vm_name' is absent" >&2
                sed 's/^/    /' "$error_file" >&2 || true
                rm -f "$output_file" "$error_file"
                return 251
                ;;
            *)
                echo "  FAILURE CLASS: controller-probe-failed[$stage] rc=$rc" >&2
                sed 's/^/    /' "$error_file" >&2 || true
                rm -f "$output_file" "$error_file"
                return 250
                ;;
        esac
    done
}

# _dump_long_stage_diagnostics IP VM_NAME SESSION FAILURE_CLASS
# Captures the evidence the rc.03 smoke lost, before the scenario EXIT trap can
# reap the VM. Every remote subsection is failure-tolerant so one missing source
# does not suppress the others.
_dump_long_stage_diagnostics() {
    local ip="$1" vm_name="$2" session="$3" failure_class="$4"
    echo "  ══ long-stage forensics: ${failure_class}[${session}] (before teardown) ══"
    echo "  -- provider state --"
    timeout 15 hcloud server describe "$vm_name" 2>&1 || echo "    hcloud describe unavailable"
    echo "  -- in-VM evidence --"
    if ! timeout 45 ssh "${SSH_OPTS[@]}" root@"$ip" "
        echo '--- tmux capture-pane (${session}, last 200 lines) ---'
        sudo -u statbus tmux capture-pane -p -S -200 -t '${session}' 2>&1 || true
        echo '--- /tmp/${session}.log (tail -100) ---'
        tail -100 '/tmp/${session}.log' 2>&1 || true
        echo '--- journalctl for statbus user units (last 200) ---'
        uid=\$(id -u statbus 2>/dev/null || true)
        if [ -n \"\$uid\" ]; then
            sudo -u statbus env XDG_RUNTIME_DIR=\"/run/user/\$uid\" \
                journalctl --user --no-pager -n 200 --unit='statbus*' 2>&1 || \
                journalctl --no-pager -n 200 _UID=\"\$uid\" 2>&1 || true
        else
            echo 'statbus user is absent'
        fi
        echo '--- docker ps -a --no-trunc ---'
        docker ps -a --no-trunc 2>&1 || true
    " 2>&1
    then
        echo "    in-VM evidence unavailable after 45s"
    fi
    echo "  ══ end long-stage forensics ══"
}

# Run a long shell command on the VM inside a detached tmux session, then
# poll for completion via reconnecting ssh. Survives mobile/flaky links: an
# rc=255 reconnects to the same logfile offset instead of killing the stage.
# The bash command itself runs as the statbus user.
#
# Usage:
#   _run_long_via_tmux <ip> <session-name> <bash-command> [vm-name]
# Side effects:
#   /tmp/<session>.log   — full stdout+stderr
#   /tmp/<session>.exit  — exit code of the bash command (written after)
# Returns:
#   the bash command's exit code, 253 for no-progress stall, 254 for overall
#   timeout, 251 for provider-confirmed VM loss.
#
# Tunable: LONG_CMD_MAX_MIN (default 45) — overall time budget in minutes.
_run_long_via_tmux() {
    local ip="$1" session="$2" cmd="$3" vm_name="${4:-}"
    local max_min="${LONG_CMD_MAX_MIN:-45}"
    local poll_secs="${LONG_CMD_POLL_SECS:-15}"
    local no_progress_secs="${LONG_CMD_NO_PROGRESS_SECS:-300}"
    local max_iter=$(( max_min * 60 / poll_secs ))

    # Ensure tmux is installed (idempotent — installed by hardening normally).
    timeout 60 ssh "${SSH_OPTS[@]}" root@"$ip" \
        'command -v tmux >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y tmux >/dev/null 2>&1' \
        || true

    # Launch the command in a detached tmux session running as statbus.
    # Wrap with exit-code capture: bash -c '<cmd>; echo $? > /tmp/<session>.exit'
    # The outer redirection > /tmp/<session>.log captures everything.
    #
    # GIT_TERMINAL_PROMPT=0: tmux gives the stage a tty, so a git that receives
    # a transient GitHub 401 on an anonymous fetch PROMPTS for a username and
    # blocks forever (rc.04 first live watchdog catch: v2026.08.1's best-effort
    # `git ls-remote` in configureDeployFetch hung at 'Username for
    # https://github.com:'). These stages are non-interactive by construction —
    # any prompt is a hang. Without a tty git already fails fast, so this only
    # restores the no-tty behavior the product paths get from systemd/ssh.
    timeout 60 ssh "${SSH_OPTS[@]}" root@"$ip" "
        rm -f /tmp/${session}.exit /tmp/${session}.log
        sudo -u statbus tmux new-session -d -s ${session} \\
            'bash -lc \"export GIT_TERMINAL_PROMPT=0; ( ${cmd} ) > /tmp/${session}.log 2>&1; echo \\\$? > /tmp/${session}.exit\"'
    " || {
        echo "  ERROR: could not start tmux session ${session} on $ip" >&2
        return 254
    }

    # Poll for completion. STATBUS-345 named the component that failed the
    # actionable-fail-fast test: this CONTROLLER's synchronous `cur_lines=$(ssh
    # ... wc -l | tr)` read had neither a per-probe timeout nor a no-progress
    # deadline. A live SSH connection with a wedged remote read still answers
    # OpenSSH keepalives, so it sat inside that one command substitution for 57
    # silent minutes until GitHub killed the job. Every read below is now bounded,
    # rc=255 reconnects, and five minutes without a new tailed line dumps evidence
    # and fails with a stage-named class.
    local i seen_lines=0 last_progress now progress_decision started_at overall_deadline watch_deadline
    local snapshot_state="running" cur_lines=0 remote_exit="" completed=0 probe_rc
    local snapshot_command tail_command sleep_secs remaining
    started_at=$(date +%s)
    last_progress="$started_at"
    overall_deadline=$((started_at + max_min * 60))
    for ((i = 0; i < max_iter; i++)); do
        now=$(date +%s)
        if [ "$now" -ge "$overall_deadline" ]; then
            echo "  FAILURE CLASS: overall-timeout[$session] after ${max_min}min" >&2
            _dump_long_stage_diagnostics "$ip" "$vm_name" "$session" overall-timeout
            return 254
        fi
        watch_deadline=$((last_progress + no_progress_secs))
        [ "$overall_deadline" -lt "$watch_deadline" ] && watch_deadline="$overall_deadline"
        snapshot_command="lines=\$(wc -l < '/tmp/${session}.log' 2>/dev/null || printf 0); if [ -f '/tmp/${session}.exit' ]; then code=\$(cat '/tmp/${session}.exit'); printf 'done %s %s\\n' \"\$code\" \"\$lines\"; else printf 'running %s\\n' \"\$lines\"; fi"
        if _watch_ssh_probe "$ip" "$vm_name" "$session" "$snapshot_command" "$watch_deadline"; then
            # shellcheck disable=SC2086  # intentional tokenization of protocol fields
            set -- $WATCH_SSH_OUTPUT
            snapshot_state="${1:-invalid}"
            if [ "$snapshot_state" = "done" ]; then
                remote_exit="${2:-}"
                cur_lines="${3:-}"
            else
                cur_lines="${2:-}"
            fi
            case "$cur_lines" in
                ''|*[!0-9]*)
                    echo "  FAILURE CLASS: controller-protocol-failed[$session] invalid line count: '$WATCH_SSH_OUTPUT'" >&2
                    _dump_long_stage_diagnostics "$ip" "$vm_name" "$session" controller-protocol-failed
                    return 250
                    ;;
            esac
        else
            probe_rc=$?
            case "$probe_rc" in
                75) snapshot_state=running; cur_lines="$seen_lines" ;;
                251) return 251 ;;
                252)
                    now=$(date +%s)
                    if [ "$now" -ge $((last_progress + no_progress_secs)) ]; then
                        echo "  FAILURE CLASS: stalled-stage[$session] — zero new tailed log lines for ${no_progress_secs}s" >&2
                        _dump_long_stage_diagnostics "$ip" "$vm_name" "$session" stalled-stage
                        return 253
                    fi
                    echo "  FAILURE CLASS: overall-timeout[$session] after ${max_min}min" >&2
                    _dump_long_stage_diagnostics "$ip" "$vm_name" "$session" overall-timeout
                    return 254
                    ;;
                *)
                    _dump_long_stage_diagnostics "$ip" "$vm_name" "$session" controller-probe-failed
                    return "$probe_rc"
                    ;;
            esac
        fi

        if [ "$cur_lines" -gt "$seen_lines" ]; then
            # Read from the exact prior offset. `tail -n DELTA` could skip lines if
            # the remote log grows between the snapshot and this read.
            tail_command="tail -n +$((seen_lines + 1)) '/tmp/${session}.log' | head -n $((cur_lines - seen_lines))"
            if _watch_ssh_probe "$ip" "$vm_name" "$session" "$tail_command" "$watch_deadline"; then
                [ -n "$WATCH_SSH_OUTPUT" ] && printf '%s\n' "$WATCH_SSH_OUTPUT"
                seen_lines="$cur_lines"
                last_progress=$(date +%s)
            else
                probe_rc=$?
                case "$probe_rc" in
                    75) ;;
                    251) return 251 ;;
                    252)
                        now=$(date +%s)
                        if [ "$now" -ge $((last_progress + no_progress_secs)) ]; then
                            echo "  FAILURE CLASS: stalled-stage[$session] — could not tail new log lines inside ${no_progress_secs}s" >&2
                            _dump_long_stage_diagnostics "$ip" "$vm_name" "$session" stalled-stage
                            return 253
                        fi
                        echo "  FAILURE CLASS: overall-timeout[$session] after ${max_min}min" >&2
                        _dump_long_stage_diagnostics "$ip" "$vm_name" "$session" overall-timeout
                        return 254
                        ;;
                    *)
                        _dump_long_stage_diagnostics "$ip" "$vm_name" "$session" controller-probe-failed
                        return "$probe_rc"
                        ;;
                esac
            fi
        fi

        if [ "$snapshot_state" = "done" ] && [ "$seen_lines" -ge "$cur_lines" ]; then
            completed=1
            break
        fi

        now=$(date +%s)
        progress_decision=$(watch_progress_decision "$seen_lines" "$seen_lines" "$now" "$last_progress" "$no_progress_secs")
        if [ "$progress_decision" = stalled ]; then
            echo "  FAILURE CLASS: stalled-stage[$session] — zero new tailed log lines for ${no_progress_secs}s" >&2
            _dump_long_stage_diagnostics "$ip" "$vm_name" "$session" stalled-stage
            return 253
        fi
        sleep_secs="$poll_secs"
        watch_deadline=$((last_progress + no_progress_secs))
        [ "$overall_deadline" -lt "$watch_deadline" ] && watch_deadline="$overall_deadline"
        remaining=$((watch_deadline - now))
        [ "$remaining" -lt "$sleep_secs" ] && sleep_secs="$remaining"
        [ "$sleep_secs" -gt 0 ] && sleep "$sleep_secs"
    done

    if [ "$completed" -ne 1 ]; then
        echo "  FAILURE CLASS: overall-timeout[$session] after ${max_min}min" >&2
        _dump_long_stage_diagnostics "$ip" "$vm_name" "$session" overall-timeout
        return 254
    fi

    case "$remote_exit" in
        ''|*[!0-9]*)
            echo "  FAILURE CLASS: controller-protocol-failed[$session] invalid exit code: '$remote_exit'" >&2
            _dump_long_stage_diagnostics "$ip" "$vm_name" "$session" controller-protocol-failed
            return 250
            ;;
    esac
    if [ "$remote_exit" -ne 0 ]; then
        echo "  FAILURE CLASS: remote-stage-failed[$session] exit=$remote_exit" >&2
    fi
    return "$remote_exit"
}

# _dump_bootstrap_failure_diagnostics IP VM_NAME
# STATBUS-227 AC#4 / doc-032 "stop guessing": called from _apply_hardening's
# two failure paths (HARDENING TIMEOUT and HARDENING FAILED), BEFORE the
# caller's EXIT trap reaps the VM. The rc.03 triage found a real gap: "one
# SSH read returned nothing" is equally consistent with "the machine died"
# and "the machine was too busy to answer inside our read timeout" — two
# different remedies, and nobody had probed which. This closes that gap by
# capturing, while the VM still (might) exist:
#   - a reachability probe: ping + a FRESH ssh connection (not reusing the
#     one that just failed) + Hetzner's own power-state view — a box that
#     answers a NEW connection was never dead;
#   - dmesg / journalctl -k (the OOM killer names its victim) + free -m +
#     df -h, gated on that fresh SSH having worked;
#   - the provider console, AS FAR AS HETZNER'S API ALLOWS: unlike AWS/
#     DigitalOcean, Hetzner Cloud has no text console-log endpoint — only
#     an interactive VNC WebSocket (`hcloud server request-console`). We
#     request one and log the (short-lived) URL for manual post-mortem
#     when KEEP_VM_ON_FAILURE=1 keeps the box alive; an automated TEXT
#     capture of console output is not something this provider's API
#     supports. Flagged here rather than silently doing less than doc-032
#     asked for.
# Every capture is individually timeout-bounded and failure-tolerant
# (`|| ...`) — a genuinely dead box must not hang the forensics, and one
# failed capture must not skip the rest. All output goes to stderr so it
# lands in the same job log the "HARDENING FAILED"/"TIMEOUT" line does.
_dump_bootstrap_failure_diagnostics() {
    local ip="$1" vm_name="$2"
    echo "  ══ bootstrap-failure forensics (STATBUS-227/doc-032, before teardown) ══" >&2

    echo "  -- reachability: ping --" >&2
    timeout 15 ping -c 3 -W 3 "$ip" >&2 || echo "    ping: unreachable/failed" >&2

    echo "  -- reachability: FRESH ssh connection (not reusing the one that failed) --" >&2
    # shellcheck disable=SC2016  # single-quoted on purpose: $(...) must expand
    # remotely on the VM, not locally on the runner.
    if timeout 15 ssh "${SSH_OPTS[@]}" -o ConnectTimeout=10 root@"$ip" \
        'echo "fresh SSH OK; uptime: $(uptime -p 2>/dev/null || true)"' >&2
    then
        echo "    → answered a NEW connection: NOT dead — only unresponsive to the prior read (or recovered since)." >&2
    else
        echo "    → did not answer a fresh SSH connection either." >&2
    fi

    echo "  -- provider power state (hcloud server describe) --" >&2
    timeout 15 hcloud server describe "$vm_name" -o format='{{.Status}}' >&2 || echo "    hcloud describe: failed" >&2

    echo "  -- dmesg / journalctl -k / free -m / df -h (needs the fresh SSH above to have worked) --" >&2
    timeout 30 ssh "${SSH_OPTS[@]}" -o ConnectTimeout=10 root@"$ip" '
        echo "---dmesg (tail -100)---"; dmesg 2>/dev/null | tail -100
        echo "---journalctl -k (tail -100)---"; journalctl -k --no-pager 2>/dev/null | tail -100
        echo "---free -m---"; free -m
        echo "---df -h---"; df -h
    ' >&2 || echo "    in-VM diagnostics unreachable — consistent with a genuinely dead/wedged box." >&2

    echo "  -- provider console --" >&2
    echo "    Hetzner Cloud has NO text console-log API (unlike AWS/DigitalOcean) — only an" >&2
    echo "    interactive VNC WebSocket session. Requesting one for manual post-mortem (the" >&2
    echo "    URL/token below is short-lived, and only reachable at all if KEEP_VM_ON_FAILURE=1" >&2
    echo "    kept the box alive past this run)." >&2
    timeout 15 hcloud server request-console "$vm_name" >&2 || echo "    request-console: failed" >&2

    echo "  ══ end bootstrap-failure forensics ══" >&2
}

# Run the project hardening + statbus user setup on a freshly-booted VM.
# Idempotent — safe to call again after a rebuild.
_apply_hardening() {
    local ip="$1" sb_binary="${2:-}"

    echo "  waiting for cloud-init..."
    ssh "${SSH_OPTS[@]}" root@"$ip" 'cloud-init status --wait' 2>/dev/null || true

    echo "  transferring setup files..."
    [ -n "$sb_binary" ] && {
        scp -O "${SSH_OPTS[@]}" "$sb_binary" root@"$ip":/tmp/sb
        ssh "${SSH_OPTS[@]}" root@"$ip" 'chmod 0755 /tmp/sb'
    }
    scp -O "${SSH_OPTS[@]}" "$HARNESS_ROOT/ops/setup-ubuntu-lts-24.sh" root@"$ip":/tmp/setup.sh
    ssh "${SSH_OPTS[@]}" root@"$ip" 'chmod 0755 /tmp/setup.sh'

    local env_config_file users_file
    env_config_file=$(mktemp)
    cat > "$env_config_file" << 'ENVCONFIG'
DEPLOYMENT_SLOT_NAME=Install Test
DEPLOYMENT_SLOT_CODE=test
DEPLOYMENT_SLOT_PORT_OFFSET=1
CADDY_DEPLOYMENT_MODE=development
SITE_DOMAIN=statbus-test.local
STATBUS_URL=https://statbus-test.local
BROWSER_REST_URL=https://statbus-test.local
SERVER_REST_URL=http://proxy:80
DEBUG=false
PUBLIC_DEBUG=false
ENVCONFIG

    # STATBUS-297 (fixture-era-accuracy ruling): a harness must construct
    # states history could have produced. UPGRADE_ROLE is a STATBUS-254
    # (733b0df4d) concept — writing it onto a box about to install a
    # PRE-254 era (BASE_SHA not a descendant of 733b0df4d, e.g.
    # cross-version-rename-handoff's pinned 730b5001c) builds a box that
    # never existed: that era's own `./sb config generate` still SEEDS
    # UPGRADE_CHANNEL, so the box ends up with BOTH keys and 254's own
    # loud hand-set-channel guard refuses — a harness artifact, not a real
    # bug (the collision behind three reds and two wrong attributions at
    # rc.11/14/15, STATBUS-297). Gate on BASE_SHA (the global every arc
    # sets before calling bootstrap_install_test_vm/arc_prepare_box, per
    # arc-helpers.sh's own contract) being a descendant of 733b0df4d: a
    # pre-254 box gets no role key at all, and its own era's binary seeds
    # the channel exactly as history did; every other arc's BASE_SHA is the
    # run's own current commit (always post-254), so this is a no-op there.
    # BASE_SHA unset falls back to the pre-297 unconditional write — the
    # only callers of this function are arc_prepare_box/reset_vm_state,
    # both downstream of an arc script that has already required BASE_SHA.
    # STATBUS-307 INVERTS THIS RULE RATHER THAN RETIRING IT. There are now THREE
    # eras, and the harness must write what each era's box actually carried:
    #
    #   pre-254   → NOTHING. That era's own config generate seeds UPGRADE_CHANNEL.
    #   254-era   → UPGRADE_ROLE=production. The channel is derived from the role,
    #               and that era REFUSES a channel written into .env.config.
    #   307-era   → UPGRADE_CHANNEL=stable. UPGRADE_ROLE no longer exists; a box
    #               carrying only a role would derive its channel from the MODE,
    #               and these VMs run in development mode → "local" →
    #               migrationChannelClass=channelLocalDev, which is the opposite
    #               of what every arc needs.
    #
    # The two written forms are mutually incompatible — 254 refuses the channel
    # key, 307 ignores the role key — so this cannot be collapsed into writing
    # both. Dropping the line entirely would be worse still: it would build a
    # 307-era box on the local channel and silently disarm the release-bless
    # behaviour the arcs exist to exercise.
    #
    # ERA PROBE, deliberately not a commit SHA. The 254 gate could name
    # 733b0df4d because that commit existed when the gate was written; 307's own
    # commit does not exist while 307 is being built, and back-filling a SHA
    # after the fact is the kind of step that gets forgotten. So the probe asks
    # the tree itself: does the channel mechanism FILE exist at that commit? That
    # is the era, stated in terms of the thing that defines it.
    # AN ABSENT BASE_SHA MEANS CURRENT CODE, so it routes to the CURRENT era —
    # branch one, not the fallback. The previous form sent it to the 254 branch,
    # which was right only BY ACCIDENT: the one-time translator turns a written
    # role into channel=stable, so the arcs still got release behaviour. The
    # moment that translator is deleted — and upgrade_channel.go says in terms
    # that it SHOULD be, once the fleet has run it — an empty BASE_SHA would
    # write a key nothing reads, the box would derive "local" from its
    # development mode, and every arc would silently lose release-bless with
    # nothing going red. A default that is correct only while a temporary
    # translator exists is a trap with a timer on it.
    if [ -z "${BASE_SHA:-}" ] || git -C "$HARNESS_ROOT" cat-file -e "$BASE_SHA:cli/internal/config/upgrade_channel.go" 2>/dev/null; then
        cat >> "$env_config_file" << 'ENVCONFIG'
# STATBUS-307: the channel is the setting, written exactly where it is chosen.
# These VMs run in development MODE, which would derive "local" — but the arcs
# need release-channel behaviour (migrationChannelClass=channelRelease), so the
# box declares stable explicitly. A written channel always wins over the mode,
# which is precisely what this key exists for.
UPGRADE_CHANNEL=stable
ENVCONFIG
    elif git -C "$HARNESS_ROOT" merge-base --is-ancestor 733b0df4d "$BASE_SHA" 2>/dev/null; then
        cat >> "$env_config_file" << 'ENVCONFIG'
# STATBUS-254 era: declare what the box IS; the channel is derived from it.
# production -> stable, which is what this harness wants even though the box
# runs in development MODE (the upgrade axis is deliberately decoupled from the
# front-door mode — STATBUS-106), so migrationChannelClass stays channelRelease.
UPGRADE_ROLE=production
ENVCONFIG
    fi
    scp -O "${SSH_OPTS[@]}" "$env_config_file" root@"$ip":/tmp/env-config
    ssh "${SSH_OPTS[@]}" root@"$ip" 'chmod 0644 /tmp/env-config'
    rm -f "$env_config_file"

    users_file=$(mktemp)
    cat > "$users_file" << 'USERS'
- email: test@statbus.org
  password: test-install-password-2026
  role: admin_user
  display_name: Admin
USERS
    scp -O "${SSH_OPTS[@]}" "$users_file" root@"$ip":/tmp/users.yml
    ssh "${SSH_OPTS[@]}" root@"$ip" 'chmod 0644 /tmp/users.yml'
    rm -f "$users_file"

    ssh "${SSH_OPTS[@]}" root@"$ip" 'cat > /root/.setup-ubuntu.env << EOF
ADMIN_EMAIL="test@statbus.org"
GITHUB_USERS="jhf"
EXTRA_LOCALES=""
CADDY_PLUGINS=""
EOF'

    echo "  === Stage: Hardening (detached tmux for survivability) ==="
    local logfile="$HARNESS_ROOT/tmp/install-recovery-${VM_NAME:-unknown}-bootstrap.log"
    # Hardening runs as root, not statbus. Override the helper's user briefly
    # by running it directly (tmux must run AS root here since /tmp/setup.sh
    # needs root, and the statbus user doesn't exist yet at this point).
    ssh "${SSH_OPTS[@]}" root@"$ip" \
        'command -v tmux >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y tmux >/dev/null 2>&1' \
        || true
    ssh "${SSH_OPTS[@]}" root@"$ip" "
        rm -f /tmp/harden.exit /tmp/harden.log
        tmux new-session -d -s harden 'bash /tmp/setup.sh --non-interactive --skip-stages=4 > /tmp/harden.log 2>&1; echo \$? > /tmp/harden.exit'
    "
    local max_iter=$(( ${LONG_CMD_MAX_MIN:-45} * 60 / 15 )) i=0 seen=0
    for ((i=0; i<max_iter; i++)); do
        if ssh "${SSH_OPTS[@]}" root@"$ip" 'test -f /tmp/harden.exit' 2>/dev/null; then
            break
        fi
        local cur
        cur=$(ssh "${SSH_OPTS[@]}" root@"$ip" 'wc -l < /tmp/harden.log 2>/dev/null' 2>/dev/null | tr -d ' ') || true
        if [ -n "$cur" ] && [ "$cur" -gt "$seen" ] 2>/dev/null; then
            ssh "${SSH_OPTS[@]}" root@"$ip" "tail -n $((cur - seen)) /tmp/harden.log" 2>/dev/null | tee -a "$logfile" || true
            seen="$cur"
        fi
        sleep 15
    done
    if ! ssh "${SSH_OPTS[@]}" root@"$ip" 'test -f /tmp/harden.exit' 2>/dev/null; then
        echo "  HARDENING TIMEOUT after ${LONG_CMD_MAX_MIN:-45}min" >&2
        _dump_bootstrap_failure_diagnostics "$ip" "$VM_NAME"
        return 1
    fi
    local harden_exit
    harden_exit=$(ssh "${SSH_OPTS[@]}" root@"$ip" 'cat /tmp/harden.exit' 2>/dev/null | tr -d ' \n') || true
    if [ "$harden_exit" != "0" ]; then
        echo "  HARDENING FAILED with exit code: '$harden_exit' (empty = SSH read failure)" >&2
        _dump_bootstrap_failure_diagnostics "$ip" "$VM_NAME"
        return 1
    fi

    echo "  creating statbus user + linger..."
    ssh "${SSH_OPTS[@]}" root@"$ip" '
        useradd -m -s /bin/bash -G docker statbus 2>/dev/null || true
        usermod -aG docker statbus 2>/dev/null || true
        loginctl enable-linger statbus 2>/dev/null || true
        grep -q XDG_RUNTIME_DIR /home/statbus/.profile 2>/dev/null \
            || echo "export XDG_RUNTIME_DIR=/run/user/\$(id -u)" >> /home/statbus/.profile
    '

    echo "  fetching personal SSH keys from GitHub (ed25519 only)..."
    ssh "${SSH_OPTS[@]}" root@"$ip" '
        # Root authorized_keys (already seeded by Hetzner for statbus-ci; append personal keys)
        mkdir -p /root/.ssh && chmod 700 /root/.ssh
        touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys

        # Statbus user authorized_keys
        mkdir -p /home/statbus/.ssh && chmod 700 /home/statbus/.ssh
        touch /home/statbus/.ssh/authorized_keys && chmod 600 /home/statbus/.ssh/authorized_keys
        chown statbus:statbus /home/statbus/.ssh /home/statbus/.ssh/authorized_keys

        # jhf
        if keys=$(curl -sf https://github.com/jhf.keys | grep '"'"'^ssh-ed25519'"'"'); then
            echo "$keys" >> /root/.ssh/authorized_keys
            echo "$keys" >> /home/statbus/.ssh/authorized_keys
        else
            echo "WARNING: could not fetch jhf GitHub keys (network blip); skipping" >&2
        fi

        # hhssb
        if keys=$(curl -sf https://github.com/hhssb.keys | grep '"'"'^ssh-ed25519'"'"'); then
            echo "$keys" >> /root/.ssh/authorized_keys
            echo "$keys" >> /home/statbus/.ssh/authorized_keys
        else
            echo "WARNING: could not fetch hhssb GitHub keys (network blip); skipping" >&2
        fi

        # Propagate CI key: Hetzner seeds the statbus-ci key to root only.
        # After the curl loops above, root has: Hetzner CI key + personal keys.
        # Copy everything to statbus and dedup so `ssh statbus@vm` works from
        # CI and from any key that can reach root (canonical operator model:
        # the same key that reaches root also reaches the statbus operator user).
        sort -u /root/.ssh/authorized_keys > /tmp/.ak_merge
        cat /tmp/.ak_merge > /home/statbus/.ssh/authorized_keys
        rm -f /tmp/.ak_merge
        chown statbus:statbus /home/statbus/.ssh/authorized_keys
        chmod 600 /home/statbus/.ssh/authorized_keys
    '

    STATBUS_UID=$(ssh "${SSH_OPTS[@]}" root@"$ip" id -u statbus 2>/dev/null) || true
    local i
    for i in $(seq 1 20); do
        if ssh "${SSH_OPTS[@]}" root@"$ip" "sudo -u statbus XDG_RUNTIME_DIR=/run/user/$STATBUS_UID systemctl --user is-system-running" 2>/dev/null | grep -E "running|degraded" >/dev/null; then
            break
        fi
        sleep 0.5
    done

    # Per-VM exec function. CALLERS MUST USE `VM_EXEC ...` (not `$VM_EXEC`).
    # OpenSSH joins multi-arg commands with bare spaces and DOES NOT
    # re-quote — so `$VM_EXEC bash -c "long string"` arrives on the VM
    # as `bash -c long -s -m 3 ...` (mangled). The function path uses
    # printf %q to escape each arg before assembling one quoted remote
    # command string for ssh.
    #
    # TRAP (r13 autopsy, 2026-07-05, foreman-verified on a kept VM):
    # `sudo -i -u statbus -- ...` re-quotes the command line ITSELF before
    # handing it to statbus's login shell, and that re-quoting does not
    # reliably protect bare `$VARNAME` references (parens happen to survive
    # via a different escape; a lone `$` does not) — a `$` that must reach
    # the VM as LITERAL TEXT (e.g. building a shell script whose body
    # references `$SOME_VAR` for evaluation at a LATER, unrelated run) can
    # come back silently expanded to empty, and a multi-line body can be
    # mangled outright. Never pass such content as a VM_EXEC/bash -c
    # argument — use VM_SCRIPT (or VM_SCRIPT_INLINE for a short one-off body)
    # below instead; VM_EXEC itself refuses a multi-line argument and names
    # them as the remedy (STATBUS-021).
    VM_IP="$ip"
}

VM_EXEC() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            *$'\n'*)
                cat >&2 <<BANNER

═══════════════════════════════════════════════════════════════════════
BLOCKED: VM_EXEC was called with a multi-line argument.

VM_EXEC's transport (printf %q + \`sudo -i -u statbus -- <args>\`) is safe
ONLY for single-line, locally-expanded arguments (see the TRAP comment
above this function) — the sudo -i login-shell re-quoting silently mangles
multi-line content, and a script body's own \$VARNAME references can come
back expanded instead of staying literal for later evaluation on the VM.

Offending argument (first 200 chars):
$(printf '%.200s' "$arg")

WHAT TO DO:
  - Ship a script FILE instead: VM_SCRIPT <local-script-path> [args...]
  - For a short one-off body: VM_SCRIPT_INLINE <name> <<'EOF' ... EOF
    (the heredoc delimiter MUST be quoted, or the body gets expanded
    locally before it ever reaches the VM).

Hook source: VM_EXEC (test/install-recovery/lib/vm-bootstrap.sh)
═══════════════════════════════════════════════════════════════════════
BANNER
                return 1
                ;;
        esac
    done
    local quoted_args
    quoted_args=$(printf '%q ' "$@")
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" "sudo -i -u statbus -- $quoted_args"
}

# VM_SCRIPT <local-script-path> [args...] — STATBUS-021: scp a LOCAL file to
# the VM and execute it there as the statbus user via VM_EXEC. NEVER
# construct the script ON the VM via an ssh heredoc — that routes the
# payload through the same ssh -> sudo -> shell evaluation layers the
# multi-line VM_EXEC bug class lives in (see VM_EXEC's TRAP comment above).
# Writing the file LOCALLY — the call site's heredoc uses a QUOTED delimiter,
# so its content is never evaluated before it is written — and shipping the
# finished bytes via scp is the only path where no shell ever touches the
# payload in transit.
#
# The remote copy is named uniquely (PID-suffixed) and KEPT after execution
# (never rm'd here) — the VM is ephemeral, and forensics on a kept/failed VM
# benefit from being able to re-read exactly what ran.
VM_SCRIPT() {
    local local_path="$1"; shift
    local remote_path
    remote_path="/tmp/vm-script-$(basename "$local_path")-$$.sh"
    scp -O "${SSH_OPTS[@]}" "$local_path" root@"$VM_IP":"$remote_path" >/dev/null
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" "chmod 0755 $remote_path"
    VM_EXEC bash "$remote_path" "$@"
}

# VM_SCRIPT_INLINE <name> [args...] — the quoted-heredoc-stdin variant of
# VM_SCRIPT, for short scripts that don't warrant their own file in the repo.
# Call-site shape (the delimiter MUST be quoted — 'EOF', never bare EOF — or
# bash expands/interprets the body locally before it ever reaches the VM):
#   VM_SCRIPT_INLINE probe <<'EOF'
#   #!/bin/sh
#   echo "$SOME_VAR at $(date)"
#   EOF
# Reads the script body from STDIN, writes it to a local temp file, and
# delegates to VM_SCRIPT — inheriting the same never-evaluate-on-the-VM
# guarantee. Unlike VM_SCRIPT, the local temp file here is ours to clean up.
VM_SCRIPT_INLINE() {
    local name="$1"; shift
    local local_path
    local_path=$(mktemp "/tmp/vm-script-inline-${name}-XXXXXX")
    cat > "$local_path"
    VM_SCRIPT "$local_path" "$@"
    local rc=$?
    rm -f "$local_path"
    return $rc
}

bootstrap_install_test_vm() {
    local vm_name="$1"
    local install_version="${2:-}"
    _check_name_safety "$vm_name" || return 1

    # STATBUS-208 defect A: finalize the run-unique name HERE, before the
    # refuse-on-existing check and before VM_NAME is published — every
    # caller downstream (the refuse check below, hcloud server create,
    # VM_NAME's readers in the scenario/arc script: install_statbus_in_vm,
    # cleanup_vm's EXIT trap) sees only the already-suffixed name from this
    # point on. The refuse-on-existing check's OWN code is intentionally
    # unchanged — with unique names it simply stops tripping cross-run.
    vm_name="$(_suffixed_vm_name "$vm_name" "$(_run_suffix)")"
    VM_NAME="$vm_name"

    if ! command -v hcloud >/dev/null 2>&1; then
        echo "ERROR: hcloud CLI not installed. brew install hcloud" >&2
        return 1
    fi

    # Build sb binary locally if no release was specified.
    # CI sets STATBUS_SB_BINARY to a pre-extracted binary (avoids a fresh build).
    local sb_binary=""
    if [ -z "$install_version" ]; then
        if [ -n "${STATBUS_SB_BINARY:-}" ]; then
            if [ ! -f "$STATBUS_SB_BINARY" ]; then
                echo "ERROR: STATBUS_SB_BINARY is set but file does not exist: $STATBUS_SB_BINARY" >&2
                return 1
            fi
            sb_binary="$STATBUS_SB_BINARY"
            echo "Using pre-built sb binary: $sb_binary"
        else
            local build_target="linux/amd64"  # Hetzner CX23 is x86_64
            echo "Building sb for $build_target..."
            (cd "$HARNESS_ROOT" && ./dev.sh build-sb "$build_target")
            sb_binary="${HARNESS_ROOT}/sb-${build_target//\//-}"
        fi
    fi

    # Refuse if the VM already exists — another test-install run may be in progress.
    if hcloud server describe "$vm_name" >/dev/null 2>&1; then
        echo "ERROR: VM '$vm_name' already exists. Another test-install run may be in progress (CI or local)." >&2
        echo "  Inspect:  hcloud server describe $vm_name" >&2
        echo "  If stale: hcloud server delete $vm_name" >&2
        return 1
    fi

    echo "Provisioning Hetzner $HCLOUD_SERVER_TYPE in $HCLOUD_LOCATION: $vm_name"
    # STATBUS-208 defect B + STATBUS-231: bounded retry-with-backoff on
    # TRANSIENT hcloud capacity errors only — two known classes so far:
    #   - resource_limit_exceeded: the account-quota error. The shared
    #     hetzner-vm-fleet concurrency group (the workflow-side fix)
    #     already keeps peak demand within the account limit, but a
    #     straggler VM from the PREVIOUS group can still be mid-teardown
    #     when the next group's first create fires; this is defense for
    #     exactly that residual window, not a substitute for the group.
    #   - resource_unavailable ("error during placement"): Hetzner
    #     momentarily has no capacity to PLACE the VM in this location —
    #     nothing to do with our account limit, a minutes-long provider-side
    #     blip that clears on its own. Observed 3x in one day at rc.03
    #     (both 0-happy install-recovery baselines, then the rc.03
    #     spot-check's own working arc, run 32131797267) before this
    #     retry's trigger was widened to cover it.
    # Any OTHER create failure (bad image name, quota for a different
    # resource, auth) fails immediately — retrying those would just burn
    # 5 minutes before reporting the same permanent error.
    local create_attempt max_create_attempts=5 create_backoff_s=60 create_stderr create_err
    for ((create_attempt = 1; create_attempt <= max_create_attempts; create_attempt++)); do
        create_stderr=$(mktemp)
        if hcloud server create \
            --name "$vm_name" \
            --type "$HCLOUD_SERVER_TYPE" \
            --image "$HCLOUD_IMAGE" \
            --location "$HCLOUD_LOCATION" \
            --ssh-key "$HCLOUD_SSH_KEY" \
            >/dev/null 2>"$create_stderr"; then
            rm -f "$create_stderr"
            break
        fi
        create_err=$(cat "$create_stderr")
        rm -f "$create_stderr"
        if ! printf '%s' "$create_err" | grep -E "resource_limit_exceeded|resource_unavailable" >/dev/null; then
            echo "ERROR: hcloud server create failed for '$vm_name': $create_err" >&2
            return 1
        fi
        if [ "$create_attempt" -eq "$max_create_attempts" ]; then
            echo "ERROR: hcloud server create exhausted $max_create_attempts attempts (transient capacity error every time) for '$vm_name': $create_err" >&2
            return 1
        fi
        echo "  hcloud server create hit a transient capacity error (attempt $create_attempt/$max_create_attempts) — retrying in ${create_backoff_s}s..." >&2
        echo "    $create_err" >&2
        sleep "$create_backoff_s"
    done
    # STATBUS-207 ownership guard: only set once `hcloud server create`
    # itself has actually succeeded (set -e would have exited above on
    # failure, e.g. DEFECT B's resource_limit_exceeded or STATBUS-231's
    # resource_unavailable exhausting their retries — the flag never gets
    # set on those paths either, correctly).
    VM_OWNED_BY_THIS_RUN=1

    VM_IP=$(_hcloud_server_ip "$vm_name") || return 1
    echo "  VM_IP=$VM_IP"

    _wait_for_ssh "$VM_IP" 90
    _apply_hardening "$VM_IP" "$sb_binary"

    echo "VM $vm_name bootstrap complete."
}

# Reset VM to fresh OS state using hcloud server rebuild. Same server, same
# IP, fresh disk image. ~30s + hardening. The cheap path for approach-B.
reset_vm_state() {
    local vm_name="$1"
    _check_name_safety "$vm_name" || return 1
    VM_NAME="$vm_name"

    if ! hcloud server describe "$vm_name" >/dev/null 2>&1; then
        echo "ERROR: $vm_name does not exist; cannot reset. Call bootstrap_install_test_vm first." >&2
        return 1
    fi

    echo "Reimaging $vm_name to fresh $HCLOUD_IMAGE (server id and IP preserved)..."
    hcloud server rebuild "$vm_name" --image "$HCLOUD_IMAGE" > /dev/null

    VM_IP=$(_hcloud_server_ip "$vm_name") || return 1
    echo "  VM_IP=$VM_IP (unchanged)"

    # Caller pre-built sb_binary is already cached in $HARNESS_ROOT —
    # rebuild only wipes the VM disk, not the host workspace.
    local sb_binary=""
    local build_target="linux/amd64"
    sb_binary="${HARNESS_ROOT}/sb-${build_target//\//-}"
    [ -f "$sb_binary" ] || sb_binary=""

    _wait_for_ssh "$VM_IP" 90
    _apply_hardening "$VM_IP" "$sb_binary"

    echo "VM $vm_name reset complete."
}

# Run install inside a bootstrapped VM.
#   install_statbus_in_vm <vm_name>                  → run the REAL install.sh --commit <HEAD-sha>
#   install_statbus_in_vm <vm_name> v2026.05.0-rc.X  → download from release
# Caller may pre-set SB_INSTALL_EXTRA_ARGS (e.g. "--recovery=auto").
#
# No-version EXIT CONTRACT (STATBUS-060):
#   install.sh exits 0 for BOTH success and rollback (./sb install rc=75 → install.sh
#   prints a rollback banner and exits 0). Catastrophic failures are non-zero.
#   Callers must use the upgrade row state (FINAL_STATE=failed|rolled_back) to
#   distinguish success from rollback — exit code alone is insufficient.
install_statbus_in_vm() {
    local vm_name="$1"
    local install_version="${2:-}"
    local extra_args="${SB_INSTALL_EXTRA_ARGS:-}"
    # No-seed mode (opt-in via SB_INSTALL_SKIP_SEED): force a full-migrations-from-tag
    # baseline so a real v<tag>→HEAD migration delta exists for the stall/kill injects
    # (the published seed is dumped at HEAD's migration level and would otherwise
    # collapse the delta). Pure harness-side, NO product change: withhold the
    # origin/db-seed tracked-branch so a RELEASE binary's git-branch seed
    # (db seed fetch → origin/db-seed) finds no ref and falls through to full
    # migrations. Default (unset) preserves the seed shortcut → passing scenarios
    # are unaffected.
    # NOTE: this reaches the RELEASE-binary (versioned) baseline only, whose seed is
    # git-branch-based. A HEAD-binary (no-version) install uses a Docker-image seed
    # (statbus-seed:<short>) that this does NOT disable — such a baseline instead
    # relies on a populated DB (checkSeedRestored's dbHasUserData R5 short-circuit,
    # install.go) so the seed step is skipped. No current no-seed scenario needs a
    # HEAD-binary no-seed baseline.
    local seed_branch_cmd="git remote set-branches --add origin db-seed"
    if [ -n "${SB_INSTALL_SKIP_SEED:-}" ]; then
        seed_branch_cmd="true  # SB_INSTALL_SKIP_SEED: origin/db-seed withheld (release-binary git-branch seed disabled → full migrations)"
    fi
    _check_name_safety "$vm_name" || return 1

    local ip
    ip=$(_hcloud_server_ip "$vm_name") || return 1

    local install_script
    install_script=$(mktemp)
    if [ -z "$install_version" ]; then
        # STATBUS-060/082: run the REAL install.sh (operator path), PINNED to the
        # exact commit under test with --commit (STATBUS-039: the operator's only
        # action is install.sh). install.sh --commit <sha>:
        #   RESCUE mode (~/statbus/.git exists): git fetch origin <sha> → checkout
        #     current → procure binary from the PUBLISHED image → ./sb install.
        #   Binary procurement: docker pull ghcr.io/statisticsnorway/statbus-sb:<short>
        #     — NO build fallback under --commit (determinism: test the published
        #     artifact CI ships; a missing image refuses, naming it).
        # install.sh exits 0 for both success and rollback; see EXIT CONTRACT above.
        #
        # Fork 1A: upload in-repo install.sh (matches HEAD, no curl network hop).
        # Fork 2D: --commit pins procurement to the exact target (no master drift).
        # Fork 3: no 75-tolerance at call sites; outcome from upgrade row state only.

        # Upload the in-repo install.sh as /tmp/statbus-install.sh (NOT /tmp/install.sh —
        # the shared section below uploads the wrapper script to /tmp/install.sh and runs
        # `bash /tmp/install.sh`; using the same name would cause the wrapper to call itself).
        _wait_for_ssh "$ip" 30
        # STATBUS-082: pin install.sh to the EXACT commit under test (git HEAD,
        # guaranteed on origin by run.sh's preflight_head_on_origin) via --commit.
        # This replaces the master-drifting `--channel edge` (which resolved the
        # moving tip at run time — the nondeterminism this ticket names) AND removes
        # the SB_RECOVERY_REUSE_STAGED_BINARY reuse-gate (deterministic but it
        # BYPASSED install.sh — the fidelity loss). --commit is BOTH: deterministic
        # (exact sha) and install.sh-in-the-loop (the operator's sole action,
        # STATBUS-039). scp-a-binary bypasses now survive only as per-scenario named
        # exceptions, never this default path.
        #
        # STATBUS-184: re-verify HEAD is STILL on origin RIGHT HERE, immediately
        # before it is captured — run.sh's top-level check ran before this VM was
        # even provisioned (and before any earlier scenario in a multi-scenario
        # run), which is not "guaranteed" against a HEAD that moved since.
        _assert_head_still_on_origin
        local commit_under_test
        commit_under_test="$(git -C "$HARNESS_ROOT" rev-parse HEAD)"
        scp -O "${SSH_OPTS[@]}" "$HARNESS_ROOT/install.sh" root@"$ip":/tmp/statbus-install.sh
        ssh "${SSH_OPTS[@]}" root@"$ip" 'chmod 0755 /tmp/statbus-install.sh'

        cat > "$install_script" << SCRIPT
set -e
# If ~/statbus/.git does not exist (no prior install), do a minimal clone first
# so install.sh always enters RESCUE mode (git update + binary procure + ./sb install).
# install.sh --commit FRESH would clone ~/statbus itself but would then call
# ./sb install WITHOUT .env.config in place — we must pre-place config files before
# install.sh's ./sb install step. The pre-clone ensures RESCUE mode so we control
# timing: config files land before ./sb install runs. Idempotent for RESCUE callers.
if [ ! -d ~/statbus/.git ]; then
    for attempt in 1 2 3; do
        if git clone --depth 50 https://github.com/statisticsnorway/statbus.git ~/statbus; then
            break
        fi
        rc=\$?
        echo "GitHub clone retry [git-clone] \${attempt}/3 (rc=\$rc)" >&2
        [ "\$attempt" -eq 3 ] && exit "\$rc"
        rm -rf ~/statbus
        sleep 10
    done
    # Add db-seed refspec so install's own 'git fetch origin db-seed' creates the
    # remote-tracking ref (a single-branch shallow clone restricts the refspec).
    git -C ~/statbus remote set-branches --add origin db-seed
fi
# Pre-place config files: ./sb install (called by install.sh) needs .env.config.
# For RESCUE mode these survive install.sh's 'git checkout -B current origin/master'.
cp /tmp/env-config ~/statbus/.env.config
cp /tmp/users.yml ~/statbus/.users.yml
# Run the real install.sh (uploaded as /tmp/statbus-install.sh to avoid a naming
# conflict with the harness wrapper at /tmp/install.sh). Always in RESCUE mode
# (~/statbus/.git guaranteed above). --commit <sha>: fetches the EXACT commit,
# procures its PUBLISHED statbus-sb image (no build fallback), then calls ./sb install.
# Exits 0 for both success and rollback; catastrophic failures are non-zero.
STATBUS_MIN_DISK_GB=5 bash /tmp/statbus-install.sh --commit ${commit_under_test} --trust-github-user jhf
SCRIPT
    else
        cat > "$install_script" << SCRIPT
set -e
VM_ARCH=\$(uname -m)
case "\$VM_ARCH" in
    x86_64)        GOARCH=amd64 ;;
    arm64|aarch64) GOARCH=arm64 ;;
    *)             echo "Unsupported: \$VM_ARCH"; exit 1 ;;
esac
SB_URL="https://github.com/statisticsnorway/statbus/releases/download/${install_version}/sb-linux-\${GOARCH}"
curl --retry 5 --retry-delay 5 --retry-all-errors -fsSL "\$SB_URL" -o ~/sb.tmp
chmod +x ~/sb.tmp
if [ ! -d ~/statbus/.git ]; then
    for attempt in 1 2 3; do
        if git clone --depth 1 --branch ${install_version} https://github.com/statisticsnorway/statbus.git ~/statbus; then
            break
        fi
        rc=\$?
        echo "GitHub clone retry [git-clone] \${attempt}/3 (rc=\$rc)" >&2
        [ "\$attempt" -eq 3 ] && exit "\$rc"
        rm -rf ~/statbus
        sleep 10
    done
fi
mv ~/sb.tmp ~/statbus/sb
cd ~/statbus
# A '--depth 1 --branch <tag>' clone is implicitly single-branch — the
# refspec is narrowed to just the tag's branch, so a subsequent
# 'git fetch origin db-seed' downloads data but does NOT create
# refs/remotes/origin/db-seed. ./sb install's seed-fetch step then sees
# 'fatal: invalid object name origin/db-seed' on the git-show that
# follows, falls back to migrations-from-scratch (~30 min on a fresh DB),
# and any harness scenario spends its time replaying migrations instead
# of exercising the recovery code path under test. Extending the
# tracked-branch list before the install fixes the ref creation.
$seed_branch_cmd
cp /tmp/env-config .env.config 2>/dev/null || true
cp /tmp/users.yml .users.yml 2>/dev/null || true
STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf $extra_args
SCRIPT
    fi

    # Wait for SSH to be responsive before uploading — bootstrap activity
    # (package installs, service starts — the Homebrew comfort layer this
    # comment used to name is gone as of STATBUS-227/doc-032, but ordinary
    # apt work can still do this) can leave sshd's accept queue saturated
    # for a few seconds, causing immediate "Operation timed out"
    # on the very next connection.
    _wait_for_ssh "$ip" 30
    scp -O "${SSH_OPTS[@]}" -o LogLevel=VERBOSE "$install_script" root@"$ip":/tmp/install.sh
    ssh "${SSH_OPTS[@]}" -o LogLevel=VERBOSE root@"$ip" 'chmod 0644 /tmp/install.sh'
    rm -f "$install_script"

    # Run the install in a detached tmux session as statbus, poll for
    # completion. Survives mobile-internet drops — even if every poll
    # roundtrip fails, the install keeps running on the VM and we resume
    # from the logfile on next poll success.
    local install_log="${HARNESS_ROOT}/tmp/install-recovery-${vm_name}-install.log"
    _run_long_via_tmux "$ip" "install" "bash /tmp/install.sh" "$vm_name" \
        | tee -a "$install_log"
    return ${PIPESTATUS[0]}
}

# install_statbus_at_sha <vm_name> <sha> — fresh install pinned to an EXACT commit.
#
# The upgrade-arc harness (STATBUS-071) needs the baseline A = base_sha EXACTLY:
# the defect branch B is committed off base_sha, so the box must start AT base_sha
# for A→B to be a clean single-migration forward. install_statbus_in_vm cannot do
# this — its empty-version path installs master HEAD (drifts between fire and
# install) and its tag path downloads a release binary (no release is post-086,
# which the register/schedule arc requires). This helper is install.sh --channel
# edge pinned to <sha>: blobless full clone → checkout <sha> → toolchain-free
# binary procurement of statbus-sb:<short> (mirrors sbimage.ProcureShort:
# docker pull → create → cp /sb → rm → chmod) → ./sb install. The per-commit sb
# image was built by the master-push images.yaml run for <short> (the arc's
# image-wait gates on it).
#
# Relies on bootstrap_install_test_vm having already uploaded /tmp/env-config +
# /tmp/users.yml and applied OS setup (docker present). Same EXIT CONTRACT as the
# no-version install_statbus_in_vm: ./sb install rc=75 (rollback) → install exits
# 0; callers decide success from the upgrade/install row state, not the exit code.
install_statbus_at_sha() {
    local vm_name="$1"
    local sha="$2"
    local short="${sha:0:8}"
    _check_name_safety "$vm_name" || return 1
    [ -n "$sha" ] || { echo "ERROR: install_statbus_at_sha requires a commit SHA" >&2; return 1; }

    # NOTE: ephemeral arc-signer trust is injected POST-install by the caller
    # (working-arc.sh), NOT here. A pre-install UPGRADE_TRUSTED_SIGNER_arc is
    # scrubbed by install's checkSignersDone (install.go:1592-1650): it runs
    # `git verify-commit HEAD` against ALL configured signers and DELETES every
    # UPGRADE_TRUSTED_SIGNER_* if HEAD doesn't verify — and the arc key signs
    # B/C, never HEAD=A (=this sha, a master commit jhf signed). So the box is
    # installed with --trust-github-user jhf only (jhf verifies A → survives the
    # scrub); the caller adds arc afterward via config generate + unit restart.

    local ip
    ip=$(_hcloud_server_ip "$vm_name") || return 1

    local install_script
    install_script=$(mktemp)
    cat > "$install_script" << SCRIPT
set -e
# Blobless full-history clone so ANY commit is checkoutable (a --depth clone could
# miss base_sha if master advanced); fast — blobs are fetched on demand only.
if [ ! -d ~/statbus/.git ]; then
    git clone --filter=blob:none https://github.com/statisticsnorway/statbus.git ~/statbus
fi
cd ~/statbus
# Pin the tree to base_sha A — deterministic, NO master drift. The fetch is a
# belt-and-suspenders net (the blobless clone already has the full commit graph).
git fetch --filter=blob:none origin ${sha} 2>/dev/null || true
git checkout -q ${sha}
# Toolchain-free binary procurement for A (mirrors install.sh edge /
# sbimage.ProcureShort): pull the per-commit sb image, copy /sb out.
docker pull ghcr.io/statisticsnorway/statbus-sb:${short}
cid=\$(docker create ghcr.io/statisticsnorway/statbus-sb:${short})
docker cp "\$cid":/sb ./sb
docker rm "\$cid"
chmod +x ./sb
# Pre-place config: ./sb install needs .env.config + .users.yml.
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf
SCRIPT

    _wait_for_ssh "$ip" 30
    scp -O "${SSH_OPTS[@]}" "$install_script" root@"$ip":/tmp/install.sh
    ssh "${SSH_OPTS[@]}" root@"$ip" 'chmod 0644 /tmp/install.sh'
    rm -f "$install_script"

    local install_log="${HARNESS_ROOT}/tmp/install-recovery-${vm_name}-install.log"
    _run_long_via_tmux "$ip" "install" "bash /tmp/install.sh" "$vm_name" \
        | tee -a "$install_log"
    return ${PIPESTATUS[0]}
}

# Upload the local HEAD sb binary to /tmp/sb on the VM.
#
# Needed by any scenario that bootstraps WITH an INSTALL_VERSION (the
# version-branch bootstrap does NOT upload /tmp/sb — it fetches the
# release binary directly into ~/statbus/sb) but then runs a custom
# inline install script whose first action is `cp /tmp/sb ./sb`.  Without
# this upload that cp fails, set -e exits the subshell before ./sb install
# ever runs, and no migrate/upgrade process appears.
#
# install_statbus_in_vm's no-version branch already does this upload
# internally (vm-bootstrap.sh lines 472-484).  Scenarios that bypass
# install_statbus_in_vm with their own inline scripts call this helper
# explicitly instead.
#
# Always rebuilds sb-linux-amd64 from the current HEAD unless STATBUS_SB_BINARY
# is set (CI pre-extraction bypass).  The "build if absent" gate was dropped
# because a stale binary (built from an older commit) embeds an older commitSHA
# via ldflags; stalenessGuard in cli/cmd/root.go:85 detects the mismatch and
# triggers self-heal rebuild+re-exec on the VM — but the VM has no Go, so
# exit 127 aborts the scenario before the inject site is ever reached.
# Rebuilding here adds ~10-15s (CGO_ENABLED=0 cross-compile) once per
# upload_sb_to_vm call, which is negligible vs the ~10-15 min scenario wall-clock.
# STATBUS_SB_BINARY overrides the binary path (used by CI pre-extraction).
upload_sb_to_vm() {
    local vm_name="$1"
    _check_name_safety "$vm_name" || return 1
    local ip
    ip=$(_hcloud_server_ip "$vm_name") || return 1
    local sb_binary="${STATBUS_SB_BINARY:-}"
    if [ -z "$sb_binary" ]; then
        echo "  Building sb-linux-amd64 from HEAD (always rebuild to prevent staleness)..."
        (cd "$HARNESS_ROOT" && ./dev.sh build-sb linux/amd64)
        sb_binary="${HARNESS_ROOT}/sb-linux-amd64"
    fi
    if [ ! -f "$sb_binary" ]; then
        echo "FATAL: sb binary not found at $sb_binary after build attempt" >&2
        return 1
    fi

    # Instrument every scp/ssh below so failures are unmissable.
    # Two-layer capture:
    #  (a) LogLevel=VERBOSE on each call — SSH_OPTS has LogLevel=ERROR which
    #      suppresses transport-layer error messages (e.g. "Connection reset
    #      by peer" at INFO/VERBOSE) before they reach stderr.  Override to
    #      VERBOSE so the full SSH diagnostic appears.
    #  (b) 2>>"$log" captures ALL remaining stderr, including scp-protocol
    #      errors that bypass the SSH log level.
    # set -x traces every command + its expansion; yes, noisy — that's the
    # point right now.
    local scp_log="/tmp/upload-sb-scp-$$.log"
    local ssh_log="/tmp/upload-sb-ssh-$$.log"
    echo "  upload_sb_to_vm: stderr → $scp_log (scp) / $ssh_log (ssh)"

    # Probe SSH before starting — post-install the VM may be briefly under
    # load (Docker container restarts, service health checks) and sshd's
    # accept queue can be saturated, causing SYN-drops on every new
    # connection.  Waiting here prevents a cascade of chunk failures.
    _wait_for_ssh "$ip" 30

    set -x

    local scp_rc=0
    # Upload via 2 MB chunks to work around the SSH channel-window deadlock on
    # cx23-class targets (Ubuntu 24.04, OpenSSH 9.6p1, kernel 6.8.0-111).
    #
    # Root cause: cx23's sshd fills its 4 MB initial SSH channel window but
    # never sends CHANNEL_WINDOW_ADJUST, permanently stalling every single-pass
    # transfer > 4 MB regardless of protocol (SFTP or legacy scp -O).  The
    # identical sshd on niue (kernel 6.8.0-79) does not exhibit this.
    #
    # Fix: split into 2 MB chunks; each chunk fits within the initial window so
    # no WINDOW_ADJUST exchange is ever needed and the transfer completes.
    # Reassemble with cat on the remote.  Keep -O (legacy wire protocol) to
    # avoid the separate macOS OpenSSH 10.0+ SFTP pipelining deadlock.
    local chunk_dir
    chunk_dir=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; return 1; }
    split -b 2m "$sb_binary" "$chunk_dir/sb-upload-chunk-" 2>>"$scp_log" || scp_rc=$?
    if [ "$scp_rc" -eq 0 ]; then
        local chunk_count=0
        for chunk in "$chunk_dir/sb-upload-chunk-"*; do
            chunk_count=$((chunk_count + 1))
        done
        set +x
        echo "  uploading $(basename "$sb_binary") in ${chunk_count}×2MB chunks (SSH window-adjust workaround)..."
        set -x
        for chunk in "$chunk_dir/sb-upload-chunk-"*; do
            local chunk_name
            chunk_name="$(basename "$chunk")"
            local attempt
            for attempt in 1 2 3; do
                if scp -O "${SSH_OPTS[@]}" -o LogLevel=VERBOSE \
                    "$chunk" root@"$ip":/tmp/"$chunk_name" \
                    2>>"$scp_log"; then
                    break
                fi
                scp_rc=$?
                if [ "$attempt" -eq 3 ]; then
                    set +x
                    echo "  chunk $chunk_name: failed after 3 attempts" >&2
                    set -x
                    break 2
                fi
                set +x
                echo "  chunk $chunk_name: attempt $attempt failed (rc=$scp_rc), waiting 15s before retry..." >&2
                set -x
                sleep 15
                scp_rc=0
            done
        done
    fi
    rm -rf "$chunk_dir"
    if [ "$scp_rc" -eq 0 ]; then
        local assemble_rc=0
        for attempt in 1 2 3; do
            if ssh "${SSH_OPTS[@]}" -o LogLevel=VERBOSE root@"$ip" \
                'cat /tmp/sb-upload-chunk-* > /tmp/sb && rm -f /tmp/sb-upload-chunk-*' \
                2>>"$scp_log"; then
                break
            fi
            assemble_rc=$?
            if [ "$attempt" -eq 3 ]; then
                scp_rc=$assemble_rc
                break
            fi
            set +x
            echo "  assembly attempt $attempt failed (rc=$assemble_rc), waiting 15s..." >&2
            set -x
            sleep 15
            assemble_rc=0
        done
    fi
    if [ "$scp_rc" -ne 0 ]; then
        set +x
        echo "SCP FAILED (exit $scp_rc) uploading $(basename "$sb_binary") → root@${ip}:/tmp/sb" >&2
        echo "  Full stderr ($scp_log):" >&2
        cat "$scp_log" >&2
        return 1
    fi

    local chmod_rc=0
    ssh "${SSH_OPTS[@]}" -o LogLevel=VERBOSE root@"$ip" 'chmod 0755 /tmp/sb' \
        2>"$ssh_log" || chmod_rc=$?
    if [ "$chmod_rc" -ne 0 ]; then
        set +x
        echo "SSH chmod FAILED (exit $chmod_rc)" >&2
        cat "$ssh_log" >&2
        return 1
    fi

    # Atomically swap the binary into ~/statbus/sb using the production
    # mv-then-cp pattern (mirrors replaceBinaryOnDisk in service.go):
    #   mv changes the OLD inode's path — the running process keeps reading
    #   its old inode and exits normally.
    #   cp writes to a FRESH inode at the ./sb path — no ETXTBSY.
    # Without this, a naive `cp /tmp/sb ./sb` in the install script hits
    # ETXTBSY whenever the statbus-upgrade service is running (Phase 1
    # leaves the service up; Phase 3's script runs while it's still live).
    local swap_rc=0
    ssh "${SSH_OPTS[@]}" -o LogLevel=VERBOSE root@"$ip" '
        dst=/home/statbus/statbus/sb
        if [ -f "$dst" ]; then
            mv "$dst" "${dst}.old" 2>/dev/null || true
        fi
        cp /tmp/sb "$dst"
        chmod +x "$dst"
        chown statbus:statbus "$dst"
        rm -f "${dst}.old"
    ' 2>>"$ssh_log" || swap_rc=$?
    if [ "$swap_rc" -ne 0 ]; then
        set +x
        echo "SSH atomic-swap FAILED (exit $swap_rc)" >&2
        echo "  Full stderr ($ssh_log):" >&2
        cat "$ssh_log" >&2
        return 1
    fi

    set +x
    echo "  /tmp/sb uploaded and atomically swapped into ~/statbus/sb ($vm_name)"
}

# Upload a harness install-script to the VM and chmod 0755 so that
# `sudo -u statbus bash /tmp/install-*.sh` can read it.
#
# Background: mktemp creates files with mode 0600; scp preserves that
# mode; the remote file therefore lands as root:root 0600. The statbus
# user cannot READ it, so `bash /tmp/install-*.sh` exits 126 (Permission
# denied) even though the invocation uses the `bash` prefix.  Forcing
# 0755 after scp makes the file world-readable and statbus-executable.
#
# Usage:
#   upload_install_script_to_vm "$VM_NAME" "$INSTALL_SCRIPT" /tmp/install-cNN.sh
#
# The helper removes the local temp file after upload (replaces the
# caller's `rm -f "$INSTALL_SCRIPT"` pattern).
upload_install_script_to_vm() {
    local vm_name="$1"
    local src_path="$2"
    local dest_path="$3"
    _check_name_safety "$vm_name" || return 1
    local ip
    ip=$(_hcloud_server_ip "$vm_name") || return 1
    scp -O "${SSH_OPTS[@]}" "$src_path" root@"$ip":"$dest_path"
    ssh "${SSH_OPTS[@]}" root@"$ip" "chmod 0755 $dest_path"
    rm -f "$src_path"
    echo "  $dest_path uploaded to VM ($vm_name)"
}

# Cleanup helper. KEEP_VM=1 leaves the VM running for debugging — accrues
# €0.0072/hr until you `hcloud server delete <name>`.
#
# KEEP_VM_ON_FAILURE=1 is an alias intended for diagnostic runs where you
# expect the scenario to fail and want the VM preserved for post-mortem.
# Semantically equivalent to KEEP_VM=1 — both unconditionally skip deletion
# when set.  Use KEEP_VM_ON_FAILURE=1 to make intent explicit in CI logs or
# local one-off debug runs; cleanup_vm does not receive the exit code so it
# cannot distinguish failure from success — that distinction is in the
# operator's hands.
#
# Post-mortem helpers:
#   ssh root@<ip>                         — root shell
#   ssh statbus@<ip>                      — operator user (has systemd bus)
#   ssh root@<ip> journalctl --user -u statbus-upgrade@statbus --no-pager
#   hcloud server delete <name>           — delete when done

# dump_stage_tmux_logs — surface detached-tmux per-stage install logs to stdout
# (→ the scenario's CI log) before the VM is reaped or left up.
#
# Inline-dispatch scenarios run `./sb install` in a DETACHED tmux session that
# writes the install's stdout/stderr to /tmp/<session>.log ON THE VM (see the
# _start_install_with_env-style runners in the scenarios). That file is NOT in
# the CI artifacts, so when an inline install misbehaves (e.g. detects the wrong
# install state and never dispatches the scheduled upgrade, so the inject stall
# never fires) the failure is otherwise undiagnosable from the CI log alone.
#
# Called from cleanup_vm so EVERY scenario benefits automatically, on BOTH
# success and failure, before the VM is deleted (or left running under KEEP_VM).
# Best-effort: a no-op when no stage logs exist or the VM is unreachable; it must
# never fail or slow cleanup beyond one SSH round-trip.
dump_stage_tmux_logs() {
    local vm_name="$1"
    local ip
    ip=$(hcloud server ip "$vm_name" 2>/dev/null) || return 0
    [ -n "$ip" ] && [ "$ip" != "?" ] || return 0
    echo "──────── detached-tmux stage logs (/tmp/stage*.log on $vm_name) ────────"
    ssh "${SSH_OPTS[@]}" root@"$ip" bash -s <<'REMOTE' 2>/dev/null || echo "  (could not retrieve stage logs — VM unreachable?)"
shopt -s nullglob
logs=(/tmp/stage*.log)
if [ ${#logs[@]} -eq 0 ]; then
    echo "  (no /tmp/stage*.log on VM — scenario did not use a detached-tmux install)"
    exit 0
fi
for f in "${logs[@]}"; do
    ex="${f%.log}.exit"
    code="(no .exit file — still running or killed before exit)"
    [ -f "$ex" ] && code="$(cat "$ex" 2>/dev/null)"
    echo ""
    echo "════ $f  [exit: $code] ════"
    cat "$f" 2>/dev/null || echo "  (cat failed)"
done
REMOTE
    echo "──────── end stage logs ────────"
}

# _dump_unit_diagnostics UNIT
# Capture journal + status + sb-version for UNIT to stderr while the VM is
# still alive. Called by vm_restart_unit on failure so diagnostics land in the
# scenario log BEFORE set -e fires the EXIT trap and cleanup_vm reaps the VM.
# Each sub-command is best-effort (|| true); never aborts the caller.
_dump_unit_diagnostics() {
    local unit="${1:-statbus-upgrade@statbus.service}"
    echo "  ── unit diagnostics: $unit ──" >&2
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -u statbus XDG_RUNTIME_DIR=/run/user/$STATBUS_UID journalctl --user -xeu '$unit' --no-pager | tail -120" >&2 || true
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -u statbus XDG_RUNTIME_DIR=/run/user/$STATBUS_UID systemctl --user status '$unit' --no-pager" >&2 || true
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -i -u statbus -- bash -c 'cd ~/statbus && ./sb --version 2>/dev/null || true; git rev-parse HEAD 2>/dev/null || true'" >&2 || true
    echo "  ── end unit diagnostics ──" >&2
}

# _vm_unit_op OP UNIT [WAIT_S]
# Internal: issue `systemctl --user OP UNIT` on the VM, wait WAIT_S seconds,
# then check is-active. On any failure (command non-zero OR unit not active)
# dumps diagnostics via _dump_unit_diagnostics before returning non-zero.
# Does NOT call exit — let the caller / set -e decide.
_vm_unit_op() {
    local op="$1"
    local unit="${2:-statbus-upgrade@statbus.service}"
    local wait_s="${3:-5}"

    if ! VM_EXEC systemctl --user "$op" "$unit"; then
        echo "  ✗ systemctl --user $op $unit returned non-zero — capturing diagnostics:" >&2
        _dump_unit_diagnostics "$unit"
        return 1
    fi
    sleep "$wait_s"
    local state
    state=$(VM_EXEC systemctl --user is-active "$unit" 2>/dev/null | tr -d ' \r\n' || echo "?")
    if [ "$state" != "active" ]; then
        echo "  ✗ unit $unit not active after $op (state=$state) — capturing diagnostics:" >&2
        _dump_unit_diagnostics "$unit"
        return 1
    fi
    return 0
}

# vm_restart_unit UNIT [WAIT_S]
# Restart a stopped-or-running unit. Dumps diagnostics on failure before
# returning non-zero so logs survive before cleanup_vm reaps the VM.
vm_restart_unit() { _vm_unit_op restart "$@"; }

# vm_start_unit UNIT [WAIT_S]
# Start a stopped unit. Use instead of vm_restart_unit when the unit is
# already stopped (avoids a redundant stop step). Same diagnostic behaviour.
vm_start_unit() { _vm_unit_op start "$@"; }

cleanup_vm() {
    local vm_name="$1"
    _check_name_safety "$vm_name" || return 1

    # STATBUS-207/208 ownership guard: refuse to act on a VM this run did
    # not create — a cross-run name collision (two workflows deriving the
    # same VM name from the same scenario slug, e.g. test-install.yaml and
    # install-recovery-harness.yaml both running 0-happy-install) must
    # never let one job's cleanup delete (or even probe) another job's
    # live VM. bootstrap_install_test_vm only sets VM_OWNED_BY_THIS_RUN
    # after `hcloud server create` itself succeeded; a caller whose
    # bootstrap hit the refuse-on-existing check (another run's VM already
    # has this name) never sets it, so this call becomes a logged no-op
    # instead of deleting a VM this job never created.
    if [ "${VM_OWNED_BY_THIS_RUN:-0}" != "1" ]; then
        echo "cleanup_vm: NOT deleting '$vm_name' — this run never created it (VM_OWNED_BY_THIS_RUN unset)." >&2
        echo "  If this fired after a refuse-on-existing error, '$vm_name' belongs to a different run — leaving it to its own owner." >&2
        return 0
    fi

    # Surface detached-tmux stage logs (success OR failure) BEFORE reaping/leaving
    # the VM. Best-effort; a no-op for scenarios that never used a tmux install.
    dump_stage_tmux_logs "$vm_name"

    if [ "${KEEP_VM:-0}" = "1" ] || [ "${KEEP_VM_ON_FAILURE:-0}" = "1" ]; then
        local ip
        ip=$(hcloud server ip "$vm_name" 2>/dev/null || echo "?")
        local reason="KEEP_VM=1"
        [ "${KEEP_VM_ON_FAILURE:-0}" = "1" ] && reason="KEEP_VM_ON_FAILURE=1"
        echo "$reason — leaving $vm_name running for post-mortem (€0.0072/hr)"
        echo "  ssh root@$ip"
        echo "  ssh statbus@$ip"
        echo "  journalctl: ssh root@$ip journalctl --user -u statbus-upgrade@statbus --no-pager -n 200"
        echo "  upload logs: /tmp/upload-sb-scp-*.log  /tmp/upload-sb-ssh-*.log"
        echo "  Delete when done: hcloud server delete $vm_name"
        return 0
    fi
    echo "Deleting VM: $vm_name"
    hcloud server delete "$vm_name" 2>/dev/null || true
}
