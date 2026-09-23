#!/usr/bin/env bash
# awesome-claude-docker — build the image and install the `claude` launcher.
#
# Re-run to update. It always produces ONE complete image: the base Dockerfile
# plus, if present, your tool layer (~/.claude-docker/Dockerfile) appended to it
# as a second stage. With a tool layer the image is rebuilt on every run, so each
# tool is at its latest release (the base steps come from the build cache);
# without one it is rebuilt on a new Claude Code release, a Dockerfile change,
# or once a week.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
IMAGE="${CLAUDE_DOCKER_IMAGE:-awesome-claude-docker:latest}"
PERSONAL="${CLAUDE_DOCKER_PERSONAL:-$HOME/.claude-docker}"
LAUNCHER="${CLAUDE_DOCKER_LAUNCHER:-/usr/local/bin/claude}"
DOCKER="$(command -v docker 2>/dev/null || echo /usr/local/bin/docker)"
MANAGED="awesome-claude-docker.managed=1"

"$DOCKER" info >/dev/null 2>&1 || { echo "error: Docker is not running — start Docker Desktop"; exit 1; }

label() { "$DOCKER" image inspect -f "{{ index .Config.Labels \"awesome-claude-docker.$1\" }}" "$IMAGE" 2>/dev/null || true; }

latest="$("$DOCKER" run --rm --entrypoint npm node:22-trixie-slim view @anthropic-ai/claude-code version </dev/null 2>/dev/null | tail -1 || true)"
version="${CLAUDE_CODE_VERSION:-${latest:-latest}}"
week="$(date +%G-W%V)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if [ -f "$PERSONAL/Dockerfile" ]; then
    {
        echo "# syntax=docker/dockerfile:1"
        grep -v '^# syntax=' "$here/Dockerfile"
        echo
        echo "# ---- tool layer: $PERSONAL/Dockerfile"
        echo "FROM base"
        grep -vE '^# syntax=|^ARG BASE[[:space:]]*$|^FROM \$\{?BASE\}?[[:space:]]*$' "$PERSONAL/Dockerfile"
    } > "$work/Dockerfile"
    context="$PERSONAL"
    refresh="$(date +%s)"
else
    cp "$here/Dockerfile" "$work/Dockerfile"
    context="$here"
    refresh="$week"
fi
recipe="$(shasum -a 256 "$work/Dockerfile" | cut -c1-12)"

if [ ! -f "$PERSONAL/Dockerfile" ] \
   && [ "$(label claude)" = "$version" ] \
   && [ "$(label recipe)" = "$recipe" ] \
   && [ "$(label week)" = "$week" ]; then
    echo "image is current (Claude Code $version)"
else
    echo "building $IMAGE (Claude Code $version$([ -f "$PERSONAL/Dockerfile" ] && echo ", tool layer from $PERSONAL"))"
    "$DOCKER" build -f "$work/Dockerfile" \
        --label "$MANAGED" \
        --label "awesome-claude-docker.claude=$version" \
        --label "awesome-claude-docker.recipe=$recipe" \
        --label "awesome-claude-docker.week=$week" \
        --build-arg "BASE_REFRESH=$week" \
        --build-arg "REFRESH=$refresh" \
        --build-arg "CLAUDE_CODE_VERSION=$version" \
        --build-arg "USER_UID=$(id -u)" \
        --build-arg "USER_GID=$(id -g)" \
        --build-arg "USER_NAME=$(id -un)" \
        --build-arg "USER_HOME=$(cd "$HOME" && pwd -P)" \
        -t "$IMAGE" "$context"
fi

# Earlier versions kept a separate :base tag; one complete image is enough.
"$DOCKER" rmi "${IMAGE%%:*}:base" >/dev/null 2>&1 || true

# Remove only the images this installer built and has just superseded.
"$DOCKER" image prune -f --filter "label=$MANAGED" >/dev/null

if [ -e "$LAUNCHER" ] && ! grep -qE "awesome-claude-docker|claude-docker-x86" "$LAUNCHER" 2>/dev/null; then
    backup="$LAUNCHER.pre-docker"
    [ -e "$backup" ] && backup="$backup.$(date +%Y%m%d%H%M%S)"
    mv "$LAUNCHER" "$backup" 2>/dev/null || sudo mv "$LAUNCHER" "$backup"
    echo "kept the previous launcher as $backup"
fi
mkdir -p "$(dirname "$LAUNCHER")"
install -m 755 "$here/bin/claude" "$LAUNCHER" 2>/dev/null || sudo install -m 755 "$here/bin/claude" "$LAUNCHER"

echo "done: $("$LAUNCHER" --version </dev/null)"
