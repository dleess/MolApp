#!/usr/bin/env bash
# Install Ralph for Codex CLI into the current git repository.
#
# Usage:
#   bash install-ralph-codex.sh
#
# Then, from the target repository:
#   ./scripts/ralph/ralph.sh --tool codex 10

set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' was not found in PATH."
}

require_command git
require_command jq
require_command codex

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Run this installer from inside a git repository."
INSTALL_DIR="$REPO_ROOT/scripts/ralph"

if [ -e "$INSTALL_DIR" ]; then
  BACKUP_DIR="$REPO_ROOT/scripts/ralph.backup-$(date +%Y%m%d-%H%M%S)"
  echo "Existing scripts/ralph found. Backing up to: $BACKUP_DIR"
  mkdir -p "$(dirname "$BACKUP_DIR")"
  mv "$INSTALL_DIR" "$BACKUP_DIR"
fi

mkdir -p "$INSTALL_DIR"

cat > "$INSTALL_DIR/ralph.sh" <<'RALPH_SH'
#!/usr/bin/env bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [--tool amp|claude|codex] [max_iterations]

set -euo pipefail

TOOL="codex"
MAX_ITERATIONS=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)
      if [ $# -lt 2 ]; then
        echo "Error: --tool requires a value: amp, claude, or codex." >&2
        exit 1
      fi
      TOOL="${2:-}"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

if [[ "$TOOL" != "amp" && "$TOOL" != "claude" && "$TOOL" != "codex" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp', 'claude', or 'codex'." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Error: Ralph must be installed inside a git repository." >&2
  exit 1
}

PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"

command -v jq >/dev/null 2>&1 || {
  echo "Error: Required command 'jq' was not found in PATH." >&2
  exit 1
}

case "$TOOL" in
  amp)
    command -v amp >/dev/null 2>&1 || {
      echo "Error: Required command 'amp' was not found in PATH." >&2
      exit 1
    }
    [ -f "$SCRIPT_DIR/prompt.md" ] || {
      echo "Error: Missing $SCRIPT_DIR/prompt.md for Amp." >&2
      exit 1
    }
    ;;
  claude)
    command -v claude >/dev/null 2>&1 || {
      echo "Error: Required command 'claude' was not found in PATH." >&2
      exit 1
    }
    [ -f "$SCRIPT_DIR/CLAUDE.md" ] || {
      echo "Error: Missing $SCRIPT_DIR/CLAUDE.md for Claude Code." >&2
      exit 1
    }
    ;;
  codex)
    command -v codex >/dev/null 2>&1 || {
      echo "Error: Required command 'codex' was not found in PATH." >&2
      exit 1
    }
    [ -f "$SCRIPT_DIR/CODEX.md" ] || {
      echo "Error: Missing $SCRIPT_DIR/CODEX.md for Codex CLI." >&2
      exit 1
    }
    ;;
esac

if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH="$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")"
  LAST_BRANCH="$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")"

  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    DATE="$(date +%Y-%m-%d)"
    FOLDER_NAME="$(echo "$LAST_BRANCH" | sed 's|^ralph/||')"
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "Archived to: $ARCHIVE_FOLDER"

    {
      echo "# Ralph Progress Log"
      echo "Started: $(date)"
      echo "---"
    } > "$PROGRESS_FILE"
  fi
fi

if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH="$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")"
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

if [ ! -f "$PROGRESS_FILE" ]; then
  {
    echo "# Ralph Progress Log"
    echo "Started: $(date)"
    echo "---"
  } > "$PROGRESS_FILE"
fi

echo "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS"

for i in $(seq 1 "$MAX_ITERATIONS"); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"
  echo "==============================================================="

  if [[ "$TOOL" == "amp" ]]; then
    OUTPUT="$(amp --dangerously-allow-all < "$SCRIPT_DIR/prompt.md" 2>&1 | tee /dev/stderr)" || true
  elif [[ "$TOOL" == "claude" ]]; then
    OUTPUT="$(claude --dangerously-skip-permissions --print < "$SCRIPT_DIR/CLAUDE.md" 2>&1 | tee /dev/stderr)" || true
  else
    OUTPUT="$(codex exec \
      --dangerously-bypass-approvals-and-sandbox \
      --ask-for-approval never \
      --cd "$PROJECT_ROOT" \
      < "$SCRIPT_DIR/CODEX.md" 2>&1 | tee /dev/stderr)" || true
  fi

  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  fi

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
RALPH_SH

cat > "$INSTALL_DIR/CODEX.md" <<'CODEX_MD'
# Ralph Agent Instructions for Codex CLI

You are an autonomous Codex coding agent working on a software project.

## Files

- Project root: the git repository root passed to Codex with `--cd`.
- Ralph directory: `scripts/ralph` inside the project root.
- PRD file: `scripts/ralph/prd.json`.
- Progress log: `scripts/ralph/progress.txt`.

## Your Task

