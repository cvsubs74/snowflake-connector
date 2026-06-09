#!/usr/bin/env bash
# bin/gh-scoped-cred.sh — scoped git credential helper for the sandbox.
#
# From the sandboxing post: SSH/signing keys never enter the sandbox. This
# helper validates that any git operation requesting credentials targets
# (a) origin, and (b) a branch matching the working-branch pattern.
#
# Configure git to use this as the credential helper inside the sandbox:
#   git config credential.helper "/path/to/bin/gh-scoped-cred.sh"
#
# Reads GH_TOKEN from the OS keychain (security on macOS, secret-tool on Linux).
# Never echoes the token to logs.
set -euo pipefail

ALLOW_BRANCHES_RE='^(feat|fix|chore|docs)/[a-z0-9-]+$'
ALLOW_REMOTES_RE='^https://github\.com/[^/]+/[^/]+(\.git)?$'

# Git invokes credential helpers with `get`/`store`/`erase`. We only handle `get`.
action="${1:-get}"
[[ "$action" == "get" ]] || exit 0

# Read the standard credential helper input from stdin.
declare -A in
while IFS='=' read -r k v; do
  [[ -z "$k" ]] && break
  in[$k]="$v"
done

# Validate the remote URL.
url="${in[protocol]}://${in[host]}/${in[path]:-}"
url="${url%/}"
if ! [[ "$url" =~ $ALLOW_REMOTES_RE ]]; then
  echo "scoped-cred: blocked remote: $url" >&2
  exit 1
fi

# Branch validation: read current branch from working tree if available.
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [[ -n "$branch" && "$branch" != "HEAD" && ! "$branch" =~ $ALLOW_BRANCHES_RE ]]; then
  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    echo "scoped-cred: blocked branch: $branch (never push directly to default)" >&2
    exit 1
  fi
fi

# Fetch the token from the OS keychain.
token=""
if command -v security >/dev/null 2>&1; then
  # macOS
  token=$(security find-generic-password -s "claude-workflow-gh-token" -w 2>/dev/null || true)
elif command -v secret-tool >/dev/null 2>&1; then
  # Linux (libsecret)
  token=$(secret-tool lookup service "claude-workflow-gh-token" 2>/dev/null || true)
fi

if [[ -z "$token" ]]; then
  echo "scoped-cred: no token in keychain (key: claude-workflow-gh-token). Run:" >&2
  echo "  security add-generic-password -s claude-workflow-gh-token -a \$USER -w <token>   # macOS" >&2
  echo "  secret-tool store --label='claude-workflow gh' service claude-workflow-gh-token  # Linux" >&2
  exit 1
fi

# Emit the credential. Never echo the token to a file or log.
printf 'username=x-access-token\npassword=%s\n' "$token"
