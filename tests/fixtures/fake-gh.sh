#!/usr/bin/env bash
# tests/fixtures/fake-gh.sh — fake `gh` CLI stub for E2E tests.
#
# Wired into PATH by lib_e2e.sh's e2e_setup() so that all `gh` invocations
# in a test process resolve to this stub instead of the real gh binary.
#
# State is persisted to $GH_STATE_FILE (set by e2e_setup).
#
# Supported subcommand families:
#   gh issue create   --title <t> [--body <b>] [--label <l>] [--label <l2>...]
#   gh issue edit <N> --add-label <label>
#   gh issue edit <N> --remove-label <label>
#   gh issue view <N> --json <fields> [--jq <expr>]
#   gh issue close <N>
#   gh issue list [--label <l>] [--state <s>] [--json <fields>] [--limit <n>]
#   gh issue comment <N> --body <text>
#   gh pr create   --title <t> [--body <b>] [--head <branch>] [--base <branch>]
#   gh pr edit <N> --add-label <label>
#   gh pr edit <N> --remove-label <label>
#   gh pr view <N> [--json <fields>] [--jq <expr>]
#   gh pr merge <N> [--squash] [--delete-branch | -d]
#   gh pr list [--state <s>] [--json <fields>] [--limit <n>]
#
# Any unrecognised subcommand exits 1 with a message on stderr.
#
# SENTINEL: this script emits "# fake-gh.sh" as its first output line when
# called with --version, allowing tests to verify the stub is active.
#
# Design doc: docs/design/DESIGN-sdlc-e2e-test-suite.md

set -euo pipefail

# ---------------------------------------------------------------------------
# Require GH_STATE_FILE
# ---------------------------------------------------------------------------
if [[ -z "${GH_STATE_FILE:-}" ]]; then
  echo "fake-gh.sh: GH_STATE_FILE is not set. Was e2e_setup() called?" >&2
  exit 1
fi

if [[ ! -f "$GH_STATE_FILE" ]]; then
  echo "fake-gh.sh: GH_STATE_FILE does not exist: $GH_STATE_FILE" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# _read_state: cat the state file (atomic reads; jq is called in callers)
_read_state() { cat "$GH_STATE_FILE"; }

# _write_state <jq_filter>: apply filter atomically using a tmp file
_write_state() {
  local filter="$1"
  shift
  jq "$filter" "$@" "$GH_STATE_FILE" > "${GH_STATE_FILE}.tmp" \
    && mv "${GH_STATE_FILE}.tmp" "$GH_STATE_FILE"
}

# _next_issue / _next_pr: return the next auto-increment number
_next_issue() { jq -r '.next_issue_number' "$GH_STATE_FILE"; }
_next_pr()    { jq -r '.next_pr_number'    "$GH_STATE_FILE"; }

# _normalize_labels <json_input>
# Transforms a labels field from string array to real-gh-format object array.
# Real gh stores: [{"name":"bug","color":"...","description":"..."}]
# Stub stores internally: ["bug","in-progress"]
# This normalizer converts stub-internal format to real-gh format so that
# --json labels --jq '[.labels[].name]' works correctly.
_normalize_labels() {
  local input="$1"
  printf '%s' "$input" | jq '
    if type == "array" then
      map(if type == "string" then {"name": ., "color": "", "description": ""} else . end)
    else
      if type == "string" then {"name": ., "color": "", "description": ""} else . end
    end'
}

# _prepare_for_output <json_input>
# Applies label normalization to a single issue/PR object or an array of them.
_prepare_for_output() {
  local input="$1"
  printf '%s' "$input" | jq '
    def norm_labels:
      if .labels? then
        .labels = [.labels[] |
          if type == "string" then {"name": ., "color": "", "description": ""} else . end]
      else . end;
    if type == "array" then map(norm_labels)
    else norm_labels
    end'
}

# _apply_jq_output <fields_csv> <jq_expr> <json_input>
# Applies label normalization, --json field selection, then optional --jq expression.
# Outputs raw strings (no JSON quotes) when the final result is a string — mirrors
# how real `gh` behaves with --jq.
_apply_jq_output() {
  local fields="$1"   # comma-separated field names (may be empty)
  local jq_expr="$2"  # jq expression (may be empty)
  local input="$3"    # JSON string to filter

  # Always normalize labels to object format before output
  local result
  result="$(_prepare_for_output "$input")"

  # Field selection: use jq's built-in `to_entries / from_entries` to pick
  # only the requested keys. Works on both objects and arrays-of-objects.
  if [[ -n "$fields" ]]; then
    # Build a JSON array of the requested field names for use inside jq
    local fields_json
    fields_json="$(printf '%s' "$fields" | tr ',' '\n' | jq -Rn '[inputs | select(length>0)]')"

    result="$(printf '%s' "$result" | jq \
      --argjson f "$fields_json" \
      'if type == "array"
       then map(to_entries | map(select(.key | IN($f[]))) | from_entries)
       else   to_entries | map(select(.key | IN($f[]))) | from_entries
       end')"
  fi

  # Optional --jq expression applied on top; output is raw (mirrors real gh behavior)
  if [[ -n "$jq_expr" ]]; then
    printf '%s' "$result" | jq -r "$jq_expr"
  else
    printf '%s\n' "$result"
  fi
}

