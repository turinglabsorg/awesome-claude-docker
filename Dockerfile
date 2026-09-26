# Debian 13 (glibc 2.41): recent enough for binaries built on current distros
FROM node:22-trixie-slim AS base

# install.sh passes the current ISO week, so these layers — browser and CLIs
# included — are rebuilt with current versions at least once a week.
ARG BASE_REFRESH

# Base toolset for a coding agent, plus the official apt repositories of the
# GitHub CLI and the Docker CLI.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git ripgrep jq curl wget unzip ca-certificates gnupg openssh-client \
      python3 python3-pip python3-venv build-essential less procps tmux \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/github-cli.gpg \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && arch="$(dpkg --print-architecture)" \
 && codename="$(. /etc/os-release && echo "$VERSION_CODENAME")" \
 && echo "deb [arch=$arch signed-by=/etc/apt/keyrings/github-cli.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $codename stable" > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh docker-ce-cli docker-compose-plugin docker-buildx-plugin \
 && rm -rf /var/lib/apt/lists/*

ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
 && claude --version

# Headless browser for chrome-devtools-mcp, Playwright and Puppeteer: Google
# Chrome on amd64 (it has no arm64 build), Chromium elsewhere, exposed as
# google-chrome either way. Installed after Claude Code so each Claude update
# also brings a current browser.
RUN if [ "$(dpkg --print-architecture)" = amd64 ]; then \
      curl -fsSL -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
      && apt-get update \
      && apt-get install -y --no-install-recommends /tmp/chrome.deb fonts-liberation \
      && rm -f /tmp/chrome.deb; \
    else \
      apt-get update \
      && apt-get install -y --no-install-recommends chromium fonts-liberation \
      && ln -sf /usr/bin/chromium /usr/bin/google-chrome; \
    fi \
 && rm -rf /var/lib/apt/lists/* \
 && google-chrome --version

# Mirror the host user (same uid, gid, name and home path): the host home is
# bind-mounted at the same path and used as HOME, and tools that look the user
# up (git, ssh, os.userInfo) need a matching passwd entry.
ARG USER_UID=1000
ARG USER_GID=1000
ARG USER_NAME=claude
ARG USER_HOME=/home/claude
RUN (getent group "${USER_GID}" >/dev/null || groupadd -g "${USER_GID}" "${USER_NAME}") \
 && useradd -o -u "${USER_UID}" -g "${USER_GID}" -M -d "${USER_HOME}" -s /bin/bash "${USER_NAME}"

# The host ~/.docker holds plugins and contexts built for the host OS (on macOS
# they are Mach-O binaries or links into Docker.app), and the CLI would pick
# them over the image's. Give the CLI its own config dir: the host config.json
# (registries, credential helpers) through a link, Linux plugins from here.
RUN mkdir -p /etc/scott/docker \
 && ln -s /usr/libexec/docker/cli-plugins /etc/scott/docker/cli-plugins \
 && ln -s "${USER_HOME}/.docker/config.json" /etc/scott/docker/config.json
ENV DOCKER_CONFIG=/etc/scott/docker

# Claude Code on Linux pastes images through xclip. This one only reads the
# clipboard image, from the bridge the launcher starts on the Mac host
# (SCOTT_BRIDGE); anything else fails as if xclip were not installed.
COPY --chmod=755 <<'EOF' /usr/local/bin/xclip
#!/bin/sh
read=0 target=
while [ $# -gt 0 ]; do
    case "$1" in
        -o|-out) read=1 ;;
        -t|-target) shift; target="${1:-}" ;;
    esac
    shift
done
if [ -n "${SCOTT_BRIDGE:-}" ] && [ "$read" = 1 ]; then
    case "$target" in
        TARGETS) exec curl -fsS --max-time 15 "http://$SCOTT_BRIDGE/targets" ;;
        image/png) exec curl -fsS --max-time 15 "http://$SCOTT_BRIDGE/png" ;;
    esac
fi
echo "xclip (scott): only reading the clipboard image is supported" >&2
exit 1
EOF

# Host tools: install.sh links each name in CLAUDE_DOCKER_HOST_TOOLS to this
# client, which runs the host's copy through the launcher's bridge.
COPY --chmod=755 <<'EOF' /usr/local/bin/scott-host
#!/usr/bin/env python3
"""Run a host tool from inside the container.

Hands the arguments, the working directory and the tool's own environment
variables (those named after it, e.g. GH_* for gh) to the launcher's host
bridge, streams stdin to it and the tool's stdout and stderr back, and exits
with the tool's exit code. Invoked through a link named after the tool, or as
`scott-host <tool> [args...]`.
"""
import json
import os
import socket
import struct
import sys
import threading


def send(sock, kind, data=b""):
    sock.sendall(kind + struct.pack(">I", len(data)) + data)


def receive(sock, size):
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            return None
        data += chunk
    return data


def forward_stdin(sock):
    try:
        if not os.isatty(0):
            while True:
                chunk = os.read(0, 65536)
                if not chunk:
                    break
                send(sock, b"I", chunk)
        send(sock, b"I")
    except OSError:
        pass


IN_CONTAINER = "/usr/local/lib/scott/in-container"


def main():
    tool, args = os.path.basename(sys.argv[0]), sys.argv[1:]
    if tool == "scott-host":
        if not args:
            sys.stderr.write("usage: scott-host <tool> [args...]\n")
            return 2
        tool, args = args[0], args[1:]
    # Subcommands that need this container (say `grog:up`, which shares a port
    # listening here) run the image's own copy instead of the host's.
    local = os.path.join(IN_CONTAINER, tool)
    wanted = os.environ.get("CLAUDE_DOCKER_IN_CONTAINER", "").split()
    if args and "%s:%s" % (tool, args[0]) in wanted and os.access(local, os.X_OK):
        os.execv(local, [tool] + args)
    address, _, token = os.environ.get("SCOTT_BRIDGE", "").rpartition("/")
    host, _, port = address.rpartition(":")
    if not (token and host and port.isdigit()):
        sys.stderr.write("scott: %s runs on the host, and this container has no host bridge\n" % tool)
        return 127
    try:
        sock = socket.create_connection((host, int(port)), timeout=10)
    except OSError as error:
        sys.stderr.write("scott: cannot reach the host bridge for %s: %s\n" % (tool, error))
        return 127
    sock.settimeout(None)
    prefix = "".join(c if c.isalnum() else "_" for c in tool.upper()) + "_"
    env = {k: v for k, v in os.environ.items() if k.startswith(prefix)}
    send(sock, b"R", json.dumps({"token": token, "tool": tool, "args": args,
                                 "cwd": os.getcwd(), "env": env}).encode())
    threading.Thread(target=forward_stdin, args=(sock,), daemon=True).start()
    streams = {b"O": sys.stdout.buffer, b"E": sys.stderr.buffer}
    while True:
        head = receive(sock, 5)
        data = receive(sock, struct.unpack(">I", head[1:])[0]) if head else None
        if data is None:
            sys.stderr.write("scott: the host bridge closed the connection during %s\n" % tool)
            return 255
        if head[:1] == b"X":
            return struct.unpack(">I", data)[0]
        stream = streams.get(head[:1])
        if stream:
            try:
                stream.write(data)
                stream.flush()
            except BrokenPipeError:
                return 141


if __name__ == "__main__":
    code = main()
    try:
        sys.stdout.flush()
    except OSError:
        pass
    os._exit(code & 255)
EOF

ENV LANG=C.UTF-8
# The container is removed on every exit, so an in-place update would be lost;
# updates happen by rebuilding the image (re-run install.sh).
ENV DISABLE_AUTOUPDATER=1

ENTRYPOINT ["claude"]
