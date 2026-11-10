#!/bin/bash
# Monthly BRREG intake (STATBUS-600). One run brings StatBus up to the BRREG
# files built on the 1st of the run month, and closes the units BRREG deleted
# since the previous run.
#
# Jobs per month, in this order (owner decisions, STATBUS-600 Q1 and Q6):
#   import_hovedenhet_YYYY_MM          legal units, full file          brreg_hovedenhet_2025
#   import_underenhet_YYYY_MM          establishments, full file       brreg_underenhet_2025
#   import_roller_YYYY_MM              legal relationships, full file  brreg_roller_2025
#   import_hovedenhet_slettet_YYYY_MM  legal unit closures             legal_unit_source_dates
#   import_underenhet_slettet_YYYY_MM  establishment closures          establishment_for_lu_source_dates
# A closure job exists only when its list has rows.
#
# YYYY_MM is the month the files cover: the run on 2 December imports November,
# and the full-file jobs are valid from 1 November (owner, Q4), so a unit born
# in November counts as a November birth.
#
# Closures. A unit BRREG deleted (feed: Sletting) closes on its slettedato. A
# unit StatBus still counts that is absent from the full file with no deletion
# in the feed closes on its slettedato when the BRREG lookup has one, otherwise
# on the 1st of the run month, and is counted separately (owner, Q5).
#
# Catch-up (--deletions-only --since A --until B): BRREG publishes only today's
# full file, so a past month replays only its deletions, with their exact
# dates. A baseline loaded with its real snapshot date, followed by one
# catch-up run per month, exercises the monthly change path at once instead of
# over months (owner, Q10).
#
# The run reports to Slack and stops at the first failure without retrying
# (owner, Q7, Q8, AC5). The month's jobs and StatBus's own history hold the
# figures; the Slack message compares this month's jobs with the previous
# month's.
#
# Usage:
#   brreg-monthly.sh [--month YYYY-MM] [--since YYYY-MM-DD] [--label SUFFIX] [--dry-run]
#     --month           month the files cover (default: the previous calendar month)
#     --since           read the deletion feed from this date (default: the date the
#                       previous run read it, else the 1st of --month)
#     --label           job slug suffix instead of YYYY_MM (an extra run inside a month)
#     --deletions-only  catch-up month: only the closure jobs for the feed window
#     --until           end of the feed window, exclusive (with --deletions-only)
#     --dry-run         download, fit and count; create no jobs and change nothing
#   Tests: --database NAME, --files DIR (enheter.csv, underenheter.csv, roller.json.gz),
#          --process-inline (run the worker queues in this session)
# Environment: USER_EMAIL (the StatBus user that owns the jobs), SLACK_TOKEN (optional),
#   STATBUS_DIR (the StatBus checkout whose ./sb and database the run uses; default: the
#   checkout this script is in, so the scripts can live in their own clone),
#   BRREG_MONTHLY_STATE (state directory; default tmp/brreg-monthly in STATBUS_DIR).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "${STATBUS_DIR:-$SCRIPT_DIR/../../..}" && pwd)"
cd "$WORKSPACE"
[ -x ./sb ] || { echo "brreg-monthly: no ./sb in $WORKSPACE; set STATBUS_DIR" >&2; exit 2; }

MONTH="" SINCE="" UNTIL="" LABEL="" DRY_RUN=0 DELETIONS_ONLY=0 DATABASE="" FILES="" PROCESS_INLINE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --month) MONTH=$2; shift 2 ;;
        --since) SINCE=$2; shift 2 ;;
        --until) UNTIL=$2; shift 2 ;;
        --label) LABEL=$2; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --deletions-only) DELETIONS_ONLY=1; shift ;;
        --database) DATABASE=$2; shift 2 ;;
        --files) FILES=$2; shift 2 ;;
        --process-inline) PROCESS_INLINE=1; shift ;;
        -h|--help) sed -n '2,48p' "$0"; exit 0 ;;
        *) echo "brreg-monthly: unknown argument $1" >&2; exit 2 ;;
    esac
done

STATE_DIR="${BRREG_MONTHLY_STATE:-$WORKSPACE/tmp/brreg-monthly${DATABASE:+-$DATABASE}}"
mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/run-$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee -a "$LOG") 2>&1

