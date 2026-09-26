# scott

> *Great Scott!* The official Claude Code, in a container that thinks it's
> home — on your real files, with your real `~/.claude` — even on a Mac that
> was already vintage when Claude was born.

Anthropic ships Claude Code for macOS as a native binary that expects AVX2.
Your 2013 Mac Pro has never heard of AVX2, and says so with `SIGILL`.

You could buy a new Mac, like a reasonable person. Or you could notice that
the **Linux** build of Claude Code doesn't need AVX2, put it in Docker, and
make it behave so much like the native install that neither you nor Claude can
tell the difference.

*Roads? Where we're going, we don't need AVX2.*

```bash
git clone https://github.com/turinglabsorg/scott
cd scott
./install.sh
cd ~/some/project && claude
```

Nothing to relearn: `claude` is still `claude`.

## It works on your files, not in some pocket dimension

- Your **home is mounted at the same absolute path and used as `HOME`**, so
  Claude finds your real `~/.claude` — CLAUDE.md, skills, settings, memory,
  sessions — plus `~/.claude.json` and whatever they point to.
- The **working directory is the folder you launched `claude` from**. Outside
  your home? That folder — or the root of its git repo — gets mounted at the
  same path too.
- **Edits land straight on your disk.** The container keeps nothing and is
  gone the moment you exit. No alternate 1985 where your files live now.
- It runs as **you** — same uid, gid and user name — so the files it creates
  are yours, and git and ssh see the same person you are.
- macOS quietly symlinks `/tmp`, `/var` and `/etc` into `/private`. The launch
  folder is reachable under both names, so paths you type still work.

Arguments, pipes and the TTY go straight through: `claude -p`, `--resume`,
`--model`, `cat file | claude -p "…"` — all as usual.

Claude Code settings in your environment come along too (`ANTHROPIC_*`,
`CLAUDE_CODE_*`, `DISABLE_*`, `BW_*`, `BITWARDENCLI_*`, `HUSH_*`, timeouts,
proxies). They pass **by name**, so no key ever shows up on a command line. A
base URL pointing at the host loopback is rewritten to `host.docker.internal`,
so wrappers that aim Claude at a local server keep working:
`ollama launch claude --model <model>` runs this launcher and reaches the
host's Ollama from inside the container.

The Bitwarden CLI keeps its data in a different place on each OS. On macOS the
launcher points the Linux one at `~/Library/Application Support/Bitwarden CLI`,
so an existing login — like an agent's own account used through a secrets
tool — works inside without logging in again.

## Some things stay in your own timeline

