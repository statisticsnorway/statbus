#!/usr/bin/env bash
# A rented server for measuring StatBus import and recalculation speed per
# commit, on a machine the size of a production host with nothing else on it.
# Each round checks out one commit and runs that commit's own code: the sb
# binary from its statbus-sb image, the worker from its statbus-worker image,
# the seed from its statbus-seed image, its migrations. The BRREG loader is the
# measurement's input and the same for every round: samples/norway/brreg from
# the commit this script is run from. Nothing
# is compiled on the box. Delete it when the measurement is done; what it holds
# goes with it.
#
#   ops/bench-box.sh up        create the server and prepare it (or show it if it exists):
#                              the published setup script (base system, statbus
#                              account, Docker), python3-venv, the StatBus checkout
#   ops/bench-box.sh data      copy the BRREG files from rune (statbus@rune.statbus.org,
#                              read only) to the box, server to server
#   ops/bench-box.sh run <base> <candidate> [order]
#                              alternating rounds of two commits (default order
#                              base candidate candidate base), detached on the box;
#                              each round: fresh database, full BRREG import, full
#                              recalculation, fingerprint of every public table
#   ops/bench-box.sh progress  the running measurement's log so far
#   ops/bench-box.sh stop      end the running measurement, every round of it
#
# Recalculation on restored data (no import), one commit per box:
#   ops/bench-box.sh stack <commit>      that commit's stack, empty database
#   ops/bench-box.sh restore <dump>      a Norway dump from rune:statbus/dbdumps,
#                              then the commit's migrations on top
#   ops/bench-box.sh recalc <label> [pct]
#                              time one recalculation by the commit's worker:
#                              full (default), or after renaming pct percent of
#                              the legal units (the same units on every box)
#   ops/bench-box.sh series <base> <candidate> [pcts, default "1 50 99"]
#                              after restore at <base> and one recalc, the whole
#                              comparison, detached: freeze the database (copy in
#                              Postgres, about a minute), base's changes, then the
#                              candidate on a fresh copy of the frozen base:
#                              migrate, full recalculation, the same changes.
#                              Results in ~/bench/series; follow with: series-log
#   ops/bench-box.sh series-log   the series log so far
#   Add --box NAME to any command to address a second box, statbus-bench-NAME.
#   ops/bench-box.sh results   copy the round logs and fingerprints to tmp/bench/
#                              and print the summary
#   ops/bench-box.sh ssh       log in as statbus
#   ops/bench-box.sh status    (or info) the box: address, type, created
#   ops/bench-box.sh down      delete it (billing stops)
#
# Commits are anything git rev-parse accepts (v2026.11.4-rc.01, master, a SHA).
# A commit without published images (a branch not on master) has its images
# built on the box by docker compose, once; like pulled images, they stay in
# the box's Docker cache for later rounds.
#
# Cost: ccx33 (8 dedicated cores, 32 GB, 240 GB) is about EUR 0.24 per hour,
# billed hourly. A four-round run takes a few hours. It shares the project's
# dedicated-core limit with the release ladder's LXD fleet host; if up is
# refused for cores, it names the dedicated servers holding them, and a
# release outranks a measurement: down the box when the release needs the cores.

# The whole script is one block, so bash reads it completely before running:
# editing this file during a long run changes nothing for the running copy.
{
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1090
source "${STATBUS_CREDENTIALS_FILE:-$ROOT/.env.credentials}"
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN is required in .env.credentials}"
export HCLOUD_TOKEN

name=statbus-bench
# --box NAME, anywhere on the command line, addresses a second box
# (statbus-bench-NAME), so two commits can be measured side by side.
args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --box) [[ "${2:-}" =~ ^[a-z0-9]+$ ]] || { echo "--box takes a short name of lower-case letters and digits" >&2; exit 2; }
               name=statbus-bench-$2; shift 2 ;;
        *) args+=("$1"); shift ;;
    esac