[ -n "${USER_EMAIL:-}" ] || { echo "brreg-monthly: USER_EMAIL must be set" >&2; exit 2; }
if [ -z "$MONTH" ]; then
    year=$((10#$(date +%Y))); month=$((10#$(date +%m) - 1))
    [ "$month" -gt 0 ] || { month=12; year=$((year - 1)); }
    MONTH=$(printf '%04d-%02d' "$year" "$month")
fi
[[ "$MONTH" =~ ^[0-9]{4}-[0-9]{2}$ ]] || { echo "brreg-monthly: --month must be YYYY-MM" >&2; exit 2; }
VALID_FROM="$MONTH-01"
SUFFIX=${LABEL:-${MONTH/-/_}}
[[ "$SUFFIX" =~ ^[a-z0-9_]+$ ]] || { echo "brreg-monthly: --label must be lower-case letters, digits and _" >&2; exit 2; }
[ -n "$SINCE" ] || SINCE=$(cat "$STATE_DIR/last-since" 2>/dev/null || echo "$VALID_FROM")
[ "$DELETIONS_ONLY" = 0 ] || [ -n "$UNTIL" ] || { echo "brreg-monthly: --deletions-only needs --until" >&2; exit 2; }
SERVER=$(hostname -f 2>/dev/null || hostname)
PYTHON=python3  # the helpers use only the standard library, except roller extraction (ijson)
KIND="intake"; [ "$DELETIONS_ONLY" = 0 ] || KIND="catch-up ${SINCE}..${UNTIL}"

notify() {
    # Post one message to Slack; a Slack outage never fails the run.
    [ -n "${SLACK_TOKEN:-}" ] || { echo "brreg-monthly: SLACK_TOKEN not set, not posting"; return 0; }
    local text=$1
    text=${text//\\/\\\\}; text=${text//\"/\\\"}
    curl -s -o /dev/null -w "slack HTTP %{http_code}\n" -X POST https://slack.com/api/chat.postMessage \
        -H "Authorization: Bearer ${SLACK_TOKEN}" -H "Content-Type: application/json" \
        -d "{\"channel\":\"#statbus-utvikling\",\"text\":\"${text}\",\"unfurl_links\":false}" || true
}
fail() {
    echo "brreg-monthly: FAILED: $1"
    notify ":x: BRREG ${KIND} ${MONTH} on *${SERVER}* stopped: $1. Log: ${LOG}"
    exit 1
}
trap 'fail "unexpected error at line $LINENO"' ERR

exec 9>"$STATE_DIR/lock"
flock -n 9 || fail "another run holds $STATE_DIR/lock"

DB_ARGS=()
[ -z "$DATABASE" ] || DB_ARGS=(-d "$DATABASE")
sb_psql() { ./sb psql ${DB_ARGS[@]+"${DB_ARGS[@]}"} -X -q -v ON_ERROR_STOP=1 "$@"; }
sql_value() { sb_psql -t -A -c "$1"; }

# Wait for an upgrade, up to 2 hours, then skip the month (owner, Q7).
busy=0
for _ in $(seq 1 24); do
    busy=$(sql_value "SELECT count(*) FROM public.upgrade WHERE state IN ('scheduled','in_progress');")
    [ "$busy" = 0 ] && break
    echo "brreg-monthly: upgrade scheduled or in progress, waiting 5 minutes"
    sleep 300
done
[ "$busy" = 0 ] || fail "an upgrade was still scheduled or running after 2 hours; month ${MONTH} skipped"

existing=$(sql_value "SELECT string_agg(slug, ', ') FROM public.import_job WHERE slug LIKE 'import\\_%\\_${SUFFIX}';")
[ -z "$existing" ] || fail "jobs for ${SUFFIX} already exist (${existing}); nothing done"
[ "$(sql_value "SELECT count(*) FROM public.user WHERE email = '${USER_EMAIL}';")" = 1 ] || fail "no StatBus user ${USER_EMAIL}"

started=$(date +%s)
WORK="$STATE_DIR/$SUFFIX"
mkdir -p "$WORK"

# --- Full files -------------------------------------------------------------
if [ "$DELETIONS_ONLY" = 0 ]; then
    echo "== download"
    for file in enheter.csv underenheter.csv roller.json.gz; do
        if [ -n "$FILES" ]; then
            [ -f "$FILES/$file" ] && cp "$FILES/$file" "$WORK/$file"
            continue
        fi
        case "$file" in
            roller.json.gz) url="https://data.brreg.no/enhetsregisteret/api/roller/totalbestand" ;;
            *) url="https://data.brreg.no/enhetsregisteret/api/${file%.csv}/lastned/csv" ;;
        esac
        if [ "$file" = roller.json.gz ]; then
            curl -sS --fail --retry 3 --output "$WORK/$file" "$url"
        else
            curl -sS --fail --retry 3 --output "$WORK/$file.gz" "$url"
            gunzip -f "$WORK/$file.gz"
        fi
    done
    [ -f "$WORK/enheter.csv" ] && [ -f "$WORK/underenheter.csv" ] || fail "enheter.csv or underenheter.csv missing"

    echo "== fit files to the definitions"
    if [ "$DRY_RUN" = 0 ]; then
        sb_psql < "$SCRIPT_DIR/../getting-started.sql" > /dev/null
        for d in hovedenhet underenhet roller; do
            if [ "$(sql_value "SELECT count(*) FROM public.import_definition WHERE slug = 'brreg_${d}_2025';")" = 0 ]; then
                [ "$d" != roller ] || sb_psql < "$SCRIPT_DIR/seed-legal-rel-types.sql" > /dev/null
                sb_psql < "$SCRIPT_DIR/create-import-definition-${d}-2025.sql" > /dev/null
            fi
        done
        # A definition created before the status bridge lacks status_code. Add it in place:
        # re-running the creation script deletes the definition and every job made from it.
        sb_psql -c "
            WITH d AS (SELECT id FROM public.import_definition WHERE slug = 'brreg_hovedenhet_2025'),
            sc AS (
                INSERT INTO public.import_source_column (definition_id, column_name, priority)
                SELECT d.id, 'status_code', (SELECT max(priority) + 1 FROM public.import_source_column WHERE definition_id = d.id)
                FROM d WHERE NOT EXISTS (SELECT 1 FROM public.import_source_column WHERE definition_id = d.id AND column_name = 'status_code')
                RETURNING id, definition_id)
            INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id, target_data_column_purpose)
            SELECT sc.definition_id, sc.id, dc.id, 'source_input'
            FROM sc JOIN public.import_data_column dc ON dc.column_name = 'status_code_raw' AND dc.purpose = 'source_input'
            JOIN public.import_step s ON s.id = dc.step_id AND s.code = 'status';" > /dev/null
    fi
    for d in hovedenhet underenhet; do
        sql_value "SELECT sc.column_name FROM public.import_source_column sc JOIN public.import_definition d ON d.id = sc.definition_id WHERE d.slug = 'brreg_${d}_2025' ORDER BY sc.priority;" > "$WORK/$d-columns.txt"
        [ -s "$WORK/$d-columns.txt" ] || fail "import definition brreg_${d}_2025 is missing"
    done
    grep -qx 'status_code' "$WORK/hovedenhet-columns.txt" || echo status_code >> "$WORK/hovedenhet-columns.txt"
    "$PYTHON" "$SCRIPT_DIR/brreg-fit-csv.py" --columns "$WORK/hovedenhet-columns.txt" \
        --in "$WORK/enheter.csv" --out "$WORK/hovedenhet.csv" --derive-status
    "$PYTHON" "$SCRIPT_DIR/brreg-fit-csv.py" --columns "$WORK/underenhet-columns.txt" \
        --in "$WORK/underenheter.csv" --out "$WORK/underenhet.csv" --only-parents "$WORK/enheter.csv"
    if [ -f "$WORK/roller.json.gz" ]; then
        # Roller extraction streams a multi-GB JSON file with ijson, in its own environment.
        venv="$STATE_DIR/.venv"
        [ -x "$venv/bin/python3" ] || python3 -m venv "$venv"
        "$venv/bin/python3" -c "import ijson" 2>/dev/null || "$venv/bin/pip" install -q ijson
        "$venv/bin/python3" "$SCRIPT_DIR/extract-roller-to-csv.py" "$WORK/roller.json.gz" "$WORK/enheter.csv" "$WORK/roller.csv"
    fi
