#!/usr/bin/env bash
#
# generate-review.sh — produce side-by-side diff data for /pre-pr-review.
# Writes temp files and a manifest, prints a summary to stdout.
#
# Usage: generate-review.sh [base-branch]
#   base-branch defaults to 'development' if not provided.

set -euo pipefail

# ---------------------------------------------------------------------------
# Phase 1: Setup
# ---------------------------------------------------------------------------

# Default base branch matches the one named in SKILL.md.
base_branch="${1:-development}"

# Validate the base branch exists locally.
if ! git rev-parse --verify "$base_branch" >/dev/null 2>&1; then
    echo "Error: base branch '$base_branch' does not exist." >&2
    exit 1
fi

# Create a per-run temp directory: timestamp prefix for human-readable
# breadcrumbs, random suffix from mktemp for guaranteed uniqueness.
timestamp=$(date +%Y%m%d-%H%M%S)
temp_dir=$(mktemp -d "/tmp/diff-report-$timestamp-XXXX")
mkdir -p "$temp_dir/old" "$temp_dir/new"

manifest="$temp_dir/manifest.txt"
: > "$manifest"

# ---------------------------------------------------------------------------
# Phase 2: Get the list of changed files
# ---------------------------------------------------------------------------

# Three-dot syntax compares against the merge base, not the base branch's
# current tip — so changes others have merged into the base branch since
# we diverged don't pollute our diff. --no-renames decomposes renames
# into delete + add pairs, which our classification handles cleanly.
mapfile -t changed_files < <(git diff --name-status --no-renames "$base_branch"...HEAD)

# Clean exit if there's nothing to review.
if [ ${#changed_files[@]} -eq 0 ]; then
    echo "No changes between $base_branch and HEAD. Nothing to review."
    rm -rf "$temp_dir"
    exit 0
fi

# ---------------------------------------------------------------------------
# Phase 3: Classify and filter
# ---------------------------------------------------------------------------

# Filter category lists. Edit these to change what gets filtered.
lockfiles=(composer.lock package-lock.json yarn.lock pnpm-lock.yaml)
build_output_paths=(public/hot public/mix-manifest.json)
build_output_prefix="public/build/"
binary_extensions=(png jpg jpeg gif webp ico pdf woff woff2 ttf eot)

# Build lookup maps from numstat: per-file additions, deletions, and
# git's own binary-file flag.
declare -A additions
declare -A deletions
declare -A git_binary_files
while IFS=$'\t' read -r adds dels path; do
    if [ "$adds" = "-" ] && [ "$dels" = "-" ]; then
        git_binary_files["$path"]=1
    else
        additions["$path"]=$adds
        deletions["$path"]=$dels
    fi
done < <(git diff --numstat --no-renames "$base_branch"...HEAD)

# Output accumulators.
to_render=()    # entries: "<mode>\t<status>\t<path>"
filtered=()     # entries: "<path>\t<reason>"

for entry in "${changed_files[@]}"; do
    status="${entry%%$'\t'*}"
    path="${entry#*$'\t'}"
    basename="${path##*/}"
    extension="${basename##*.}"

    # Filter: lockfile?
    is_lockfile=0
    for lf in "${lockfiles[@]}"; do
        if [ "$basename" = "$lf" ]; then is_lockfile=1; break; fi
    done
    if [ "$is_lockfile" = "1" ]; then
        filtered+=("$path"$'\t'"lockfile")
        continue
    fi

    # Filter: build output?
    is_build=0
    if [[ "$path" == "$build_output_prefix"* ]]; then is_build=1; fi
    for bp in "${build_output_paths[@]}"; do
        if [ "$path" = "$bp" ]; then is_build=1; break; fi
    done
    if [ "$is_build" = "1" ]; then
        filtered+=("$path"$'\t'"build output")
        continue
    fi

    # Filter: binary?
    is_binary=0
    for be in "${binary_extensions[@]}"; do
        if [ "$extension" = "$be" ]; then is_binary=1; break; fi
    done
    if [ -n "${git_binary_files[$path]:-}" ]; then is_binary=1; fi
    if [ "$is_binary" = "1" ]; then
        filtered+=("$path"$'\t'"binary")
        continue
    fi

    # Not filtered — decide rendering mode.
    case "$status" in
        D)
            mode="diff_deleted" ;;
        A)
            if [ "$extension" = "md" ]; then
                mode="preview"
            else
                mode="diff_new"
            fi
            ;;
        M)
            mode="diff_edited" ;;
        *)
            # Unexpected status (T, C, U, etc.). Treat as edited so we
            # don't drop it silently.
            mode="diff_edited" ;;
    esac
    to_render+=("$mode"$'\t'"$status"$'\t'"$path")
