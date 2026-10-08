#!/usr/bin/env bash
# Scenario: 0-interactive-setup-choices  (STATBUS-474; STATBUS-400 AC2,
# STATBUS-465, STATBUS-466)
#
# A real guest answers every setup question at its default and finishes a
# standalone country install, through the candidate's own install.sh on a PTY.
#
# WHAT IT DRIVES (expect, matched by the question's own words, never by order):
#   - Deployment mode:  Enter. The suggestion must be standalone (STATBUS-465)
#                       and the question must explain development, standalone
#                       and private.
#   - Domain name:      et.statbus-test.local, a domain whose first label is a
#                       country code.
#   - Country name:     Enter. The suggestion must come "from the domain" and
#                       be the country the installer's own list names for "et".
#   - Country code:     Enter. The suggestion must be "et", accepted at once
#                       (no not-a-country-code warning, no re-ask).
#   - Release signer:   Enter ([Y/n], default yes) for jhf.
#   Any other question fails the run: a development question means the mode
#   default was not standalone, a first-administrator question means the
#   supplied users file was ignored, and anything unknown is named in the
#   failure. Every wait is bounded and names what it was waiting for.
#
# WHY "et": the expected country name is not written here. It is read from
# dbseed/country/country_codes.csv in the candidate tree, the database's
# country seed that cli/internal/installinput/countries_table.go is generated
# from (TestCountryTableMatchesSeed keeps the two identical). Ethiopia is an
# SSB country slot (et), and its alpha-2 code is two letters, so the
# installer's domain rule (first label, two letters, known code) applies.
#
# WHAT IT ASSERTS AFTER THE INSTALL:
#   - the installer exited 0 and printed "Installation complete!";
#   - .env.config: CADDY_DEPLOYMENT_MODE=standalone, SITE_DOMAIN, the country's
#     DEPLOYMENT_SLOT_NAME and DEPLOYMENT_SLOT_CODE (never StatBus/local), a
#     stored UPGRADE_TRUSTED_SIGNER_jhf;
#   - the generated .env carries the same values and the slot-derived names
#     (COMPOSE_INSTANCE_NAME=statbus-et, POSTGRES_APP_DB=statbus_et);
#   - the running containers are named statbus-et-{db,rest,app,worker,proxy};
#   - the installed binary is the candidate;
#   - the site answers: health, CA-verified HTTPS on /rest/ and the web app,
#     and the upgrade service unit is active.
#   Each mismatch prints the expected and the arrived value.
#
# CERTIFICATE (an assumption about the harness, stated here so it is visible):
# the questionnaire does not ask for a certificate (that is STATBUS-399's
# design), so this install's Caddy starts with automatic ACME for a domain no
# public CA can reach. install.sh places the harness certificate files in
# caddy/data/custom-certs (STATBUS_HARNESS_CERT_STAGING, as every harness
# standalone install does), and the scenario then selects them with
# `./sb cert install`, the documented operator step, and only then checks
# HTTPS. The harness CA certificate is re-issued for this
# scenario's domain when the guest's certificate does not cover it (the LXD
# base issues it for statbus-test.local only; the Hetzner path already issues
# it for HARNESS_SITE_DOMAIN).
#
# STATUS: UNRUN. Written for STATBUS-474 and never executed on a guest. Its
# first run on the LXD fleet waits on the owner's decision about the scenario
# catalogue's CI cost.
# HARNESS_SKIP_DEFAULT: on demand only (run.sh and lxd/run-forks.sh skip any
# scenario containing this marker), so it adds nothing to the default RC
# fault gate. Remove this marker once a real run has gone green and the owner
# has funded it in the default catalogue. Run it explicitly with:
#   test/install-recovery/lxd/run-forks.sh <candidate-tag> --scenario 0-interactive-setup-choices
#
# Usage:
#   ./test/install-recovery/scenarios/0-interactive-setup-choices.sh <vm_name>

set -euo pipefail

