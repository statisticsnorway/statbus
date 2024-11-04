#!/bin/bash
#
#!/bin/bash
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd ../../.. && pwd )"

$WORKSPACE/samples/norway/brreg/download-to-tmp.sh

psql < samples/norway/brreg/brreg-draw-samples.sql
