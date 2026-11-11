#!/usr/bin/env bash
# ops/bench-box.sh series: one comparison of two commits on the bench box, run
# detached as statbus in ~/statbus. Arguments: base sha, candidate sha, the
# change sizes in percent ("1 50 99").
#
# Starting point: the box runs the base commit's stack, its app database holds a
# restored dump at the base's migrations, and one full recalculation has run
# (ops/bench-box.sh restore, then recalc). Nothing restores again: every run
# starts from a copy of one frozen database, made inside Postgres (CREATE
# DATABASE ... TEMPLATE, about a minute for the 24 GB Norway register).
#   1. freeze the app database as bench_base; fingerprint it.
#   2. base: each change size in turn on the app database.
#   3. candidate: app database := copy of bench_base, the candidate's stack and
#      migrations on it, a full recalculation, then each change size in turn.
# A change of p percent renames the current record of every legal unit whose
# id % 100 < p: the same units for both commits. Per step, ~/bench/series has a
# .log (wall time, failed tasks, time per command), the worker's log and a
# fingerprint of every public table.
set -euo pipefail
cd ~/statbus
out=~/bench/series; mkdir -p "$out"
exec >> "$out/series.log" 2>&1
log() { echo "$(date -u +%FT%TZ) $*"; }
sql() { ./sb psql -X -At -v ON_ERROR_STOP=1 "$@" < /dev/null; }
admin() { docker compose exec -T db psql -U postgres -d postgres -X -At -v ON_ERROR_STOP=1 -c "$1" < /dev/null; }
base_sha=$1 candidate_sha=$2 pcts=$3
app_db=$(./sb dotenv -f .env get POSTGRES_APP_DB)

copy_db() { # from to: replace database `to` with a copy of `from`
    admin "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname IN ('$1', '$2') AND pid <> pg_backend_pid()" > /dev/null
    admin "DROP DATABASE IF EXISTS $2" > /dev/null
    admin "CREATE DATABASE $2 TEMPLATE $1" > /dev/null
}

step() { # label full|percent
    local label=$1 pct=$2 first changed t0 t1
    docker compose stop worker > /dev/null 2>&1 || true
    sql -c "VACUUM (ANALYZE)" > /dev/null
    first=$(sql -c "SELECT coalesce(max(id), 0) FROM worker.tasks")
    if [ "$pct" = full ]; then
        sql -c "SELECT worker.enqueue_derive_statistical_unit_all()" > /dev/null
        changed=all
    else
        # The WHERE names the rows (safeupdate): the chosen share of current records.
        changed=$(sql -c "WITH c AS (UPDATE public.legal_unit SET name = left(name, 230) || ' (bench $label)' WHERE id % 100 < $pct AND valid_until = 'infinity' RETURNING 1) SELECT count(*) FROM c")
    fi
    t0=$(date +%s)
    docker compose run --rm -T --no-deps worker timeout 36000 /app/bin/statbus worker --stop-when-idle > "$out/$label.worker.log" 2>&1 < /dev/null
    t1=$(date +%s)
    {
        echo "$label change=$pct rows=$changed wall_s=$((t1 - t0)) failed=$(sql -c "SELECT count(*) FROM worker.tasks WHERE id > $first AND state = 'failed'") commit=$(git describe --tags --always)"
        sql -F ' ' -c "SELECT command, count(*), round(sum(process_duration_ms) / 1000, 1) FROM worker.tasks WHERE id > $first GROUP BY 1 ORDER BY 3 DESC NULLS LAST LIMIT 10" | sed 's/^/  /'
    } > "$out/$label.log"
    ./sb psql -X -At -v ON_ERROR_STOP=1 < ~/bench/fingerprint.sql > "$out/$label.fingerprint"
    echo "  fingerprint $(md5sum < "$out/$label.fingerprint" | cut -c1-12)" >> "$out/$label.log"
    cat "$out/$label.log"
}

checkout() { # sha: that commit's code, sb and images
    git fetch -q origin && git checkout -q -f --detach "$1"
    rm -f ./sb; ./dev.sh postgres-variables > /dev/null 2>&1 < /dev/null || true
    # Commits before STATBUS-616 keep the image's build time on the procured sb.
    touch ./sb
    ./sb config generate > /dev/null
    docker compose --profile all_except_app pull -q
    docker compose up -d --wait db proxy rest > /dev/null 2>&1
    docker compose stop worker > /dev/null 2>&1 || true
}

log "series start: base $base_sha, candidate $candidate_sha, changes $pcts %; load $(cut -d' ' -f1-3 /proc/loadavg)"
[ "$(git rev-parse HEAD)" = "$base_sha" ] || { log "the box is at $(git rev-parse HEAD), not the base $base_sha: run stack/restore/recalc at the base first"; exit 1; }
docker compose stop worker rest > /dev/null 2>&1 || true
t0=$(date +%s); copy_db "$app_db" bench_base; log "bench_base frozen in $(( $(date +%s) - t0 )) s"
docker compose start rest > /dev/null 2>&1
./sb psql -X -At -v ON_ERROR_STOP=1 < ~/bench/fingerprint.sql > "$out/base-full.fingerprint"
log "base-full fingerprint $(md5sum < "$out/base-full.fingerprint" | cut -c1-12)"
for pct in $pcts; do log "base-change-$pct"; step "base-change-$pct" "$pct"; done

log "candidate $candidate_sha"
docker compose stop worker rest > /dev/null 2>&1 || true
t0=$(date +%s); copy_db bench_base "$app_db"; log "$app_db = bench_base in $(( $(date +%s) - t0 )) s"
checkout "$candidate_sha"
t0=$(date +%s); ./sb migrate up > "$out/candidate-migrate.log" 2>&1 < /dev/null
log "candidate migrated in $(( $(date +%s) - t0 )) s to $(sql -c 'SELECT max(version) FROM db.migration'), $(./sb --version | head -1)"
log "candidate-full"; step candidate-full full
for pct in $pcts; do log "candidate-change-$pct"; step "candidate-change-$pct" "$pct"; done
log "series done, load $(cut -d' ' -f1-3 /proc/loadavg)"
