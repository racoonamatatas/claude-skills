#!/usr/bin/env bash
#
# setup.sh — link this repo into ~/.claude/skills so Claude Code can find it.
# Safe to re-run. Refuses to overwrite anything unexpected.

set -euo pipefail

# Resolve the repo's absolute path, regardless of where this script was invoked from.
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="$HOME/.claude/skills"

# Ensure ~/.claude exists.
mkdir -p "$HOME/.claude"

# Decide what to do based on what's currently at $target.
if [ -L "$target" ]; then
    # It's already a symlink. Check whether it points where we want.
    current="$(readlink "$target")"
    if [ "$current" = "$repo_dir" ]; then
        echo "Already linked: $target -> $repo_dir"
        exit 0
    else
        echo "Error: $target is a symlink to $current, not $repo_dir." >&2
        echo "Remove it manually if you want to relink, then re-run." >&2
        exit 1
    fi
elif [ -d "$target" ]; then
    # It's a real directory. Only safe to remove if empty.
    if [ -z "$(ls -A "$target")" ]; then
        rmdir "$target"
    else
        echo "Error: $target exists and contains files." >&2
        echo "Move or remove it manually, then re-run." >&2
        exit 1
    fi
elif [ -e "$target" ]; then
    # Something else (a regular file, somehow). Refuse.
    echo "Error: $target exists and is not a directory or symlink." >&2
    echo "Investigate manually, then re-run." >&2
    exit 1
fi

# At this point, $target either didn't exist or was an empty directory we just removed.
ln -s "$repo_dir" "$target"
echo "Linked $target -> $repo_dir"