#!/usr/bin/env bash
#
# re abort - Abort current session
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh"

RALPH_DIR=".ralph"

usage() {
    cat << 'EOF'
re abort - Abort current session

USAGE:
    re abort [options]

OPTIONS:
    -h, --help        Show this help

DESCRIPTION:
    Aborts the current session and stops the loop.
    Use 're start' to begin a new session.
EOF
}

abort_session() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
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

    require_active_session

    local session_id
    session_id=$(read_frontmatter "$RALPH_DIR/state.md" "session_id")
    local status
    status=$(read_frontmatter "$RALPH_DIR/state.md" "status")

    if [[ "$status" == "aborted" ]]; then
        log_warn "Session is already aborted"
    fi

    # Kill running loop process and all children (including claude)
    if [[ -f "$RALPH_DIR/.loop.pid" ]]; then
        local loop_pid
        loop_pid=$(cat "$RALPH_DIR/.loop.pid" 2>/dev/null)
        if [[ -n "$loop_pid" ]] && kill -0 "$loop_pid" 2>/dev/null; then
            log_info "Killing loop process and children (PID: $loop_pid)..."
            # Kill all child processes first (including claude)
            pkill -TERM -P "$loop_pid" 2>/dev/null || true
            # Also kill any claude processes that might be grandchildren
            pkill -TERM -f "claude.*--print.*--dangerously-skip-permissions" 2>/dev/null || true
            sleep 0.5
            # Then kill the loop itself
            kill -TERM "$loop_pid" 2>/dev/null || true
            sleep 0.5
            # Force kill if still running
            if kill -0 "$loop_pid" 2>/dev/null; then
                pkill -KILL -P "$loop_pid" 2>/dev/null || true
                kill -KILL "$loop_pid" 2>/dev/null || true
            fi
        fi
        rm -f "$RALPH_DIR/.loop.pid"
    fi
    # Final cleanup: kill any orphaned claude processes for this directory
    pkill -TERM -f "claude.*--print.*--dangerously-skip-permissions" 2>/dev/null || true

    log_info "Aborting session $session_id"

    # Update status
    sed -i.bak "s/^status: .*/status: aborted/" "$RALPH_DIR/state.md"
    rm -f "$RALPH_DIR/state.md.bak"

    log_success "Session aborted"
    echo ""
    echo "To start fresh: re start"
}

abort_session "$@"
