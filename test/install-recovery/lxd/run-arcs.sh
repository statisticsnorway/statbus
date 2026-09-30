#!/usr/bin/env bash
# STATBUS-425 M3b: the upgrade-arc suite's LXD driver — the local counterpart
# of upgrade-arc-harness.yaml's construct+run-arc jobs, and the SAME driver
# M4's workflow step will call (mirrors run-forks.sh's relationship to
# lxd-fleet.yaml and run-smoke.sh's relationship to test-smoke.yaml — one
# code path, local and CI, so a local verdict here is the exact evidence M4
# relies on). No separate "shadow workflow" exists or is needed.
#
# Builds the same 7 fixture lineages construct_upgrade_target's workflow step
# builds (working/failing/oom/ceiling/healthpark/codeonly/crollback), maps
# every arcs/*-arc.sh to its lineage via the IDENTICAL case statement
# upgrade-arc-harness.yaml's "Resolve fixture lineage for the scenario" step
# uses (kept textually parallel on purpose — a change to one without the
# other is the exact drift this driver exists to prevent), then runs each
# arc against a fresh LXD fork of the candidate's own installed checkpoint.
#
# cross-version-rename-handoff is the one arc with NO construct lineage (see
# the case statement below and the workflow's own comment) — it pins a fixed
# pre-rename release commit and targets the run's own post-rename commit.
#
# Plain per-lineage variables (WORKING_B_FULL, FAILING_B_FULL, ...), never
# associative arrays: macOS ships bash 3.2 (no `declare -A`), and this driver
# runs from developer machines as well as CI (same constraint run-forks.sh
# documents for its own duplicate-check loop).
set -euo pipefail
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
TAG=${1:?usage: run-arcs.sh <tag> [--arc slug ...]}
shift
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]] || exit 2
export LXD_CANDIDATE=$TAG HARNESS_LXD_BACKEND=1
source "$ROOT/test/install-recovery/lib/lxd-backend.sh"
source "$ROOT/ops/lxd-fleet/marker.sh"
source "$ROOT/test/install-recovery/lib/upgrade-target.sh"
source "$ROOT/test/install-recovery/lxd/proc-tree.sh"
source "$ROOT/test/install-recovery/lxd/arc-job.sh"

PINNED_ROOT="${JCODE_SCRATCH_DIR:?JCODE_SCRATCH_DIR required}/lxd-s2-pinned-${TAG//[^a-zA-Z0-9-]/-}"
if [ ! -d "$PINNED_ROOT/.git" ] && [ ! -f "$PINNED_ROOT/.git" ]; then
    git -C "$ROOT" worktree add --detach "$PINNED_ROOT" "$TAG"
fi
[ "$(git -C "$PINNED_ROOT" rev-parse HEAD)" = "$(git -C "$ROOT" rev-parse "$TAG^{commit}")" ] || {
    echo 'REFUSE: pinned worktree HEAD is not candidate tag' >&2; exit 2;
}

