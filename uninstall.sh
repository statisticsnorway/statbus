#!/usr/bin/env bash
# Standalone StatBus removal: curl -fsSL https://statbus.org/uninstall.sh | bash
set -eo pipefail
exec 2>&1
DIR="${HOME}/statbus"
LOG="${HOME}/statbus-uninstall.log"
KEEP_DUMPS=1
KEEP_CREDENTIALS=1
if [[ ${STATBUS_UNINSTALL_CONFIRM:-} != yes-delete-everything ]] && (exec 3</dev/tty) 2>/dev/null; then
    exec 3</dev/tty
    INTERACTIVE=1
else
    INTERACTIVE=0
fi
if [[ $INTERACTIVE == 0 ]]; then
    if [[ ${STATBUS_UNINSTALL_CONFIRM:-} != yes-delete-everything ]]; then
        echo 'Non-interactive removal requires STATBUS_UNINSTALL_CONFIRM=yes-delete-everything.'
        exit 1
    fi
    KEEP_DUMPS=0
    KEEP_CREDENTIALS=0
fi
if [[ $INTERACTIVE == 1 ]]; then
    echo 'Remove this StatBus installation? Backups and credentials are kept by default.'
    read -r -u 3 -p 'Delete database dumps too? [y/N] ' answer
    [[ $answer != [yY]* ]] || KEEP_DUMPS=0
    read -r -u 3 -p 'Delete credentials too? [y/N] ' answer
    [[ $answer != [yY]* ]] || KEEP_CREDENTIALS=0
fi
# The Go install/upgrade mutex and install.sh's statbus_repo_lock are the
# exclusive flock on this exact inode. Never unlink it until the last operation.
if [[ -d $DIR ]]; then
    [[ -d $DIR/tmp ]] || mkdir -p "$DIR/tmp"
    flag="$DIR/tmp/upgrade-in-progress.json"
    marker_owned=0
    exec 9<>"$flag"
    if ! perl -e 'use Fcntl ":flock"; open(my $f, "<&=9") or exit 2; exit(flock($f, LOCK_EX|LOCK_NB) ? 0 : 1);'; then
        echo 'Install/upgrade mutex is held; refusing removal.'
        exit 1
    fi
    if [[ ! -s $flag ]]; then
        printf '{"id":0,"commit_sha":"","started_at":"","invoked_by":"uninstall.sh","trigger":"install","holder":"install"}\n' >&9
        marker_owned=1
    fi
    # On refusal, remove only our own marker while still holding its flock.
    # The successful removal deletes tmp last, immediately before exit.
    trap 'if [[ $marker_owned == 1 && -e $flag ]]; then rm -f -- "$flag"; fi' EXIT
fi
project=statbus
if [[ -f "$DIR/.env" ]]; then
    configured=$(grep '^COMPOSE_INSTANCE_NAME=' "$DIR/.env" | tail -1 | cut -d= -f2- | tr -d '"\r' || true)
    [[ $configured =~ ^statbus(-[a-zA-Z0-9_-]+)?$ ]] || { echo 'Invalid compose project name; refusing removal.'; exit 1; }
    project=$configured
