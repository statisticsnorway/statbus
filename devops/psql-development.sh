#!/bin/bash
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

# When using scripted input, such as "< some.sql" then interactive TTY is required.
args="-i"
if test -t 0; then
  # Enable the TTY in docker,with -t
  # as required for an interactive psql promp
  args="-ti"
fi

docker exec $args $(docker ps  | awk '/statbus-postgres/{print $1}') psql -U statbus_development statbus_development $@