# ---------------------------------------------------------------------------
# Parse top-level subcommand
# ---------------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
  echo "fake-gh.sh: no subcommand given" >&2
  exit 1
fi

# Handle --version sentinel
if [[ "$1" == "--version" ]]; then
  echo "# fake-gh.sh"
  exit 0
fi

NOUN="$1"; shift  # "issue" | "pr"
if [[ $# -eq 0 ]]; then
  echo "fake-gh.sh: no action given for: $NOUN" >&2
  exit 1
fi
ACTION="$1"; shift  # "create" | "edit" | "view" | "merge" | "list" | "close" | "comment"

# ===========================================================================
# ISSUE subcommands
# ===========================================================================
if [[ "$NOUN" == "issue" ]]; then

  # -------------------------------------------------------------------------
  # gh issue create --title <t> [--body <b>] [--label <l>...]
  # -------------------------------------------------------------------------
  if [[ "$ACTION" == "create" ]]; then
    title=""
    body=""
    labels=()

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --title|-t)  title="$2";        shift 2 ;;
        --body|-b)   body="$2";         shift 2 ;;
        --label|-l)  labels+=("$2");    shift 2 ;;
        *)           shift ;;
      esac
    done

    local_num="$(_next_issue)"
    labels_json="$(printf '%s\n' "${labels[@]+"${labels[@]}"}" | jq -Rn '[inputs | select(length>0)]')"

    _write_state \
      --arg n   "$local_num" \
      --arg t   "$title" \
      --arg b   "$body" \
      --argjson l "$labels_json" \
      '.issues[$n] = {
        "number": ($n | tonumber),
        "title": $t,
        "body": $b,
        "state": "open",
        "labels": $l,
        "comments": []
      } | .next_issue_number = (.next_issue_number + 1)'

    printf 'https://github.com/owner/repo/issues/%s\n' "$local_num"
    exit 0
  fi

  # -------------------------------------------------------------------------
  # gh issue edit <N> --add-label <label> | --remove-label <label>
  # -------------------------------------------------------------------------
  if [[ "$ACTION" == "edit" ]]; then
    local_num="$1"; shift
    op=""
    label=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --add-label)    op="add";    label="$2"; shift 2 ;;
        --remove-label) op="remove"; label="$2"; shift 2 ;;
        *)              shift ;;
      esac
    done

    if [[ "$op" == "add" ]]; then
      _write_state \
        --arg n "$local_num" --arg l "$label" \
        '.issues[$n].labels = ((.issues[$n].labels // []) + [$l] | unique)'
    elif [[ "$op" == "remove" ]]; then
      _write_state \
        --arg n "$local_num" --arg l "$label" \
        '.issues[$n].labels = ((.issues[$n].labels // []) | map(select(. != $l)))'
    fi

    printf 'https://github.com/owner/repo/issues/%s\n' "$local_num"
    exit 0
  fi

  # -------------------------------------------------------------------------
  # gh issue view <N> [--json <fields>] [--jq <expr>]
  # -------------------------------------------------------------------------
  if [[ "$ACTION" == "view" ]]; then
    local_num="$1"; shift
    json_fields=""
    jq_expr=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --json) json_fields="$2"; shift 2 ;;
        --jq)   jq_expr="$2";    shift 2 ;;
        *)      shift ;;
      esac
    done

    local_issue="$(jq --arg n "$local_num" '.issues[$n] // empty' "$GH_STATE_FILE")"
    if [[ -z "$local_issue" ]]; then
      echo "fake-gh.sh: issue #$local_num not found" >&2
      exit 1
    fi

    _apply_jq_output "$json_fields" "$jq_expr" "$local_issue"
    exit 0
  fi

  # -------------------------------------------------------------------------
  # gh issue close <N>
  # -------------------------------------------------------------------------
  if [[ "$ACTION" == "close" ]]; then
    local_num="$1"; shift
    _write_state --arg n "$local_num" '.issues[$n].state = "closed"'
    printf 'Closed issue #%s\n' "$local_num"
    exit 0
  fi

  # -------------------------------------------------------------------------
  # gh issue comment <N> --body <text>
  # -------------------------------------------------------------------------
  if [[ "$ACTION" == "comment" ]]; then
    local_num="$1"; shift
    comment_body=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --body|-b) comment_body="$2"; shift 2 ;;
        *)         shift ;;
      esac
    done

    _write_state \
      --arg n "$local_num" --arg c "$comment_body" \
      '.issues[$n].comments = ((.issues[$n].comments // []) + [$c])'

    printf 'https://github.com/owner/repo/issues/%s#issuecomment-0\n' "$local_num"
    exit 0
  fi

  # -------------------------------------------------------------------------
  # gh issue list [--label <l>] [--state <s>] [--json <fields>] [--limit <n>]
  # -------------------------------------------------------------------------
  if [[ "$ACTION" == "list" ]]; then
    filter_label=""
    filter_state="open"
    json_fields=""
    jq_expr=""
    limit=30

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --label|-l)  filter_label="$2"; shift 2 ;;
        --state|-s)  filter_state="$2"; shift 2 ;;
        --json)      json_fields="$2";  shift 2 ;;
        --jq)        jq_expr="$2";      shift 2 ;;
        --limit)     limit="$2";        shift 2 ;;
        *)           shift ;;
      esac
    done

    # Build filter expression
    _list_result="$(jq \
      --arg s  "$filter_state" \
      --arg l  "$filter_label" \
      --argjson lim "$limit" \
      '[.issues[] |
        select($s == "all" or .state == $s) |
        select($l == "" or (.labels | any(. == $l)))
      ] | .[:$lim]' \
      "$GH_STATE_FILE")"

    _apply_jq_output "$json_fields" "$jq_expr" "$_list_result"
    exit 0
  fi

  echo "fake-gh.sh: unknown issue action: $ACTION" >&2
  exit 1
