#!/usr/bin/env bash
# scott — build the image and install the `claude` launcher.
#
# Re-run to update. It always produces ONE complete image: the base Dockerfile
# plus, if present, your tool layer (~/.claude-docker/Dockerfile) appended to it
# as a second stage. With a tool layer the image is rebuilt on every run, so each
# tool is at its latest release (the base steps come from the build cache);
# without one it is rebuilt on a new Claude Code release, a Dockerfile change,
# or once a week.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
PERSONAL="${CLAUDE_DOCKER_PERSONAL:-$HOME/.claude-docker}"
# The launcher's settings, for the ones the image depends on (the host tools)
# shellcheck disable=SC1091
[ -f "$PERSONAL/env" ] && . "$PERSONAL/env"
IMAGE="${CLAUDE_DOCKER_IMAGE:-scott:latest}"
LAUNCHER="${CLAUDE_DOCKER_LAUNCHER:-/usr/local/bin/claude}"
DOCKER="$(command -v docker 2>/dev/null || echo /usr/local/bin/docker)"
MANAGED="scott.managed=1"

"$DOCKER" info >/dev/null 2>&1 || { echo "error: Docker is not running — start Docker Desktop"; exit 1; }

label() { "$DOCKER" image inspect -f "{{ index .Config.Labels \"scott.$1\" }}" "$IMAGE" 2>/dev/null || true; }

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
# Host tools: each name in CLAUDE_DOCKER_HOST_TOOLS becomes a link to the
# image's scott-host, which runs the host's copy through the launcher's bridge.
# Added last, so it replaces any copy of the same name installed above.
read -r -a tools <<< "${CLAUDE_DOCKER_HOST_TOOLS:-}"
for tool in ${tools[@]+"${tools[@]}"}; do
    if ! [[ "$tool" =~ ^[A-Za-z0-9._-]+$ ]] || [ "$tool" = scott-host ]; then
        echo "error: not a usable command name in CLAUDE_DOCKER_HOST_TOOLS: $tool"
        exit 1
    fi
done
host_tools="${tools[*]+"${tools[*]}"}"
if [ -n "$host_tools" ]; then
    {
        echo
        echo "# ---- host tools (CLAUDE_DOCKER_HOST_TOOLS)"
        echo "RUN for tool in $host_tools; do ln -sf scott-host \"/usr/local/bin/\$tool\"; done"
    } >> "$work/Dockerfile"
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
        --label "scott.claude=$version" \
        --label "scott.recipe=$recipe" \
        --label "scott.week=$week" \
        --build-arg "BASE_REFRESH=$week" \
        --build-arg "REFRESH=$refresh" \
        --build-arg "CLAUDE_CODE_VERSION=$version" \
        --build-arg "USER_UID=$(id -u)" \
        --build-arg "USER_GID=$(id -g)" \
        --build-arg "USER_NAME=$(id -un)" \
        --build-arg "USER_HOME=$(cd "$HOME" && pwd -P)" \
        -t "$IMAGE" "$context"
fi

# One complete image is enough: drop the separate :base tag earlier versions
# kept, and the images this project built under its previous names.
for old in "${IMAGE%%:*}:base" great-scott:latest awesome-claude-docker:latest awesome-claude-docker:base claude-docker-x86:latest; do
    [ "$old" = "$IMAGE" ] || "$DOCKER" rmi "$old" >/dev/null 2>&1 || true
done

# Remove only the images this installer built and has just superseded.
"$DOCKER" image prune -f --filter "label=$MANAGED" >/dev/null

if [ -e "$LAUNCHER" ] && ! grep -qE "turinglabsorg/(scott|great-scott|awesome-claude-docker|claude-docker-x86)" "$LAUNCHER" 2>/dev/null; then
    backup="$LAUNCHER.pre-docker"
    [ -e "$backup" ] && backup="$backup.$(date +%Y%m%d%H%M%S)"
    mv "$LAUNCHER" "$backup" 2>/dev/null || sudo mv "$LAUNCHER" "$backup"
    echo "kept the previous launcher as $backup"
fi
mkdir -p "$(dirname "$LAUNCHER")"
install -m 755 "$here/bin/claude" "$LAUNCHER" 2>/dev/null || sudo install -m 755 "$here/bin/claude" "$LAUNCHER"

echo "done: $("$LAUNCHER" --version </dev/null)"
