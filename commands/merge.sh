#!/usr/bin/env bash
#
# re merge - Finalize completed session
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh"

RALPH_DIR=".ralph"

usage() {
    cat << 'EOF'
re merge - Finalize completed session

USAGE:
    re merge [options]

OPTIONS:
    --force           Finalize even if session isn't marked complete
    --from-archive    Sync completed criteria from latest archived session to plan.md
    -h, --help        Show this help

DESCRIPTION:
    Finalizes a completed session:
    1. Syncs completion status from state.md to plan.md
    2. Archives session files
    3. Resets for next session

EXAMPLES:
    re merge              # Finalize completed session
    re merge --force      # Finalize even if not complete
    re merge --from-archive  # Sync from archived session to plan.md
EOF
}

merge_from_archive() {
    require_ralph_dir

    # Find latest archive
    local latest_archive
    latest_archive=$(ls -t "$RALPH_DIR/archive" 2>/dev/null | head -1)

    if [[ -z "$latest_archive" ]]; then
        log_error "No archived sessions found"
        exit 1
    fi

    local archive_state="$RALPH_DIR/archive/$latest_archive/state.md"
    if [[ ! -f "$archive_state" ]]; then
        log_error "No state.md in archive: $latest_archive"
        exit 1
    fi

    log_info "Syncing from archive: $latest_archive"

    # Extract checked criteria numbers from archived state.md
    local completed_nums
    completed_nums=$(grep -oE "^- \[x\] [0-9]+" "$archive_state" 2>/dev/null | grep -oE "[0-9]+" || true)

    if [[ -z "$completed_nums" ]]; then
        log_info "No completed criteria found in archive"
        exit 0
    fi

    # Update plan.md checkboxes for each completed criterion
    local count=0
    for num in $completed_nums; do
        if grep -q "^- \[ \] ${num}\." "$RALPH_DIR/plan.md" 2>/dev/null; then
            sed -i.bak "s/^- \[ \] ${num}\./- [x] ${num}./" "$RALPH_DIR/plan.md"
            count=$((count + 1))
        fi
    done
    rm -f "$RALPH_DIR/plan.md.bak"

    log_success "Synced $count criteria from archive to plan.md"
}

merge_session() {
    local force=false
    local from_archive=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force=true
                shift
                ;;
            --from-archive)
                from_archive=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    if [[ "$from_archive" == "true" ]]; then
        merge_from_archive
        return
    fi

    require_active_session

    # Get session info
    local status
    status=$(read_frontmatter "$RALPH_DIR/state.md" "status")
    local session_id
    session_id=$(read_frontmatter "$RALPH_DIR/state.md" "session_id")

    # Check status
    if [[ "$status" != "completed" && "$force" != "true" ]]; then
        log_error "Session is not completed (status: $status)"
        echo "Use --force to finalize anyway."
        exit 1
    fi

    log_info "Finalizing session $session_id..."

    # Sync completion status from state.md to plan.md
    log_info "Updating plan.md with completion status..."
    if [[ -f "$RALPH_DIR/state.md" && -f "$RALPH_DIR/plan.md" ]]; then
        # Extract checked criteria numbers from state.md
        local completed_nums
        completed_nums=$(grep -oE "^- \[x\] [0-9]+" "$RALPH_DIR/state.md" 2>/dev/null | grep -oE "[0-9]+" || true)

        # Update plan.md checkboxes for each completed criterion
        for num in $completed_nums; do
            # Replace [ ] with [x] for this criterion number
            sed -i.bak "s/^- \[ \] ${num}\./- [x] ${num}./" "$RALPH_DIR/plan.md"
        done
        rm -f "$RALPH_DIR/plan.md.bak"

        # Add completion timestamp as comment
        echo "" >> "$RALPH_DIR/plan.md"
        echo "<!-- Session $session_id completed $(date -u +%Y-%m-%dT%H:%M:%SZ) -->" >> "$RALPH_DIR/plan.md"

        local count
        count=$(echo "$completed_nums" | wc -w | tr -d ' ')
        log_success "plan.md updated with $count completed criteria"
    fi

    # Archive the session
    local archive_dir="$RALPH_DIR/archive/$(date +%Y%m%d_%H%M%S)_${session_id}"
    mkdir -p "$archive_dir"

    # Move session files to archive
    mv "$RALPH_DIR/state.md" "$archive_dir/"
    mv "$RALPH_DIR/context" "$archive_dir/" 2>/dev/null || true
    mv "$RALPH_DIR/signals.yaml" "$archive_dir/" 2>/dev/null || true
    mv "$RALPH_DIR/decision.yaml" "$archive_dir/" 2>/dev/null || true
    mv "$RALPH_DIR/tokens" "$archive_dir/" 2>/dev/null || true
    mv "$RALPH_DIR/diff" "$archive_dir/" 2>/dev/null || true
    mv "$RALPH_DIR/tests" "$archive_dir/" 2>/dev/null || true

    # Recreate empty directories
    mkdir -p "$RALPH_DIR"/{context/iterations,diff,tokens,tests}

    # Reset health
    bb --classpath "$RE_HOME/lib" -m brain.circuit-breaker reset "$RALPH_DIR" 2>/dev/null || true

    log_success "Session archived to $archive_dir"

    # Commit all changes
    log_info "Committing changes..."
    if bash "$RE_HOME/lib/orchestration/git.sh" has-changes 2>/dev/null; then
        git add -A
        git commit -m "[re] Session $session_id completed" || true
        log_success "Changes committed"
    else
        log_info "No uncommitted changes to commit"
    fi

    echo ""
    echo "Session finalized. Ready for next task."
    echo ""
    echo "Next steps:"
    echo "  re plan                 # Update plan.md with new tasks"
    echo "  re start                # Start new session"
}

merge_session "$@"