VM_NAME="${1:-statbus-recovery-0-interactive-setup-choices}"
HARNESS_DEPLOYMENT_MODE=standalone
HARNESS_UPGRADE_CHANNEL=stable
COUNTRY_CODE=et
SETUP_DOMAIN="${COUNTRY_CODE}.statbus-test.local"
# The harness provisions its CA-signed certificate and /etc/hosts entry for
# this name (Hetzner), and assert_harness_https_passes probes it.
HARNESS_SITE_DOMAIN="$SETUP_DOMAIN"
TRUSTED_SIGNER=jhf
# Seconds without a question (before the signer answer) or without an
# installer step line (after it) before the run fails rather than hangs.
QUESTION_TIMEOUT_S="${QUESTION_TIMEOUT_S:-900}"
PROGRESS_TIMEOUT_S="${PROGRESS_TIMEOUT_S:-1800}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
REPO_ROOT="$(cd "$LIB_DIR/../../.." && pwd)"
source "$LIB_DIR/release-baseline.sh"
TARGET_TAGS=$(git -C "$REPO_ROOT" tag --points-at HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' || true)
INSTALL_TARGET_TAG="${INSTALL_TARGET_TAG:-$(printf '%s\n' "$TARGET_TAGS" | select_release_baseline_from_tags v9999.99.999999)}"
_release_tag_parts "$INSTALL_TARGET_TAG" >/dev/null
TARGET_SHA=$(git -C "$REPO_ROOT" rev-parse "${INSTALL_TARGET_TAG}^{commit}")
[ "$TARGET_SHA" = "$(git -C "$REPO_ROOT" rev-parse HEAD)" ] || { echo 'candidate tag must point at HEAD' >&2; exit 1; }

# The country the installer will suggest for the domain's first label, read
# from the same list the installer uses. Exactly one row must carry the code.
COUNTRY_CSV="$REPO_ROOT/dbseed/country/country_codes.csv"
[ -f "$COUNTRY_CSV" ] || { echo "FAIL: the installer's country list is missing: $COUNTRY_CSV" >&2; exit 1; }
COUNTRY_ALPHA2=$(printf '%s' "$COUNTRY_CODE" | tr '[:lower:]' '[:upper:]')
[[ "$COUNTRY_ALPHA2" =~ ^[A-Z]{2}$ ]] || { echo "FAIL: COUNTRY_CODE '$COUNTRY_CODE' is not two letters; the domain rule only reads two-letter labels" >&2; exit 1; }
COUNTRY_ROWS=$(tr -d '\r' < "$COUNTRY_CSV" | grep -E ",${COUNTRY_ALPHA2},[A-Z]{3},[0-9]{3}$" || true)
[ "$(printf '%s\n' "$COUNTRY_ROWS" | grep -c .)" = 1 ] || {
    echo "FAIL: expected exactly one row with alpha-2 $COUNTRY_ALPHA2 in $COUNTRY_CSV, found:" >&2
    printf '%s\n' "$COUNTRY_ROWS" >&2
    exit 1
}
COUNTRY_NAME=${COUNTRY_ROWS%,*,*,*}
COUNTRY_NAME=${COUNTRY_NAME#\"}
COUNTRY_NAME=${COUNTRY_NAME%\"}
# The installer shows "Bahamas (the)" as "Bahamas" (installinput.displayName).
COUNTRY_NAME=${COUNTRY_NAME% (the)}
[ -n "$COUNTRY_NAME" ] || { echo "FAIL: could not read the country name for $COUNTRY_ALPHA2 from $COUNTRY_CSV" >&2; exit 1; }
# The name travels as one argument through VM_EXEC/expect; keep it plain.
[[ "$COUNTRY_NAME" =~ ^[A-Za-z][A-Za-z\ .\'-]*$ ]] || { echo "FAIL: country name '$COUNTRY_NAME' needs quoting this scenario does not do; choose another code" >&2; exit 1; }

source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/assertions.sh"
trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 0-interactive-setup-choices (STATBUS-474)"
echo "  Candidate: $INSTALL_TARGET_TAG"
echo "  Domain: $SETUP_DOMAIN  expected country: $COUNTRY_NAME ($COUNTRY_CODE)"
echo "════════════════════════════════════════════════════════════════"

bootstrap_install_test_vm "$VM_NAME" "$INSTALL_TARGET_TAG"
IP=$(_hcloud_server_ip "$VM_NAME")
_wait_for_ssh "$IP" 30
VM_ROOT_EXEC bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y expect >/dev/null'
# The candidate's own install.sh, never statbus.org's moving master.
scp -O "${SSH_OPTS[@]}" "$REPO_ROOT/install.sh" root@"$IP":/tmp/statbus-install.sh
VM_ROOT_EXEC chmod 0644 /tmp/statbus-install.sh
VM_EXEC test ! -e /home/statbus/statbus || { echo 'FAIL: a fresh install needs an absent ~/statbus; this guest already has one' >&2; exit 1; }
VM_EXEC test -r /tmp/users.yml || { echo 'FAIL: the harness users file /tmp/users.yml is not readable by statbus' >&2; exit 1; }

echo ""
echo "── the scenario's domain resolves locally and the harness CA certificate covers it ──"
# shellcheck disable=SC2016 # $1 is expanded by the guest's bash, not here.
VM_ROOT_EXEC bash -c 'grep -qwF "$1" /etc/hosts || printf "127.0.0.1 %s\n" "$1" >> /etc/hosts' _ "$SETUP_DOMAIN"
VM_SCRIPT_INLINE setup-choices-cert "$SETUP_DOMAIN" <<'REMOTE'
#!/usr/bin/env bash
set -euo pipefail
domain="$1"
d="$HOME/harness-certs"
[ -r "$d/ca.crt" ] && [ -r "$d/ca.key" ] || { echo "FAIL: harness CA missing from $d" >&2; exit 1; }
if ! openssl x509 -in "$d/domain.crt" -noout -checkhost "$domain" 2>/dev/null | grep -q ' does match'; then
    openssl req -newkey rsa:2048 -nodes -sha256 -subj "/CN=$domain" -keyout "$d/domain.key" -out "$d/domain.csr" >/dev/null 2>&1
    printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\n' "$domain" > "$d/extensions"
    openssl x509 -req -in "$d/domain.csr" -CA "$d/ca.crt" -CAkey "$d/ca.key" -CAcreateserial -days 7 -sha256 -extfile "$d/extensions" -out "$d/domain.pem" >/dev/null 2>&1
    cat "$d/domain.pem" "$d/ca.crt" > "$d/domain.crt"
    chmod 0600 "$d/domain.key"
    echo "  re-issued the harness certificate for $domain"
fi
openssl x509 -in "$d/domain.crt" -noout -checkhost "$domain" | grep -q ' does match' || { echo "FAIL: harness certificate does not cover $domain" >&2; exit 1; }
getent hosts "$domain" | grep -q '^127\.0\.0\.1' || { echo "FAIL: $domain does not resolve to 127.0.0.1 on the guest" >&2; exit 1; }
echo "  ✓ $domain resolves locally and the harness certificate covers it"
REMOTE

echo ""
echo "── stage the PTY driver (expect) and its runner on the guest ──"
VM_SCRIPT_INLINE setup-choices-prepare "$INSTALL_TARGET_TAG" "$SETUP_DOMAIN" "$COUNTRY_NAME" "$COUNTRY_CODE" "$TRUSTED_SIGNER" "$QUESTION_TIMEOUT_S" "$PROGRESS_TIMEOUT_S" <<'REMOTE'
#!/usr/bin/env bash
set -euo pipefail
rm -f "$HOME/setup-choices-transcript.txt" "$HOME/setup-choices-prompts.txt"
cat > "$HOME/setup-choices.exp" <<'EXPECT'
#!/usr/bin/expect -f
# STATBUS-474: answer every setup question at its default on a real PTY.
# Questions are recognised by their own words, in whatever order they come.
if {[llength $argv] != 6} {
    puts stderr "usage: setup-choices.exp domain country-name country-code signer question-timeout progress-timeout"
    exit 2
}
lassign $argv domain want_name want_code want_signer question_timeout progress_timeout
# The candidate's install.sh as staged by the scenario. The variable exists
# only so the driver itself can be exercised against a recorded transcript.
set installer /tmp/statbus-install.sh
if {[info exists env(SETUP_CHOICES_INSTALLER)]} { set installer $env(SETUP_CHOICES_INSTALLER) }
# Text that is not a question or a step line accumulates until the next
# question; keep all of it so a failure can show what the installer printed.
match_max 262144
set prompts_file "$env(HOME)/setup-choices-prompts.txt"
log_file -noappend "$env(HOME)/setup-choices-transcript.txt"
array set asked {mode 0 domain 0 name 0 code 0 trust 0}

proc asked_summary {} {
    global asked
    return "mode=$asked(mode) domain=$asked(domain) country-name=$asked(name) country-code=$asked(code) signer=$asked(trust)"
}
proc fail {msg} {
    puts stderr "\nSETUP-CHOICES FAIL: $msg"
    puts stderr "SETUP-CHOICES questions asked so far: [asked_summary]"
    exit 1
}
proc expect_value {what want got} {
    if {$want ne $got} { fail "$what: expected '$want', arrived '$got'" }
    puts stderr "SETUP-CHOICES ✓ $what: '$got'"
}
# The question exactly as shown, for the ticket's record of observed prompts.
proc record {what text} {
    global prompts_file
    set f [open $prompts_file a]
    puts $f "=== $what ==="
    puts $f [string map {"\r" ""} $text]
    close $f
}

set timeout $question_timeout
spawn -noecho bash $installer
expect {
    -re {Deployment mode \(development/standalone/private\) \[([^]\r\n]*)\]: } {
        incr asked(mode)
        set buf $expect_out(buffer)
        record "deployment mode" $buf
        if {$asked(mode) > 1} { fail "the deployment-mode question was asked again: Enter did not accept the suggestion ($buf)" }
        foreach m {development standalone private} {
            if {![regexp -line "^\\s+${m}: \\S" $buf]} { fail "the deployment-mode question does not explain $m; it showed: $buf" }
        }
        expect_value "suggested deployment mode" standalone $expect_out(1,string)
        send "\r"
        exp_continue
    }
    -re {Domain name \[[^]\r\n]*\]: } {
        incr asked(domain)
        record "domain name" $expect_out(buffer)
        if {$asked(domain) > 1} { fail "the domain question was asked again after '$domain': $expect_out(buffer)" }
        send -- "$domain\r"
        exp_continue
    }
    -re {Country name \[([^]\r\n]*)\]: } {
        incr asked(name)
        set buf $expect_out(buffer)
        record "country name" $buf
        if {$asked(name) > 1} { fail "the country-name question was asked again: Enter did not accept the suggestion ($buf)" }
        if {[string first "Suggested from the domain $domain" $buf] < 0} {
            fail "the country-name suggestion is not from the domain $domain; the question showed: $buf"
        }
        expect_value "suggested country name" $want_name $expect_out(1,string)
        send "\r"
        exp_continue
    }
    -re {Country code \[([^]\r\n]*)\]: } {
        incr asked(code)
        set buf $expect_out(buffer)
        record "country code" $buf
        if {$asked(code) > 1} { fail "the country-code question was asked again (a warning or re-ask after Enter): $buf" }
        if {[string first "Suggested from $want_name" $buf] < 0} {
            fail "the country-code suggestion is not from $want_name; the question showed: $buf"
        }
        expect_value "suggested country code" $want_code $expect_out(1,string)
        send "\r"
        exp_continue
    }
    -re {(Display name|Deployment code \(short, lowercase\)) \[[^]\r\n]*\]: } {
        record "unexpected development question" $expect_out(buffer)
        fail "a development-mode question was asked ('$expect_out(1,string)'): the installed mode is not standalone"
    }
    -re {Email \[[^]\r\n]*\]: } {
        record "unexpected administrator question" $expect_out(buffer)
        fail "the first-administrator question was asked although STATBUS_USERS_FILE was supplied"
    }
    -re {Trust key\(s\) from github\.com/([A-Za-z0-9-]+)\? \[Y/n\] } {
        incr asked(trust)
        record "release signer" $expect_out(buffer)
        foreach k {mode domain name code} {
            if {$asked($k) != 1} { fail "the signer question came before every setup question was asked exactly once" }
        }
        expect_value "release signer offered" $want_signer $expect_out(1,string)
        send "\r"
    }
    -re {\[[0-9]+/[0-9]+\] Trusted signers +(OK|DONE)} {
        fail "the Trusted signers step finished without asking which release signer to trust"
    }
    -re {\[[0-9]+/[0-9]+\] [^\r\n]*FAILED[^\r\n]*} {
        fail "an installer step failed before the questions were finished: $expect_out(0,string)"
    }
    -re {\[[^]\r\n]*\]: $} {
        record "unexpected question" $expect_out(buffer)
        fail "an unexpected question was asked: [string trim $expect_out(buffer)]"
    }
    -re {\[[YyNn]/[YyNn]\] $} {
        record "unexpected question" $expect_out(buffer)
        fail "an unexpected yes/no question was asked: [string trim $expect_out(buffer)]"
    }
    -re {\[[0-9]+/[0-9]+\] [^\r\n]+\r?\n} { exp_continue }
    timeout { fail "no question or installer step line for ${question_timeout}s while waiting for the setup questions" }
    eof { fail "the installer ended before every setup question was asked" }
}