done

# ---------------------------------------------------------------------------
# Phase 4: Sort by group (markdown first), then size, then path
# ---------------------------------------------------------------------------

# Group 0 = markdown (.md), group 1 = everything else.
# Markdown files contain context (plans, decisions); reading context
# before code matches the developer's review workflow.

if [ ${#to_render[@]} -gt 0 ]; then
    sorted=()
    while IFS= read -r line; do
        # Strip the three prefix fields (group, count, path) used for sorting.
        sorted+=("${line#*$'\t'*$'\t'*$'\t'}")
    done < <(
        for entry in "${to_render[@]}"; do
            path="${entry##*$'\t'}"
            adds="${additions[$path]:-0}"
            dels="${deletions[$path]:-0}"
            count=$((adds + dels))
            if [[ "$path" == *.md ]]; then group=0; else group=1; fi
            printf '%s\t%s\t%s\t%s\n' "$group" "$count" "$path" "$entry"
        done | sort -k1,1n -k2,2n -k3,3
    )
    to_render=("${sorted[@]}")
fi

# ---------------------------------------------------------------------------
# Phase 5: Write temp files and manifest
# ---------------------------------------------------------------------------

merge_base=$(git merge-base "$base_branch" HEAD)

ensure_parent() {
    mkdir -p "$(dirname "$1")"
}

for entry in "${to_render[@]}"; do
    mode="${entry%%$'\t'*}"
    rest="${entry#*$'\t'}"
    status="${rest%%$'\t'*}"
    path="${rest#*$'\t'}"

    old_file="$temp_dir/old/$path"
    new_file="$temp_dir/new/$path"

    case "$mode" in
        diff_edited)
            ensure_parent "$old_file"
            ensure_parent "$new_file"
            git show "$merge_base:$path" > "$old_file"
            git show "HEAD:$path" > "$new_file"
            ;;
        diff_new)
            ensure_parent "$old_file"
            ensure_parent "$new_file"
            : > "$old_file"
            git show "HEAD:$path" > "$new_file"
            ;;
        diff_deleted)
            ensure_parent "$old_file"
            ensure_parent "$new_file"
            git show "$merge_base:$path" > "$old_file"
            : > "$new_file"
            ;;
        preview)
            ensure_parent "$new_file"
            git show "HEAD:$path" > "$new_file"
            ;;
    esac

    adds="${additions[$path]:-0}"
    dels="${deletions[$path]:-0}"
    printf '%s\t%s\t%s\t%s\n' "$mode" "$path" "$adds" "$dels" >> "$manifest"
done

# ---------------------------------------------------------------------------
# Phase 6: Print summary
# ---------------------------------------------------------------------------

current_branch=$(git rev-parse --abbrev-ref HEAD)

echo "Reviewing $current_branch vs $base_branch"
echo
echo "Files (${#to_render[@]}):"
for entry in "${to_render[@]}"; do
    mode="${entry%%$'\t'*}"
    rest="${entry#*$'\t'}"
    path="${rest#*$'\t'}"

    adds="${additions[$path]:-0}"
    dels="${deletions[$path]:-0}"

    case "$mode" in
        diff_edited)  marker="[edit]" ;;
        diff_new)     marker="[add]" ;;
        diff_deleted) marker="[remove]" ;;
        preview)      marker="[preview]" ;;
    esac

    printf '  %s %s (+%s -%s)\n' "$marker" "$path" "$adds" "$dels"
done

if [ ${#filtered[@]} -gt 0 ]; then
    echo
    echo "Filtered (${#filtered[@]}):"
    for entry in "${filtered[@]}"; do
        path="${entry%%$'\t'*}"
        reason="${entry#*$'\t'}"
        printf '  %s (%s)\n' "$path" "$reason"
    done
fi

echo
echo "Manifest: $manifest"