done
set -- ${args[@]+"${args[@]}"}
type=ccx33
image=ubuntu-26.04
# Falkenstein, rune's data centre: the BRREG files travel server to server.
location=fsn1
ssh_key='jorgen@veridit.no'
label=statbus-purpose=bench-box
github_users=jhf
rune=statbus@rune.statbus.org
repo=https://github.com/statisticsnorway/statbus.git
results="$ROOT/tmp/bench"
# ssh forwards LANG and LC_*; the box has only C.UTF-8 and en_US.UTF-8.
export LANG=C.UTF-8 LC_ALL=C.UTF-8
unset LANGUAGE

describe() { hcloud server describe "$name" -o json 2>/dev/null || true; }

# A same-name server that is not labelled as ours is someone else's: refuse.
require_ours() {
    [ "$(jq -r '.labels["statbus-purpose"] // empty' <<<"$1")" = bench-box ] \
        || { echo "REFUSE: server '$name' exists but is not labelled $label" >&2; exit 1; }
}

box_ip() {
    # Looked up once per command: a describe right after create can come back
    # empty, and every later ssh needs the same address.
    if [ -z "${BOX_IP:-}" ]; then
        local server
        server=$(describe)
        [ -n "$server" ] || { echo "No server '$name'; run: ops/bench-box.sh up" >&2; exit 1; }
        require_ours "$server"
        BOX_IP=$(jq -er '.public_net.ipv4.ip' <<<"$server")
    fi
    echo "$BOX_IP"
}

box() { # user command...: run a command on the box
    local user=$1 ip; shift
    ip=$(box_ip)
    [ -n "$ip" ] || exit 1
    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$user@$ip" "$@"
}

# box_script user [ssh options...] < script: run a script on the box from a file.
# A script fed to "bash -s" on stdin is read by the first command in it that
# reads stdin (docker compose, psql), which swallows the rest of the script.
box_script() {
    local user=$1 ip f; shift
    ip=$(box_ip)
    [ -n "$ip" ] || exit 1
    f=bench-step-$$.sh
    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$user@$ip" "cat > /tmp/$f"
    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$@" "$user@$ip" \
        "bash -euo pipefail /tmp/$f < /dev/null; rc=\$?; rm -f /tmp/$f; exit \$rc"
}

wait_for_ssh() {
    local ip=$1 i
    ssh-keygen -R "$ip" >/dev/null 2>&1 || true
    for ((i = 0; i < 90; i++)); do
        if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "root@$ip" 'cloud-init status --wait >/dev/null 2>&1; true' 2>/dev/null; then
            return 0
        fi
        sleep 2
    done
    echo "SSH as root did not answer on $ip within 3 minutes" >&2
    exit 1
}

# The published setup script, the one operators run, limited to the stages a
# measurement box needs: no firewall, SSH hardening or unattended upgrades on
# a box that lives for hours and listens only on loopback (development mode).
# Setup asks for the server's full name, as for any StatBus server; this box
# has no public one, so it is given a .local name, as manual-box does.
prepare() {
    box_script root <<EOF
set -euo pipefail
cat > /root/.setup-ubuntu.env <<CFG
GITHUB_USERS="$github_users"
SERVICE_USER="statbus"
EXTRA_LOCALES=""
SERVER_FQDN="$name.statbus-test.local"
CFG
curl -fsSL https://statbus.org/setup.sh -o /root/setup.sh
cd /root && HOME=/root bash -l /root/setup.sh --non-interactive --only-stages "base-system service-account core-tools" > /root/setup.log 2>&1 \
    || { tail -40 /root/setup.log; exit 1; }
# Releases before STATBUS-616 do not install python3-venv in core-tools; the
# loader's helpers need it.
dpkg -s python3-venv > /dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y -q python3-venv > /dev/null
EOF
    box_script statbus <<EOF
set -euo pipefail
[ -d ~/statbus/.git ] || git clone -q $repo ~/statbus
mkdir -p ~/statbus/tmp
# A development slot, as CI's fast-tests job writes it: every port on loopback,
# no public name. Without it, config generate takes the box for a standalone
# installation and asks for its domain.
[ -f ~/statbus/.env.config ] && grep -q '^CADDY_DEPLOYMENT_MODE=' ~/statbus/.env.config || cat > ~/statbus/.env.config <<CFG
DEPLOYMENT_SLOT_NAME=Bench
DEPLOYMENT_SLOT_CODE=bench
DEPLOYMENT_SLOT_PORT_OFFSET=1
CADDY_DEPLOYMENT_MODE=development
SITE_DOMAIN=localhost
CFG
EOF
}