1. Read `scripts/ralph/prd.json`.
2. Read `scripts/ralph/progress.txt`, checking the `Codebase Patterns` section first if it exists.
3. Check you are on the correct branch from PRD `branchName`. If not, check it out or create it from the repository's main branch.
4. Pick the highest priority user story where `passes: false`.
5. Implement that single user story.
6. Run the project's quality checks, such as typecheck, lint, tests, builds, or the checks documented in the repo.
7. Update nearby `AGENTS.md` files only when you discover genuinely reusable project knowledge.
8. If checks pass, commit all changes with message: `feat: [Story ID] - [Story Title]`.
9. Update `scripts/ralph/prd.json` to set `passes: true` for the completed story.
10. Append your progress to `scripts/ralph/progress.txt`.

## Progress Report Format

Append to `scripts/ralph/progress.txt`; never replace the file.

```markdown
## [Date/Time] - [Story ID]
- What was implemented
- Files changed
- Quality checks run and results
- Browser verification result, if this was a frontend story
- **Learnings for future iterations:**
  - Patterns discovered
  - Gotchas encountered
  - Useful context
---
```

The learnings section is critical. Future Ralph iterations rely on git history, `progress.txt`, `prd.json`, and `AGENTS.md` for memory.

## Consolidate Patterns

If you discover a reusable pattern that future iterations should know, add it to a `## Codebase Patterns` section at the top of `scripts/ralph/progress.txt`. Create that section if it does not exist.

Only add patterns that are general and reusable. Do not add story-specific details or temporary debugging notes to this section.

## Update AGENTS.md Files

Before committing, check whether edited files have learnings worth preserving in nearby `AGENTS.md` files.

Good additions include:

- API patterns or conventions specific to a module
- Non-obvious requirements or gotchas
- Dependencies between files that must stay synchronized
- Testing approaches for that area
- Configuration or environment requirements

Do not add:

- Story-specific implementation details
- Temporary debugging notes
- Information already captured in `progress.txt`

## Quality Requirements

- All commits must pass the project's relevant quality checks.
- Do not commit broken code.
- Keep changes focused and minimal.
- Follow existing code patterns.
- Do not revert unrelated user changes.

## Browser Testing for Frontend Stories

For any story that changes UI, verify it in a browser when a browser-capable tool is available, such as Codex browser tooling, MCP browser tooling, or Playwright.

If browser tooling is unavailable, record in `scripts/ralph/progress.txt` that manual browser verification is needed and explain what should be checked.

## Stop Condition

After completing a user story, check whether all stories have `passes: true`.

If all stories are complete and passing, reply with:

```text
<promise>COMPLETE</promise>
```

If stories remain with `passes: false`, end your response normally so the next Ralph iteration can continue.

## Important

- Work on one story per iteration.
- Commit only after checks pass.
- Keep CI green.
- Read `Codebase Patterns` before starting each story.
CODEX_MD

cat > "$INSTALL_DIR/prd.json.example" <<'PRD_JSON'
{
  "project": "MyApp",
  "branchName": "ralph/task-priority",
  "description": "Task Priority System - Add priority levels to tasks",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add priority field to database",
      "description": "As a developer, I need to store task priority so it persists across sessions.",
      "acceptanceCriteria": [
        "Add priority column to tasks table: 'high' | 'medium' | 'low' (default 'medium')",
        "Generate and run migration successfully",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-002",
      "title": "Display priority indicator on task cards",
      "description": "As a user, I want to see task priority at a glance.",
      "acceptanceCriteria": [
        "Each task card shows colored priority badge (red=high, yellow=medium, gray=low)",
        "Priority visible without hovering or clicking",
        "Typecheck passes",
        "Verify in browser using Codex browser tooling, MCP browser tooling, or Playwright"
      ],
      "priority": 2,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-003",
      "title": "Add priority selector to task edit",
      "description": "As a user, I want to change a task's priority when editing it.",
      "acceptanceCriteria": [
        "Priority dropdown in task edit modal",
        "Shows current priority as selected",
        "Saves immediately on selection change",
        "Typecheck passes",
        "Verify in browser using Codex browser tooling, MCP browser tooling, or Playwright"
      ],
      "priority": 3,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-004",
      "title": "Filter tasks by priority",
      "description": "As a user, I want to filter the task list to see only high-priority items.",
      "acceptanceCriteria": [
        "Filter dropdown with options: All | High | Medium | Low",
        "Filter persists in URL params",
        "Empty state message when no tasks match filter",
        "Typecheck passes",
        "Verify in browser using Codex browser tooling, MCP browser tooling, or Playwright"
      ],
      "priority": 4,
      "passes": false,
      "notes": ""
    }
  ]
}
PRD_JSON

: > "$INSTALL_DIR/progress.txt"
chmod +x "$INSTALL_DIR/ralph.sh"

echo "Installed Ralph for Codex CLI into: $INSTALL_DIR"
echo ""
echo "Next steps:"
echo "  1. cp scripts/ralph/prd.json.example scripts/ralph/prd.json"
echo "  2. Edit scripts/ralph/prd.json for your project"
echo "  3. ./scripts/ralph/ralph.sh --tool codex 10"