# STATBUS-425 M3b (found live, real incident: two of this session's own
# retries at the same tag raced against this SAME shared PINNED_ROOT —
# one's git index.lock genuinely collided with the other's; a THIRD,
# unluckier interleaving corrupted the crollback lineage's C branch
# entirely, its `git commit` for C silently landing on the SAME tree as B
# because the second process's own `git checkout -B "$_c_branch" ...` for
# an EARLIER lineage momentarily left the worktree on B's branch while the
# first process's C commit ran there instead — verdict FAIL with no product
# signal at all, a pure harness data race, not caught by any assertion
# because the arc's own scripts never re-derive B/C from the branch names,
# only trust the env vars this driver computed). PINNED_ROOT is a single
# shared checkout keyed only by TAG (never by PID or run id, by design —
# reused warm across sessions), so construct's `git checkout -B`/`git
# commit`/`git push` sequence for EVERY lineage must run under a real,
# cross-process exclusive lock for the whole construct phase, not just a
# post-hoc HEAD-matches-tag check (which only catches the case where the
# OTHER process finishes LAST, not this shape).
#
# `mkdir` (not flock): flock(1) is NOT preinstalled on macOS (confirmed:
# `which flock` failed on this exact dev machine before this fix), and this
# driver explicitly also runs from developer machines, not only CI Linux
# runners (see the module header's bash-3.2 comment for the same
# "developer machine, not only CI" constraint). `mkdir` is atomic
# test-and-set on every POSIX filesystem this worktree could live on (no
# extra binary dependency), which is the same portability reasoning the
# rest of this codebase already uses for lock-like guards (e.g. harden-
# host.sh's own fleet-hardening.active marker is a plain file existence
# check under `set -C`-style exclusivity, not flock). A waiting invocation
# polls rather than blocking on an fd, bounded by the same 1800s budget.
# The lock directory lives ALONGSIDE PINNED_ROOT, never inside it: found
# live on the very first clean-run attempt after adding this lock — an
# in-tree lock directory (even untracked) is visible to
# _ut_fixture_base's own tree-identity diff (upgrade-target.sh), which
# genuinely failed construct with "the fixture base's tree differs from
# BASE_SHA OUTSIDE .github/workflows/" naming the lock's own holder file.
# A sibling path has no such interaction with anything that inspects
# PINNED_ROOT's git state.
PINNED_ROOT_LOCKDIR="${PINNED_ROOT}.construct.lock.d"
LOCK_HELD=0
echo "── acquiring PINNED_ROOT construct lock (another run-arcs.sh invocation may be using $PINNED_ROOT) ──"
if ! dirlock_acquire "$PINNED_ROOT_LOCKDIR" 1800 "${GITHUB_RUN_ID:-manual}"; then
    echo "REFUSE: could not acquire PINNED_ROOT construct lock within 1800s — a live invocation holds it (holder: $(cat "$PINNED_ROOT_LOCKDIR/holder" 2>/dev/null || echo unknown))" >&2
    exit 1
fi
LOCK_HELD=1
release_pinned_root_lock() {
    if [ "$LOCK_HELD" = 1 ]; then
        rmdir "$PINNED_ROOT_LOCKDIR" 2>/dev/null || rm -rf "$PINNED_ROOT_LOCKDIR"
        LOCK_HELD=0
    fi
}
trap release_pinned_root_lock EXIT
echo "── PINNED_ROOT construct lock acquired ──"

RUN_DIR="$PINNED_ROOT/tmp/lxd-arcs-${TAG}-$(date -u +%Y%m%dT%H%M%S)"
mkdir -p "$RUN_DIR"
printf 'arc\thetzner_verdict\tlxd_verdict\tlxd_wall_s\tlxd_rc\tlineage\n' > "$RUN_DIR/comparison.tsv"

# Per-run own marker (M2'/M3a: smoke, the fault driver and this arc driver
# can be genuinely active on the box concurrently once M4 lands; a single
# shared marker file cannot represent "more than one job is active").
MARKER_ID=$(lxd_marker_id "$TAG" arcs)
MARKER_HELD=0

