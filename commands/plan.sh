#!/usr/bin/env bash
#
# re plan - Show prompt for Claude to edit plan.md
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh" 2>/dev/null || {
    BOLD='\033[1m'
    DIM='\033[2m'
    CYAN='\033[0;36m'
    NC='\033[0m'
}

RALPH_DIR=".ralph"

usage() {
    cat << 'EOF'
re plan - Show prompt for Claude to edit plan.md

USAGE:
    re plan [options]

OPTIONS:
    -h, --help      Show this help

DESCRIPTION:
    Outputs a prompt you can copy to Claude to help edit or add to plan.md.
    Use this to:
    - Add new tasks/criteria
    - Move backlog items to active criteria
    - Update the implementation plan
EOF
}

show_plan_prompt() {
    # Check if .ralph exists
    if [[ ! -d "$RALPH_DIR" ]]; then
        echo -e "${RED:-}error:${NC} No .ralph directory. Run 're init' first."
        exit 1
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}Copy this prompt to Claude to edit plan.md${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
    cat << 'PROMPT'
Read .ralph/plan.md and help me update it.

I want to: [DESCRIBE CHANGES HERE]

═══════════════════════════════════════════════════════════════════════
CRITICAL STRUCTURE RULES (parser will break if violated):
═══════════════════════════════════════════════════════════════════════

The parser reads ONLY what's under "## Completion Criteria" and STOPS
at the next "##" heading. Everything after is IGNORED.

CORRECT structure:
```
## Completion Criteria        ← Parser starts here
### Section A                 ← Use ### for subsections (OK)
- [ ] 0. Task one
- [ ] 1. Task two
### Section B                 ← More ### subsections (OK)
- [ ] 2. Task three
### Context                   ← Even context can use ### if needed
...
## Backlog                    ← Parser stops here, backlog ignored
```

WRONG structure (tasks 145+ would be IGNORED):
```
## Completion Criteria
- [ ] 0. Task...
## Some Other Section         ← BREAKS PARSING! Use ### instead
- [ ] 145. Task...            ← This is NEVER seen by parser
```

═══════════════════════════════════════════════════════════════════════
RULES FOR ADDING/UPDATING TASKS:
═══════════════════════════════════════════════════════════════════════

1. STRUCTURE:
   - ALL numbered criteria go under "## Completion Criteria"
   - Use "### Subsection Name" to organize (NOT ##)
   - "## Backlog" goes at the END (items here are NOT worked on)

2. NUMBERING:
   - Format: "- [ ] N. Description" (N = number)
   - Start from 0, increment sequentially
   - Find highest existing number, add +1 for new tasks
   - NEVER duplicate numbers

3. DEDUPLICATION (important for AI agents iterating):
   - ALWAYS search existing criteria before adding
   - Check for similar wording, same files, same intent
   - If duplicate found, skip or merge with existing

4. CRITERIA QUALITY:
   - Make objectively verifiable
   - One atomic task per criterion
   - Reference specific files/lines when possible
   - Group by priority: (P0 - Critical), (P1 - High), (P2 - Medium)

5. PRESERVE:
   - Keep [x] items unchanged (they're done)
   - Don't renumber existing items

Do NOT implement - just update the plan file.
PROMPT
    echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
    echo ""

    # Show current plan summary if it exists
    if [[ -f "$RALPH_DIR/plan.md" ]]; then
        echo "Current plan.md summary:"
        echo ""

        # Count criteria (only numbered ones in Completion Criteria)
        local cnt_done cnt_todo cnt_backlog
        cnt_done=$(grep -cE "^- \[x\] [0-9]+\." "$RALPH_DIR/plan.md" 2>/dev/null) || cnt_done=0
        cnt_todo=$(grep -cE "^- \[ \] [0-9]+\." "$RALPH_DIR/plan.md" 2>/dev/null) || cnt_todo=0
        cnt_backlog=$(grep -cE "^- \[ \] (BLOCKED|FUTURE|NEEDS_INPUT):" "$RALPH_DIR/plan.md" 2>/dev/null) || cnt_backlog=0

        printf "  ✓ Done:    %d\n" "$cnt_done"
        printf "  ○ Todo:    %d\n" "$cnt_todo"
        printf "  ◌ Backlog: %d\n" "$cnt_backlog"
        echo ""
    fi
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    *)
        show_plan_prompt
        ;;
esac