fi
downloaded=$(date +%s)

# --- Closures ---------------------------------------------------------------
echo "== closures since ${SINCE}${UNTIL:+ until ${UNTIL}}"
feed_read_on=$(date -u +%Y-%m-%d)
sql_value "SELECT ei.ident || ',' || min(lu.valid_from) FROM public.external_ident ei JOIN public.external_ident_type t ON t.id = ei.type_id JOIN public.legal_unit lu ON lu.id = ei.legal_unit_id WHERE t.code = 'tax_ident' GROUP BY ei.ident;" > "$WORK/known-legal-units.txt"
sql_value "SELECT ei.ident || ',' || min(es.valid_from) FROM public.external_ident ei JOIN public.external_ident_type t ON t.id = ei.type_id JOIN public.establishment es ON es.id = ei.establishment_id WHERE t.code = 'tax_ident' GROUP BY ei.ident;" > "$WORK/known-establishments.txt"
declare -A feed_summary
for kind in hovedenhet underenhet; do
    register=enheter; known="known-legal-units.txt"
    [ "$kind" = hovedenhet ] || { register=underenheter; known="known-establishments.txt"; }
    feed_summary[$kind]=$("$PYTHON" "$SCRIPT_DIR/brreg-deletions-since.py" --register "$register" \
        --since "$SINCE" ${UNTIL:+--until "$UNTIL"} --known "$WORK/$known" \
        --out "$WORK/${kind}-slettet.csv" --gone-out "$WORK/${kind}-gone.txt")
    echo "${feed_summary[$kind]}"
