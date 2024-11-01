#!/bin/bash
#
#!/bin/bash
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd ../.. && pwd )"

pushd $WORKSPACE/tmp
if test \! -f "enheter.csv"; then
  echo "Download brreg enheter"
  cd tmp
  curl --output enheter.csv.gz 'https://data.brreg.no/enhetsregisteret/oppslag/enheter/lastned/csv/v2'
  gunzip enheter.csv.gz
fi

if test \! -f "underenheter.csv"; then
  echo "Download brreg underenheter"
  cd tmp
  curl --output underenheter.csv.gz 'https://data.brreg.no/enhetsregisteret/oppslag/underenheter/lastned/csv/v2'
  gunzip underenheter.csv.gz
fi
popd

psql < samples/norway/brreg-draw-samples.sql
