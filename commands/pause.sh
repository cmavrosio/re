#!/usr/bin/env bash
#
# re pause - Pause session after current iteration
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh"

RALPH_DIR=".ralph"

usage() {
    cat << 'EOF'
re pause - Pause session after current iteration

USAGE:
    re pause [options]

OPTIONS:
    --immediate     Don't wait for current iteration (same as abort)
    -h, --help      Show this help

DESCRIPTION:
    Sets a flag that tells the loop to pause after the current iteration
    completes. Use 're resume' to continue.
EOF
}

pause_session() {
    local immediate=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --immediate)
                immediate=true
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

    require_ralph_dir

    if [[ ! -f "$RALPH_DIR/state.md" ]]; then
        log_error "No active session"
        exit 1
    fi

    local status
    status=$(read_frontmatter "$RALPH_DIR/state.md" "status")

    if [[ "$status" != "running" ]]; then
        log_warn "Session is not running (status: $status)"
        exit 0
    fi

    if [[ "$immediate" == "true" ]]; then
        # Kill loop process and all children (including claude)
        if [[ -f "$RALPH_DIR/.loop.pid" ]]; then
            local loop_pid
            loop_pid=$(cat "$RALPH_DIR/.loop.pid" 2>/dev/null)
            if [[ -n "$loop_pid" ]] && kill -0 "$loop_pid" 2>/dev/null; then
                log_info "Stopping loop process and children..."
                # Kill all child processes first (including claude)
                pkill -TERM -P "$loop_pid" 2>/dev/null || true
                # Also kill any claude processes that might be grandchildren
                pkill -TERM -f "claude.*--print.*--dangerously-skip-permissions" 2>/dev/null || true
                sleep 0.5
                # Then kill the loop itself
                kill -TERM "$loop_pid" 2>/dev/null || true
            fi
            rm -f "$RALPH_DIR/.loop.pid"
        fi
        # Update status
        sed -i.bak "s/^status: .*/status: paused/" "$RALPH_DIR/state.md"
        rm -f "$RALPH_DIR/state.md.bak"
        log_success "Session paused immediately"
    else
        # Create pause flag file - loop will check this
        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$RALPH_DIR/.pause_requested"
        log_success "Pause requested - will pause after current iteration"
        echo ""
        echo "The session will pause after the current iteration completes."
        echo "Use 're resume' to continue when ready."
    fi
}

pause_session "$@"