show() {
    local server=$1
    cat <<EOF
Box:      $name, $(jq -r '.public_net.ipv4.ip' <<<"$server") ($type, $image, $location), created $(jq -r '.created' <<<"$server")
Log in:   ops/bench-box.sh ssh
Data:     ops/bench-box.sh data
Measure:  ops/bench-box.sh run <base> <candidate>
EOF
}

# One measurement, run on the box as statbus in ~/statbus, detached from the
# laptop. Writes ~/bench/<run>/: run.log, and per round round-<n>-<label>.log and
# .fingerprint. Arguments: run id, then label=sha pairs in round order.
round_script() {
    cat <<'ROUNDS'
set -euo pipefail
run=$1; shift
out=~/bench/$run; mkdir -p "$out"
exec > >(tee -a "$out/run.log") 2>&1
cd ~/statbus
sql() { ./sb psql -X -At -v ON_ERROR_STOP=1 "$@"; }
n=0
for pair in "$@"; do
    n=$((n + 1)); label=${pair%%=*}; sha=${pair#*=}
    log="$out/round-$n-$label.log"
    echo "== round $n $label $sha start $(date -u +%FT%TZ) load $(cut -d' ' -f1-3 /proc/loadavg)"
    # A round runs as its own bash -e script, so its first failing step ends it
    # (inside an || list, set -e would not apply). It is a file, not a heredoc on
    # stdin: a step that reads stdin (docker compose exec, psql) would swallow the
    # rest of the script.
    sed -n '/^#ROUND-BEGIN$/,/^#ROUND-END$/p' ~/bench/rounds.sh > ~/bench/round.sh
    out="$out" n="$n" label="$label" sha="$sha" bash -euo pipefail ~/bench/round.sh < /dev/null > "$log" 2>&1 \
        || { echo "round $n FAILED, see $log"; tail -20 "$log"; exit 1; }
    grep -E '^(commit|sb|seed|import|recalc|fingerprint) ' "$log" | sed 's/^/  /'
done
first=$(ls "$out"/round-1-*.fingerprint)
same=1
for f in "$out"/round-*.fingerprint; do cmp -s "$first" "$f" || { same=0; echo "FINGERPRINT DIFFERS: $f"; diff "$first" "$f" | head -20; }; done
[ "$same" = 1 ] && echo "all rounds: fingerprints identical"
echo "== done $(date -u +%FT%TZ)"
exit
#ROUND-BEGIN
        cd ~/statbus
        sql() { ./sb psql -X -At -v ON_ERROR_STOP=1 "$@"; }
        # The commit's own code and images. A previous round's stack is removed
        # with its volume: every round starts from the same empty database.
        docker compose --profile all down -v --remove-orphans > /dev/null 2>&1 || true
        git fetch -q origin && git checkout -q -f --detach "$sha" && git clean -fdq -e tmp/ -e .env.config -e .env.credentials -e .users.yml
        # The BRREG loader is the measurement's input, not the code under test:
        # every round loads with the same loader, the one bench-box ships from
        # its own commit, so all rounds get the same rows in the same way.
        tar -xf ~/bench/loader.tar
        [ -f .users.yml ] || cp .users.example .users.yml
        echo "commit $(git rev-parse HEAD) $(git describe --tags --always)"
        rm -f ./sb
        # dev.sh procures ./sb from the commit's statbus-sb image before it reads
        # .env; on the first round there is no .env yet, so only ./sb is checked.
        ./dev.sh postgres-variables > /dev/null 2>&1 || true
        [ -x ./sb ] || { echo "dev.sh did not procure ./sb"; exit 1; }
        # Commits before STATBUS-616 keep the image's build time on the procured
        # sb, older than this clone's files, so their dev.sh procures it again on
        # every call. Taking now as its mtime makes it current for those commits too.
        touch ./sb
        echo "sb $(./sb --version 2>&1 | head -1)"
        ./sb config generate > /dev/null
        docker compose --profile all_except_app pull -q || docker compose --profile all_except_app build -q
        docker compose up -d --wait db proxy rest > /dev/null
        ./dev.sh create-db-structure > /dev/null
        ./sb users create > /dev/null
        ./dev.sh recreate-seed > /dev/null
        ./dev.sh create-test-template > /dev/null
        docker compose images --format '{{.Service}} {{.Repository}}:{{.Tag}}' 2>/dev/null || docker compose images
        echo "seed migration $(sql -d statbus_seed -c 'SELECT max(version) FROM db.migration')"
        # The benchmark database. The service worker stays down: the timed worker
        # is a one-off container of the same image, run with --stop-when-idle.
        db=bench_round_$n
        sql -d postgres -c "ALTER DATABASE statbus_test_template WITH ALLOW_CONNECTIONS = true" -c "CREATE DATABASE $db WITH TEMPLATE statbus_test_template" -c "ALTER DATABASE statbus_test_template WITH ALLOW_CONNECTIONS = false" > /dev/null
        sql -d "$db" -f test/setup.sql > /dev/null
        USER_EMAIL=test.admin@statbus.org samples/norway/brreg/brreg-import-downloads-from-tmp.sh --database "$db" --valid-from 2026-04-01 > "$out/round-$n-$label.load.log" 2>&1
        timed() { # phase: run the worker until idle, report wall time and per command time
            local phase=$1 first t0 t1
            first=$(sql -d "$db" -c "SELECT coalesce(max(id), 0) FROM worker.tasks")
            t0=$(date +%s)
            docker compose run --rm -T --no-deps worker timeout 36000 /app/bin/statbus worker --stop-when-idle --database "$db" > "$out/round-$n-$label.$phase.worker.log" 2>&1
            t1=$(date +%s)
            echo "$phase wall_s $((t1 - t0)) failed $(sql -d "$db" -c "SELECT count(*) FROM worker.tasks WHERE id > $first AND state = 'failed'")"
            sql -d "$db" -F ' ' -c "SELECT command, count(*), round(sum(process_duration_ms) / 1000, 1) FROM worker.tasks WHERE id > $first GROUP BY 1 ORDER BY 3 DESC NULLS LAST LIMIT 12" | sed "s/^/  $phase /"
        }
        timed import
        sql -d "$db" -c "SELECT slug, state, imported_rows FROM public.import_job ORDER BY id" | sed 's/^/  job /'
        unfinished=$(sql -d "$db" -c "SELECT count(*) FROM public.import_job WHERE state <> 'finished'")
        [ "$unfinished" = 0 ] || { echo "import: $unfinished job(s) not finished"; exit 1; }
        sql -d "$db" -c "SELECT worker.enqueue_derive_statistical_unit_all()" > /dev/null
        timed recalc
        sql -d "$db" < "$HOME/bench/fingerprint.sql" > "$out/round-$n-$label.fingerprint"
        echo "fingerprint $(md5sum < "$out/round-$n-$label.fingerprint" | cut -c1-12) tables $(wc -l < "$out/round-$n-$label.fingerprint")"
#ROUND-END
ROUNDS
}

case "${1:-}" in
up)
    server=$(describe)
    if [ -z "$server" ]; then
        # Hetzner enforces the project's core limit itself and does not publish it
        # through its API, so the create is the check. When it is refused, name
        # the dedicated-core servers holding the cores: the release ladder's LXD
        # fleet host (ops/lxd-fleet/up.sh) is one, and a release outranks a
        # measurement.
        if ! hcloud server create --name "$name" --type "$type" --image "$image" \
            --location "$location" --ssh-key "$ssh_key" --label "$label" >/dev/null; then
            echo "Dedicated-core servers running now: $(hcloud server list -o json | jq -r '[.[] | select(.server_type.cpu_type == "dedicated") | "\(.name) (\(.server_type.name))"] | join(", ")')" >&2
            exit 1
        fi
        server=$(describe)
    fi
    require_ours "$server"
    BOX_IP=$(jq -er '.public_net.ipv4.ip' <<<"$server")
    wait_for_ssh "$BOX_IP"
    prepare
    show "$server"
    ;;