phase=setup
finalize() {
    local rc=$? slug pid
    trap - EXIT INT TERM HUP
    # Owned arc children first (STATBUS-425 M3b review rec 2): they still
    # need the marker and the remote fixture branches (`git fetch origin
    # $B_BRANCH`).
    # Each arc subshell's run_bounded TERMs then KILLs its own process group
    # and returns only once the group is empty; a subshell that ignores that
    # is KILLed and its recorded group is stopped directly. Anything still
    # alive afterwards blocks marker release and branch deletion.
    # The shell's own job table is the authority, never the pids array, and
    # jobs are addressed by JOBSPEC (%N), never by raw pid. A raw pid taken
    # from `jobs -rp` can be reaped (and, in principle, reused by an unrelated
    # process) between the snapshot and the signal; that check-then-signal gap
    # cannot be closed for a pid. `jobs -r` lists only RUNNING jobs, so finished
    # ones are never selected. Two jobspec cases (both measured, see
    # stop_running_jobs in proc-tree.sh): a job already REMOVED from the table is
    # refused by bash ("no such job") and no signal is sent; a finished job still
    # RETAINED in the table resolves, and bash's kill skips its dead processes
    # (source-level liveness check) rather than refusing the spec. Either way no
    # raw pid is signalled, and liveness is read from the plain running list.
    local leak=0
    # Selection by jobspec, TERM, poll on the running-job table, KILL, wait:
    # see stop_running_jobs (proc-tree.sh) for why kill -0 %N is not used.
    stop_running_jobs $(( ${ARC_TIMEOUT_GRACE_S:-120} + 40 ))
    for slug in "${arcs[@]+"${arcs[@]}"}"; do
        [ -f "$RUN_DIR/$slug.pgid" ] || continue
        stop_group "$(cat "$RUN_DIR/$slug.pgid")" 5 || { leak=1; echo "✗ arc $slug process group still alive; not releasing marker or fixtures" >&2; }
    done
    pids=()
    # The shared pinned worktree is restored to its tag ONLY while this
    # invocation actually holds the construct lock, and BEFORE the lock is
    # released (STATBUS-425 M3b review): after release another invocation may
    # already be constructing in it, and an invocation that never held (or
    # already released) the lock must not touch it at all. The normal
    # post-construct path restores explicitly before its own release, so no
    # unlocked safety net exists. This trap REPLACES the earlier
    # `trap release_pinned_root_lock EXIT` (bash keeps one trap per signal),
    # hence the release here; it is a no-op unless LOCK_HELD=1.
    if [ "${LOCK_HELD:-0}" = 1 ]; then
        if [ -n "${PINNED_ROOT:-}" ] && [ -n "${TAG:-}" ]; then
            ( cd "$PINNED_ROOT" && git checkout -q --detach "$TAG" ) 2>/dev/null || true
        fi
        release_pinned_root_lock
    fi
    for slug in "${arcs[@]+"${arcs[@]}"}"; do
        [ -f "$RUN_DIR/$slug.row" ] || continue
        cat "$RUN_DIR/$slug.row" >> "$RUN_DIR/comparison.tsv"
    done
    if [ "$rc" -ne 0 ]; then
        printf '%s\t\tPHASE_FAILED\t\t%s\t\n' "$phase" "$rc" >> "$RUN_DIR/comparison.tsv"
    fi
    # Release only if actually acquired: acquiring before this trap is armed
    # (or before arc-selection validation) would leak the marker on an early
    # exit that never held it.
    if [ "$MARKER_HELD" = 1 ] && [ "$leak" = 0 ]; then
        lxd_marker_release "$LXD_HOST" "$MARKER_ID" || true
    fi
    # Symmetric with construct_upgrade_target's own ARC_NO_PUSH guard: nothing
    # was pushed when it's set, so there is nothing to delete.
    # RUN_ID is only assigned at construct: an earlier exit (bad --arc, marker
    # refusal) has nothing pushed, and must not abort this trap under set -u
    # (which would also replace the intended exit code).
    if [ "${ARC_NO_PUSH:-0}" != "1" ] && [ -n "${RUN_ID:-}" ] && [ "$leak" = 0 ]; then
        for spec in working failing oom ceiling healthpark codeonly crollback; do
            delete_throwaway_branches "$spec" "$RUN_ID" || true
        done
    fi
}
arcs=()
pids=()
trap finalize EXIT
# Signals must run finalize with the conventional 128+n status. `exit` inside
# a trap handler interrupts a blocking `wait` and then fires the EXIT trap.
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# ── select the arc domain ────────────────────────────────────────────────
if [ "$#" -eq 0 ]; then
    for script in "$ROOT"/test/install-recovery/arcs/*-arc.sh; do
        slug=${script##*/}; slug=${slug%-arc.sh}
        arcs+=("$slug")
    done
else
    while [ "$#" -gt 0 ]; do
        [ "$1" = --arc ] && [ "$#" -ge 2 ] || { echo 'Expected --arc slug' >&2; exit 2; }
        arcs+=("$2"); shift 2
    done
fi
dup=$(printf '%s\n' "${arcs[@]}" | sort | uniq -d)
[ -z "$dup" ] || { echo "Duplicate arc slug: $dup" >&2; exit 2; }
for slug in "${arcs[@]}"; do
    [ -f "$ROOT/test/install-recovery/arcs/${slug}-arc.sh" ] || {
        echo "Unknown arc: $slug (no test/install-recovery/arcs/${slug}-arc.sh)" >&2; exit 2;
    }
done

lxd_marker_acquire "$LXD_HOST" "$MARKER_ID"
MARKER_HELD=1

# arc_lineage_for SLUG — the SAME mapping upgrade-arc-harness.yaml's
# "Resolve fixture lineage for the scenario" step encodes (kept textually
# parallel; see the header comment). A change to one belongs with a matching
# change to the other.
arc_lineage_for() {
    case "$1" in
        failing|postswap-rollback-restore-watchdog|restore-broke-reattempt|deploy-status-proof|boot-migrate-churn-alive-idle|rollback-schema-floor-adoption|rollback-schema-floor-failure) echo failing ;;
        postswap-migration-oom)       echo oom ;;
        postswap-migration-ceiling)   echo ceiling ;;
        postswap-health-park)         echo healthpark ;;
        un-park-to-completion)        echo codeonly ;;
        c-rollback-resurrection)      echo crollback ;;
        cross-version-rename-handoff) echo crossversion ;;
        *)                            echo working ;;
    esac
}
needs_lineage() {
    local want="$1" slug lineage
    for slug in "${arcs[@]}"; do
        lineage=$(arc_lineage_for "$slug")
        [ "$lineage" = "$want" ] && return 0
    done
    return 1
}

