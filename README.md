# Claude skills

A small, curated set of personal [Claude Code](https://claude.com/claude-code)
skills, published as a sample of how I package repeatable work into skills.

## Platform

- Linux only.
- On Windows, use WSL2.

## Requirements

- bash 4 or newer
- VS Code with the `code` CLI on PATH (for `pre-pr-review`)
- The GitHub CLI (`gh`) and `jq` on PATH (for `pr-herald`; `spitball` uses `gh` once, to bootstrap its notes repo on a fresh machine)

## Setup on a new machine

Setup creates a symlink at `~/.claude/skills` pointing to this repo, so Claude Code finds the skills here. Pick a directory where you keep code repositories. The example below uses `~/Projects/`. Run these commands from your terminal:

```bash
    git clone <repo-url> ~/Projects/claude-skills
    cd ~/Projects/claude-skills
    ./setup.sh
```

After running, `~/.claude/skills` will be a symlink to wherever you cloned the repo. Any skill you add to the repo automatically becomes available to Claude Code. The setup script is safe to re-run and won't overwrite anything unexpected.

## Skills

In the order they'd show up in a feature's life:

- **spitball**: the phase before planning — a high-paced memory dump for a raw idea, captured into a self-contained visual HTML note (one per idea) in its own notes repo. Deliberately inverts planning's rules: at most one sharpening question per turn, no scope critique, forks named but never forced. The note is the residue; the conversation is the workspace.
- **pre-pr-review**: a side-by-side view of the diffs of all changed files (with sensible filtering) on a feature branch, opened in a new VS Code window. For self-review before opening a PR. Reads the branch against its merge base so changes others merged in the meantime don't pollute the view; renders new/edited/deleted files as diff tabs and new markdown as preview tabs; filters lockfiles, build output, and binaries (visibly — nothing is dropped silently).
- **pr-herald**: reads a PR's review discussion (human + bot reviews, inline comments with resolution state, CI) and relays the plain-language bottom line back to you in chat — the verdict, what's still open and needs you, and what was already handled. Read-only; it never posts. Built to cut through noisy multi-round, multi-agent (bot-reviewer) threads where a single finding gets raised, confirmed, and resolved across many comments.

## Future ideas

Ideas parked here so they're not forgotten:

- Review someone else's PR (related to but distinct from `pre-pr-review`).
- A write counterpart to `pr-herald` that posts the plain-language digest as a comment on the PR (outward-facing, team-visible) — kept separate from the read-only herald on purpose.
- A living guide capturing transferable design lessons learned while building skills like these.

## Notes

This is a personal repo. If something doesn't work for you, fork it and adapt — I won't be maintaining it for other use cases.
