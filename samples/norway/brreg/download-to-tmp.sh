#!/bin/bash
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd ../../.. && pwd )"

# Ensure Python venv exists with required packages
VENV_DIR="$WORKSPACE/.venv"
if test ! -d "$VENV_DIR"; then
  echo "Creating Python venv"
  python3 -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install --quiet --upgrade pip ijson
PYTHON="$VENV_DIR/bin/python3"

pushd $WORKSPACE/tmp
if test \! -f "enheter.csv"; then
  echo "Download brreg enheter"
  curl --output enheter.csv.gz 'https://data.brreg.no/enhetsregisteret/api/enheter/lastned/csv'
  gunzip enheter.csv.gz
fi

if test \! -f "underenheter.csv"; then
  echo "Download brreg underenheter"
  curl --output underenheter.csv.gz 'https://data.brreg.no/enhetsregisteret/api/underenheter/lastned/csv'
  gunzip underenheter.csv.gz
fi

if test \! -f "underenheter_filtered.csv"; then
  $PYTHON $WORKSPACE/samples/norway/brreg/filter-tmp-underenheter.py
fi

if test \! -f "roller.json.gz"; then
  echo "Download brreg roller (totalbestand)"
  curl --output roller.json.gz 'https://data.brreg.no/enhetsregisteret/api/roller/totalbestand'
fi

if test \! -f "roller_legal_relationships.csv"; then
  $PYTHON $WORKSPACE/samples/norway/brreg/extract-roller-to-csv.py
fi

popd
