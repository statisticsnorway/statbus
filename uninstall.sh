#!/usr/bin/env bash
# Standalone StatBus removal: curl -fsSL https://statbus.org/uninstall.sh | bash
# Also invoked by ./sb uninstall. Never source files from the checkout.
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
# Compute the plan from actual resources, without trusting .env as shell code.
project=statbus
if [[ -f "$DIR/.env" ]]; then
    configured=$(grep '^COMPOSE_INSTANCE_NAME=' "$DIR/.env" | tail -1 | cut -d= -f2- | tr -d '"\r' || true)
    [[ $configured =~ ^statbus(-[a-zA-Z0-9_-]+)?$ ]] || { echo 'Invalid compose project name; refusing removal.'; exit 1; }
    project=$configured
fi
units=()
for unit in "$HOME/.config/systemd/user/statbus-upgrade@.service" /etc/systemd/system/statbus-upgrade@.service; do
    # Multi-tenant slots share the host template. Never remove it for one slot.
    [[ $unit != /etc/* || $USER != statbus_* ]] || continue
    [[ ! -e $unit ]] || units+=("$unit")
done
containers=()
volumes=()
networks=()
images=()
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    while IFS= read -r id; do [[ -z $id ]] || containers+=("$id"); done < <(docker ps -aq --filter "label=com.docker.compose.project=$project")
    while IFS= read -r id; do [[ -z $id ]] || volumes+=("$id"); done < <(docker volume ls -q --filter "label=com.docker.compose.project=$project")
    while IFS= read -r id; do [[ -z $id ]] || networks+=("$id"); done < <(docker network ls -q --filter "label=com.docker.compose.project=$project")
    for id in "${containers[@]}"; do
        image=$(docker inspect --format '{{.Config.Image}}' "$id")
        [[ $image != ghcr.io/statisticsnorway/statbus-* ]] || images+=("$image")
    done
    if [[ -f $DIR/.env && -f $DIR/docker-compose.yml ]]; then
        while IFS= read -r image; do
            [[ $image != ghcr.io/statisticsnorway/statbus-* ]] || images+=("$image")
        done < <(cd "$DIR" && docker compose config --images 2>/dev/null)
    fi
elif [[ -d $DIR ]]; then
    echo 'Docker is unavailable. Refusing to leave containers or volumes behind; start Docker and retry.'
    exit 1
fi
if [[ -d $DIR || -e /etc/systemd/system/statbus-upgrade@.service ]]; then
    if ! sudo -n true 2>/dev/null; then
        if [[ -e $DIR/caddy/data || -e /etc/systemd/system/statbus-upgrade@.service ]]; then
            echo 'Removal requires sudo for root-owned installation files or system units. Run sudo -v and retry.'
            exit 1
        fi
        USE_SUDO=0
    else
        USE_SUDO=1
    fi
fi
remaining=()
if [[ -d $DIR ]]; then
    shopt -s dotglob nullglob
    for path in "$DIR"/*; do
        [[ $KEEP_DUMPS == 1 && $path == "$DIR/dbdumps" ]] && continue
        [[ $KEEP_CREDENTIALS == 1 && $path == "$DIR/.env.credentials" ]] && continue
        remaining+=("$path")
    done
fi
echo 'StatBus removal plan (only listed resources will be deleted):'
for id in "${containers[@]}"; do echo "  Container: $id"; done
for id in "${volumes[@]}"; do echo "  Volume: $id"; done
for id in "${networks[@]}"; do echo "  Network: $id"; done
for id in "${images[@]}"; do echo "  Image tag: $id"; done
for id in "${units[@]}"; do echo "  Unit file: $id"; done
for path in "${remaining[@]}"; do echo "  Path (recursively): $path"; done
[[ $KEEP_DUMPS == 0 || ! -e $DIR/dbdumps ]] || echo "  Keep: $DIR/dbdumps"
[[ $KEEP_CREDENTIALS == 0 || ! -e $DIR/.env.credentials ]] || echo "  Keep: $DIR/.env.credentials"
if [[ $INTERACTIVE == 1 ]]; then
    read -r -u 3 -p 'Type DELETE to execute this exact plan: ' answer
    [[ $answer == DELETE ]] || { echo 'Removal cancelled.'; exit 1; }
fi
# Do not terminate an active upgrade while it is mutating the database.
if command -v systemctl >/dev/null 2>&1; then
    echo 'Step 1: stopping StatBus upgrade service'
    systemctl --user disable --now "statbus-upgrade@${USER}.service" >>"$LOG" 2>&1 || true
    if [[ $USER != statbus_* && -e /etc/systemd/system/statbus-upgrade@.service ]]; then
        sudo systemctl disable --now "statbus-upgrade@${USER}.service" >>"$LOG" 2>&1 || true
    fi
fi
echo 'Step 2: removing Docker resources'
((${#containers[@]} == 0)) || docker rm -f "${containers[@]}" >>"$LOG" 2>&1
((${#volumes[@]} == 0)) || docker volume rm "${volumes[@]}" >>"$LOG" 2>&1
((${#networks[@]} == 0)) || docker network rm "${networks[@]}" >>"$LOG" 2>&1
((${#images[@]} == 0)) || docker image rm "${images[@]}" >>"$LOG" 2>&1 || true
echo 'Step 3: removing units and checkout files'
for id in "${units[@]}"; do
    if [[ $id == /etc/* ]]; then sudo rm -f -- "$id" >>"$LOG" 2>&1; else rm -f -- "$id" >>"$LOG" 2>&1; fi
done
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload >>"$LOG" 2>&1 || true
    if [[ -e /etc/systemd/system ]]; then sudo -n systemctl daemon-reload >>"$LOG" 2>&1 || true; fi
fi
for path in "${remaining[@]}"; do
    if [[ ${USE_SUDO:-0} == 1 ]]; then sudo -n rm -rf -- "$path" >>"$LOG" 2>&1; else rm -rf -- "$path" >>"$LOG" 2>&1; fi
done
rmdir "$DIR" 2>/dev/null || true
echo "Removal complete. Details: $LOG"
