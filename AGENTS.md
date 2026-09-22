# Agent instructions — claude-docker-x86

- Scope: a Docker image plus a launcher that run the official Linux build of
  Claude Code on Intel Macs without AVX2. Keep it a thin wrapper: Claude Code
  is installed from npm at image build time, never patched or redistributed.
- Invariants of `bin/claude` — do not break them:
  - the host home is mounted at the same path and used as `HOME`
  - the working directory is the host folder the launcher was started from;
    folders outside the home are mounted at the same path (git root if any)
  - the container is ephemeral (`--rm`) and runs as the host uid/gid
- Before pushing, test on an Intel Mac without AVX2 with Docker running:
  1. `CLAUDE_DOCKER_LAUNCHER=<tmp>/claude ./install.sh`
  2. `<tmp>/claude --version` without a TTY
  3. `CLAUDE_DOCKER_ENTRYPOINT=bash <tmp>/claude -c '…'` from a subfolder of a
     git repo, both inside and outside the home: `pwd` and the git root must
     match the host paths, and a file written inside must appear on the host
     owned by the user
  4. start `<tmp>/claude` in a TTY (e.g. tmux) and check that the UI renders
  5. `CLAUDE_DOCKER_ENTRYPOINT=google-chrome <tmp>/claude --headless=new
     --no-sandbox --screenshot=<launch folder>/shot.png https://example.com`
     from a folder under `/Users` and from one under `/tmp`: the PNG must
     appear on the host
  6. with the chrome-devtools MCP configured, `claude mcp list` reports it
     connected
- Code, docs and commit messages in English.