# The questions are done. Every later step must finish without another
# question; a step line keeps the run alive, silence beyond the bound fails.
set timeout $progress_timeout
set complete 0
expect {
    -re {\[[0-9]+/[0-9]+\] [^\r\n]*FAILED[^\r\n]*} {
        puts stderr "SETUP-CHOICES step failure: $expect_out(0,string)"
        exp_continue
    }
    -re {\[[0-9]+/[0-9]+\] [^\r\n]+\r?\n} { exp_continue }
    -re {Installation complete!} { set complete 1; exp_continue }
    -re {\[[^]\r\n]*\]: $} {
        record "unexpected question" $expect_out(buffer)
        fail "an unexpected question was asked after the signer answer: [string trim $expect_out(buffer)]"
    }
    -re {\[[YyNn]/[YyNn]\] $} {
        record "unexpected question" $expect_out(buffer)
        fail "an unexpected yes/no question was asked after the signer answer: [string trim $expect_out(buffer)]"
    }
    timeout { fail "no installer step line for ${progress_timeout}s after the questions were answered" }
    eof {}
}
set result [wait]
set status [lindex $result 3]
if {$status != 0} { fail "the installer exited $status after the questions were answered" }
if {!$complete} { fail "the installer exited 0 without printing 'Installation complete!'" }
puts stderr "SETUP-CHOICES questions asked: [asked_summary]"
EXPECT
chmod 0600 "$HOME/setup-choices.exp"
{
    printf '#!/usr/bin/env bash\nset -euo pipefail\ncd "$HOME"\n'
    # No answers file: the point is the interactive questions. The users file
    # is supplied so the first-administrator questions are not part of this run.
    # The harness certificate is staged the way every harness standalone
    # install stages it (install.sh places it in caddy/data/custom-certs);
    # the questionnaire does not select it, `./sb cert install` does, below.
    printf 'unset STATBUS_ENV_CONFIG\n'
    printf 'export STATBUS_INSTALL_VERSION=%q STATBUS_USERS_FILE=/tmp/users.yml STATBUS_MIN_DISK_GB=5 GIT_TERMINAL_PROMPT=0\n' "$1"
    printf 'export STATBUS_HARNESS_CERT_STAGING="$HOME/harness-certs"\n'
    printf 'exec expect "$HOME/setup-choices.exp" %q %q %q %q %q %q\n' "$2" "$3" "$4" "$5" "$6" "$7"
} > "$HOME/setup-choices-run.sh"
chmod 0700 "$HOME/setup-choices-run.sh"
echo "  ✓ staged ~/setup-choices.exp and ~/setup-choices-run.sh"
REMOTE

