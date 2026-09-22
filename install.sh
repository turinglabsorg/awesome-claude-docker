#!/usr/bin/env bash
# claude-docker-x86 — build the image and install the `claude` launcher.
# Re-run to update Claude Code to the latest release.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
IMAGE="${CLAUDE_DOCKER_IMAGE:-claude-docker-x86:latest}"
LAUNCHER="${CLAUDE_DOCKER_LAUNCHER:-/usr/local/bin/claude}"
DOCKER="$(command -v docker 2>/dev/null || echo /usr/local/bin/docker)"

"$DOCKER" info >/dev/null 2>&1 || { echo "error: Docker is not running — start Docker Desktop"; exit 1; }

latest="$("$DOCKER" run --rm --entrypoint npm node:22-slim view @anthropic-ai/claude-code version </dev/null 2>/dev/null | tail -1 || true)"
version="${CLAUDE_CODE_VERSION:-${latest:-latest}}"
current="$("$DOCKER" run --rm --entrypoint claude "$IMAGE" --version </dev/null 2>/dev/null | awk '{print $1}' || true)"
recipe="$(shasum -a 256 "$here/Dockerfile" | cut -c1-12)"
built_recipe="$("$DOCKER" image inspect -f '{{ index .Config.Labels "claude-docker-x86.dockerfile" }}' "$IMAGE" 2>/dev/null || true)"

if [ "$current" = "$version" ] && [ "$built_recipe" = "$recipe" ]; then
    echo "image already on Claude Code $current"
else
    echo "building $IMAGE with Claude Code $version (current: ${current:-none})"
    "$DOCKER" build \
        --label "claude-docker-x86.dockerfile=$recipe" \
        --build-arg "CLAUDE_CODE_VERSION=$version" \
        --build-arg "USER_UID=$(id -u)" \
        --build-arg "USER_GID=$(id -g)" \
        --build-arg "USER_NAME=$(id -un)" \
        --build-arg "USER_HOME=$(cd "$HOME" && pwd -P)" \
        -t "$IMAGE" "$here"
fi

if [ -e "$LAUNCHER" ] && ! grep -q "claude-docker-x86" "$LAUNCHER" 2>/dev/null; then
    backup="$LAUNCHER.pre-docker"
    [ -e "$backup" ] && backup="$backup.$(date +%Y%m%d%H%M%S)"
    mv "$LAUNCHER" "$backup" 2>/dev/null || sudo mv "$LAUNCHER" "$backup"
    echo "kept the previous launcher as $backup"
fi
mkdir -p "$(dirname "$LAUNCHER")"
install -m 755 "$here/bin/claude" "$LAUNCHER" 2>/dev/null || sudo install -m 755 "$here/bin/claude" "$LAUNCHER"

echo "done: $("$LAUNCHER" --version </dev/null)"