# ── construct: one build per lineage actually needed by the selection ──────
# construct_upgrade_target operates on the CURRENT WORKING DIRECTORY's git
# repo (git checkout -B ..., git commit, ...) — it was written for CI, where
# the job's checkout IS the candidate tree. This driver's own checkout
# ($ROOT) is a live development worktree, never the candidate — so every
# construct call below runs from $PINNED_ROOT, never from $ROOT. (Found live:
# a first attempt without this cd ran construct_upgrade_target with $ROOT as
# CWD; it was caught only because a coincidental unrelated uncommitted edit
# in $ROOT made git refuse the checkout — a repo with a clean tree would have
# had construct_upgrade_target silently branch $ROOT itself off the tag and
# commit synthetic fixture migrations onto it.)
#
# construct_upgrade_target also leaves the repo's HEAD on the LAST lineage's
# C branch when it returns (never restores the starting ref) — so after every
# construct call below, PINNED_ROOT is explicitly reset back to the pinned
# tag before anything else touches it, keeping the shared persistent
# worktree exactly as later runs (and other sessions/workflows sharing the
# same JCODE_SCRATCH_DIR) expect to find it.
#
# construct_upgrade_target's `git push -f origin ...` for B/C is a LOCAL git
# operation to the real github.com, not a guest-facing call — but
# lxd-backend.sh's own PATH-prepended ssh shim (installed above by sourcing
# it) intercepts EVERY bare `ssh` call this process's descendants make,
# including git's, and refuses github.com's ssh transport with "does not
# match fork IP" (found live: the plain M2'/M3a shim's guest-only purpose
# does not distinguish git's own transport from a guest-facing call — it
# was never exercised by a git push before this driver). GIT_SSH_COMMAND
# routes git's OWN ssh transport at the real ssh binary directly, bypassing
# PATH (and therefore the shim) for git alone; every other command in this
# script still goes through the shim exactly as intended.
export GIT_SSH_COMMAND="$_LXD_REAL_SSH"
phase=construct
export RUN_ID="${GITHUB_RUN_ID:-manual}-$$"
BASE_SHA="$(git -C "$ROOT" rev-parse "$TAG^{commit}")"
echo "── constructing fixture lineages for: ${arcs[*]} ──"
cd "$PINNED_ROOT"

if needs_lineage working; then
    construct_upgrade_target "$BASE_SHA" working
    WORKING_B_FULL="$B_FULL"; WORKING_B_BRANCH="$B_BRANCH"
    WORKING_C_FULL="$C_FULL"; WORKING_C_BRANCH="$C_BRANCH"
    WORKING_V="$V_VERSION"; WORKING_V2="$V_VERSION_2"
fi
if needs_lineage failing; then
    construct_upgrade_target "$BASE_SHA" failing
    FAILING_B_FULL="$B_FULL"; FAILING_B_BRANCH="$B_BRANCH"
    FAILING_C_FULL="$C_FULL"; FAILING_C_BRANCH="$C_BRANCH"
    FAILING_V="$V_VERSION"
fi
if needs_lineage oom; then
    construct_upgrade_target "$BASE_SHA" oom
    OOM_B_FULL="$B_FULL"; OOM_B_BRANCH="$B_BRANCH"; OOM_V="$V_VERSION"
fi
if needs_lineage ceiling; then
    construct_upgrade_target "$BASE_SHA" ceiling
    CEILING_B_FULL="$B_FULL"; CEILING_B_BRANCH="$B_BRANCH"; CEILING_V="$V_VERSION"
fi
if needs_lineage healthpark; then
    construct_upgrade_target "$BASE_SHA" healthpark
    HEALTHPARK_B_FULL="$B_FULL"; HEALTHPARK_B_BRANCH="$B_BRANCH"; HEALTHPARK_B_SHORT="$B_SHORT"
    HEALTHPARK_C_FULL="$C_FULL"; HEALTHPARK_C_BRANCH="$C_BRANCH"
    HEALTHPARK_V="$V_VERSION"; HEALTHPARK_V2="$V_VERSION_2"; HEALTHPARK_V3="$V_VERSION_3"
