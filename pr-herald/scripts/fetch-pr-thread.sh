#!/usr/bin/env bash
# Fetch and normalise a PR's full discussion into a single JSON bundle.
#
# Usage: fetch-pr-thread.sh [<pr-number>|<branch>]
#   no arg    -> the PR for the current branch
#   number    -> that PR
#   branch    -> the open PR whose head is that branch; if none is open, its
#                highest-numbered PR, which then reads back as nothing to do
#
# Prints a short human summary to stdout, and one line "Bundle: <path>"
# naming a JSON file the caller reads to do the distillation.
#
# The bundle joins what two GitHub surfaces know:
#   - PR meta + aggregate reviewDecision + CI rollup   (gh pr view --json)
#   - every discussion surface, paginated to exhaustion (GraphQL): summary-level
#     reviews, issue-level comments, and inline review threads WITH per-thread
#     isResolved / isOutdated state
#
# All three discussion surfaces go through GraphQL rather than `gh pr view`
# because `gh pr view --json reviews,comments` issues `first: 100` with no
# paging: past 100 it keeps the OLDEST hundred and drops the newest — the
# opposite of what a herald needs. Inline threads additionally have no REST
# equivalent that exposes isResolved. Reviewed on PR #1909.
set -euo pipefail

arg="${1:-}"

command -v gh >/dev/null || { echo "error: gh CLI not on PATH" >&2; exit 1; }
command -v jq >/dev/null || { echo "error: jq not on PATH" >&2; exit 1; }

# --- drain a paginated GraphQL connection ------------------------------------
# $1 query (takes $cursor, selects pageInfo{hasNextPage endCursor} on the
#    connection), $2 --jq path to that connection, $3 starting cursor
#    ("null" to start at the beginning), $@ any further -F variables.
# Echoes the concatenated .nodes of every page as one JSON array.
paginate() {
  local query="$1" path="$2" cursor="$3"; shift 3
  local acc="[]" page
  while :; do
    page="$(gh api graphql -f query="$query" -F cursor="$cursor" "$@" --jq "$path")"
    acc="$(jq -n --argjson acc "$acc" --argjson page "$page" '$acc + $page.nodes')"
    [[ "$(jq -r '.pageInfo.hasNextPage' <<<"$page")" == "true" ]] || break
    cursor="$(jq -r '.pageInfo.endCursor' <<<"$page")"
  done
  printf '%s' "$acc"
}

# --- resolve repo (owner/name) from the current gh context -------------------
repo_json="$(gh repo view --json owner,name 2>/dev/null)" \
  || { echo "error: not inside a GitHub repo (gh repo view failed)" >&2; exit 1; }
owner="$(jq -r '.owner.login' <<<"$repo_json")"
name="$(jq -r '.name' <<<"$repo_json")"

# --- resolve the PR number ---------------------------------------------------
if [[ -z "$arg" ]]; then
  pr="$(gh pr view --json number --jq .number 2>/dev/null)" \
    || { echo "error: no PR for the current branch — pass a PR number or branch name" >&2; exit 1; }
elif [[ "$arg" =~ ^[0-9]+$ ]]; then
  pr="$arg"
else
  # The target is the open PR. The closed/merged fallback exists only so that a
  # stale branch resolves to something readable instead of erroring; it is not
  # the case being optimised for. The previous `--state all | .[0]` could hand
  # back a merged PR while an open one existed, and leant on gh's unspecified
  # list order — max_by(.number) picks the newest deterministically instead.
  pr="$(gh pr list --head "$arg" --state open --json number --jq 'max_by(.number).number' 2>/dev/null || true)"
  if [[ -z "$pr" || "$pr" == "null" ]]; then
    pr="$(gh pr list --head "$arg" --state all --json number --jq 'max_by(.number).number' 2>/dev/null || true)"
  fi
  [[ -n "$pr" && "$pr" != "null" ]] \
    || { echo "error: no PR found with head branch '$arg'" >&2; exit 1; }
fi

# --- PR meta + CI rollup ------------------------------------------------------
pr_json="$(gh pr view "$pr" --json \
  number,title,url,state,isDraft,headRefName,headRefOid,reviewDecision,mergeable,statusCheckRollup)"

# --- summary-level reviews ----------------------------------------------------
# state: APPROVED / CHANGES_REQUESTED / COMMENTED / DISMISSED
reviews_query='
query($owner:String!,$repo:String!,$number:Int!,$cursor:String){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      reviews(first:100, after:$cursor){
        pageInfo{ hasNextPage endCursor }
        nodes{
          id
          author{ login }
          authorAssociation
          body
          state
          submittedAt
          commit{ oid }
        }
      }
    }
  }
}'

# --- issue-level (non-inline) comments ----------------------------------------
# Where bot proclamations land, so this is the surface carrying the
# machine-readable footer verdict the distillation rules tell the model to trust.
comments_query='
query($owner:String!,$repo:String!,$number:Int!,$cursor:String){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      comments(first:100, after:$cursor){
        pageInfo{ hasNextPage endCursor }
        nodes{
          id
          author{ login }
          authorAssociation
          body
          createdAt
          url
          isMinimized
          minimizedReason
        }
      }
    }
  }
}'

