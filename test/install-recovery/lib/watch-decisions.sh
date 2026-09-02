#!/bin/bash
# Pure decision functions for vm-bootstrap.sh's tmux controller watch loop.
# No environment, network, or Hetzner dependencies: shell tests can exercise
# every classification without provisioning a VM.

watch_ssh_rc_class() {
    case "$1" in
        0) printf '%s\n' success ;;
        # OpenSSH's connection-loss status and GNU timeout's probe ceiling are
        # both controller transport failures. The detached tmux stage survives.
        124|255) printf '%s\n' reconnect ;;
        *) printf '%s\n' fatal ;;
    esac
}

# watch_reconnect_decision RC ATTEMPT MAX_ATTEMPTS VM_STATE
# VM_STATE is consulted only after the bounded reconnect window is exhausted:
# alive, missing, or unknown.
watch_reconnect_decision() {
    local class
    class=$(watch_ssh_rc_class "$1")
    case "$class" in
        success) printf '%s\n' success ;;
        fatal) printf '%s\n' fatal ;;
        reconnect)
            if [ "$2" -lt "$3" ]; then
                printf '%s\n' retry
            else
                case "$4" in
                    missing) printf '%s\n' vm-gone ;;
                    alive|unknown) printf '%s\n' resume ;;
                    *) printf '%s\n' fatal ;;
                esac
            fi
            ;;
    esac
}

# watch_progress_decision CURRENT_LINES SEEN_LINES NOW LAST_PROGRESS WINDOW
watch_progress_decision() {
    local current="$1" seen="$2" now="$3" last_progress="$4" window="$5"
    if [ "$current" -gt "$seen" ]; then
        printf '%s\n' advanced
    elif [ $((now - last_progress)) -ge "$window" ]; then
        printf '%s\n' stalled
    else
        printf '%s\n' waiting
    fi
}
