#!/usr/bin/env bash
# STATBUS-492: ops/setup-ubuntu-lts.sh must refuse a plain `sudo ./setup.sh`
# (SUDO_USER set, HOME still the invoking user's home) and name `sudo -i`,
# while a root login shell (HOME is not that user's home) proceeds. A root login
# reached with sudo from root itself (SUDO_USER=root, HOME is root's home, as
# with `ssh root@box` then `sudo -i`) is a root login shell and proceeds too.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/ops/setup-ubuntu-lts.sh"
me="$(id -un)"
myhome="$(eval echo "~$me")"
fail=0

out="$(SUDO_USER="$me" HOME="$myhome" bash "$SCRIPT" --help 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && grep -q "sudo -i" <<<"$out"; then
  echo "PASS plain-sudo refused (rc=$rc): $(grep 'sudo -i' <<<"$out")"
else
  echo "FAIL plain-sudo not refused (rc=$rc)"; fail=1
fi

other_home="$(mktemp -d)"
out="$(SUDO_USER="$me" HOME="$other_home" bash "$SCRIPT" --help 2>&1)"; rc=$?
rmdir "$other_home"
if [[ $rc -eq 0 ]]; then
  echo "PASS login-shell HOME proceeds"
else
  echo "FAIL login-shell HOME refused (rc=$rc): $out"; fail=1
fi

root_home="$(eval echo "~root")"
out="$(SUDO_USER=root HOME="$root_home" bash "$SCRIPT" --help 2>&1)"; rc=$?
if [[ $rc -eq 0 ]]; then
  echo "PASS sudo -i from root (HOME=$root_home) proceeds"
else
  echo "FAIL sudo -i from root refused (rc=$rc): $out"; fail=1
fi
exit $fail