echo ""
echo "── install.sh on a PTY: Enter at mode, $SETUP_DOMAIN, Enter at country name, code and signer ──"
INSTALL_LOG="${HARNESS_ROOT:-$REPO_ROOT}/tmp/install-recovery-${VM_NAME}-install.log"
PROMPTS_LOG="${HARNESS_ROOT:-$REPO_ROOT}/tmp/install-recovery-${VM_NAME}-prompts.txt"
mkdir -p "$(dirname "$INSTALL_LOG")"
set +e
_run_long_via_tmux "$IP" setup-choices "bash /home/statbus/setup-choices-run.sh" "$VM_NAME" | tee -a "$INSTALL_LOG"
INSTALL_RC=${PIPESTATUS[0]}
set -e
VM_EXEC cat /home/statbus/setup-choices-prompts.txt > "$PROMPTS_LOG" 2>/dev/null || true
echo ""
echo "── questions as the installer showed them (also in $PROMPTS_LOG) ──"
cat "$PROMPTS_LOG" 2>/dev/null || echo "  (no questions were recorded)"
if [ "$INSTALL_RC" -ne 0 ]; then
    echo "" >&2
    echo "── installer diagnostics: tail of ~/statbus/tmp/install-last-run-output.txt ──" >&2
    VM_EXEC bash -c 'tail -n 80 ~/statbus/tmp/install-last-run-output.txt 2>/dev/null || echo "(no install output file)"' >&2 || true
    echo "FAIL: the interactive install did not finish (exit $INSTALL_RC); see SETUP-CHOICES lines above" >&2
    exit 1