fi

# ===========================================================================
# PR subcommands
# ===========================================================================
if [[ "$NOUN" == "pr" ]]; then

  # -------------------------------------------------------------------------
  # gh pr create --title <t> [--body <b>] [--head <branch>] [--base <branch>]
  # -------------------------------------------------------------------------
  if [[ "$ACTION" == "create" ]]; then
    title=""
    body=""
    head_branch=""
    base_branch="main"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --title|-t)  title="$2";       shift 2 ;;
        --body|-b)   body="$2";        shift 2 ;;
        --head)      head_branch="$2"; shift 2 ;;
        --base)      base_branch="$2"; shift 2 ;;
        *)           shift ;;
      esac
    done

    local_num="$(_next_pr)"

    _write_state \
      --arg n    "$local_num" \
      --arg t    "$title" \
      --arg b    "$body" \
      --arg head "$head_branch" \
      --arg base "$base_branch" \
      '.prs[$n] = {
        "number": ($n | tonumber),
        "title": $t,
        "body": $b,
        "state": "open",
        "head_branch": $head,
        "base_branch": $base,
        "labels": [],
        "comments": [],
        "merged_at": null
      } | .next_pr_number = (.next_pr_number + 1)'

    printf 'https://github.com/owner/repo/pull/%s\n' "$local_num"
    exit 0
  fi

  # -------------------------------------------------------------------------
  # gh pr edit <N> --add-label <label> | --remove-label <label>
  # -------------------------------------------------------------------------
  if [[ "$ACTION" == "edit" ]]; then
    local_num="$1"; shift
    op=""
    label=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --add-label)    op="add";    label="$2"; shift 2 ;;
        --remove-label) op="remove"; label="$2"; shift 2 ;;
        *)              shift ;;
      esac
    done

    if [[ "$op" == "add" ]]; then
      _write_state \
        --arg n "$local_num" --arg l "$label" \
        '.prs[$n].labels = ((.prs[$n].labels // []) + [$l] | unique)'
    elif [[ "$op" == "remove" ]]; then
      _write_state \
        --arg n "$local_num" --arg l "$label" \
        '.prs[$n].labels = ((.prs[$n].labels // []) | map(select(. != $l)))'
    fi

    printf 'https://github.com/owner/repo/pull/%s\n' "$local_num"
    exit 0
  fi

  # -------------------------------------------------------------------------
  # gh pr view <N> [--json <fields>] [--jq <expr>]
  # -------------------------------------------------------------------------
  if [[ "$ACTION" == "view" ]]; then
    local_num="$1"; shift
    json_fields=""
    jq_expr=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --json) json_fields="$2"; shift 2 ;;
        --jq)   jq_expr="$2";    shift 2 ;;
        *)      shift ;;
      esac
    done

    local_pr="$(jq --arg n "$local_num" '.prs[$n] // empty' "$GH_STATE_FILE")"
    if [[ -z "$local_pr" ]]; then
      echo "fake-gh.sh: PR #$local_num not found" >&2
      exit 1
    fi

    _apply_jq_output "$json_fields" "$jq_expr" "$local_pr"
    exit 0
  fi

  # -------------------------------------------------------------------------
  # gh pr merge <N> [--squash] [--delete-branch | -d]
  #
  # Simulates merge:
  #   - PR state → "merged"
  #   - Closes #N in body → issue state → "closed"
  #   - Deletes the remote branch (push --delete to origin)
  #
  # Note: the LOCAL branch is NOT deleted here. Real `gh pr merge --delete-branch`
  # deletes the remote branch and the local tracking ref, but cannot delete a
  # local branch that is currently checked out in a worktree (git refuses).
  # The archetype test pattern is: merge → remove worktree → then assert
  # assert_branch_deleted. e2e_remove_worktree handles the local branch cleanup.
  # -------------------------------------------------------------------------
  if [[ "$ACTION" == "merge" ]]; then
    local_num="$1"; shift
    # Consume remaining flags silently (--squash, --delete-branch, -d are accepted)
    while [[ $# -gt 0 ]]; do shift; done

    _pr_json="$(jq --arg n "$local_num" '.prs[$n] // empty' "$GH_STATE_FILE")"
    if [[ -z "$_pr_json" ]]; then
      echo "fake-gh.sh: PR #$local_num not found" >&2
      exit 1
    fi

    _head_branch="$(printf '%s' "$_pr_json" | jq -r '.head_branch')"
    _body="$(printf '%s' "$_pr_json" | jq -r '.body')"
    _timestamp="2026-05-22T00:00:00Z"

    # Mark PR merged
    _write_state \
      --arg n "$local_num" --arg ts "$_timestamp" \
      '.prs[$n].state = "merged" | .prs[$n].merged_at = $ts'

    # Auto-close issues referenced by Closes #N (case-insensitive)
    while IFS= read -r _issue_num; do
      [[ -z "$_issue_num" ]] && continue
      _write_state --arg n "$_issue_num" '.issues[$n].state = "closed"'
    done < <(printf '%s' "$_body" | grep -oiE 'closes[[:space:]]+#[0-9]+' | grep -oE '[0-9]+' || true)

    # Delete remote branch (fails silently if already gone or no sandbox configured)
    if [[ -n "$_head_branch" && "$_head_branch" != "null" ]]; then
      _sandbox_work="${SANDBOX_WORK:-}"
      if [[ -n "$_sandbox_work" ]]; then
        git -C "$_sandbox_work" push --quiet origin --delete "$_head_branch" 2>/dev/null || true
      fi
    fi

    printf 'Merged pull request #%s\n' "$local_num"
    exit 0
  fi

  # -------------------------------------------------------------------------
  # gh pr list [--state <s>] [--json <fields>] [--jq <expr>] [--limit <n>]
  # -------------------------------------------------------------------------
  if [[ "$ACTION" == "list" ]]; then
    filter_state="open"
    json_fields=""
    jq_expr=""
    limit=30

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --state|-s)  filter_state="$2"; shift 2 ;;
        --json)      json_fields="$2";  shift 2 ;;
        --jq)        jq_expr="$2";      shift 2 ;;
        --limit)     limit="$2";        shift 2 ;;
        *)           shift ;;
      esac
    done

    _list_result="$(jq \
      --arg s "$filter_state" \
      --argjson lim "$limit" \
      '[.prs[] |
        select($s == "all" or .state == $s)
      ] | .[:$lim]' \
      "$GH_STATE_FILE")"

    _apply_jq_output "$json_fields" "$jq_expr" "$_list_result"
    exit 0
  fi

  # -------------------------------------------------------------------------
  # gh pr comment <N> --body <text>
  # -------------------------------------------------------------------------
  if [[ "$ACTION" == "comment" ]]; then
    local_num="$1"; shift
    comment_body=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --body|-b) comment_body="$2"; shift 2 ;;
        *)         shift ;;
      esac
    done

    _write_state \
      --arg n "$local_num" --arg c "$comment_body" \
      '.prs[$n].comments = ((.prs[$n].comments // []) + [$c])'

    printf 'https://github.com/owner/repo/pull/%s#issuecomment-0\n' "$local_num"
    exit 0
  fi

  echo "fake-gh.sh: unknown pr action: $ACTION" >&2
  exit 1
fi

echo "fake-gh.sh: unknown noun: $NOUN (supported: issue, pr)" >&2
exit 1