fi
if needs_lineage codeonly; then
    construct_upgrade_target "$BASE_SHA" codeonly
    CODEONLY_B_FULL="$B_FULL"; CODEONLY_B_BRANCH="$B_BRANCH"
fi
if needs_lineage crollback; then
    construct_upgrade_target "$BASE_SHA" crollback
    CROLLBACK_B_FULL="$B_FULL"; CROLLBACK_B_BRANCH="$B_BRANCH"; CROLLBACK_B_SHORT="$B_SHORT"
    CROLLBACK_C_FULL="$C_FULL"; CROLLBACK_C_BRANCH="$C_BRANCH"
    CROLLBACK_V2="$V_VERSION_2"; CROLLBACK_V3="$V_VERSION_3"
fi
# ARC_PUBKEY set (and exported) by the first construct_upgrade_target call above.
ARC_PUBKEY_FINAL="${ARC_PUBKEY:-}"

# Restore the pinned worktree to the tag it is named for (see comment above)
# BEFORE leaving PINNED_ROOT, then return to $ROOT — every remaining phase
# below runs from $ROOT, referencing $ROOT/test/install-recovery/... paths
# explicitly, and has no CWD dependency on either worktree.
git checkout -q --detach "$TAG"
cd "$ROOT"
[ "$(git -C "$PINNED_ROOT" rev-parse HEAD)" = "$BASE_SHA" ] || {
    echo "REFUSE: PINNED_ROOT did not return to $TAG after construct — refusing to leave the shared worktree in an unexpected state" >&2
    exit 1
}
# Release the construct lock now: every remaining phase (images, base, run,
# verdict) never touches PINNED_ROOT's git state again, so holding the lock
# further would only block a concurrent invocation's construct phase for no
# reason. Explicit release_pinned_root_lock call (not just leaving it to the
# EXIT trap) lets a waiting invocation proceed immediately rather than
# waiting for THIS run's entire arc-run phase to finish too. The finalize
# trap installed below (before arc dispatch) REPLACES this function's own
# EXIT trap (bash keeps only the LAST trap per signal) — call it directly
# here so this phase's release is not silently lost the moment finalize's
# trap is armed.
release_pinned_root_lock
echo "── PINNED_ROOT construct lock released ──"

# ── dispatch images.yaml + wait for per-commit service images ──────────────
# Found live (first real smoke test): "no image-wait needed" was WRONG. The
# daemon's `docker compose up -d --no-build` (service.go) requires the four
# service images (db/app/worker/proxy) to already exist at each B/C commit's
# short SHA — sbimage.ProcureShort only ever fetches the toolchain-free `sb`
# binary image, never the service images, and has no build fallback anyway
# (its local-build path requires the CALLER's worktree to already be AT the
# target commit, which no fork guest's checkout ever is). Without a real
# dispatch+wait here every arc failed identically: "docker_images_status
# building" then "manifest unknown" for all four services. Mirrors CI's own
# construct job (dispatch) + image-wait job (poll) exactly, scoped to only
# the B/C short SHAs this run's selected lineages actually produced (never
# the full 7-lineage set CI always builds, since a narrow --arc selection
# here should not pay for lineages nothing in the selection rides).
phase=images
declare_short() { git -C "$PINNED_ROOT" rev-parse --short=8 "$1"; }
IMAGE_BRANCHES=() IMAGE_SHORTS=()
add_image_target() {
    local full="$1" branch="$2" short
    [ -n "$full" ] || return 0
    short=$(declare_short "$full")
    IMAGE_BRANCHES+=("$branch"); IMAGE_SHORTS+=("$short")
}
if needs_lineage working; then
    add_image_target "$WORKING_B_FULL" "$WORKING_B_BRANCH"
    add_image_target "$WORKING_C_FULL" "$WORKING_C_BRANCH"
fi
if needs_lineage failing; then
    add_image_target "$FAILING_B_FULL" "$FAILING_B_BRANCH"
    add_image_target "$FAILING_C_FULL" "$FAILING_C_BRANCH"