fi
echo "PASS: every setup question was asked once and accepted at its default; the installer printed Installation complete!"

echo ""
echo "── the answers reached .env.config and the generated .env ──"
MISMATCHES=0
check_value() {
    local file=$1 key=$2 want=$3 got
    got=$(VM_EXEC bash -c "cd ~/statbus && ./sb dotenv -f $file get $key" 2>/dev/null || true)
    if [ "$got" = "$want" ]; then
        echo "  ✓ $file $key=$got"
    else
        echo "  ✗ $file $key: expected '$want', arrived '$got'" >&2
        MISMATCHES=$((MISMATCHES + 1))
    fi
}
check_value .env.config CADDY_DEPLOYMENT_MODE standalone
check_value .env.config SITE_DOMAIN "$SETUP_DOMAIN"
check_value .env.config DEPLOYMENT_SLOT_NAME "$COUNTRY_NAME"
check_value .env.config DEPLOYMENT_SLOT_CODE "$COUNTRY_CODE"
check_value .env CADDY_DEPLOYMENT_MODE standalone
check_value .env SITE_DOMAIN "$SETUP_DOMAIN"
check_value .env DEPLOYMENT_SLOT_NAME "$COUNTRY_NAME"
check_value .env DEPLOYMENT_SLOT_CODE "$COUNTRY_CODE"
check_value .env COMPOSE_INSTANCE_NAME "statbus-$COUNTRY_CODE"
check_value .env POSTGRES_APP_DB "statbus_$COUNTRY_CODE"
SIGNER_KEY=$(VM_EXEC bash -c "cd ~/statbus && ./sb dotenv -f .env.config get UPGRADE_TRUSTED_SIGNER_$TRUSTED_SIGNER" 2>/dev/null || true)
if [ -n "$SIGNER_KEY" ]; then
    echo "  ✓ .env.config UPGRADE_TRUSTED_SIGNER_$TRUSTED_SIGNER is stored"
