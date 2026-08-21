---
name: pre-pr-review
description: "Use when the user invokes /pre-pr-review or asks for a review of their changes before opening a PR. Generates a side-by-side visual diff in VS Code of all files changed on the current branch, as a self-review before submitting. This is NOT for diffing a specific file, NOR for reviewing someone else's branch."
---

## Procedure

1.  Run `git status --porcelain` to check for uncommitted changes. If any are present, halt the skill, list the uncommitted files, and tell the user to commit them (suggest the commit skill) before re-running.

2. Determine the base branch. Default to `development`. Allow the user to override via argument.

3. Run the helper script `${CLAUDE_SKILL_DIR}/scripts/generate-review.sh <base-branch>`. The script writes diff temp files and prints a summary to stdout.

4. Confirm with user before opening the review window. 

5. Read the manifest file that is mentioned in stdout (`Manifest: <path>`). Open all entries in a single `code --new-window` invocation, passing each entry's file as arguments - `--diff <old_file> <new_file>` for diff modes, bare `<new_file>` for preview mode. Batching ensures VS Code focuses the first (leftmost) tab rather than the last one opened.

## Gotchas

- Temp files are stored under a real directory structure (`old/<path>/file.ext`), not flattened. This lets VS Code auto-disambiguate same-named files in tab titles.

- Preserve file extensions on temp files (so VS Code applies the right syntax highlighting).

- Previous review windows are never touched — they're breadcrumbs.

- Filtering must always be visible — filtered files appear in the summary with a reason. Silent filtering breaks user trust.

- The filter is opt-out, not mandatory. If the user names a filtered file, include it in the review.

- Don't reimplement `.gitignore` filtering. Git already excludes ignored files from git diff; adding a second filter layer would either be a no-op or actively misleading.

- The script uses three-dot diff syntax (`base...HEAD`) so the diff is against the merge base, not the base branch's current tip. This means changes others have merged into the base branch since you diverged don't pollute the review.

- The manifest is the source of truth for what to open and in what order. Don't parse the human-readable summary — it's for the user, not for driving tab opening.

- The first `code` call uses `--new-window`, subsequent calls use `--reuse-window`. The default behavior of `code` (no window flag) targets the most recently used window, which could be the user's coding window or a previous review window — both undesirable.

## Rendering rules

- Edited files render as standard diff tabs.

- New files (non-markdown) render as diff tabs with empty left side. The empty side is the visual signal that this is a new file.

- Deleted files render as diff tabs with empty right side.

- New `.md` files render as preview tabs, not diff tabs (raw markdown is harder to read than rendered, and there's no old version to compare against anyway).

- Edited and deleted `.md` files render as standard diff tabs (you need to see what changed).

## Filter list

### Lockfiles
- `composer.lock`
- `package-lock.json`
- `yarn.lock`
- `pnpm-lock.yaml`

### Build output

- `public/build/**`
- `public/hot`
- `public/mix-manifest.json`

### Binary files

- By extension: `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.ico`, `.pdf`, `.woff`, `.woff2`, `.ttf`, `.eot` (and similar)
- Anything git itself flags as binary (catches what the extension list misses)

## Manifest format
Tab-separated, one line per file, in tab order. Format:
- `<mode>\t<path>\t<additions>\t<deletions>`
- `mode` is one of: `diff_edited`, `diff_new`, `diff_deleted`, `preview`
- For diff modes, files are at `<temp_dir>/old/<path>` and `<temp_dir>/new/<path>`
- For preview mode, only `<temp_dir>/new/<path>` exists
