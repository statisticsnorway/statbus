#!/bin/sh
cd "$(dirname "$0")/.." || exit 1
[ -x ./sb ] || exit 0
exec ./sb upgrade check
