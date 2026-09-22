# claude-docker-x86

Run the **latest official Claude Code** on Intel Macs without AVX2 — Ivy Bridge
and older: Mac Pro 2013, 2012 iMacs and MacBook Pros, older Xeons — working
directly on your files and with your own Claude context.

## Why

- The macOS x64 build of Claude Code needs AVX2 and dies on pre-Haswell CPUs
  with `SIGILL` (exit code 132).
- The **Linux x64 build runs on CPUs without AVX2**.
- Running the JavaScript extracted from the macOS binary on upstream Bun
  ([claude-cli-x86-fix](https://github.com/turinglabsorg/claude-cli-x86-fix))
  is no longer enough from 2.1.280: the interactive UI now depends on APIs that
  exist only in the Bun build shipped inside Claude Code's own binary.
- So this runs the official, unmodified Linux build in Docker — which on an
  Intel Mac executes on the same CPU.

Verified on a Mac Pro 2013 (Xeon E5-1620 v2: AVX, no AVX2/FMA/BMI2), macOS
12.7.6, Docker 28.1.1, Claude Code 2.1.280: `--version`, interactive UI, file
writes and git from inside and outside the home.

## It works on your filesystem, not in the container

- Your **home is bind-mounted at the same absolute path and used as `HOME`**,
  so Claude sees your real `~/.claude` (CLAUDE.md, skills, settings, memory,
  sessions), `~/.claude.json`, `~/.agents` and whatever they reference.
- The **working directory is the folder you launched `claude` from**. If it is
  outside your home, that folder — or the root of its git repo — is mounted at
  the same path too.
- **Edits land directly on the host filesystem.** The container keeps no state
  of its own and is removed on exit.
- It runs with **your uid/gid and a matching user**, so files it creates are
  owned by you and git/ssh see the same user as on the host.

## Install / update

Requires Docker Desktop running.

```bash
git clone https://github.com/turinglabsorg/claude-docker-x86
cd claude-docker-x86
./install.sh
```

Then `claude` works as usual, from any folder. The first time, run `/login`.
Re-run `./install.sh` to update: it rebuilds the image only when a new release
is out. A previous `claude` launcher, if any, is kept as `claude.pre-docker`.

The Linux build keeps its login in `~/.claude/.credentials.json` (the macOS
build uses the Keychain), so that file exists in your home after `/login`.

## Options

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_DOCKER_MOUNTS` | — | extra host paths to mount at the same path, space-separated |
| `CLAUDE_DOCKER_ENTRYPOINT` | — | run something else in the same environment, e.g. `CLAUDE_DOCKER_ENTRYPOINT=bash claude` |
| `CLAUDE_DOCKER_IMAGE` | `claude-docker-x86:latest` | image tag |
| `CLAUDE_DOCKER_LAUNCHER` (install.sh) | `/usr/local/bin/claude` | where the launcher is installed |
| `CLAUDE_CODE_VERSION` (install.sh) | latest | pin a Claude Code version |

## Limitations

- Commands Claude runs execute in **Linux**: macOS-only tools (`brew`, `open`,
  `pbcopy`, the Keychain, Xcode) and macOS binaries in your home do not work
  inside. The image ships git, ripgrep, jq, curl, python3, Node 22 and an SSH
  client; extend the `Dockerfile` for more.
- `node_modules` with native addons built on macOS do not load inside, and vice
  versa.
- Hooks, MCP servers and plugins from your config run inside the container
  too; the ones that call macOS binaries fail there.
- A `UseKeychain` line in `~/.ssh/config` is macOS-only; OpenSSH on Linux
  rejects it unless `IgnoreUnknown UseKeychain` comes before it.
- Docker Desktop must share the paths you work in (`/Users`, `/Volumes`,
  `/private`, `/tmp` by default).
- Each rebuild leaves the previous image dangling; `docker image prune`
  reclaims the space.

On Linux you do not need any of this: install Claude Code normally, the Linux
build runs natively on CPUs without AVX2.

## License

MIT
