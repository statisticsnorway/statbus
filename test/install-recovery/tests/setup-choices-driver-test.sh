#!/usr/bin/env bash
# STATBUS-474: the setup-choices driver recognises the installer's questions
# as the installer prints them today.
#
# Field case (v2026.10.6-rc.01, LXD fleet run 41076193713): the certificate
# offer had become "Do you have a certificate to install now? [y/N]: "
# (2907d8da7), the driver still waited for "(yes/no) [no]", never recognised
# the offer, and failed the first gate run. Gate runs are the expensive place
# to learn that, so this test runs the scenario's own expect driver against a
# stand-in installer whose certificate prompt is built from the product's
# Go source (askCertYesNo's format and askInstallCert's question). Changing
# that wording without the driver now fails here, in Harness Selftest.
#
# The stand-in asks in the product's step order: Trusted signers (step 7)
# before Certificate (step 8), per the step table in cli/cmd/install.go.
#
# Point SETUP_CHOICES_SCENARIO at an older scenario file to see the red half.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCENARIO="${SETUP_CHOICES_SCENARIO:-$ROOT/test/install-recovery/scenarios/0-interactive-setup-choices.sh}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/setup-choices-driver-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

command -v expect >/dev/null || { echo "FAIL expect is not installed"; exit 1; }

# The driver exactly as the scenario stages it on the guest (the literal
# heredoc line, not an expansion).
# shellcheck disable=SC2016
sed -n '/^cat > "\$HOME\/setup-choices.exp" <<.EXPECT.$/,/^EXPECT$/p' "$SCENARIO" | sed '1d;$d' > "$WORK/setup-choices.exp"
[ -s "$WORK/setup-choices.exp" ] || { echo "FAIL could not extract the expect driver from $SCENARIO"; exit 1; }

# The certificate question as the product prints it: askInstallCert's label,
# formatted by askCertYesNo ("%s [y/N]: ").
label=$(grep -o 'askCertificateYesNo("[^"]*")' "$ROOT/cli/cmd/install_cert.go" | head -1 | sed 's/^askCertificateYesNo("//; s/")$//')
format=$(sed -n '/^func askCertYesNo/,/^}/p' "$ROOT/cli/cmd/install_cert.go" | grep -o 'fmt.Printf("[^"]*"' | head -1 | sed 's/^fmt.Printf("//; s/"$//')
[ -n "$label" ] && [ -n "$format" ] || { echo "FAIL could not read the certificate prompt from cli/cmd/install_cert.go"; exit 1; }
# shellcheck disable=SC2059 # the format is the product's own Printf format
cert_prompt=$(printf "$format" "$label")

cat > "$WORK/installer.sh" <<EOF
#!/usr/bin/env bash
echo "[4/19] Configuration        RUNNING"
echo "  How will people reach StatBus?"
echo "    development: testing on this computer only"
echo "    standalone: this computer serves the public website on ports 80 and 443"
echo "    private: another web server forwards visitors to StatBus"
read -r -p "  Deployment mode (development/standalone/private) [standalone]: " a
echo "  The web address people will use. For local testing, use local.statbus.org."
read -r -p "  Domain name [box.lxd]: " a
echo "  Suggested from the domain et.statbus-test.local; press Enter to accept it."
read -r -p "  Country name [Ethiopia]: " a
echo "  Suggested from Ethiopia; press Enter to accept it."
read -r -p "  Country code [et]: " a
echo "[4/19] Configuration        DONE"
echo "[7/19] Trusted signers      RUNNING"
read -r -p "Trust key(s) from github.com/jhf? [Y/n] " a
echo "[7/19] Trusted signers      DONE"
echo "[8/19] Certificate          RUNNING"
read -r -p "$cert_prompt" a
[ -z "\$a" ] || { echo "certificate answer was '\$a', expected Enter"; exit 3; }
echo "[8/19] Certificate          DONE"
echo "Installation complete!"
EOF
chmod +x "$WORK/installer.sh"

HOME="$WORK" SETUP_CHOICES_INSTALLER="$WORK/installer.sh" \
    expect "$WORK/setup-choices.exp" et.statbus-test.local Ethiopia et jhf 20 20 >"$WORK/run.log" 2>&1
rc=$?
summary=$(grep -o 'SETUP-CHOICES questions asked: .*' "$WORK/run.log" | tail -1)
if [ "$rc" -eq 0 ] && [ "$summary" = "SETUP-CHOICES questions asked: mode=1 domain=1 country-name=1 country-code=1 certificate-offer=1 signer=1" ]; then
    echo "PASS the driver answers every setup question once, including the certificate offer '$cert_prompt'"
    exit 0
fi
echo "FAIL the driver did not answer the installer's questions (exit $rc)"
grep 'SETUP-CHOICES' "$WORK/run.log" | tail -4
exit 1
