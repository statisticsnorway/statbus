#!/bin/bash

# Pure, fail-closed predicates shared by arcs and their bounded local regression.
# Callers own diagnostics so each scenario can name the exact failed contract.
arc_c9_signature_is_nonterminal() {
    [ "${1:-}" = "running" ] &&
        [ "${2:-}" = "in_progress" ] &&
        [ "${3:-}" = "t" ] &&
        [ "${4:-}" = "t" ]
}

arc_health_park_fields_match() {
    local failure_code="${1:-}"
    local parked_reason="${2:-}"
    local target_short="${3:-}"

    [ "$failure_code" = "HEALTHCHECK_REST_DOWN" ] &&
        [ -n "$target_short" ] &&
        [[ "$parked_reason" == *"the application cannot serve at ${target_short} past warmup"* ]]
}