fi
units=()
for unit in "$HOME/.config/systemd/user/statbus-upgrade@.service" /etc/systemd/system/statbus-upgrade@.service; do
    [[ $unit != /etc/* || $USER != statbus_* ]] || continue
    [[ ! -e $unit ]] || units+=("$unit")
done
images=()
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    while IFS= read -r image; do
        [[ $image != ghcr.io/statisticsnorway/statbus-* ]] || images+=("$image")
    done < <(docker image ls --format '{{.Repository}}:{{.Tag}}' | grep '^ghcr.io/statisticsnorway/statbus-' || true)
    # Project labels include stopped containers, orphan volumes and networks.
    containers=$(docker ps -aq --filter "label=com.docker.compose.project=$project")
    volumes=$(docker volume ls -q --filter "label=com.docker.compose.project=$project")
    networks=$(docker network ls -q --filter "label=com.docker.compose.project=$project")
elif [[ -d $DIR ]]; then
    echo 'Docker is unavailable. Refusing to leave containers or volumes behind; start Docker and retry.'
    exit 1
fi
remaining=()
if [[ -d $DIR ]]; then
    shopt -s dotglob nullglob
    for path in "$DIR"/*; do
        [[ $KEEP_DUMPS == 1 && $path == "$DIR/dbdumps" ]] && continue
        [[ $KEEP_CREDENTIALS == 1 && $path == "$DIR/.env.credentials" ]] && continue
        [[ $path == "$DIR/tmp" ]] && continue
        remaining+=("$path")
    done
fi
# Preflight the entire tree, including tmp, before stopping anything. sudo -n
# must actually be able to traverse and remove the paths, not merely run true.
USE_SUDO=0
if [[ -d $DIR ]]; then
    if ! root_paths=$(find "$DIR" -mindepth 1 ! -user "$(id -u)" -print -quit 2>/dev/null); then
        root_paths=uninspectable
    fi
    if [[ -n $root_paths ]] || [[ ! -w $DIR ]] || [[ -e /etc/systemd/system/statbus-upgrade@.service && $USER != statbus_* ]]; then
        # Exercise the exact sudo rm command on a nested probe before teardown.
        probe=$(mktemp -d "$DIR/tmp/.uninstall-preflight.XXXXXXXX")
        sudo -n sh -c 'test -d "$1" && find "$1" -mindepth 1 -exec test -r {} \; -exec test -w {} \; && test -w "$1"' sh "$DIR" >/dev/null 2>&1 && sudo -n rm -rf -- "$probe" || { echo 'Whole-tree removal requires working sudo access; run sudo -v and retry.'; exit 1; }
        USE_SUDO=1
    else
        # Ownership alone is not sufficient: non-writable nested directories
        # can prevent recursive deletion even for their owner.
        find "$DIR" -type d ! -perm -u+w -print -quit | grep -q . && { echo 'Checkout contains non-writable directories; refusing removal.'; exit 1; }
    fi
fi
echo 'StatBus removal plan (only listed resources will be deleted):'
[[ -z ${containers:-} ]] || echo "  Project containers: $containers"
[[ -z ${volumes:-} ]] || echo "  Project volumes: $volumes"
[[ -z ${networks:-} ]] || echo "  Project networks: $networks"
for image in "${images[@]}"; do echo "  Image tag: $image"; done
for unit in "${units[@]}"; do echo "  Unit file: $unit"; done
for path in "${remaining[@]}"; do echo "  Path (recursively): $path"; done
[[ ! -d $DIR/tmp ]] || echo "  Path (recursively, last): $DIR/tmp"
[[ $KEEP_DUMPS == 0 || ! -e $DIR/dbdumps ]] || echo "  Keep: $DIR/dbdumps"
[[ $KEEP_CREDENTIALS == 0 || ! -e $DIR/.env.credentials ]] || echo "  Keep: $DIR/.env.credentials"
if [[ $INTERACTIVE == 1 ]]; then
    read -r -u 3 -p 'Type DELETE to execute this exact plan: ' answer
    [[ $answer == DELETE ]] || { echo 'Removal cancelled.'; exit 1; }
fi
if command -v systemctl >/dev/null 2>&1 && { ((${#units[@]} > 0)) || [[ $(systemctl --user is-active "statbus-upgrade@${USER}.service" 2>/dev/null || true) == active ]]; }; then
    echo 'Step 1: stopping StatBus upgrade service'
    user_unit="statbus-upgrade@${USER}.service"
    if [[ -e $HOME/.config/systemd/user/statbus-upgrade@.service ]] || [[ $(systemctl --user is-active "$user_unit" 2>/dev/null || true) == active ]]; then
        systemctl --user disable --now "$user_unit" >>"$LOG" 2>&1
        [[ $(systemctl --user is-active "$user_unit" 2>/dev/null || true) == inactive ]] || { echo 'User upgrade service is not inactive; refusing removal.'; exit 1; }
    fi
    if [[ $USER != statbus_* && -e /etc/systemd/system/statbus-upgrade@.service ]]; then
        sudo -n systemctl disable --now "$user_unit" >>"$LOG" 2>&1
        [[ $(sudo -n systemctl is-active "$user_unit" 2>/dev/null || true) == inactive ]] || { echo 'System upgrade service is not inactive; refusing removal.'; exit 1; }
    fi
fi
echo 'Step 2: removing Docker resources'
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if [[ -f $DIR/docker-compose.yml && -f $DIR/.env ]]; then
        (cd "$DIR" && docker compose --profile all down -v) >>"$LOG" 2>&1
    else
        [[ -z ${containers:-} ]] || docker rm -f $containers >>"$LOG" 2>&1
        [[ -z ${volumes:-} ]] || docker volume rm $volumes >>"$LOG" 2>&1
        [[ -z ${networks:-} ]] || docker network rm $networks >>"$LOG" 2>&1
    fi
    for image in "${images[@]}"; do docker image rm "$image" >>"$LOG" 2>&1; done
fi
echo 'Step 3: removing units and checkout files'
for unit in "${units[@]}"; do
    if [[ $unit == /etc/* ]]; then sudo -n rm -f -- "$unit" >>"$LOG" 2>&1; else rm -f -- "$unit" >>"$LOG" 2>&1; fi
done
if command -v systemctl >/dev/null 2>&1 && { ((${#units[@]} > 0)) || [[ $(systemctl --user is-active "statbus-upgrade@${USER}.service" 2>/dev/null || true) == active ]]; }; then
    systemctl --user daemon-reload >>"$LOG" 2>&1
    if [[ $USE_SUDO == 1 && $USER != statbus_* ]]; then sudo -n systemctl daemon-reload >>"$LOG" 2>&1; fi
fi
for path in "${remaining[@]}"; do
    if [[ $USE_SUDO == 1 ]]; then sudo -n rm -rf -- "$path" >>"$LOG" 2>&1; else rm -rf -- "$path" >>"$LOG" 2>&1; fi
done
# tmp is last, so the lock remains discoverable through all prior deletion.
if [[ -d $DIR/tmp ]]; then
    if [[ $USE_SUDO == 1 ]]; then sudo -n rm -rf -- "$DIR/tmp" >>"$LOG" 2>&1; else rm -rf -- "$DIR/tmp" >>"$LOG" 2>&1; fi
fi
rmdir "$DIR" 2>/dev/null || true
echo "Removal complete. Details: $LOG"