data)
    # Server to server with this laptop's key forwarded: rune is only read.
    ip=$(box_ip)
    ssh -A -o BatchMode=yes "statbus@$ip" \
        "ssh-keygen -F rune.statbus.org >/dev/null || ssh-keyscan -H rune.statbus.org >> ~/.ssh/known_hosts 2>/dev/null; rsync -a --info=stats1 $rune:statbus/tmp/enheter.csv $rune:statbus/tmp/underenheter_filtered.csv $rune:statbus/tmp/roller_legal_relationships.csv ~/statbus/tmp/ && md5sum ~/statbus/tmp/enheter.csv ~/statbus/tmp/underenheter_filtered.csv ~/statbus/tmp/roller_legal_relationships.csv"
    ;;
run)
    base=${2:?Usage: ops/bench-box.sh run <base> <candidate> [order, default: base candidate candidate base]}
    candidate=${3:?Usage: ops/bench-box.sh run <base> <candidate> [order]}
    order=${4:-base candidate candidate base}
    base_sha=$(git -C "$ROOT" rev-parse --verify "$base^{commit}")
    candidate_sha=$(git -C "$ROOT" rev-parse --verify "$candidate^{commit}")
    pairs=""
    for r in $order; do
        case "$r" in
            base) pairs="$pairs base=$base_sha" ;;
            candidate) pairs="$pairs candidate=$candidate_sha" ;;
            *) echo "Order words are base and candidate, got: $r" >&2; exit 2 ;;
        esac
    done
    run_id=$(date -u +%Y%m%dT%H%M%SZ)
    # One measurement at a time: two would share the database and the CPUs.
    if box statbus 'pgrep -f "bench/round" > /dev/null'; then
        echo "REFUSE: a measurement is running on the box. See: ops/bench-box.sh progress; end it with: ops/bench-box.sh stop" >&2
        exit 1
    fi
    box statbus "mkdir -p ~/bench && cat > ~/bench/rounds.sh" < <(round_script)
    box statbus "cat > ~/bench/fingerprint.sql" < "$ROOT/ops/bench-box-fingerprint.sql"
    git -C "$ROOT" archive HEAD samples/norway/brreg samples/norway/getting-started.sql \
        | box statbus "cat > ~/bench/loader.tar"
    echo "Loader: samples/norway/brreg at $(git -C "$ROOT" rev-parse --short HEAD) (this checkout's HEAD) for every round"
    # setsid with every stream redirected: the run holds none of this ssh
    # session's streams, so the ssh returns at once and the run outlives it.
    box statbus "setsid bash ~/bench/rounds.sh $run_id$pairs > /dev/null 2>&1 < /dev/null & echo started"
    echo "Run $run_id: $base ($base_sha) against $candidate ($candidate_sha), rounds: $order"
    echo "Follow:  ops/bench-box.sh progress     Collect: ops/bench-box.sh results"
    ;;
