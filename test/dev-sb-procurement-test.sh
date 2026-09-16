#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRATCH_ROOT=${JCODE_SCRATCH_DIR:-$REPO_ROOT/tmp}

run_dirty_cli_case() {
    local name=$1 existing_sb=$2
    local fixture
    fixture=$(mktemp -d "$SCRATCH_ROOT/dev-sb-dirty-${name}.XXXXXX")
    git clone --quiet --no-hardlinks "$REPO_ROOT" "$fixture/repo"
    cp "$REPO_ROOT/dev.sh" "$fixture/repo/dev.sh"
    mkdir -p "$fixture/bin" "$fixture/repo/.db-seed"
    printf 'test placeholder\n' >"$fixture/repo/.db-seed/seed.pg_dump"

    cat >"$fixture/bin/docker" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$fixture/docker.log"
exit 98
EOF
    cat >"$fixture/bin/go" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"$fixture/go.log"
out=''
while [ "\$#" -gt 0 ]; do
    if [ "\$1" = '-o' ]; then out=\$2; shift 2; continue; fi
    shift
done
[ -n "\$out" ]
cat >"\$out" <<'SB'
#!/usr/bin/env bash
case "\${1:-}" in
  committed-drift) exit 0 ;;
  db) exit 0 ;;
esac
exit 0
SB
chmod +x "\$out"
EOF
    chmod +x "$fixture/bin/docker" "$fixture/bin/go"

    if [ "$existing_sb" = true ]; then
        cat >"$fixture/repo/sb" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = committed-drift ] && exit 0
exit 0
EOF
        chmod +x "$fixture/repo/sb"
        # Reproduce the second review hole: dirty source is deliberately older
        # than sb, so the historical mtime check cannot see it.
        touch -t 203001010000 "$fixture/repo/sb"
    fi

    printf '\n// dirty %s regression fixture\n' "$name" >>"$fixture/repo/cli/main.go"
    if [ "$existing_sb" = true ]; then
        touch -t 202001010000 "$fixture/repo/cli/main.go"
    fi

    (
        cd "$fixture/repo"
        PATH="$fixture/bin:/usr/bin:/bin" ./dev.sh test-install-recovery --print-selected >/dev/null
    )

    test -s "$fixture/go.log"
    test ! -e "$fixture/docker.log"
    echo "PASS: $name used source build and never attempted image procurement"
}

run_dirty_cli_case absent-sb false
run_dirty_cli_case older-mtime-dirty-cli true

fixture=$(mktemp -d "$SCRATCH_ROOT/dev-sb-missing-image.XXXXXX")
git clone --quiet --no-hardlinks "$REPO_ROOT" "$fixture/repo"
cp "$REPO_ROOT/dev.sh" "$fixture/repo/dev.sh"
mkdir -p "$fixture/bin" "$fixture/repo/.db-seed"
printf 'test placeholder\n' >"$fixture/repo/.db-seed/seed.pg_dump"
cat >"$fixture/bin/docker" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$fixture/docker.log"
case "\$1 \$2" in
  'manifest inspect') sleep 600 ;;
  *) exit 97 ;;
esac
EOF
cat >"$fixture/bin/go" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"$fixture/go.log"
out=''
while [ "\$#" -gt 0 ]; do
    if [ "\$1" = '-o' ]; then out=\$2; shift 2; continue; fi
    shift
done
cat >"\$out" <<'SB'
#!/usr/bin/env bash
[ "\${1:-}" = db ] && exit 0
exit 0
SB
chmod +x "\$out"
EOF
chmod +x "$fixture/bin/docker" "$fixture/bin/go"
(
    cd "$fixture/repo"
    PATH="$fixture/bin:/usr/bin:/bin" ./dev.sh test-install-recovery --print-selected >/dev/null
)
grep -q '^manifest inspect ghcr.io/statisticsnorway/statbus-sb:' "$fixture/docker.log"
test "$(wc -l <"$fixture/docker.log" | tr -d ' ')" -eq 1
test -s "$fixture/go.log"
echo "PASS: missing image was manifest-probed once and fell back without docker pull"