done

# Units StatBus still counts that the full file no longer lists and the feed did not report
# (owner, Q5): close on the BRREG slettedato when the lookup has one, else on the 1st of the
# run month. Only a run with a full file can see them.
missing_counts='{}'
if [ "$DELETIONS_ONLY" = 0 ]; then
    run_month_start=$(date -u +%Y-%m-01)
    sql_value "SELECT DISTINCT ei.ident FROM public.external_ident ei JOIN public.external_ident_type t ON t.id = ei.type_id JOIN public.legal_unit lu ON lu.id = ei.legal_unit_id WHERE t.code = 'tax_ident' AND lu.valid_until = 'infinity' AND lu.death_date IS NULL;" > "$WORK/alive-hovedenhet.txt"
    sql_value "SELECT DISTINCT ei.ident FROM public.external_ident ei JOIN public.external_ident_type t ON t.id = ei.type_id JOIN public.establishment es ON es.id = ei.establishment_id WHERE t.code = 'tax_ident' AND es.valid_until = 'infinity' AND es.death_date IS NULL;" > "$WORK/alive-underenhet.txt"
    missing_counts=$("$PYTHON" "$SCRIPT_DIR/brreg-close-missing.py" --work "$WORK" --run-month-start "$run_month_start")
    echo "missing from the file without a feed deletion: $missing_counts"
fi
fitted=$(date +%s)

if [ "$DRY_RUN" = 1 ]; then
    echo "brreg-monthly: dry run, no jobs created"
    exit 0
fi

# --- Jobs -------------------------------------------------------------------
echo "== create and load the jobs"
create_job() { # slug definition valid_from(empty: dates per row) description
    local valid_cols="" valid_vals=""
    if [ -n "$3" ]; then valid_cols=", default_valid_from, default_valid_to"; valid_vals=", '$3'::date, 'infinity'::date"; fi
    sb_psql -c "INSERT INTO public.import_job (definition_id, slug, description, edit_comment, user_id, review${valid_cols})
        SELECT d.id, '$1', '$4', 'BRREG ${KIND} ${MONTH}', u.id, false${valid_vals}
        FROM public.import_definition d, public.user u WHERE d.slug = '$2' AND u.email = '${USER_EMAIL}';" > /dev/null
}
slugs=""
add_job() { # slug definition valid_from file columns description
    [ "$(wc -l < "$4")" -gt 1 ] || { echo "no rows for $1"; return 0; }
    create_job "$1" "$2" "$3" "$6"
    sb_psql -c "\\copy public.$1_upload $5 FROM '$4' WITH CSV HEADER"
    slugs="${slugs:+$slugs,}'$1'"
}
if [ "$DELETIONS_ONLY" = 0 ]; then
    add_job "import_hovedenhet_${SUFFIX}" brreg_hovedenhet_2025 "$VALID_FROM" "$WORK/hovedenhet.csv" "" "BRREG legal units, register as of the end of ${MONTH}"
    add_job "import_underenhet_${SUFFIX}" brreg_underenhet_2025 "$VALID_FROM" "$WORK/underenhet.csv" "" "BRREG establishments, register as of the end of ${MONTH}"
    [ ! -f "$WORK/roller.csv" ] || add_job "import_roller_${SUFFIX}" brreg_roller_2025 "$VALID_FROM" "$WORK/roller.csv" "" "BRREG legal relationships as of the end of ${MONTH}"
