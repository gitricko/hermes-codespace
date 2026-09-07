#!/usr/bin/env bash
# dts.sh — Docker Test Shell. Run commands in a fresh, mounted, uid-1000 container.
#
# The whole point: test in a throwaway container so the host's installed libs,
# stale state, and services never pollute the test.
#
# Usage:
#   dts up                  # fresh container, repo bind-mounted at /src (installs NOTHING)
#   dts exec "<cmd>"        # run <cmd> inside container as uid-1000 user, bash -l, TTY-aware
#   dts apt "<pkgs>"        # apt-get update + install as ROOT (the one privileged path)
#   dts shell               # interactive shell (-it) for a human at a terminal
#   dts clean               # remove the container
#   dts status              # show container state
#
# Config (env vars):
#   IMAGE          base image            (default ubuntu:24.04)
#   CONTAINER      container name        (default dts-test)
#   CONTAINER_UID  user uid              (default 1000)
#   CONTAINER_GID  user gid              (default 1000)

set -euo pipefail

IMAGE="${IMAGE:-ubuntu:24.04}"
CONTAINER="${CONTAINER:-dts-test}"
CONTAINER_UID="${CONTAINER_UID:-1000}"
CONTAINER_GID="${CONTAINER_GID:-1000}"
REPO_PATH="$(pwd)"
MOUNT="/src"

# Resolve the uid-1000 user's home (Ubuntu/Debian: ubuntu; fallback: /home/vscode)
user_home() {
    # Ask the container which user owns uid 1000; default to /home/ubuntu
    docker exec "${CONTAINER}" bash -c "getent passwd ${CONTAINER_UID} | cut -d: -f6" 2>/dev/null \
        | tr -d '\n' || true
    [ -n "${_HOME:-}" ] || echo /home/ubuntu
}

home="/home/ubuntu"

color() { [ -t 1 ] && printf '\033[1;34m%s\033[0m\n' "$*" || echo "$*"; }
log()  { color "[dts] $*"; }

docker_env_flags() {
    printf -- '--user %s:%s -e HOME=%s' "${CONTAINER_UID}" "${CONTAINER_GID}" "${home}"
}

cmd_up() {
    if docker inspect "${CONTAINER}" >/dev/null 2>&1; then
        log "container ${CONTAINER} exists; use 'exec', 'clean', or 'rm -f ${CONTAINER}' first"
        exit 1
    fi
    log "creating ${CONTAINER} from ${IMAGE} (mount ${REPO_PATH} -> ${MOUNT})"
    docker run -d --name "${CONTAINER}" -v "${REPO_PATH}:${MOUNT}" "${IMAGE}" sleep infinity >/dev/null
    sleep 1
    # Ensure uid-1000 user exists and owns the mount (Ubuntu/Debian: ubuntu user)
    docker exec -u 0:0 "${CONTAINER}" bash -c "
        id ${CONTAINER_UID} >/dev/null 2>&1 || useradd -m -u ${CONTAINER_UID} ubuntu 2>/dev/null || true
        chown -R ${CONTAINER_UID}:${CONTAINER_GID} ${MOUNT}
        [ -d \"${home}\" ] || (mkdir -p ${home} && chown ${CONTAINER_UID}:${CONTAINER_GID} ${home})
    " >/dev/null
    home=$(docker exec "${CONTAINER}" bash -c "getent passwd ${CONTAINER_UID} | cut -d: -f6" | tr -d '\n')
    log "container ready. home=${home}. Install packages via: dts apt '<pkgs>' (root)"
    log "verify the mount: diff <(md5sum <file>) <(dts exec 'md5sum /src/<file>')"
}

cmd_exec() {
    docker inspect "${CONTAINER}" >/dev/null 2>&1 || { log "container not up; run 'dts up' first"; exit 1; }
    if [ "$#" -lt 1 ]; then
        log "usage: dts exec <command>"
        exit 1
    fi
    if [ -t 1 ]; then
        # Host stdout is a TTY (a real human) -> allocate a PTY inside
        docker exec -it $(docker_env_flags) "${CONTAINER}" bash -l -c "$*"
    else
        # Scripted/agent mode -> no -t (avoids 'input device is not a TTY'), keep stdin open
        docker exec -i $(docker_env_flags) "${CONTAINER}" bash -l -c "$*"
    fi
}

# Privileged/root exec. apt-get (and other package managers) need root, but a
# normal-user container can't run them as uid 1000. This is the ONE root path.
cmd_apt() {
    docker inspect "${CONTAINER}" >/dev/null 2>&1 || { log "container not up; run 'dts up' first"; exit 1; }
    if [ "$#" -lt 1 ]; then
        log "usage: dts apt '<pkg1> <pkg2> ...'   (runs apt-get update && install as root)"
        exit 1
    fi
    docker exec -u 0:0 -e DEBIAN_FRONTEND=noninteractive "${CONTAINER}" bash -c "apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq -o Dpkg::Options::='--force-confnew' $* "
}

cmd_shell() {
    docker inspect "${CONTAINER}" >/dev/null 2>&1 || { log "container not up; run 'dts up' first"; exit 1; }
    docker exec -it $(docker_env_flags) "${CONTAINER}" bash -l
}

cmd_clean() {
    if docker inspect "${CONTAINER}" >/dev/null 2>&1; then
        docker rm -f "${CONTAINER}" >/dev/null
        log "removed ${CONTAINER}"
    else
        log "no container ${CONTAINER} to remove"
    fi
}

cmd_status() {
    docker inspect "${CONTAINER}" >/dev/null 2>&1 || { log "container ${CONTAINER} not running"; exit 1; }
    docker ps --filter "name=${CONTAINER}" --format '{{.Names}}  {{.Image}}  {{.Status}}'
    log "mount: ${REPO_PATH} -> ${MOUNT}"
}

help_() {
    sed -n '2,20p' "$0" | sed 's/^#//'
    exit 0
}

cmd="${1:-help}"
shift || true
case "${cmd}" in
    up)     cmd_up "$@" ;;
    exec)   cmd_exec "$@" ;;
    apt)    cmd_apt "$@" ;;
    shell)  cmd_shell "$@" ;;
    clean)  cmd_clean "$@" ;;
    status) cmd_status "$@" ;;
    help|-h|--help) help_ ;;
    *)      log "unknown command: ${cmd}"; help_ ;;
esac