fi
if needs_lineage oom; then add_image_target "$OOM_B_FULL" "$OOM_B_BRANCH"; fi
if needs_lineage ceiling; then add_image_target "$CEILING_B_FULL" "$CEILING_B_BRANCH"; fi
if needs_lineage healthpark; then
    add_image_target "$HEALTHPARK_B_FULL" "$HEALTHPARK_B_BRANCH"
    add_image_target "$HEALTHPARK_C_FULL" "$HEALTHPARK_C_BRANCH"
fi
if needs_lineage codeonly; then add_image_target "$CODEONLY_B_FULL" "$CODEONLY_B_BRANCH"; fi
if needs_lineage crollback; then
    add_image_target "$CROLLBACK_B_FULL" "$CROLLBACK_B_BRANCH"
    add_image_target "$CROLLBACK_C_FULL" "$CROLLBACK_C_BRANCH"
fi

if [ "${#IMAGE_BRANCHES[@]}" -gt 0 ]; then
    echo "── dispatching images.yaml for ${#IMAGE_BRANCHES[@]} fixture branch(es) ──"
    for branch in "${IMAGE_BRANCHES[@]}"; do
        for attempt in 1 2 3 4 5; do
            if gh workflow run images.yaml --ref "$branch" --repo statisticsnorway/statbus 2>>"$RUN_DIR/images-dispatch.log"; then
                echo "Dispatched images.yaml for ${branch} (attempt ${attempt})."
                break
            fi
            [ "$attempt" -eq 5 ] && { echo "::error::could not dispatch images.yaml for ${branch} after 5 attempts" >&2; exit 1; }
            echo "  dispatch for ${branch} failed (attempt ${attempt}/5) — ref not propagated yet? retrying in 5s..." >&2
            sleep 5
        done
    done

    echo "── waiting for images at: ${IMAGE_SHORTS[*]} ──"
    IMAGES_WAIT_BUDGET_S=${IMAGES_WAIT_BUDGET_S:-2400}
    IMAGES_WAIT_INTERVAL_S=${IMAGES_WAIT_INTERVAL_S:-30}
    services="app worker db proxy"
    start=$(date +%s)
    while :; do
        missing=""
        for short in "${IMAGE_SHORTS[@]}"; do
            for svc in $services; do
                ref="ghcr.io/statisticsnorway/statbus-${svc}:${short}"
                docker manifest inspect "$ref" >/dev/null 2>&1 || missing="${missing} statbus-${svc}:${short}"
            done
        done
        if [ -z "$missing" ]; then
            echo "All per-commit service images present."
            break
        fi
        elapsed=$(( $(date +%s) - start ))
        if [ "$elapsed" -ge "$IMAGES_WAIT_BUDGET_S" ]; then
            echo "::error title=Arc images not published::missing after $((IMAGES_WAIT_BUDGET_S/60))m:${missing}" >&2
            exit 1
        fi
        echo "Waiting for:${missing} (elapsed ${elapsed}s / ${IMAGES_WAIT_BUDGET_S}s) — re-checking in ${IMAGES_WAIT_INTERVAL_S}s..."
        sleep "$IMAGES_WAIT_INTERVAL_S"
    done
else
    echo "── no fixture image targets needed for the selected arc(s) ──"
fi

phase=base
BASE_CHECKPOINT=hardened-nothing-installed
lxd_base_for_candidate "$TAG" "$BASE_CHECKPOINT" >"$RUN_DIR/base.log" 2>&1 || {
    echo "BASE FAILED; see $RUN_DIR/base.log" >&2; exit 1;
}

MAX_PARALLEL=${LXD_PARALLEL:-6}
[[ "$MAX_PARALLEL" =~ ^[1-8]$ ]] || { echo 'LXD_PARALLEL must be 1..8' >&2; exit 2; }

# macOS Bash parses the first UTF-8 byte following an unbraced expansion as
# part of the variable name in an arc's own diagnostic printf (same class of
# issue run-forks.sh documents for scenario shells). Bytewise C on macOS,
# leaving arc assertions untouched.
arc_locale=${LC_ALL:-C}
if [ "$(uname -s)" = Darwin ]; then arc_locale=C; fi

