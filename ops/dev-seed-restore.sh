#!/bin/bash

# restore_dev_seed_or_fallback restores the development seed when present.
# Every restore failure is non-fatal because the caller immediately runs all
# migrations. Exit 22 is the stronger, preflight-only signal that the cache is
# incompatible with this checkout, so only that case deletes the stale files.
restore_dev_seed_or_fallback() {
    local workspace=$1
    local restore_rc

    if [ ! -f "$workspace/.db-seed/seed.pg_dump" ]; then
        echo "No seed found in .db-seed/, running all migrations..."
        return 0
    fi

    set +e
    ./sb db seed restore
    restore_rc=$?
    set -e

    case "$restore_rc" in
        0)
            return 0
            ;;
        22)
            echo "Seed cache is incompatible with this checkout; deleting stale .db-seed/seed.pg_dump and seed.json."
            rm -f "$workspace/.db-seed/seed.pg_dump" "$workspace/.db-seed/seed.json"
            echo "Falling back to full migrations on the untouched database."
            ;;
        *)
            echo "Error: Seed restore failed (exit $restore_rc); falling back to full migrations."
            echo "The restore is atomic, so the fresh database remains safe to migrate from scratch."
            ;;
    esac
}
