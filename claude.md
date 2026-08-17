# User-wide instructions for Claude Code (applies to every project)

## Code comments

**A comment explains unclear code. Nothing else.**

- Never comment history or evolution ("X used to do Y", "replaced Z
  because...") — that's what git is for. Rationale belongs in the commit
  message.
- Never comment what the code deliberately does *not* do, what was considered
  and rejected, or what must not be added. Absence needs no annotation.
- No justifying, no narrating, no reassuring the reader. If the prose is not
  decoding something genuinely unclear, delete it.
- One short line when needed. Best of all is code that needs no comment.
- Applies to every repo, every project.

## Client confidentiality

- **Never write a client or project name into code, comments, docs, commit
  messages or branch names in a repo that is or may become public.** This is a
  cardinal rule, not a preference.
- Treat a repo as public unless verified private — check the remote *before*
  writing, not after. A private repo with a public mirror is public.
- The same applies to anything identifying a client indirectly: hostnames,
  domains, IPs, or version numbers tied to a named estate.
- Client-specific notes belong in the private repo that owns that client, never
  in shared or vendored code.
- Applies to every repo, every project.

## Git commits

- **Never add a `Co-Authored-By: Claude …` trailer** to commit messages.
  Don't include any other "Generated with Claude Code" / attribution footer
  either. Plain commit messages only, no AI attribution of any kind.
  Applies to every repo, every project.

## Git tags

- **Never delete tags** (`git tag -d`, pushing tag deletions) — not even a tag
  you created moments ago to fix a mistake. Create a new, correct tag instead
  (e.g. bump the version). Applies to every repo, every project.

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
