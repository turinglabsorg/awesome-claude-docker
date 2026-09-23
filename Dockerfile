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
RUN mkdir -p /etc/awesome-claude-docker/docker \
 && ln -s /usr/libexec/docker/cli-plugins /etc/awesome-claude-docker/docker/cli-plugins \
 && ln -s "${USER_HOME}/.docker/config.json" /etc/awesome-claude-docker/docker/config.json
ENV DOCKER_CONFIG=/etc/awesome-claude-docker/docker

ENV LANG=C.UTF-8
# The container is removed on every exit, so an in-place update would be lost;
# updates happen by rebuilding the image (re-run install.sh).
ENV DISABLE_AUTOUPDATER=1

ENTRYPOINT ["claude"]
