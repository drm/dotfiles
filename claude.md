# User-wide instructions for Claude Code (applies to every project)

## Code comments

- Avoid prose in comments. Comment only non-obvious things; never comment
  history or evolution ("X used to do Y", "replaced Z because...") — that's
  what git is for. Rationale belongs in the commit message, not the source.
- If a comment is truly needed, one short line. Best of all is
  self-explanatory code that needs no comment.
- Applies to every repo, every project.

## Git commits

- **Never add a `Co-Authored-By: Claude …` trailer** to commit messages.
  Don't include any other "Generated with Claude Code" / attribution footer
  either. Plain commit messages only, no AI attribution of any kind.
  Applies to every repo, every project.

## Remote / detached execution

- When *you* manually start a long-running job in an interactive SSH session that
  is meant to outlive that connection (a long build, migration, data job —
  anything you'd otherwise `nohup &` or just leave running), run it inside
  `tmux`/`screen` so a dropped SSH session or laptop power loss can't orphan or
  lose it. Install tmux first if absent. Never rely on `nohup &`, a bare
  `docker run -d`, or the connection staying alive.
- This does NOT apply to remote commands that a tool/framework runs
  **synchronously and owns the lifecycle of** — e.g. install-util / Ansible
  executing a provisioning script over SSH, or an `ssh host cmd` that a script
  waits on. Those are foreground steps the orchestrator manages; wrapping them in
  tmux fights the model. Let the tool drive it.
  Applies to every repo, every project.