# `postgres-variables` is consumed by eval throughout dev.sh. A successful sb
# procurement must therefore leave stdout as shell code only; bootstrap status
# (including docker pull output with shell metacharacters) belongs on stderr.
fixture=$(mktemp -d "$SCRATCH_ROOT/dev-sb-eval-output.XXXXXX")
git clone --quiet --no-hardlinks "$REPO_ROOT" "$fixture/repo"
cp "$REPO_ROOT/dev.sh" "$fixture/repo/dev.sh"
mkdir -p "$fixture/bin" "$fixture/repo/.db-seed"
printf 'test placeholder\n' >"$fixture/repo/.db-seed/seed.pg_dump"
cat >"$fixture/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
  'manifest inspect') exit 0 ;;
  'pull ghcr.io/'*) echo 'Pull complete (cached artifact)' ;;
  'create ghcr.io/'*) echo 'fixture-container' ;;
  'cp fixture-container:/sb')
    cat >"$3" <<'SB'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  committed-drift|db) exit 0 ;;
  dotenv)
    case "${5:-}" in
      SITE_DOMAIN) echo 'eval.statbus.test' ;;
      CADDY_DEPLOYMENT_MODE) echo 'development' ;;
      POSTGRES_APP_DB) echo 'statbus_eval' ;;
      POSTGRES_ADMIN_USER) echo 'postgres' ;;
      POSTGRES_ADMIN_PASSWORD) echo 'eval-password' ;;
      CADDY_DB_PORT) echo '5432' ;;
      POSTGRES_TEST_DB) echo 'statbus_test_template' ;;
      *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
esac
SB
    ;;
  'rm fixture-container') exit 0 ;;
  *) exit 97 ;;
esac
EOF
chmod +x "$fixture/bin/docker"
(
    cd "$fixture/repo"
    stdout=$(PATH="$fixture/bin:/usr/bin:/bin" ./dev.sh postgres-variables 2>"$fixture/stderr.log")
    eval "$stdout"
    test "$PGHOST" = 'eval.statbus.test'
    test "$PGDATABASE" = 'statbus_eval'
    test "$PGPASSWORD" = 'eval-password'
    test "$POSTGRES_TEST_DB" = 'statbus_test_template'
    grep -q 'Procuring sb from image .* (no host toolchain)' "$fixture/stderr.log"
    grep -q 'Pull complete (cached artifact)' "$fixture/stderr.log"
)
echo "PASS: procured sb kept postgres-variables stdout safe to eval"

# The optional seed fetch runs before every action when the cache is absent.
# Its non-fatal fallback must also stay off stdout because postgres-variables
# callers eval that stream. This fixture intentionally has no .db-seed cache.
fixture=$(mktemp -d "$SCRATCH_ROOT/dev-sb-seed-fetch-eval.XXXXXX")
git clone --quiet --no-hardlinks "$REPO_ROOT" "$fixture/repo"
cp "$REPO_ROOT/dev.sh" "$fixture/repo/dev.sh"
cat >"$fixture/repo/sb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  committed-drift) exit 0 ;;
  db) exit 1 ;;
  dotenv)
    case "${5:-}" in
      SITE_DOMAIN) echo 'seed-failure.statbus.test' ;;
      CADDY_DEPLOYMENT_MODE) echo 'development' ;;
      POSTGRES_APP_DB) echo 'statbus_seed_failure' ;;
      POSTGRES_ADMIN_USER) echo 'postgres' ;;
      POSTGRES_ADMIN_PASSWORD) echo 'seed-failure-password' ;;
      CADDY_DB_PORT) echo '5432' ;;
      POSTGRES_TEST_DB) echo 'statbus_test_template' ;;
      *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fixture/repo/sb"
touch -t 203001010000 "$fixture/repo/sb"
(
    cd "$fixture/repo"
    stdout=$(PATH="/usr/bin:/bin" ./dev.sh postgres-variables 2>"$fixture/stderr.log")
    eval "$stdout"
    test "$PGHOST" = 'seed-failure.statbus.test'
    test "$PGDATABASE" = 'statbus_seed_failure'
    test "$PGPASSWORD" = 'seed-failure-password'
    grep -q 'Note: no seed image for this commit' "$fixture/stderr.log"
)
echo "PASS: failed seed fetch kept postgres-variables stdout safe to eval"
