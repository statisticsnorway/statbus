#!/bin/bash
# Monthly BRREG intake (STATBUS-600). One run brings the register up to the
# BRREG files built on the 1st of the run month, and closes the units BRREG
# deleted since the previous run.
#
# Four import jobs per month, in this order (owner decision, STATBUS-600 Q1):
#   import_hovedenhet_YYYY_MM          legal units, full file         brreg_hovedenhet_2025
#   import_underenhet_YYYY_MM          establishments, full file      brreg_underenhet_2025
#   import_hovedenhet_slettet_YYYY_MM  legal unit deletions (feed)    legal_unit_source_dates
#   import_underenhet_slettet_YYYY_MM  establishment deletions (feed) establishment_for_lu_source_dates
# (a deletion job is created only when its list has rows)
# YYYY_MM is the month the files cover: the run on 2 December imports November,
# and the full-file jobs are valid from 1 November (owner decision, Q4), so a
# unit born in November counts as a November birth.
#
# The run appends its figures to tmp/brreg-monthly/figures.tsv (one row per
# month: sizes, rows, run times, closed units) and posts them to Slack, next to
# the previous month, when SLACK_TOKEN is set (owner decision, Q8). A failure
# stops the run and is reported; nothing retries (STATBUS-600 AC5).
#
# Usage:
#   ./samples/norway/brreg/brreg-monthly.sh [--month YYYY-MM] [--since YYYY-MM-DD] [--dry-run]
#         [--database NAME] [--files DIR]
#     --month    month the files cover (default: the previous calendar month)
#     --since    read the deletion feed from this date (default: the date the
#                previous run read the feed, else the 1st of --month)
#     --dry-run  download, fit and count, but create no jobs
#     --database load into this database instead of the deployment's own (tests)
#     --files    use enheter.csv and underenheter.csv from DIR instead of downloading (tests)
#     --process-inline  run the import and analytics queues in this session instead of
#                waiting for the deployment's worker (tests on a scratch database)
#     --label    job slug suffix instead of YYYY_MM, for an extra run inside a month
#                (a catch-up run mid-month, so the run on the 2nd still finds its slugs free)
# Environment: USER_EMAIL (the StatBus user that owns the jobs), SLACK_TOKEN (optional),
#   STATBUS_DIR (the StatBus checkout whose ./sb and database the run uses; default: the
#   checkout this script is in). The script and its helpers may live in a separate clone,
#   so a release checkout stays clean.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "${STATBUS_DIR:-$SCRIPT_DIR/../../..}" && pwd)"
cd "$WORKSPACE"
[ -x ./sb ] || { echo "brreg-monthly: no ./sb in $WORKSPACE; set STATBUS_DIR" >&2; exit 2; }

MONTH="" SINCE="" DRY_RUN=0 DATABASE="" FILES="" PROCESS_INLINE=0 LABEL=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --month) MONTH=$2; shift 2 ;;
        --since) SINCE=$2; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --database) DATABASE=$2; shift 2 ;;
        --files) FILES=$2; shift 2 ;;
        --process-inline) PROCESS_INLINE=1; shift ;;
        --label) LABEL=$2; shift 2 ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "brreg-monthly: unknown argument $1" >&2; exit 2 ;;
    esac
done

# Run state per database: the feed cursor, figures, logs and the month's files.
# BRREG_MONTHLY_STATE overrides the directory (tests).
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
if [ -z "$SINCE" ]; then
    SINCE=$(cat "$STATE_DIR/last-since" 2>/dev/null || echo "$VALID_FROM")
fi
SERVER=$(hostname -f 2>/dev/null || hostname)
PYTHON=python3  # the helpers use only the standard library

