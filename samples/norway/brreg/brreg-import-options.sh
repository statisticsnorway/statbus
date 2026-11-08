#!/bin/bash
# shellcheck disable=SC2034 # Outputs are consumed by the sourcing loaders and cloud dispatcher.
# Shared, side-effect-free BRREG option validation. Gregorian dates are checked
# arithmetically so the interface behaves identically on Darwin and Linux.
brreg_parse_options() {
    BRREG_VALID_FROM="" BRREG_YEAR="" BRREG_DATABASE="" BRREG_HELP=0
    BRREG_FORWARD=()
    local option value year month day max_day
    while [ "$#" -gt 0 ]; do
        option=$1
        case "$option" in
            -h|--help)
                [ "$BRREG_HELP" -eq 0 ] || { echo 'Error: duplicate help option' >&2; return 1; }
                BRREG_HELP=1; shift; continue ;;
            --valid-from|--year|--database)
                [ "$#" -ge 2 ] && [ -n "$2" ] && [[ "$2" != -* ]] || { echo "Error: $option requires a value" >&2; return 1; }
                value=$2
                case "$option" in
                    --database)
                        [ -z "$BRREG_DATABASE" ] || { echo 'Error: duplicate --database' >&2; return 1; }
                        # Database names stay opaque argv data, including names
                        # requiring PostgreSQL identifier quoting. No SQL uses it.
                        BRREG_DATABASE=$value ;;
                    *)
                        [ -z "$BRREG_VALID_FROM$BRREG_YEAR" ] || { echo 'Error: choose --valid-from OR --year once' >&2; return 1; }
                        if [ "$option" = --year ]; then
                            [[ "$value" =~ ^[0-9]{4}$ ]] && [ "$value" != 0000 ] || { echo 'Error: expected year YYYY (0001-9999)' >&2; return 1; }
                            BRREG_YEAR=$value
                            BRREG_VALID_FROM="$value-01-01"
                        else
                            [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo 'Error: expected date YYYY-MM-DD' >&2; return 1; }
                            year=$((10#${value:0:4})); month=$((10#${value:5:2})); day=$((10#${value:8:2}))
                            [ "$year" -gt 0 ] && [ "$month" -ge 1 ] && [ "$month" -le 12 ] || { echo 'Error: invalid calendar date' >&2; return 1; }
                            case "$month" in
                                4|6|9|11) max_day=30 ;;
                                2) max_day=28; if (( year % 400 == 0 || (year % 4 == 0 && year % 100 != 0) )); then max_day=29; fi ;;
                                *) max_day=31 ;;
                            esac
                            [ "$day" -ge 1 ] && [ "$day" -le "$max_day" ] || { echo 'Error: invalid calendar date' >&2; return 1; }
                            BRREG_VALID_FROM=$value
                            BRREG_YEAR=${value:0:4}
                        fi ;;
                esac
                BRREG_FORWARD+=("$option" "$value")
                shift 2 ;;
            *) echo "Error: unknown argument $option" >&2; return 1 ;;
        esac
    done
}
brreg_help() {
    echo 'Usage: [--database NAME] [--valid-from YYYY-MM-DD | --year YYYY] [--help]'
    echo 'Explicit validity applies to all three jobs. --year means January 1.'
    echo 'Legacy defaults: selection current-year January 1, downloads execution date.'
    echo 'These defaults do not decide owner validity policy (STATBUS-591 AC3 pending).'
}