else
    echo "  ✗ .env.config UPGRADE_TRUSTED_SIGNER_$TRUSTED_SIGNER: expected a signing key, arrived nothing" >&2
    MISMATCHES=$((MISMATCHES + 1))
fi
echo "  .env.config as installed (deployment keys):"
VM_EXEC bash -c "cd ~/statbus && grep -E '^(CADDY_DEPLOYMENT_MODE|SITE_DOMAIN|DEPLOYMENT_SLOT_NAME|DEPLOYMENT_SLOT_CODE|DEPLOYMENT_SLOT_PORT_OFFSET)=' .env.config" | sed 's/^/    /' || true
[ "$MISMATCHES" -eq 0 ] || { echo "FAIL: $MISMATCHES configuration value(s) differ from the defaults the questions offered" >&2; exit 1; }

echo ""
echo "── the running installation is the country's, at the candidate ──"
RUNNING=$(VM_EXEC bash -c "docker ps --format '{{.Names}}'" | sort)
for service in db rest app worker proxy; do
    printf '%s\n' "$RUNNING" | grep -qx "statbus-$COUNTRY_CODE-$service" || {
        echo "FAIL: container statbus-$COUNTRY_CODE-$service is not running; running containers:" >&2
        printf '    %s\n' "$RUNNING" >&2
        exit 1
    }