notify() {
    # Post one line to Slack; never fail the run because Slack is down.
    [ -n "${SLACK_TOKEN:-}" ] || { echo "brreg-monthly: SLACK_TOKEN not set, not posting"; return 0; }
    local text=$1
    text=${text//\\/\\\\}; text=${text//\"/\\\"}
    curl -s -o /dev/null -w "slack HTTP %{http_code}\n" -X POST https://slack.com/api/chat.postMessage \
        -H "Authorization: Bearer ${SLACK_TOKEN}" -H "Content-Type: application/json" \
        -d "{\"channel\":\"#statbus-utvikling\",\"text\":\"${text}\",\"unfurl_links\":false}" || true
}

fail() {
    echo "brreg-monthly: FAILED: $1"
    notify ":x: BRREG monthly intake for ${MONTH} on *${SERVER}* stopped: $1. Log: ${LOG}"
    exit 1
}
trap 'fail "unexpected error at line $LINENO"' ERR

# One run at a time.
exec 9>"$STATE_DIR/lock"
flock -n 9 || fail "another monthly run holds $STATE_DIR/lock"

DB_ARGS=()
[ -z "$DATABASE" ] || DB_ARGS=(-d "$DATABASE")
sb_psql() { ./sb psql ${DB_ARGS[@]+"${DB_ARGS[@]}"} -X -q -v ON_ERROR_STOP=1 "$@"; }
sql_value() { sb_psql -t -A -c "$1"; }

# Wait for a running upgrade, up to 2 hours, then skip the month (owner decision, Q7).
for _ in $(seq 1 24); do
    busy=$(sql_value "SELECT count(*) FROM public.upgrade WHERE state IN ('scheduled','in_progress');")
    [ "$busy" = 0 ] && break
    echo "brreg-monthly: upgrade scheduled or in progress, waiting 5 minutes"
    sleep 300
done
[ "${busy:-0}" = 0 ] || fail "an upgrade was still scheduled or running after 2 hours; month ${MONTH} skipped"

if [ "$(sql_value "SELECT count(*) FROM public.import_job WHERE slug = 'import_hovedenhet_${SUFFIX}';")" != 0 ]; then
    fail "jobs for ${MONTH} already exist (import_hovedenhet_${SUFFIX}); nothing done"
fi
user_ok=$(sql_value "SELECT count(*) FROM public.user WHERE email = '${USER_EMAIL}';")
[ "$user_ok" = 1 ] || fail "no StatBus user ${USER_EMAIL}"

started=$(date +%s)
WORK="$STATE_DIR/$MONTH"
mkdir -p "$WORK"

echo "== download"
for register in enheter underenheter; do
    if [ -n "$FILES" ]; then
        cp "$FILES/$register.csv" "$WORK/$register.csv"
        continue
    fi
    curl -sS --fail --retry 3 --output "$WORK/$register.csv.gz" \
        "https://data.brreg.no/enhetsregisteret/api/$register/lastned/csv"
    gunzip -f "$WORK/$register.csv.gz"
done
downloaded=$(date +%s)

echo "== fit files to the definitions"
if [ "$DRY_RUN" = 0 ]; then
    sb_psql < "$SCRIPT_DIR/../getting-started.sql" > /dev/null
    for d in hovedenhet underenhet; do
        if [ "$(sql_value "SELECT count(*) FROM public.import_definition WHERE slug = 'brreg_${d}_2025';")" = 0 ]; then
            sb_psql < "$SCRIPT_DIR/create-import-definition-${d}-2025.sql" > /dev/null
        fi
    done
    # A definition created before the status bridge lacks status_code. Add it in place:
    # re-running the creation script would delete the definition and every job made from it.
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
# A dry run reads a definition it would extend; fit as the real run will.
grep -qx 'status_code' "$WORK/hovedenhet-columns.txt" || echo status_code >> "$WORK/hovedenhet-columns.txt"
lu_fit=$("$PYTHON" "$SCRIPT_DIR/brreg-fit-csv.py" --columns "$WORK/hovedenhet-columns.txt" \
    --in "$WORK/enheter.csv" --out "$WORK/hovedenhet.csv" --derive-status)
es_fit=$("$PYTHON" "$SCRIPT_DIR/brreg-fit-csv.py" --columns "$WORK/underenhet-columns.txt" \
    --in "$WORK/underenheter.csv" --out "$WORK/underenhet.csv" --only-parents "$WORK/enheter.csv")
echo "$lu_fit"; echo "$es_fit"

echo "== deletions since ${SINCE}"
feed_read_on=$(date -u +%Y-%m-%d)
sql_value "SELECT ei.ident || ',' || min(lu.valid_from) FROM public.external_ident ei JOIN public.external_ident_type t ON t.id = ei.type_id JOIN public.legal_unit lu ON lu.id = ei.legal_unit_id WHERE t.code = 'tax_ident' GROUP BY ei.ident;" > "$WORK/known-legal-units.txt"
sql_value "SELECT ei.ident || ',' || min(es.valid_from) FROM public.external_ident ei JOIN public.external_ident_type t ON t.id = ei.type_id JOIN public.establishment es ON es.id = ei.establishment_id WHERE t.code = 'tax_ident' GROUP BY ei.ident;" > "$WORK/known-establishments.txt"
lu_del=$("$PYTHON" "$SCRIPT_DIR/brreg-deletions-since.py" --register enheter --since "$SINCE" \
    --known "$WORK/known-legal-units.txt" --out "$WORK/hovedenhet-slettet.csv")
es_del=$("$PYTHON" "$SCRIPT_DIR/brreg-deletions-since.py" --register underenheter --since "$SINCE" \
    --known "$WORK/known-establishments.txt" --out "$WORK/underenhet-slettet.csv")
echo "$lu_del"; echo "$es_del"
fitted=$(date +%s)

if [ "$DRY_RUN" = 1 ]; then
    echo "brreg-monthly: dry run, no jobs created"
    exit 0
fi

echo "== create and load the four jobs"
create_job() { # slug definition valid_from(or empty for source dates) description
    local valid_cols="" valid_vals=""
    if [ -n "$3" ]; then valid_cols=", default_valid_from, default_valid_to"; valid_vals=", '$3'::date, 'infinity'::date"; fi
    sb_psql -c "INSERT INTO public.import_job (definition_id, slug, description, edit_comment, user_id, review${valid_cols})
        SELECT d.id, '$1', '$4', 'BRREG monthly intake ${MONTH}', u.id, false${valid_vals}
        FROM public.import_definition d, public.user u WHERE d.slug = '$2' AND u.email = '${USER_EMAIL}';" > /dev/null
}
create_job "import_hovedenhet_${SUFFIX}" brreg_hovedenhet_2025 "$VALID_FROM" "BRREG legal units, register as of the end of ${MONTH}"
create_job "import_underenhet_${SUFFIX}" brreg_underenhet_2025 "$VALID_FROM" "BRREG establishments, register as of the end of ${MONTH}"
sb_psql -c "\copy public.import_hovedenhet_${SUFFIX}_upload FROM '$WORK/hovedenhet.csv' WITH CSV HEADER"
sb_psql -c "\copy public.import_underenhet_${SUFFIX}_upload FROM '$WORK/underenhet.csv' WITH CSV HEADER"
# A deletion job exists only when there is something to close: an upload starts a job by
# its first row, so a job for an empty list would wait for an upload that never comes.
slugs="'import_hovedenhet_${SUFFIX}','import_underenhet_${SUFFIX}'"
for kind in hovedenhet underenhet; do
    deletions="$WORK/${kind}-slettet.csv"
    [ "$(wc -l < "$deletions")" -gt 1 ] || { echo "no ${kind} deletions to import"; continue; }
    definition=legal_unit_source_dates
    [ "$kind" = hovedenhet ] || definition=establishment_for_lu_source_dates
    create_job "import_${kind}_slettet_${SUFFIX}" "$definition" "" "BRREG ${kind} deletions since ${SINCE}"
    sb_psql -c "\copy public.import_${kind}_slettet_${SUFFIX}_upload (tax_ident, death_date, valid_from, valid_to) FROM '$deletions' WITH CSV HEADER"
    slugs="${slugs},'import_${kind}_slettet_${SUFFIX}'"
done

echo "== wait for the worker"
[ "$PROCESS_INLINE" = 0 ] || sb_psql -c "CALL worker.process_tasks(p_queue => 'import');" > /dev/null
while :; do
    pending=$(sql_value "SELECT count(*) FROM public.import_job WHERE slug IN (${slugs}) AND state NOT IN ('finished','failed','rejected','waiting_for_review');")
    [ "$pending" = 0 ] && break
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

echo "== figures"
figures=$(sql_value "SELECT concat_ws(E'\t',
    '${MONTH}', now()::date,
    (SELECT pg_database_size(current_database())),
    (SELECT count(*) FROM public.legal_unit), (SELECT count(*) FROM public.establishment),
    (SELECT count(*) FROM public.statistical_unit),
    (SELECT count(*) FROM public.statistical_unit AS su WHERE su.unit_type = 'legal_unit' AND su.used_for_counting AND su.existence_from <= now()::date AND su.existence_until > now()::date),
    (SELECT sum(imported_rows) FROM public.import_job WHERE slug IN (${slugs}))
);")
total_rows_lu=$(sql_value "SELECT total_rows FROM public.import_job WHERE slug = 'import_hovedenhet_${SUFFIX}';")
closed=$(sql_value "SELECT coalesce(sum(imported_rows),0) FROM public.import_job WHERE slug IN ('import_hovedenhet_slettet_${SUFFIX}','import_underenhet_slettet_${SUFFIX}');")
row="${figures}	$((downloaded - started))	$((imported - fitted))	$((derived - imported))	${closed}"
[ -f "$STATE_DIR/figures.tsv" ] || printf 'month\trun_date\tdb_bytes\tlegal_unit_rows\testablishment_rows\tstatistical_unit_rows\tcounted_legal_units\timported_rows\tdownload_s\timport_s\tderive_s\tclosed_units\n' > "$STATE_DIR/figures.tsv"
previous=$(tail -n 1 "$STATE_DIR/figures.tsv")
printf '%s\n' "$row" >> "$STATE_DIR/figures.tsv"
# The next run reads the feed from the day this run read it, so no deletion falls between runs.
printf '%s\n' "$feed_read_on" > "$STATE_DIR/last-since"

IFS=$'\t' read -r _ _ db lu es _ counted _ dl_s im_s de_s cl <<< "$row"
IFS=$'\t' read -r p_month _ p_db _ _ _ p_counted _ _ p_im _ _ <<< "$previous"
msg=":white_check_mark: BRREG intake ${MONTH} on *${SERVER}*: ${total_rows_lu} legal units in file, ${cl} units closed, ${counted} legal units counted (${lu} legal unit and ${es} establishment records). DB $((db / 1024 / 1024)) MB, download ${dl_s}s, import ${im_s}s, derive ${de_s}s."
if [ "$p_month" != month ] && [ -n "$p_month" ]; then
    msg="${msg} Previous (${p_month}): DB $((p_db / 1024 / 1024)) MB, import ${p_im}s, counted ${p_counted}."
fi
echo "$msg"
notify "$msg"
trap - ERR