fi
for kind in hovedenhet underenhet; do
    definition=legal_unit_source_dates
    [ "$kind" = hovedenhet ] || definition=establishment_for_lu_source_dates
    cat "$WORK/${kind}-slettet.csv" > "$WORK/${kind}-closures.csv"
    [ ! -f "$WORK/${kind}-missing-closures.csv" ] || tail -n +2 "$WORK/${kind}-missing-closures.csv" >> "$WORK/${kind}-closures.csv"
    add_job "import_${kind}_slettet_${SUFFIX}" "$definition" "" "$WORK/${kind}-closures.csv" \
        "(tax_ident, death_date, valid_from, valid_to)" "BRREG ${kind} closures since ${SINCE}${UNTIL:+ until ${UNTIL}}"
done
[ -n "$slugs" ] || slugs="''"

echo "== wait for the worker"
[ "$PROCESS_INLINE" = 0 ] || sb_psql -c "CALL worker.process_tasks(p_queue => 'import');" > /dev/null
while [ "$(sql_value "SELECT count(*) FROM public.import_job WHERE slug IN (${slugs}) AND state NOT IN ('finished','failed','rejected','waiting_for_review');")" != 0 ]; do
    sleep 60
done
imported=$(date +%s)
bad=$(sql_value "SELECT string_agg(slug || '=' || state, ', ') FROM public.import_job WHERE slug IN (${slugs}) AND state <> 'finished';")
[ -z "$bad" ] || fail "jobs did not finish: ${bad}"

echo "== wait for derived tables"
[ "$PROCESS_INLINE" = 0 ] || sb_psql -c "CALL worker.process_tasks(p_queue => 'analytics');" > /dev/null
while [ "$(sql_value "SELECT count(*) FROM worker.tasks t JOIN worker.command_registry c ON c.command = t.command WHERE c.queue = 'analytics' AND t.state IN ('pending','processing','waiting','interrupted');")" != 0 ]; do
    sleep 60
done
derived=$(date +%s)
# The next run reads the feed from the day this run read it, so no deletion falls between runs.
[ "$DELETIONS_ONLY" = 1 ] && printf '%s\n' "$UNTIL" > "$STATE_DIR/last-since" || printf '%s\n' "$feed_read_on" > "$STATE_DIR/last-since"

# --- Report -----------------------------------------------------------------
# This month's jobs next to the previous run's, read from the import jobs themselves.
report=$(sql_value "
    WITH runs AS (
        SELECT substring(slug from '_([0-9]{4}_[0-9]{2}[a-z0-9_]*)$') AS run,
               sum(imported_rows) FILTER (WHERE slug NOT LIKE '%slettet%') AS full_rows,
               sum(imported_rows) FILTER (WHERE slug LIKE '%slettet%') AS closed,
               extract(epoch FROM max(processing_stop_at) - min(created_at))::int AS seconds,
               min(created_at) AS started
        FROM public.import_job WHERE slug ~ '^import_(hovedenhet|underenhet|roller)(_slettet)?_[0-9]{4}_[0-9]{2}'
        GROUP BY 1)
    SELECT string_agg(format('%s: %s rows, %s closed, %s s', run, coalesce(full_rows, 0), coalesce(closed, 0), seconds), '; ' ORDER BY started DESC)
    FROM (SELECT * FROM runs ORDER BY started DESC LIMIT 2) last_two;")
counted=$(sql_value "SELECT count(*) FROM public.statistical_unit AS su WHERE su.unit_type = 'legal_unit' AND su.used_for_counting AND su.existence_from <= now()::date AND su.existence_until > now()::date;")
db_mb=$(sql_value "SELECT pg_database_size(current_database()) / 1024 / 1024;")
msg=":white_check_mark: BRREG ${KIND} ${MONTH} on *${SERVER}*. This and previous run: ${report}. Counted legal units today: ${counted}. DB ${db_mb} MB. Download $((downloaded - started)) s, import $((imported - fitted)) s, derive $((derived - imported)) s."
[ "$missing_counts" = '{}' ] || msg="${msg} Absent from the file without a BRREG deletion, closed: ${missing_counts}."
echo "$msg"
notify "$msg"
trap - ERR