phase=run
for slug in "${arcs[@]}"; do
    lineage=$(arc_lineage_for "$slug")
    (
        started=$(date +%s)
        export BASE_SHA SB_ARC_TRUSTED_SIGNER="$ARC_PUBKEY_FINAL" LC_ALL="$arc_locale"
        case "$lineage" in
            working)
                export B_FULL="$WORKING_B_FULL" B_BRANCH="$WORKING_B_BRANCH"
                export C_FULL="$WORKING_C_FULL" C_BRANCH="$WORKING_C_BRANCH"
                export V_VERSION="$WORKING_V" V_VERSION_2="$WORKING_V2"
                ;;
            failing)
                export B_FULL="$FAILING_B_FULL" B_BRANCH="$FAILING_B_BRANCH"
                export C_FULL="$FAILING_C_FULL" C_BRANCH="$FAILING_C_BRANCH"
                export V_VERSION="$FAILING_V"
                if [ "$slug" = rollback-schema-floor-adoption ]; then
                    export SCHEMA_FLOOR_BASE_SHA=d53731ec539b03b9378ff8828bb2be938d9e2e0f
                fi
                ;;
            oom)
                export B_FULL="$OOM_B_FULL" B_BRANCH="$OOM_B_BRANCH" V_VERSION="$OOM_V"
                ;;
            ceiling)
                export B_FULL="$CEILING_B_FULL" B_BRANCH="$CEILING_B_BRANCH" V_VERSION="$CEILING_V"
                ;;
            healthpark)
                export B_FULL="$HEALTHPARK_B_FULL" B_BRANCH="$HEALTHPARK_B_BRANCH" B_SHORT="$HEALTHPARK_B_SHORT"
                export C_FULL="$HEALTHPARK_C_FULL" C_BRANCH="$HEALTHPARK_C_BRANCH"
                export V_VERSION="$HEALTHPARK_V" V_VERSION_2="$HEALTHPARK_V2" V_VERSION_3="$HEALTHPARK_V3"
                ;;
            codeonly)
                export B_FULL="$CODEONLY_B_FULL" B_BRANCH="$CODEONLY_B_BRANCH"
                ;;
            crollback)
                export B_FULL="$CROLLBACK_B_FULL" B_BRANCH="$CROLLBACK_B_BRANCH" B_SHORT="$CROLLBACK_B_SHORT"
                export C_FULL="$CROLLBACK_C_FULL" C_BRANCH="$CROLLBACK_C_BRANCH"
                export V_VERSION_2="$CROLLBACK_V2" V_VERSION_3="$CROLLBACK_V3"
                ;;
            crossversion)
                export PRE_RENAME_BASE_SHA="${PRE_RENAME_BASE_SHA:-730b5001c099a660dc8ce28d9bf8167781704695}"
                export TARGET_SHA="$BASE_SHA" TARGET_BRANCH="$TAG"
                ;;
        esac
        # Shared per-arc runner (arc-job.sh, also used by the workflow's
        # run-arc job): slot claim, bounded run, verdict. rc is its PASS/FAIL.
        rc=0
        RUN_BOUNDED_PGID_FILE="$RUN_DIR/$slug.pgid" verdict=$(lxd_arc_run "$slug" "$RUN_DIR/$slug.log" "$MARKER_ID") || rc=$?
        verdict=${verdict##*$'\n'}
        # lxd_arc_run returns run_bounded's real rc: 125 only when the group
        # could not be emptied (pgid file kept so finalize can still stop it,
        # slot stays held); otherwise the group is gone and its (now
        # reusable) id must never be signalled again by finalize.
        [ "$rc" -eq 125 ] || rm -f "$RUN_DIR/$slug.pgid"
        printf '%s\t\t%s\t%s\t%s\t%s\n' "$slug" "$verdict" "$(( $(date +%s) - started ))" "$rc" "$lineage" > "$RUN_DIR/$slug.row"
    ) &
    pids+=("$!")
    if [ "${#pids[@]}" -ge "$MAX_PARALLEL" ]; then
        wait "${pids[0]}" || true
        pids=("${pids[@]:1}")
    fi
done
while [ "${#pids[@]}" -gt 0 ]; do
    wait "${pids[0]}" || true
    pids=("${pids[@]:1}")
done

phase=verdict
echo "Logs and comparison template: $RUN_DIR"
fail=0
for slug in "${arcs[@]}"; do
    [ -f "$RUN_DIR/$slug.row" ] || { echo "Missing result: $slug" >&2; fail=1; continue; }
    awk -F '\t' '$3 != "PASS" { exit 1 }' "$RUN_DIR/$slug.row" || { echo "FAILED: $slug"; fail=1; }
done
[ "$fail" -eq 0 ]
echo "PASSED: all ${#arcs[@]} selected arc(s)."
