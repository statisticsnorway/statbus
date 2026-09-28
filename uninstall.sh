#!/usr/bin/env bash
# Standalone StatBus removal: curl -fsSL https://statbus.org/uninstall.sh | bash
# shellcheck disable=SC2024 # LOG is in the invoking user's home; sudo is only for the command.
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
# Keep the exclusion inode outside the tree being removed, through final unlink.
command -v perl >/dev/null 2>&1 || { echo 'perl is required for the uninstall mutex.'; exit 1; }
exec 8<>"$HOME/.statbus-uninstall.lock"
if ! perl -e 'use Fcntl ":flock"; open(my $f, "<&=8") or exit 2; exit(flock($f, LOCK_EX|LOCK_NB) ? 0 : 1);'; then
    echo 'Install/uninstall mutex is held; refusing removal.'
    exit 1
fi
# The Go install/upgrade mutex and install.sh's statbus_repo_lock are the
# exclusive flock on this exact inode. Never unlink it until the last operation.
# A bind of the checkout can include submounts (even same-filesystem bind mounts).
# Inspect mountpoints, not filesystem boundaries, before any service is stopped.
refuse_nested_mounts() {
    local mounts mountpoint
    if command -v findmnt >/dev/null 2>&1; then
        mounts=$(findmnt -rn -o TARGET) || { echo 'Cannot inspect mountpoints; refusing removal. Check findmnt and retry.'; return 1; }
    elif [[ -r /proc/self/mountinfo ]]; then
        mounts=$(perl -ne 'my @fields = split / /; print "$fields[4]\n"' /proc/self/mountinfo) || { echo 'Cannot inspect mountpoints; refusing removal.'; return 1; }
    elif [[ $(uname -s) == Linux ]]; then
        echo 'Cannot inspect mountpoints; install findmnt and retry.'
        return 1
    else
        # Non-Linux hosts are used by the CLI's mocked shell tests.
        return 0
    fi
    mountpoint=$(printf '%s\n' "$mounts" | perl -MCwd=abs_path -e '
        my $base = abs_path(shift) // die "Cannot resolve checkout\n";
        $base =~ s{/$}{};
        while (my $mount = <STDIN>) {
            chomp $mount;
            next unless length $mount;
            $mount =~ s/\\x([0-9a-fA-F]{2})/chr(hex($1))/ge; # findmnt -r
            $mount =~ s/\\([0-7]{3})/chr(oct($1))/ge;   # mountinfo
            die "Invalid mount target escape\n" if $mount =~ /\\/;
            my $canonical = abs_path($mount) // die "Cannot resolve mount target: $mount\n";
            if ($canonical eq $base || index($canonical, "$base/") == 0) {
                print "$mount\n"; last;
            }
        }
    ' "$DIR") || { echo 'Cannot resolve checkout mountpoints; refusing removal.'; return 1; }
    if [[ -n $mountpoint ]]; then
        echo "Mountpoint $mountpoint is on or inside $DIR; unmount it or move it outside the checkout, then retry removal."
        return 1
    fi
}
# The marker and Docker probe write through tmp. Reject any symlink in these
# paths before opening the marker, and again under the lock.
check_tmp_boundary() {
    [[ ! -L $DIR && ! -L $DIR/tmp && -d $DIR/tmp && ! -L $DIR/tmp/upgrade-in-progress.json ]] || {
        echo 'Checkout tmp or its install lock is a symlink or not a directory; repair ~/statbus/tmp and retry.'
        return 1
    }
    if [[ -e $DIR/tmp/upgrade-in-progress.json && ! -f $DIR/tmp/upgrade-in-progress.json ]]; then
        echo 'Install lock is not a regular file inside ~/statbus/tmp; repair it and retry.'
        return 1
    fi
}
if [[ -d $DIR ]]; then
    [[ ! -L $DIR ]] || { echo 'Checkout is a symlink; refusing removal outside ~/statbus.'; exit 1; }
    # Remember the directory before scanning mounts: a root mount arriving
    # between the scan and Docker's bind cannot become the trusted source.
    checkout_inode=$(perl -e 'my @s = stat(shift) or die "Cannot stat checkout\n"; print "$s[0]:$s[1]"' "$DIR") || exit 1
    refuse_nested_mounts || exit 1
    [[ ! -L $DIR/tmp ]] || { echo 'Checkout tmp is a symlink; move it inside ~/statbus and retry.'; exit 1; }
    [[ -d $DIR/tmp ]] || mkdir -p "$DIR/tmp"
    check_tmp_boundary || exit 1
    flag="$DIR/tmp/upgrade-in-progress.json"
    marker_owned=0
    if ! { exec 9<>"$flag"; } 2>/dev/null; then
        echo 'Cannot open the install lock in ~/statbus/tmp; repair its permissions or ask an administrator to restore ownership, then retry.'
        exit 1
    fi
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
    trap 'if [[ $marker_owned == 1 && -e $flag && ! -L $DIR/tmp && ! -L $flag ]]; then rm -f -- "$flag"; fi' EXIT
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
if ((${#units[@]} > 0)) && ! command -v systemctl >/dev/null 2>&1; then
    echo 'An upgrade unit is installed but systemctl is unavailable; refusing removal.'
    exit 1
fi
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
# Every checkout deletion uses a nonrecursive private bind of HOME. Binding
# the parent omits mounts even on the checkout root; cd pins the directory,
# and the inode check rejects symlink substitutions before any file deletion.
USE_DOCKER=0
CLEANUP_IMAGE=
PULLED_CLEANUP_IMAGE=0
DOCKER_BIND="type=bind,src=$HOME,dst=/home-root,bind-recursive=disabled,bind-propagation=rprivate"
if [[ -d $DIR ]]; then
    # Docker must bind precisely the inode observed before the first mount scan.
    client_version=$(docker version --format '{{.Client.Version}}' 2>/dev/null || true)
    server_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)
    client_major=${client_version%%.*}
    server_major=${server_version%%.*}
    if [[ ! $client_major =~ ^[0-9]+$ || ! $server_major =~ ^[0-9]+$ ]] ||
        ((client_major < 25 || server_major < 25)); then
        echo 'Safe checkout removal requires Docker client and server version 25 or newer. Upgrade Docker and retry; nothing has been deleted.'
        exit 1
    fi
    if [[ -e /etc/systemd/system/statbus-upgrade@.service && $USER != statbus_* ]] && ! sudo -n true >/dev/null 2>&1; then
        echo 'Removing the system upgrade unit requires sudo; ask an administrator to run sudo -v and retry.'
        exit 1
    fi
    # On a partial install use Alpine; pull before stopping services.
    for image in "${images[@]}"; do
        if [[ $image == ghcr.io/statisticsnorway/statbus-db:* ]]; then CLEANUP_IMAGE=$image; break; fi
    done
    if [[ -z $CLEANUP_IMAGE ]]; then
        CLEANUP_IMAGE=alpine:3.20
        if ! docker image inspect "$CLEANUP_IMAGE" >/dev/null 2>&1; then
            if ! docker pull "$CLEANUP_IMAGE" >>"$LOG" 2>&1; then
                echo 'Cannot prepare a Docker cleanup image; fix Docker and retry.'
                exit 1
            fi
            PULLED_CLEANUP_IMAGE=1
        fi
    fi
    # Unsupported bind-recursive options fail closed. The helper enters the
    # checkout beneath the nonrecursive parent bind, pins cwd and verifies its
    # inode before any write, including the preflight probe.
    if ! docker run --rm --network none --user 0:0 --entrypoint /bin/sh --mount "$DOCKER_BIND" "$CLEANUP_IMAGE" -c 'cd /home-root/statbus && test "$(stat -c %d:%i .)" = "$1" && test -d ./tmp && find . -mindepth 1 -exec test -r {} \; -exec test -w {} \; && mkdir ./tmp/.uninstall-preflight.$$ && rmdir ./tmp/.uninstall-preflight.$$' sh "$checkout_inode" >>"$LOG" 2>&1; then
        [[ $PULLED_CLEANUP_IMAGE == 0 ]] || docker image rm "$CLEANUP_IMAGE" >>"$LOG" 2>&1 || true
        echo 'Docker cannot safely remove checkout files; upgrade Docker or repair its access and retry.'
        exit 1
    fi
    USE_DOCKER=1
fi
echo 'StatBus removal plan (only listed resources will be deleted):'
[[ -z ${containers:-} ]] || echo "  Project containers: $containers"
[[ -z ${volumes:-} ]] || echo "  Project volumes: $volumes"
[[ -z ${networks:-} ]] || echo "  Project networks: $networks"
for image in "${images[@]}"; do echo "  Image tag: $image"; done
[[ $USE_DOCKER == 0 ]] || echo "  Docker cleanup helper: $CLEANUP_IMAGE (removed last if pulled for this run)"
for unit in "${units[@]}"; do echo "  Unit file: $unit"; done
for path in "${remaining[@]}"; do echo "  Path (recursively): $path"; done
[[ ! -d $DIR/tmp ]] || echo "  Path (recursively, last): $DIR/tmp"
[[ $KEEP_DUMPS == 0 || ! -e $DIR/dbdumps ]] || echo "  Keep: $DIR/dbdumps"
[[ $KEEP_CREDENTIALS == 0 || ! -e $DIR/.env.credentials ]] || echo "  Keep: $DIR/.env.credentials"
if [[ $INTERACTIVE == 1 ]]; then
    read -r -u 3 -p 'Type DELETE to execute this exact plan: ' answer
    [[ $answer == DELETE ]] || { echo 'Removal cancelled.'; exit 1; }
fi
# Recheck under the install lock before teardown and again before each deletion.
if [[ -d $DIR ]]; then
    check_tmp_boundary || exit 1
    refuse_nested_mounts || exit 1
fi
user_unit="statbus-upgrade@${USER}.service"
user_state=inactive
if command -v systemctl >/dev/null 2>&1; then
    user_state=$(systemctl --user is-active "$user_unit" 2>/dev/null || true)
fi
if ((${#units[@]} > 0)) || [[ -n $user_state && $user_state != inactive && $user_state != unknown ]]; then
    echo 'Step 1: stopping StatBus upgrade service'
    if [[ -e $HOME/.config/systemd/user/statbus-upgrade@.service ]] || [[ -n $user_state && $user_state != inactive && $user_state != unknown ]]; then
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
    for image in "${images[@]}"; do
        [[ $USE_DOCKER == 1 && $image == "$CLEANUP_IMAGE" ]] || docker image rm "$image" >>"$LOG" 2>&1
    done
fi
echo 'Step 3: removing units and checkout files'
system_unit_removed=0
for unit in "${units[@]}"; do
    if [[ $unit == /etc/* ]]; then
        sudo -n rm -f -- "$unit" >>"$LOG" 2>&1
        system_unit_removed=1
    else
        rm -f -- "$unit" >>"$LOG" 2>&1
    fi
done
if command -v systemctl >/dev/null 2>&1 && { ((${#units[@]} > 0)) || [[ -n $user_state && $user_state != inactive && $user_state != unknown ]]; }; then
    systemctl --user daemon-reload >>"$LOG" 2>&1
    if [[ $system_unit_removed == 1 ]]; then sudo -n systemctl daemon-reload >>"$LOG" 2>&1; fi
fi
for path in "${remaining[@]}"; do
    check_tmp_boundary || exit 1
    refuse_nested_mounts || exit 1
    docker run --rm --network none --user 0:0 --entrypoint /bin/sh --mount "$DOCKER_BIND" "$CLEANUP_IMAGE" -c 'cd /home-root/statbus && test "$(stat -c %d:%i .)" = "$1" && rm -rf -- "./$2"' sh "$checkout_inode" "${path##*/}" >>"$LOG" 2>&1
done
# tmp is the last checkout path deleted; the outer HOME lock remains held while
# removing the helper image and the empty checkout directory afterward.
if [[ -d $DIR/tmp ]]; then
    check_tmp_boundary || exit 1
    refuse_nested_mounts || exit 1
    docker run --rm --network none --user 0:0 --entrypoint /bin/sh --mount "$DOCKER_BIND" "$CLEANUP_IMAGE" -c 'cd /home-root/statbus && test "$(stat -c %d:%i .)" = "$1" && rm -rf -- ./tmp' sh "$checkout_inode" >>"$LOG" 2>&1
fi
if [[ $USE_DOCKER == 1 ]]; then
    for image in "${images[@]}"; do
        [[ $image != "$CLEANUP_IMAGE" ]] || docker image rm "$image" >>"$LOG" 2>&1
    done
    [[ $PULLED_CLEANUP_IMAGE == 0 ]] || docker image rm "$CLEANUP_IMAGE" >>"$LOG" 2>&1
fi
if [[ -d $DIR ]]; then
    if [[ $KEEP_DUMPS == 0 && $KEEP_CREDENTIALS == 0 ]]; then rmdir "$DIR"; else rmdir "$DIR" 2>/dev/null || true; fi
fi
echo "Removal complete. Details: $LOG"
