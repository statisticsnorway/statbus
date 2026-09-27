#!/usr/bin/env bash
# Source this file, then call fleet_status_read FILE. Missing/malformed status is ERROR.
# The first line is the only authoritative classification. Metadata is informational.
fleet_status_read() {
    FLEET_STATUS=ERROR
    FLEET_DETAIL='missing or malformed fleet status'
    FLEET_PHASE=''
    local line status
    [ -f "$1" ] || return 0
    IFS= read -r line < "$1" || [ -n "$line" ] || return 0
    case "$line" in
        STATUS=PASSED|STATUS=FAILED|STATUS=SUPERSEDED|STATUS=ERROR)
            status=${line#STATUS=}
            FLEET_STATUS=$status
            FLEET_DETAIL=''
            ;;
        *) return 0 ;;
    esac
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            DETAIL=*) FLEET_DETAIL=${line#DETAIL=} ;;
            PHASE=*) FLEET_PHASE=${line#PHASE=} ;;
            *) FLEET_STATUS=ERROR; FLEET_DETAIL='malformed fleet status metadata'; return 0 ;;
        esac
    done < <(tail -n +2 "$1")
}
