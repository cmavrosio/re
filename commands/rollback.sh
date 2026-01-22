#!/usr/bin/env bash
#
# re rollback - Rollback to a previous state
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh"

RALPH_DIR=".ralph"

usage() {
    cat << 'EOF'
re rollback - Rollback to a previous state

USAGE:
    re rollback [options] [target]

ARGUMENTS:
    target    Number of commits to rollback, or commit hash
              Default: 1 (last commit)

OPTIONS:
    --hard        Hard reset (discard all changes)
    --soft        Soft reset (keep changes staged)
    --iteration N Rollback to specific iteration
    -h, --help    Show this help

EXAMPLES:
    re rollback           # Rollback 1 commit
    re rollback 3         # Rollback 3 commits
    re rollback abc123    # Rollback to specific commit
    re rollback --iteration 5  # Rollback to iteration 5
EOF
}

rollback() {
    local target="1"
    local mode="hard"
    local iteration=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hard)
                mode="hard"
                shift
                ;;
            --soft)
                mode="soft"
                shift
                ;;
            --iteration)
                iteration="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                target="$1"
                shift
                ;;
        esac
    done

    require_active_session

    # If rolling back to iteration, find the commit
    if [[ -n "$iteration" ]]; then
        log_info "Finding commit for iteration $iteration..."
        local commit
        # Try new format first, then legacy format
        commit=$(git log --oneline --grep="iteration $iteration)" -1 --format="%H" || true)
        if [[ -z "$commit" ]]; then
            commit=$(git log --oneline --grep="\[re:$iteration\]" -1 --format="%H" || true)
        fi

        if [[ -z "$commit" ]]; then
            log_error "Could not find commit for iteration $iteration"
            exit 1
        fi

        target="$commit"
        log_info "Found commit: $commit"
    fi

    # Perform rollback
    log_warn "Rolling back to: $target (mode: $mode)"

    if [[ "$target" =~ ^[0-9]+$ ]]; then
        # Numeric target = number of commits
        if [[ "$mode" == "hard" ]]; then
            git reset --hard "HEAD~$target"
        else
            git reset --soft "HEAD~$target"
        fi
    else
        # Commit hash
        if [[ "$mode" == "hard" ]]; then
            git reset --hard "$target"
        else
            git reset --soft "$target"
        fi
    fi

    # Update state iteration count
    local current_iter
    current_iter=$(read_frontmatter "$RALPH_DIR/state.md" "iteration")
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        local new_iter=$((current_iter - target))
        if [[ $new_iter -lt 0 ]]; then new_iter=0; fi
        sed -i.bak "s/^iteration: .*/iteration: $new_iter/" "$RALPH_DIR/state.md"
        rm -f "$RALPH_DIR/state.md.bak"
        log_info "Updated iteration count: $current_iter -> $new_iter"
    fi

    # Reset health counters
    log_info "Resetting health counters..."
    bb --classpath "$RE_HOME/lib" -m brain.circuit-breaker reset "$RALPH_DIR"

    log_success "Rollback complete"
    echo ""
    echo "Current commit: $(git rev-parse --short HEAD)"
    echo "To continue: re resume"
}

rollback "$@"
