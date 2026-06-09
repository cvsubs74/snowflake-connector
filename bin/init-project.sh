#!/usr/bin/env bash
# init-project.sh — replace {{PLACEHOLDERS}} in CLAUDE.md and agent files
# with project-specific values. Run once after cloning claude-workflow into a new repo.

set -euo pipefail

# Where we are
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "==> claude-workflow project initializer"
echo "    Repo root: $REPO_ROOT"
echo

# Detect existing values
DEFAULT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo main)"
DEFAULT_REPO_NAME="$(basename "$REPO_ROOT")"

# Try to detect github remote
DEFAULT_GITHUB_REPO=""
if git remote get-url origin >/dev/null 2>&1; then
  REMOTE_URL="$(git remote get-url origin)"
  # Strip prefix/suffix to get owner/repo
  DEFAULT_GITHUB_REPO="$(echo "$REMOTE_URL" \
    | sed -E 's|^git@github.com:||; s|^https?://github.com/||; s|\.git$||')"
fi

# Prompt for each value
read -rp "Project name (human-readable) [$DEFAULT_REPO_NAME]: " PROJECT_NAME
PROJECT_NAME="${PROJECT_NAME:-$DEFAULT_REPO_NAME}"

read -rp "GitHub repo (owner/name) [$DEFAULT_GITHUB_REPO]: " GITHUB_REPO
GITHUB_REPO="${GITHUB_REPO:-$DEFAULT_GITHUB_REPO}"

read -rp "Default branch [$DEFAULT_BRANCH]: " DEFAULT_BRANCH_INPUT
DEFAULT_BRANCH="${DEFAULT_BRANCH_INPUT:-$DEFAULT_BRANCH}"

read -rp "Test command (or leave blank to fill in later): " TEST_COMMAND
read -rp "Lint command (or leave blank to fill in later): " LINT_COMMAND
read -rp "Dev server command (or leave blank to fill in later): " DEV_COMMAND
read -rp "Deploy command (or leave blank to fill in later): " DEPLOY_COMMAND

echo
echo "==> Will replace:"
echo "    {{PROJECT_NAME}}     -> $PROJECT_NAME"
echo "    {{GITHUB_REPO}}      -> $GITHUB_REPO"
echo "    {{DEFAULT_BRANCH}}   -> $DEFAULT_BRANCH"
echo "    {{TEST_COMMAND}}     -> ${TEST_COMMAND:-<blank>}"
echo "    {{LINT_COMMAND}}     -> ${LINT_COMMAND:-<blank>}"
echo "    {{DEV_COMMAND}}      -> ${DEV_COMMAND:-<blank>}"
echo "    {{DEPLOY_COMMAND}}   -> ${DEPLOY_COMMAND:-<blank>}"
echo
read -rp "Proceed? [y/N]: " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted."
  exit 1
fi

# Files that may have placeholders
FILES=(
  "CLAUDE.md"
  ".claude/agents/team-lead-agent.md"
  ".claude/commands/onboard-team.md"
)

# sed -i differs between macOS and Linux
SED_INPLACE=(-i '')
if sed --version >/dev/null 2>&1; then
  # GNU sed
  SED_INPLACE=(-i)
fi

replace() {
  local placeholder="$1"
  local value="$2"
  # Skip if value is empty — leaves the placeholder in place so users see what's missing
  if [[ -z "$value" ]]; then
    return
  fi
  local esc
  esc="$(printf '%s' "$value" | sed -e 's/[\/&|]/\\&/g')"
  for f in "${FILES[@]}"; do
    if [[ -f "$f" ]]; then
      sed "${SED_INPLACE[@]}" -E "s|\{\{$placeholder\}\}|$esc|g" "$f"
    fi
  done
}

replace "PROJECT_NAME" "$PROJECT_NAME"
replace "GITHUB_REPO" "$GITHUB_REPO"
replace "DEFAULT_BRANCH" "$DEFAULT_BRANCH"
replace "TEST_COMMAND" "$TEST_COMMAND"
replace "LINT_COMMAND" "$LINT_COMMAND"
replace "DEV_COMMAND" "$DEV_COMMAND"
replace "DEPLOY_COMMAND" "$DEPLOY_COMMAND"

# Rename ARCHITECTURE.md.template if user wants
if [[ -f "docs/ARCHITECTURE.md.template" && ! -f "docs/ARCHITECTURE.md" ]]; then
  read -rp "Create docs/ARCHITECTURE.md from the template? [Y/n]: " CREATE_ARCH
  if [[ "$CREATE_ARCH" != "n" && "$CREATE_ARCH" != "N" ]]; then
    cp docs/ARCHITECTURE.md.template docs/ARCHITECTURE.md
    echo "    Created docs/ARCHITECTURE.md (template) — fill in for your project"
  fi
fi

# Seed settings.local.json from template
if [[ -f ".claude/settings.local.json.template" && ! -f ".claude/settings.local.json" ]]; then
  read -rp "Seed .claude/settings.local.json from the template? [Y/n]: " SEED_LOCAL
  if [[ "$SEED_LOCAL" != "n" && "$SEED_LOCAL" != "N" ]]; then
    cp .claude/settings.local.json.template .claude/settings.local.json
    echo "    Created .claude/settings.local.json (per-developer, gitignored)"
  fi
fi

