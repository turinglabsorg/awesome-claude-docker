# Agent instructions — scott

- Scope: a Docker image plus a launcher that run the official Claude Code as if
  it were native, with an optional personal tool layer in `~/.claude-docker/`.
  Claude Code is installed from npm at image build time, never patched or
  redistributed.
- Invariants of `bin/claude` — do not break them:
  - the host home is mounted at the same path and used as `HOME`
  - cloud identity roots never reach the container: the Google Cloud config
    dirs (`~/.config/gcloud`, `~/.config/gcloud-*`) and every path in
    `CLAUDE_DOCKER_MASK` are covered by an empty read-only tmpfs
  - the working directory is the host folder the launcher was started from;
    folders outside the home are mounted at the same path (git root if any)
  - the container is ephemeral (`--rm`) and runs as the host uid/gid
  - the Docker socket is mounted only when `CLAUDE_DOCKER_SOCKET=1`
  - environment variables pass through by name only (`-e NAME`), never with
    their values on the command line
  - the clipboard bridge (macOS, interactive sessions only) listens on
    `127.0.0.1`, requires the per-session token, serves the clipboard image
    and never text, and exits when the session ends
- Images: never copy credentials or config into an image, and never add a tool
  whose use needs a masked identity root. `install.sh` prunes only dangling
  images carrying the `scott.managed=1` label.
- Before pushing, test on a machine with Docker running:
  1. `CLAUDE_DOCKER_LAUNCHER=<tmp>/claude ./install.sh`, with and without a
     personal layer
  2. `<tmp>/claude --version` without a TTY
  3. `CLAUDE_DOCKER_ENTRYPOINT=bash <tmp>/claude -c '…'` from a subfolder of a
     git repo, both inside and outside the home: `pwd` and the git root must
     match the host paths, and a file written inside must appear on the host
     owned by the user
  4. the masked identity roots are empty and read-only inside, while the rest
     of `~/.config` is visible
  5. start `<tmp>/claude` in a TTY (e.g. tmux) and check that the UI renders
  6. `CLAUDE_DOCKER_ENTRYPOINT=google-chrome <tmp>/claude --headless=new
     --no-sandbox --screenshot=<launch folder>/shot.png https://example.com`
     from a folder under the home and from one under `/tmp`: the PNG must
     appear on the host
  7. `CLAUDE_DOCKER_SOCKET=1 CLAUDE_DOCKER_ENTRYPOINT=docker <tmp>/claude ps`
     lists the host containers, and `... docker compose version` works
  8. environment passthrough: with `ANTHROPIC_BASE_URL` on the host loopback
     (e.g. `ollama launch claude --model <model> -- -p "Reply with: OK"` with
     `<tmp>` first on `PATH`), the request reaches the host server
  9. with the chrome-devtools MCP configured, `claude mcp list` reports it
     connected
  10. with an image on the Mac clipboard, start `<tmp>/claude` in a TTY:
      Ctrl+V shows `[Image #1]`; inside, `xclip -t image/png -o` returns
      the PNG, a request without the token gets 404, `xclip -i` and text
      reads fail; the bridge listens only on `127.0.0.1` and is gone after
      the session exits
- Code, docs and commit messages in English.