# --- inline review threads + per-thread resolution state ----------------------
# A thread's comments come back oldest-first, so a capped fetch keeps the oldest
# and discards the newest — exactly the resolution state this skill reports on.
threads_query='
query($owner:String!,$repo:String!,$number:Int!,$cursor:String){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      reviewThreads(first:100, after:$cursor){
        pageInfo{ hasNextPage endCursor }
        nodes{
          id
          isResolved
          isOutdated
          path
          line
          comments(first:100){
            pageInfo{ hasNextPage endCursor }
            nodes{ author{login} body createdAt }
          }
        }
      }
    }
  }
}'

thread_comments_query='
query($id:ID!,$cursor:String){
  node(id:$id){
    ... on PullRequestReviewThread {
      comments(first:100, after:$cursor){
        pageInfo{ hasNextPage endCursor }
        nodes{ author{login} body createdAt }
      }
    }
  }
}'

pr_vars=(-F owner="$owner" -F repo="$name" -F number="$pr")

reviews="$(paginate "$reviews_query" \
  '.data.repository.pullRequest.reviews' null "${pr_vars[@]}")"
comments="$(paginate "$comments_query" \
  '.data.repository.pullRequest.comments' null "${pr_vars[@]}")"
threads="$(paginate "$threads_query" \
  '.data.repository.pullRequest.reviewThreads' null "${pr_vars[@]}")"

# top up any thread whose own comments overflowed one page
while read -r tid; do
  rest="$(paginate "$thread_comments_query" '.data.node.comments' \
    "$(jq -r --arg id "$tid" \
         '.[] | select(.id == $id) | .comments.pageInfo.endCursor' <<<"$threads")" \
    -F id="$tid")"
  threads="$(jq --arg id "$tid" --argjson rest "$rest" \
    'map(if .id == $id then .comments.nodes += $rest else . end)' <<<"$threads")"
done < <(jq -r '.[] | select(.comments.pageInfo.hasNextPage) | .id' <<<"$threads")

# shed the pagination scaffolding — the bundle keeps its documented shape
threads="$(jq 'map(del(.id) | .comments = {nodes: .comments.nodes})' <<<"$threads")"

# --- assemble the bundle -----------------------------------------------------
out_dir="$(mktemp -d)"
bundle="$out_dir/pr-${pr}-thread.json"
jq -n \
  --arg repo "$owner/$name" \
  --argjson pr "$pr_json" \
  --argjson reviews "$reviews" \
  --argjson comments "$comments" \
  --argjson threads "$threads" \
  '{
     repo: $repo,
     pr: ($pr | del(.statusCheckRollup)),
     review_decision: ($pr.reviewDecision // "NONE"),
     ci: ($pr.statusCheckRollup // []),
     reviews: $reviews,
     issue_comments: $comments,
     review_threads: $threads
   }' > "$bundle"

# --- human summary (the model reads the bundle, not this) --------------------
title="$(jq -r '.pr.title' "$bundle")"
url="$(jq -r '.pr.url' "$bundle")"
decision="$(jq -r '.review_decision' "$bundle")"
n_reviews="$(jq '.reviews | length' "$bundle")"
n_comments="$(jq '.issue_comments | length' "$bundle")"
n_threads="$(jq '.review_threads | length' "$bundle")"
n_open="$(jq '[.review_threads[] | select(.isResolved == false)] | length' "$bundle")"
ci_total="$(jq '.ci | length' "$bundle")"
# ACTION_REQUIRED / STARTUP_FAILURE / STALE are COMPLETED with a non-null
# conclusion, so they are neither failing-by-the-obvious-name nor pending. They
# are still not a pass, and an unlisted conclusion must never fall through to
# green — that is a false all-clear on a gate nobody resolved.
ci_fail="$(jq '[.ci[] | ((.conclusion // .state // "") | ascii_upcase)
                | select(. == "FAILURE" or . == "ERROR" or . == "CANCELLED"
                         or . == "TIMED_OUT" or . == "ACTION_REQUIRED"
                         or . == "STARTUP_FAILURE" or . == "STALE")]
              | length' "$bundle")"
# A check-run in flight has status != COMPLETED and a null conclusion; a legacy
# status context reports PENDING/EXPECTED. Neither is a failure — but neither is
# green either.
ci_pending="$(jq '[.ci[]
                  | ((.status // "") | ascii_upcase) as $run
                  | ((.state  // "") | ascii_upcase) as $ctx
                  | select(($run != "" and $run != "COMPLETED")
                           or $ctx == "PENDING" or $ctx == "EXPECTED")]
                 | length' "$bundle")"

echo "PR #${pr} — ${title}"
echo "${url}"
echo "Review decision: ${decision}"
echo "Reviews: ${n_reviews} · Issue comments: ${n_comments} · Inline threads: ${n_threads} (open: ${n_open})"
if [[ "$ci_total" -eq 0 ]]; then
  echo "CI: no checks reported"
elif [[ "$ci_fail" -gt 0 ]]; then
  echo "CI: ${ci_fail}/${ci_total} checks failing"
elif [[ "$ci_pending" -gt 0 ]]; then
  echo "CI: ${ci_pending}/${ci_total} checks still running"
else
  echo "CI: green (${ci_total} checks)"
fi
echo "Bundle: ${bundle}"