done
echo "  ✓ statbus-$COUNTRY_CODE-{db,rest,app,worker,proxy} are running"
BINARY_IDENTITY=$(VM_EXEC bash -c "cd ~/statbus && ./sb --version")
EXPECTED_BINARY="sb version $INSTALL_TARGET_TAG (commit ${TARGET_SHA:0:8})"
[ "$BINARY_IDENTITY" = "$EXPECTED_BINARY" ] || { echo "FAIL: installed binary: expected '$EXPECTED_BINARY', arrived '$BINARY_IDENTITY'" >&2; exit 1; }
echo "  ✓ installed binary: $BINARY_IDENTITY"

echo ""
echo "── operator installs the certificate (the questionnaire does not ask for one) ──"
CERT_LOG=$(mktemp)
VM_EXEC bash -c "cd ~/statbus && ./sb cert install /home/statbus/harness-certs/domain.crt /home/statbus/harness-certs/domain.key" >"$CERT_LOG" 2>&1 || {
    cat "$CERT_LOG" >&2
    echo "FAIL: ./sb cert install did not complete for $SETUP_DOMAIN" >&2
    exit 1
}
grep -Eq "Verified: https://$SETUP_DOMAIN serves the new certificate" "$CERT_LOG" || { cat "$CERT_LOG" >&2; echo "FAIL: ./sb cert install did not verify the certificate served for $SETUP_DOMAIN" >&2; exit 1; }
rm -f "$CERT_LOG"
echo "  ✓ certificate installed and served for $SETUP_DOMAIN"

echo ""
echo "── the site answers ──"
assert_health_passes "$VM_NAME"
assert_harness_https_passes "$VM_NAME"
APP_CODE=$(VM_EXEC curl --noproxy '*' --silent --show-error --cacert /home/statbus/harness-certs/ca.crt \
    --connect-timeout 5 --max-time 30 --output /dev/null --write-out '%{http_code}' "https://$SETUP_DOMAIN/") || APP_CODE=000
[[ "$APP_CODE" =~ ^[23][0-9][0-9]$ ]] || { echo "FAIL: the web app at https://$SETUP_DOMAIN/: expected HTTP 2xx/3xx, arrived $APP_CODE" >&2; exit 1; }
echo "  ✓ CA-verified HTTPS web app / (HTTP $APP_CODE)"
assert_systemd_active "$VM_NAME"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "PASS: 0-interactive-setup-choices: Enter at every setup question installed standalone $COUNTRY_NAME ($COUNTRY_CODE) at $SETUP_DOMAIN"
echo "════════════════════════════════════════════════════════════════"