progress)
    box statbus 'f=$(ls -t ~/bench/*/run.log 2>/dev/null | head -1); [ -n "$f" ] || { echo "No run yet."; exit 0; }; echo "$f"; cat "$f"; pgrep -f "bench/round" >/dev/null && echo "(running, load $(cut -d" " -f1-3 /proc/loadavg))" || echo "(not running)"'
    ;;
stop)
    # The run is its own session (setsid), and every round, worker container
    # client and psql it starts belongs to it: end the whole session, so no
    # round outlives its run.
    box statbus 'sids=$(ps -eo sid=,args= | awk "/bench\/round/ {print \$1}" | sort -u); [ -n "$sids" ] || { echo "Nothing running."; exit 0; }; for s in $sids; do pkill -TERM -s "$s"; done; sleep 2; for s in $sids; do pkill -KILL -s "$s" 2>/dev/null; done; cd ~/statbus && docker compose ps -q --filter name=worker-run | xargs -r docker rm -f > /dev/null; echo "Stopped session(s): $sids"'
    ;;
stack)
    # The commit's stack with an empty database, no import: for a restored dump.
    commit=${2:?Usage: ops/bench-box.sh stack <commit> [--box NAME]}
    sha=$(git -C "$ROOT" rev-parse --verify "$commit^{commit}")
    box_script statbus <<EOF
