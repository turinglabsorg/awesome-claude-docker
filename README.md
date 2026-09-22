# awesome-claude-docker

Claude Code in Docker that behaves like the native install — same folder, same
files, same `~/.claude` — plus **your own tool layer**, so your whole setup is
a couple of files you can rebuild on any machine.

```bash
git clone https://github.com/turinglabsorg/awesome-claude-docker
cd awesome-claude-docker
./install.sh
cd ~/some/project && claude
```

## It works on your filesystem, not in the container

- Your **home is bind-mounted at the same absolute path and used as `HOME`**,
  so Claude sees your real `~/.claude` (CLAUDE.md, skills, settings, memory,
  sessions), `~/.claude.json` and whatever they reference.
- The **working directory is the folder you launched `claude` from**. If it is
  outside your home, that folder — or the root of its git repo — is mounted at
  the same path too.
- **Edits land directly on the host filesystem.** The container keeps no state
  of its own and is removed on exit.
- It runs with **your uid/gid and a matching user**, so files it creates are
  owned by you and git/ssh see the same user as on the host.
- macOS symlinks `/tmp`, `/var` and `/etc` into `/private`; the launch folder
  is reachable under both forms, so paths you pass as arguments work.
- **Cloud identity roots never reach the container.** The Google Cloud config
  dirs (`~/.config/gcloud` and any `~/.config/gcloud-*` profile roots) are
  covered by an empty read-only tmpfs, so the home is mounted without them;
  `CLAUDE_DOCKER_MASK` adds more paths. Work that needs those identities stays
  on the host.

Arguments, pipes and the TTY pass straight through: `claude -p`, `--resume`,
`--model`, `cat file | claude -p "…"` all work as usual.

Claude Code settings in your environment pass through too (`ANTHROPIC_*`,
`CLAUDE_CODE_*`, `DISABLE_*`, timeouts, proxies) — by name, so keys never end
up on a command line. A base URL on the host loopback is rewritten to
`host.docker.internal`, so wrappers that point Claude at a local server keep
working: `ollama launch claude --model <model>` runs this launcher and reaches
the host's Ollama from inside the container.

## What is in the base image

Debian 13 (glibc 2.41, so binaries built on current distros run), official
Claude Code (installed from npm at build time, never modified), Node 22,
Python 3, git, gh, the Docker CLI with compose and buildx, ripgrep, jq,
curl, tmux, build-essential (so `npm install` can compile native modules for
Linux), and **Google Chrome** for headless browsing (Chromium on arm64).

## Your tool layer: `~/.claude-docker/`

| File | Purpose |
|---|---|
| `~/.claude-docker/Dockerfile` | extra tools, built on top of the base image |
| `~/.claude-docker/env` | launcher settings, sourced on every run |

Start from [`examples/Dockerfile.personal`](examples/Dockerfile.personal) and
[`examples/env`](examples/env). Keep the directory in your dotfiles: on a new
machine, clone this repo, put the directory back and run `./install.sh`.

Install **tools only** in it. Never copy credentials or config into the image:
they stay in your home, which is mounted at runtime.

## Staying current

Re-run `./install.sh` to update:

- the base image is rebuilt when a new Claude Code release is out, when its
  `Dockerfile` changes, or once it is a week old (browser and CLIs refresh);
- the personal layer is rebuilt on every run, so it installs the latest
  version of each tool;
- images the installer built and has just superseded are removed (only those:
  it filters on its own label).

Updates never happen inside the container: it is thrown away on exit.

The first time, run `/login`. The Linux build keeps its login in
`~/.claude/.credentials.json` (the macOS build uses the Keychain).

## Headless Chrome and the chrome-devtools MCP

There is no display in the container, and Docker's default seccomp profile
blocks Chrome's sandbox for a non-root user, so Chrome runs headless with
`--no-sandbox` (the container is the isolation boundary). The launcher gives
the container a 1 GB `/dev/shm`, which Chrome needs.

```bash
claude mcp add chrome-devtools --scope user -- \
  npx -y chrome-devtools-mcp@latest --headless --isolated --chrome-arg=--no-sandbox
```

For Playwright or Puppeteer, use the installed Chrome (`channel: "chrome"`, or
`executablePath: "/usr/bin/google-chrome"`) with the same `--no-sandbox` flag.

## Docker inside

Set `CLAUDE_DOCKER_SOCKET=1` (e.g. in `~/.claude-docker/env`) to give the
container the host Docker socket, so Claude can run `docker` and
`docker compose`. This hands the container full control of your Docker engine,
so it is off by default.

The Docker CLI inside uses its own config dir: your `~/.docker/config.json`
(registries, credential helpers) is linked in, while plugins come from the
image — the ones in your `~/.docker/cli-plugins` are built for the host OS.
`DOCKER_HOST` points at the mounted socket, overriding the host's context.
Registries whose credential helper needs a masked identity root cannot be
reached from inside.

## Options

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_DOCKER_SOCKET` | `0` | `1` mounts the host Docker socket |
| `CLAUDE_DOCKER_MOUNTS` | — | extra host paths to mount at the same path, space-separated |
| `CLAUDE_DOCKER_ENV` | — | extra environment variable names to pass through, space-separated |
| `CLAUDE_DOCKER_MASK` | — | extra paths to hide from the container (relative to the home, or absolute), space-separated |
| `CLAUDE_DOCKER_ENTRYPOINT` | — | run something else in the same environment, e.g. `CLAUDE_DOCKER_ENTRYPOINT=bash claude` |
| `CLAUDE_DOCKER_PERSONAL` | `~/.claude-docker` | where the tool layer and `env` live |
| `CLAUDE_DOCKER_IMAGE` | `awesome-claude-docker:latest` | image tag |
| `CLAUDE_DOCKER_LAUNCHER` (install.sh) | `/usr/local/bin/claude` | where the launcher is installed; a previous one is kept as `claude.pre-docker` |
| `CLAUDE_CODE_VERSION` (install.sh) | latest | pin a Claude Code version |

## Use cases

- **Intel Macs without AVX2** (Ivy Bridge and older: Mac Pro 2013, 2012 iMacs
  and MacBook Pros). The macOS x64 build of Claude Code needs AVX2 and dies
  with `SIGILL`; the Linux x64 build does not, and in Docker it runs on the
  same CPU. Verified on a Mac Pro 2013 (Xeon E5-1620 v2), macOS 12.7.6,
  Docker 28.1.1, Claude Code 2.1.280, Google Chrome 154.
- **A portable, reproducible setup**: the same tools and versions on every
  machine, from one repo plus your `~/.claude-docker/`.
- **A clean host**: the toolchain Claude uses lives in the image, not in your
  system.

## Limitations

- Commands Claude runs execute in **Linux**: macOS-only tools (`brew`, `open`,
  `pbcopy`, the Keychain, Xcode) and macOS binaries in your home do not work
  inside. Add Linux builds of what you need to your tool layer.
- `node_modules` with native addons built on macOS do not load inside, and vice
  versa.
- Hooks, MCP servers and plugins from your config run inside the container
  too; the ones that call macOS binaries fail there.
- A `UseKeychain` line in `~/.ssh/config` is macOS-only; OpenSSH on Linux
  rejects it unless `IgnoreUnknown UseKeychain` comes before it.
- Docker Desktop must share the paths you work in (`/Users`, `/Volumes`,
  `/private`, `/tmp` by default).

## License

MIT