# -----------------------------------------------------------------------------
# Wire up the GitHub remote. After `rm -rf .git && git init`, there is no
# origin — but the whole team workflow (PRs, labels, issue coordination) runs on
# GitHub, so a remote repo is required. Offer to create it and push an initial
# commit so `main` exists remotely. Must run BEFORE label bootstrap, which needs
# the repo to already exist.
# -----------------------------------------------------------------------------
if [[ -n "$GITHUB_REPO" ]] && ! git remote get-url origin >/dev/null 2>&1; then
  echo
  echo "==> No 'origin' remote detected. Agents coordinate entirely through"
  echo "    GitHub issues/PRs, so a remote repo is required."
  if command -v gh >/dev/null 2>&1; then
    read -rp "Create github.com/$GITHUB_REPO and push the initial commit? [Y/n]: " CREATE_REMOTE
    if [[ "$CREATE_REMOTE" != "n" && "$CREATE_REMOTE" != "N" ]]; then
      # gh repo create --push needs at least one commit on the branch.
      if ! git rev-parse HEAD >/dev/null 2>&1; then
        git add -A
        git commit -m "chore: scaffold from claude-workflow template" >/dev/null
      fi
      gh repo create "$GITHUB_REPO" --private --source=. --remote=origin --push
    fi
  else
    echo "    gh CLI not found. Install it, then run:"
    echo "      gh repo create $GITHUB_REPO --private --source=. --remote=origin --push"
  fi
fi

# Offer to bootstrap labels via gh CLI (delegates to bin/bootstrap-labels.sh,
# which is also runnable standalone for recovery).
if command -v gh >/dev/null 2>&1 && [[ -n "$GITHUB_REPO" ]]; then
  echo
  read -rp "Bootstrap GitHub labels (bug, enhancement, backlog, prioritized, ...) on $GITHUB_REPO? [Y/n]: " BOOTSTRAP_LABELS
  if [[ "$BOOTSTRAP_LABELS" != "n" && "$BOOTSTRAP_LABELS" != "N" ]]; then
    "$SCRIPT_DIR/bootstrap-labels.sh" "$GITHUB_REPO"
  fi
fi

# -----------------------------------------------------------------------------
# Sanity-check the Anthropic-engineering-derived scaffolds are present.
# These ship as part of the template — surface missing ones so a partial
# checkout doesn't silently lose capability.
# -----------------------------------------------------------------------------
echo
echo "==> Sanity-checking shipped scaffolds..."
MISSING=()
for path in \
    memory \
    evals/tasks \
    evals/graders \
    evals/harness/eval_runner.py \
    evals/prod_monitor \
    docs/contracts \
    docs/contracts/_template.md \
    docs/tool-design.md \
    tools \
    mcp/servers \
    mcp/Makefile \
    .mcp.json \
    auto-mode.yaml \
    sandbox.json \
    .claude/skills/eval-runner \
    .claude/skills/quality-monitor \
    .claude/skills/harness-mapping \
    .claude/skills/contract-negotiation \
    .claude/skills/think-tool-wiring \
    .claude/skills/safety-layering \
    .claude/skills/tool-design \
    .claude/skills/swarm-dispatch \
    .claude/skills/research-burst \
    .claude/agents/research-agent.md \
    .claude/agents/citation-agent.md \
    .claude/commands/eval.md \
    .claude/commands/swarm.md \
    .claude/commands/research.md \
    .claude/hooks/workaround-audit.sh \
    .claude/hooks/system-prompt-audit.sh \
    .claude/hooks/verification-gate.sh \
    .claude/hooks/session-opener.sh \
    .claude/hooks/deploy-reminder.sh ; do
  [[ -e "$path" ]] || MISSING+=("$path")
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
  echo "    All scaffolds present."
else
  echo "    [!] Missing ${#MISSING[@]} scaffold(s) — partial template?"
  for m in "${MISSING[@]}"; do echo "      - $m"; done
  echo "    Re-clone or re-pull the claude-workflow template to recover."
fi

# -----------------------------------------------------------------------------
# Initialize an empty `bin/init.sh` if the project doesn't have one.
# Required by the session-opener hook's "Step 3 — Smoke test" suggestion.
# -----------------------------------------------------------------------------
if [[ ! -e "bin/init.sh" ]]; then
  echo
  read -rp "Create a stub bin/init.sh (boots dev server + runs smoke)? [Y/n]: " CREATE_INIT
  if [[ "$CREATE_INIT" != "n" && "$CREATE_INIT" != "N" ]]; then
    cat > bin/init.sh <<'EOF'
#!/usr/bin/env bash
# bin/init.sh — boot the dev environment and run an end-to-end smoke check.
# Called by the session-opener hook's "Step 3". Fill in for your project.
set -euo pipefail

echo "==> [stub] Boot dev server here, e.g.:"
echo "    npm run dev &  # or: cargo run, or: docker compose up -d"
echo
echo "==> [stub] Run smoke check here, e.g.:"
echo "    curl -fsSL http://localhost:3000/health"
echo
echo "Edit bin/init.sh and remove this stub when ready."
EOF
    chmod +x bin/init.sh
    echo "    Created bin/init.sh (stub) — fill in for your project."
  fi
fi

echo
echo "==> Done."
echo
echo "Next steps:"
echo "  1. Review CLAUDE.md — fill in 'Architecture in one paragraph' and any remaining commands."
echo "  2. Review auto-mode.yaml + sandbox.json — adjust trusted_domains and block_rules for your stack."
echo "  3. Review .mcp.json — keep Playwright + GitHub, add product-specific MCPs as needed."
echo "  4. Populate memory/PROGRESS.md with the first goal."
echo "  5. Add the project's first eval task at evals/tasks/<domain>/<name>.yaml (see evals/README.md)."
echo "  6. Open Claude Code: claude"
echo "  7. Spawn the team: /onboard-team"
