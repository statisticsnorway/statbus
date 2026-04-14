#!/bin/sh
# stamp-if-clean.sh
#
# Writes the current git HEAD SHA to tmp/<stamp-name> at the project
# root — but ONLY if the app/ subtree is clean (no unstaged or staged
# changes). A dirty app/ means whatever the caller just passed (tsc,
# build, …) doesn't reflect HEAD, so the stamp would lie.
#
# Usage: ./scripts/stamp-if-clean.sh <stamp-name>
# Example: ./scripts/stamp-if-clean.sh app-tsc-passed-sha
#
# Must be run from the app/ directory (pnpm script cwd). `git diff
# -- .` from here checks only the app subtree, which matches the
# scope the stamp represents: "HEAD's app/ passed {tsc|build}".
#
# Consumed by cli/cmd/release.go:preflightChecks — `./sb release
# prerelease` refuses to tag unless the stamps cover every app/ file
# changed since the stamped SHA.
#
# Shebang is /bin/sh (POSIX) so this also runs inside the alpine-based
# Dockerfile build (node:22-alpine has no /bin/bash). When the script
# runs in a context with no .git (e.g., inside `docker build`), it
# bails out as a no-op — there's nothing meaningful to stamp.

set -e

STAMP="$1"
if [ -z "$STAMP" ]; then
    echo "usage: stamp-if-clean.sh <stamp-name>" >&2
    exit 1
fi

# Bail out gracefully when we're not in a git work tree — happens
# inside Docker builds, tarball extracts, etc. The stamp is a
# host-side prerelease gate; running it elsewhere serves no purpose.
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "Note: not in a git work tree; skipping stamp ($STAMP)."
    exit 0
fi

if git diff --quiet HEAD -- . && git diff --cached --quiet HEAD -- .; then
    mkdir -p ../tmp
    git rev-parse HEAD > "../tmp/$STAMP"
    echo "Stamp recorded ($STAMP): $(cat "../tmp/$STAMP")"
else
    echo "Note: app/ has uncommitted changes; stamp NOT updated ($STAMP)."
fi
