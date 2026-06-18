# User-wide instructions for Claude Code (applies to every project)

## Code comments

- Don't comment obvious things — the code itself is the documentation. Add a
  comment only when something is genuinely confusing; otherwise no comment is
  better than a redundant one. Shorter = clearer = better. Best of all is
  self-explanatory code that needs no comment.
- No verbose comments. If a comment is truly needed, keep it to one short line —
  never a multi-line block of rationale. Explanation of *why* belongs in the
  commit message, not the source.
- Applies to every repo, every project.

## Git commits

- **Never add a `Co-Authored-By: Claude …` trailer** to commit messages.
  Don't include any other "Generated with Claude Code" / attribution footer
  either. Plain commit messages only, no AI attribution of any kind.
  Applies to every repo, every project.

## Remote / detached execution

- Whenever something runs remotely in an SSH session but detached (a long job,
  background process, anything meant to outlive the SSH connection), ALWAYS run
  it inside `tmux`. Never rely on `nohup &`, a bare `docker run -d`, or the
  connection staying alive — a dropped SSH session (or a laptop power loss) must
  not lose or orphan the work.
- If `tmux` is not installed on the remote, install it first, then proceed.
  Applies to every repo, every project.
