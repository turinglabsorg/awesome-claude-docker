#!/usr/bin/env bash
# awesome-claude-docker — build the image and install the `claude` launcher.
#
# Re-run to update. The base image is rebuilt when a new Claude Code release is
# out, when its Dockerfile changes, or once it is a week old, so the browser and
# CLIs stay current. A personal layer (~/.claude-docker/Dockerfile) is rebuilt
# on every run, so it always installs the latest version of each tool.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
IMAGE="${CLAUDE_DOCKER_IMAGE:-awesome-claude-docker:latest}"
BASE_IMAGE="${IMAGE%%:*}:base"
PERSONAL="${CLAUDE_DOCKER_PERSONAL:-$HOME/.claude-docker}"
LAUNCHER="${CLAUDE_DOCKER_LAUNCHER:-/usr/local/bin/claude}"
DOCKER="$(command -v docker 2>/dev/null || echo /usr/local/bin/docker)"
MANAGED="awesome-claude-docker.managed=1"

"$DOCKER" info >/dev/null 2>&1 || { echo "error: Docker is not running — start Docker Desktop"; exit 1; }

label() { "$DOCKER" image inspect -f "{{ index .Config.Labels \"awesome-claude-docker.$2\" }}" "$1" 2>/dev/null || true; }

latest="$("$DOCKER" run --rm --entrypoint npm node:22-trixie-slim view @anthropic-ai/claude-code version </dev/null 2>/dev/null | tail -1 || true)"
version="${CLAUDE_CODE_VERSION:-${latest:-latest}}"
week="$(date +%G-W%V)"
recipe="$(shasum -a 256 "$here/Dockerfile" | cut -c1-12)"

if [ "$(label "$BASE_IMAGE" claude)" = "$version" ] \
   && [ "$(label "$BASE_IMAGE" recipe)" = "$recipe" ] \
   && [ "$(label "$BASE_IMAGE" week)" = "$week" ]; then
    echo "base image is current (Claude Code $version)"
else
    echo "building the base image (Claude Code $version)"
    "$DOCKER" build \
        --label "$MANAGED" \
        --label "awesome-claude-docker.claude=$version" \
        --label "awesome-claude-docker.recipe=$recipe" \
        --label "awesome-claude-docker.week=$week" \
        --build-arg "REFRESH=$week" \
        --build-arg "CLAUDE_CODE_VERSION=$version" \
        --build-arg "USER_UID=$(id -u)" \
        --build-arg "USER_GID=$(id -g)" \
        --build-arg "USER_NAME=$(id -un)" \
        --build-arg "USER_HOME=$(cd "$HOME" && pwd -P)" \
        -t "$BASE_IMAGE" "$here"
fi

if [ -f "$PERSONAL/Dockerfile" ]; then
    echo "building the personal layer from $PERSONAL/Dockerfile (latest tools)"
    "$DOCKER" build \
        --label "$MANAGED" \
        --build-arg "BASE=$BASE_IMAGE" \
        --build-arg "REFRESH=$(date +%s)" \
        -t "$IMAGE" "$PERSONAL"
else
    "$DOCKER" tag "$BASE_IMAGE" "$IMAGE"
fi

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