set -euo pipefail
cd ~/statbus
docker compose --profile all down -v --remove-orphans > /dev/null 2>&1 || true
git fetch -q origin && git checkout -q -f --detach $sha
[ -f .users.yml ] || cp .users.example .users.yml
rm -f ./sb
./dev.sh postgres-variables > /dev/null 2>&1 || true
[ -x ./sb ] || { echo "dev.sh did not procure ./sb"; exit 1; }
# Commits before STATBUS-616 keep the image's build time on the procured sb.
touch ./sb
./sb config generate > /dev/null
docker compose --profile all_except_app pull -q
docker compose up -d --wait db proxy rest > /dev/null
echo "stack \$(git describe --tags --always), \$(./sb --version | head -1)"
EOF
    ;;
restore)
    # A Norway dump from rune into this box's app database, then the box's
    # commit's migrations on top. Rune is only read.
    dump=${2:?Usage: ops/bench-box.sh restore <dump file in rune:statbus/dbdumps> [--box NAME]}
    [[ "$dump" =~ ^[A-Za-z0-9_.-]+\.pg_dump$ ]] || { echo "Not a dump file name: $dump" >&2; exit 2; }
    ip=$(box_ip)
    box_script statbus -A <<EOF
set -euo pipefail
cd ~/statbus && mkdir -p dbdumps
ssh-keygen -F rune.statbus.org > /dev/null || ssh-keyscan -H rune.statbus.org >> ~/.ssh/known_hosts 2> /dev/null
[ -s dbdumps/$dump ] || rsync -a $rune:statbus/dbdumps/$dump dbdumps/
t0=\$(date +%s)
./sb db restore dbdumps/$dump --yes > tmp/bench-restore.log 2>&1 || { tail -20 tmp/bench-restore.log; exit 1; }
docker compose stop worker > /dev/null 2>&1 || true
./sb migrate up > tmp/bench-migrate.log 2>&1 || { tail -20 tmp/bench-migrate.log; exit 1; }
echo "restored $dump in \$((\$(date +%s) - t0)) s, now at migration \$(./sb psql -X -At -c 'SELECT max(version) FROM db.migration')"
./sb psql -X -At -F ' ' -c "SELECT unit_type, count(*) FROM public.statistical_unit GROUP BY 1 ORDER BY 1" | sed 's/^/  units /'
EOF
    ;;
series)
    base=${2:?Usage: ops/bench-box.sh series <base> <candidate> [pcts] [--box NAME]}
    candidate=${3:?Usage: ops/bench-box.sh series <base> <candidate> [pcts] [--box NAME]}
    pcts=${4:-1 50 99}
    [[ "$pcts" =~ ^[0-9\ ]+$ ]] || { echo "pcts: whole numbers separated by spaces" >&2; exit 2; }
    base_sha=$(git -C "$ROOT" rev-parse --verify "$base^{commit}")
    candidate_sha=$(git -C "$ROOT" rev-parse --verify "$candidate^{commit}")
    if box statbus 'pgrep -f "bench/series.sh" > /dev/null'; then
        echo "REFUSE: a series is running on the box. See: ops/bench-box.sh series-log" >&2; exit 1
    fi
    box statbus "mkdir -p ~/bench && cat > ~/bench/fingerprint.sql" < "$ROOT/ops/bench-box-fingerprint.sql"
    box statbus "cat > ~/bench/series.sh" < "$ROOT/ops/bench-box-series.sh"
    box statbus "rm -rf ~/bench/series; setsid bash ~/bench/series.sh $base_sha $candidate_sha '$pcts' > /dev/null 2>&1 < /dev/null & echo started"
    echo "Series: $base ($base_sha) then $candidate ($candidate_sha), changes $pcts %. Follow: ops/bench-box.sh series-log"
    ;;
