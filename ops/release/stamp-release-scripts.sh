#!/usr/bin/env bash
# Stage the public scripts as release assets, stamped with the release tag.
#
# Usage: stamp-release-scripts.sh <tag> <dist-dir>
#
# install.sh, uninstall.sh and ops/setup-ubuntu-lts.sh each carry one line,
# STATBUS_RELEASE="@STATBUS_RELEASE@". The published copy has the tag there, so
# every script names the release it belongs to; the release tag is the only
# version (STATBUS-537). Run from the repository root by release.yaml.
set -euo pipefail
tag=${1:?usage: stamp-release-scripts.sh <tag> <dist-dir>}
dist=${2:?usage: stamp-release-scripts.sh <tag> <dist-dir>}
[[ "$tag" =~ ^v[0-9]{4}\.[0-9]{2}\.[0-9]+(-rc\.[0-9]+)?$ ]] || { echo "Refusing to stamp: '$tag' is not a release tag" >&2; exit 1; }
mkdir -p "$dist"
for pair in install.sh:install.sh uninstall.sh:uninstall.sh ops/setup-ubuntu-lts.sh:setup-ubuntu-lts.sh; do
    src=${pair%%:*} dst="$dist/${pair##*:}"
    [ "$(grep -c '^STATBUS_RELEASE="@STATBUS_RELEASE@"$' "$src")" = 1 ] || {
        echo "Refusing to stamp: $src must have exactly one STATBUS_RELEASE=\"@STATBUS_RELEASE@\" line" >&2; exit 1; }
    sed "s/^STATBUS_RELEASE=\"@STATBUS_RELEASE@\"\$/STATBUS_RELEASE=\"$tag\"/" "$src" > "$dst"
    grep -qx "STATBUS_RELEASE=\"$tag\"" "$dst" || { echo "Stamping $dst failed" >&2; exit 1; }
    chmod +x "$dst"
    echo "Stamped $dst with $tag"
done
