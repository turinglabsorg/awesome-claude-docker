FROM node:22-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git ripgrep jq curl ca-certificates openssh-client python3 less procps \
 && rm -rf /var/lib/apt/lists/*

ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
 && claude --version

# Google Chrome for headless browsing (chrome-devtools-mcp, Playwright,
# Puppeteer). Installed after Claude Code so each Claude update also brings a
# current Chrome.
RUN curl -fsSL -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
 && apt-get update \
 && apt-get install -y --no-install-recommends /tmp/chrome.deb fonts-liberation \
 && rm -rf /tmp/chrome.deb /var/lib/apt/lists/* \
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

ENV LANG=C.UTF-8
# The container is removed on every exit, so an in-place update would be lost;
# updates happen by rebuilding the image (re-run install.sh).
ENV DISABLE_AUTOUPDATER=1

ENTRYPOINT ["claude"]