series-log)
    box statbus 'cat ~/bench/series/series.log 2>/dev/null || echo "No series yet."; pgrep -f bench/series.sh > /dev/null && echo "(running, load $(cut -d" " -f1-3 /proc/loadavg))" || echo "(not running)"'
    ;;
recalc)
    # One timed recalculation of the box's app database by its commit's worker
    # image. full: everything. A number: first rename that percent of the
    # current legal units, chosen by id modulo 100 so every box changes the same
    # units, and time the recalculation that change sets off.
    label=${2:?Usage: ops/bench-box.sh recalc <label> [full|pct] [--box NAME]}
    pct=${3:-full}
    [[ "$label" =~ ^[a-z0-9_-]+$ ]] || { echo "Label: lower-case letters, digits, - and _" >&2; exit 2; }
    [[ "$pct" = full || "$pct" =~ ^([1-9][0-9]?|100)$ ]] || { echo "Give full or a percent 1-100" >&2; exit 2; }
    box statbus "mkdir -p ~/bench/recalc && cat > ~/bench/fingerprint.sql" < "$ROOT/ops/bench-box-fingerprint.sql"
    box_script statbus <<EOF
set -euo pipefail
cd ~/statbus
sql() { ./sb psql -X -At -v ON_ERROR_STOP=1 "\$@"; }
out=~/bench/recalc/$label
docker compose stop worker > /dev/null 2>&1 || true
sql -c "VACUUM (ANALYZE)" > /dev/null
first=\$(sql -c "SELECT coalesce(max(id), 0) FROM worker.tasks")
if [ "$pct" = full ]; then
    sql -c "SELECT worker.enqueue_derive_statistical_unit_all()" > /dev/null
    changed=all
else
    # The WHERE names the rows (safeupdate): the chosen share of current records.
    changed=\$(sql -c "WITH c AS (UPDATE public.legal_unit SET name = left(name, 230) || ' (bench $label)' WHERE id % 100 < $pct AND valid_until = 'infinity' RETURNING 1) SELECT count(*) FROM c")
fi
t0=\$(date +%s)
docker compose run --rm -T --no-deps worker timeout 36000 /app/bin/statbus worker --stop-when-idle > \$out.worker.log 2>&1
t1=\$(date +%s)
{
  echo "$label change=$pct rows=\$changed wall_s=\$((t1 - t0)) failed=\$(sql -c "SELECT count(*) FROM worker.tasks WHERE id > \$first AND state = 'failed'") commit=\$(git describe --tags --always)"
  sql -F ' ' -c "SELECT command, count(*), round(sum(process_duration_ms) / 1000, 1) FROM worker.tasks WHERE id > \$first GROUP BY 1 ORDER BY 3 DESC NULLS LAST LIMIT 10" | sed 's/^/  /'
} | tee \$out.log
sql < ~/bench/fingerprint.sql > \$out.fingerprint
echo "  fingerprint \$(md5sum < \$out.fingerprint | cut -c1-12)" | tee -a \$out.log
EOF
    ;;
results)
    ip=$(box_ip)
    mkdir -p "$results"
    rsync -a -e "ssh -o BatchMode=yes" "statbus@$ip:bench/" "$results/" --exclude rounds.sh --exclude fingerprint.sql
    latest=$(ls -td "$results"/*/ | head -1)
    echo "Copied to $results; latest run: $latest"
    cat "$latest/run.log"
    ;;
ssh|connect)
    ssh -o StrictHostKeyChecking=accept-new "statbus@$(box_ip)"
    ;;
down)
    server=$(describe)
    [ -n "$server" ] || { echo "No server '$name'; nothing to delete."; exit 0; }
    require_ours "$server"
    ip=$(jq -er '.public_net.ipv4.ip' <<<"$server")
    hcloud server delete "$name" >/dev/null
    ssh-keygen -R "$ip" >/dev/null 2>&1 || true
    echo "Deleted $name ($ip). Billing has stopped."
    ;;
status|info)
    server=$(describe)
    [ -n "$server" ] || { echo "No server '$name'."; exit 0; }
    require_ours "$server"
    show "$server"
    ;;
*)
    # The header comment is the help: every line up to the first non-comment.
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
    exit 2
    ;;
esac
exit
}
