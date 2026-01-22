#!/usr/bin/env bash
#
# re init - Initialize a new .ralph/ directory
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh" 2>/dev/null || {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
    log_error() { echo -e "${RED}error:${NC} $1" >&2; }
    log_info() { echo -e "${BLUE}info:${NC} $1"; }
    log_success() { echo -e "${GREEN}success:${NC} $1"; }
    log_warn() { echo -e "${YELLOW}warn:${NC} $1"; }
}

RALPH_DIR=".ralph"

usage() {
    cat << 'EOF'
re init - Initialize a new .ralph/ directory

USAGE:
    re init [options]

OPTIONS:
    -f, --force     Overwrite existing .ralph/ directory
    -h, --help      Show this help message

DESCRIPTION:
    Creates the .ralph/ directory structure with template files.
    Edit .ralph/plan.md to define your task, then run 're start'.
EOF
}

init_ralph() {
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force)
                force=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Check if .ralph already exists
    if [[ -d "$RALPH_DIR" ]]; then
        if [[ "$force" == "true" ]]; then
            log_warn "Removing existing $RALPH_DIR directory"
            rm -rf "$RALPH_DIR"
        else
            log_error "$RALPH_DIR already exists. Use --force to overwrite."
            exit 1
        fi
    fi

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not a git repository. Please run 're init' in a git repository."
        exit 1
    fi

    log_info "Initializing $RALPH_DIR directory..."

    # Create directory structure
    mkdir -p "$RALPH_DIR"/{context/iterations,diff,tokens,tests,logs}

    # Copy templates
    cp "$RE_HOME/templates/plan.template.md" "$RALPH_DIR/plan.md"
    cp "$RE_HOME/templates/config.template.yaml" "$RALPH_DIR/config.yaml"
    cp "$RE_HOME/templates/rules.template.md" "$RALPH_DIR/rules.md"
    cp "$RE_HOME/templates/docs.template.md" "$RALPH_DIR/docs.md"

    # Create empty files
    touch "$RALPH_DIR/context/summary.md"
    touch "$RALPH_DIR/logs/re.log"

    # Create initial health.yaml
    cat > "$RALPH_DIR/health.yaml" << 'EOF'
consecutive_errors: 0
consecutive_no_change: 0
last_error: null
last_success: null
EOF

    # Create initial tokens/usage.md
    cat > "$RALPH_DIR/tokens/usage.md" << 'EOF'
# Token Usage

| Iteration | Input | Output | Total | Cumulative |
|-----------|-------|--------|-------|------------|
EOF

    # Add .ralph to .gitignore if not already there
    if [[ -f ".gitignore" ]]; then
        if ! grep -q "^\.ralph/$" .gitignore 2>/dev/null; then
            echo "" >> .gitignore
            echo "# re (ralph enhanced) working directory" >> .gitignore
            echo ".ralph/" >> .gitignore
            log_info "Added .ralph/ to .gitignore"
        fi
    else
        cat > .gitignore << 'EOF'
# re (ralph enhanced) working directory
.ralph/
EOF
        log_info "Created .gitignore with .ralph/"
    fi

    log_success "Initialized $RALPH_DIR directory"
    echo ""
    echo "Next steps:"
    echo "  1. Edit $RALPH_DIR/plan.md to define your task"
    echo "  2. Edit $RALPH_DIR/rules.md with project guidelines"
    echo "  3. Optionally edit $RALPH_DIR/config.yaml"
    echo "  4. Run 're start' to begin"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}TIP: Ask Claude to populate plan.md${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Copy this prompt to Claude:"
    echo ""
    echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
    cat << 'PROMPT'
Read .ralph/plan.md and understand the format. Then help me define a task.

I want to: [DESCRIBE YOUR TASK HERE]

Update .ralph/plan.md with:
1. A clear task description
2. Numbered completion criteria (checkboxes that can be verified)
3. An implementation plan with steps
4. Relevant context about the codebase

Rules for completion criteria:
- Number them starting from 0 (e.g., "- [ ] 0. First task")
- Make them objectively verifiable (tests pass, file exists, etc.)
- Last criterion should usually be "All tests pass: [test command]"
- Keep to 5-10 criteria max
- If some criteria are already [x] checked, those were completed in previous sessions

Do NOT start the task yet - just populate the plan file.
PROMPT
    echo -e "${DIM}────────────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

init_ralph "$@"
