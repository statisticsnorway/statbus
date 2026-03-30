#!/bin/sh
# Container startup script.
#
# Previously this script replaced __NEXT_PUBLIC_*__ placeholders in the JS
# bundle with runtime values. That approach is no longer needed — layout.tsx
# now injects config into the HTML via window.__STATBUS_CONFIG__ at request
# time, reading process.env server-side.
#
# This entrypoint is kept for any future startup tasks.

set -e

# Execute the original command (node server.js)
exec "$@"