Your cloud identities don't get to time-travel. The Google Cloud config dirs
(`~/.config/gcloud` and any `~/.config/gcloud-*` profile roots) are covered by
an empty, read-only tmpfs, so your home is mounted *without* them.
`CLAUDE_DOCKER_MASK` hides more paths. Anything that needs those identities
stays on the host, where Biff can't reach it — and can still be called from
inside, as a [host tool](#some-tools-never-leave-1985).

## What's in the time machine

Debian 13 (glibc 2.41, so binaries built on current distros run), the official
Claude Code (installed from npm at build time, never touched), Node 22,
Python 3, git, gh, the Docker CLI with compose and buildx, ripgrep, jq, curl,
tmux, build-essential (so `npm install` can compile native modules for Linux),
and **Google Chrome** for headless browsing (Chromium on arm64, where Chrome
doesn't exist).

## Your own flux capacitor: `~/.claude-docker/`

| File | What it's for |
|---|---|
| `~/.claude-docker/Dockerfile` | your extra tools, built into the same image |
| `~/.claude-docker/env` | launcher settings, read on every run |

Start from [`examples/Dockerfile.personal`](examples/Dockerfile.personal) and
[`examples/env`](examples/env). Keep the directory in your dotfiles: on a new
machine, clone this repo, drop the directory back in, run `./install.sh`, and
your whole setup is back — no plutonium required.

Put **tools only** in there. Never copy credentials or config into the image:
they stay in your home, which is mounted at runtime.

## Staying in the present

Run `./install.sh` again to update. It always builds **one complete image**:
the base `Dockerfile` with your tool layer appended as a second stage.

- With a tool layer, the image is rebuilt on every run, so each of your tools
  is at its latest release. The base steps come from the build cache and are
  refreshed when a new Claude Code is out, when the `Dockerfile` changes, or
  once a week.
- Without one, it rebuilds only in those three cases.
- Images the installer built and has just replaced get removed — only those;
  it goes by its own label and leaves your other images alone.

Nothing ever updates *inside* the container: it's gone as soon as you exit.

The first time, run `/login`. The Linux build keeps its login in
`~/.claude/.credentials.json` (the macOS one uses the Keychain).

## Headless Chrome and the chrome-devtools MCP

There's no display in the container, and Docker's default seccomp profile won't
let Chrome build its sandbox as a non-root user. So Chrome runs headless with
`--no-sandbox`, and the container itself is the sandbox. The launcher gives it
the 1 GB of `/dev/shm` Chrome needs to not fall over.

```bash
claude mcp add chrome-devtools --scope user -- \
  npx -y chrome-devtools-mcp@latest --headless --isolated --chrome-arg=--no-sandbox
```

For Playwright or Puppeteer, use the installed Chrome (`channel: "chrome"`, or
`executablePath: "/usr/bin/google-chrome"`) with the same `--no-sandbox`.

## Some tools never leave 1985

A container that forgets everything on exit is the wrong place for tools with
a memory: the one secrets vault every agent reads and writes, the cloud CLIs
whose identities must never enter the container, the CLIs whose login lives in
the macOS Keychain. Give every Claude — and every subagent, in every session —
the host's own copy instead. List them in `~/.claude-docker/env` and re-run
`./install.sh`:

```bash
CLAUDE_DOCKER_HOST_TOOLS="gh hush devo"
```

Each name becomes a stub in the image. Run `gh` inside and the host's `gh`
runs: on the host, in the same folder, with the environment `claude` was
started with, and with the host's config and credentials. Arguments, stdin,
stdout, stderr and the exit code make the round trip, and a Ctrl+C or a
timeout inside stops the host process too. Variables named after the tool
(`GH_*` for `gh`) travel along; nothing else from inside does.

Sometimes a subcommand has to stay in the present: `grog up 4000` shares a
dev server that listens *inside* the container, so it must run in here, not on
the host. Name such subcommands in `CLAUDE_DOCKER_IN_CONTAINER` and the image's
own copy of the tool runs them, while every other subcommand still goes home:

```bash
CLAUDE_DOCKER_IN_CONTAINER="grog:up"
```

The fine print, before you blame the flux capacitor:

- A host tool runs with **your full rights on the host**, so list only what
  you'd let an agent run natively. A tool that runs other commands (`hush run`,
  `codex exec`) runs them on the host as well.
- Paths under your home and the launch folder are the same on both sides; the
  container's own `/tmp` doesn't exist out there.
- macOS only, for now.

## Pasting images across the space-time continuum

**Ctrl+V** pastes an image, as in the native Claude Code. The Linux build reads
the clipboard through `xclip`, and a container can see the Mac clipboard about
as well as Marty could phone 1955. So the `xclip` in the image asks the host
bridge (below) for the clipboard **image** — never its text: your copied
passwords stay in this century. Interactive sessions only;
`CLAUDE_DOCKER_CLIPBOARD=0` turns it off.

Your screenshots make the jump without 1.21 gigawatts. Dragging an image file
into the terminal works too, as long as the file is somewhere the container
can see (your home, or the launch folder).

## The bridge home

Both of the above ride on one small process the launcher starts on the host
for each session. It listens on `127.0.0.1` only, answers only requests that
carry a random per-session token, runs nothing but the tools you listed, and
is gone when the session ends. It needs nothing beyond `perl` and `osascript`,
which ship with macOS.

## Docker, from inside Docker

Set `CLAUDE_DOCKER_SOCKET=1` (e.g. in `~/.claude-docker/env`) and the container
gets the host Docker socket, so Claude can run `docker` and `docker compose`.
That's the keys to the whole Docker engine, so it's off by default.

Inside, the Docker CLI uses its own config dir: your `~/.docker/config.json`
(registries, credential helpers) is linked in, but the plugins come from the
image, because the ones in your `~/.docker/cli-plugins` were built for the host
OS. `DOCKER_HOST` points at the mounted socket and overrides the host's
context. Registries whose credential helper needs a masked identity stay out of
reach — on purpose.

## Options

| Variable | Default | What it does |
|---|---|---|
| `CLAUDE_DOCKER_SOCKET` | `0` | `1` mounts the host Docker socket |
| `CLAUDE_DOCKER_HOST_TOOLS` | — | commands that run on the host instead of in the container, space-separated (macOS; re-run `install.sh` after changing it) |
| `CLAUDE_DOCKER_IN_CONTAINER` | — | `tool:subcommand` pairs of host tools that run in the container instead (e.g. `grog:up`), space-separated |
| `CLAUDE_DOCKER_CLIPBOARD` | `1` | `0` skips the clipboard bridge that lets Ctrl+V paste images (macOS) |
| `CLAUDE_DOCKER_MOUNTS` | — | extra host paths to mount at the same path, space-separated |
| `CLAUDE_DOCKER_ENV` | — | extra environment variable names to pass through, space-separated |
| `CLAUDE_DOCKER_MASK` | — | extra paths to hide from the container (relative to your home, or absolute), space-separated |
| `CLAUDE_DOCKER_ENTRYPOINT` | — | run something else in the same environment, e.g. `CLAUDE_DOCKER_ENTRYPOINT=bash claude` |
| `CLAUDE_DOCKER_PERSONAL` | `~/.claude-docker` | where the tool layer and `env` live |
| `CLAUDE_DOCKER_IMAGE` | `scott:latest` | image tag |
| `CLAUDE_DOCKER_LAUNCHER` (install.sh) | `/usr/local/bin/claude` | where the launcher goes; a previous one is kept as `claude.pre-docker` |
| `CLAUDE_CODE_VERSION` (install.sh) | latest | pin a Claude Code version, if you enjoy living in the past |

## Why would anyone do this

- **Intel Macs without AVX2** — Ivy Bridge and older: Mac Pro 2013, 2012 iMacs
  and MacBook Pros. The macOS build dies with `SIGILL`; the Linux build runs in
  Docker on the very same CPU. Verified on a Mac Pro 2013 (Xeon E5-1620 v2),
  macOS 12.7.6, Docker 28.1.1, Claude Code 2.1.280, Google Chrome 154.
- **A setup that travels**: the same tools and versions on every machine, from
  this repo plus your `~/.claude-docker/`.
- **A clean host**: the toolchain Claude uses lives in the image, not all over
  your system.

## Paradoxes

Time travel has rules. So does this.

- Commands Claude runs execute in **Linux**. macOS-only things — `brew`, `open`,
  `pbcopy`, the Keychain, Xcode — and the macOS binaries in your home don't
  work inside. Add Linux builds of what you need to your tool layer, or run
  the host's copy as a [host tool](#some-tools-never-leave-1985).
- `node_modules` with native addons built on macOS won't load inside, and vice
  versa. Two timelines, two sets of binaries.
- Hooks, MCP servers and plugins from your config run inside the container
  too; the ones that call macOS binaries fail there.
- A `UseKeychain` line in `~/.ssh/config` is macOS-only; OpenSSH on Linux
  rejects it unless `IgnoreUnknown UseKeychain` comes first.
- Docker Desktop has to share the paths you work in (`/Users`, `/Volumes`,
  `/private`, `/tmp` by default).

## License

MIT. No flux capacitors were harmed.
