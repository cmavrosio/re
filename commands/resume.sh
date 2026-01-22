#!/usr/bin/env bash
#
# re resume - Resume a paused session
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh"

RALPH_DIR=".ralph"

usage() {
    cat << 'EOF'
re resume - Resume a paused session

USAGE:
    re resume [options]

OPTIONS:
    --reset-health    Reset health counters before resuming
    -h, --help        Show this help

DESCRIPTION:
    Resumes a paused or stopped session by restarting the iteration loop.
EOF
}

resume_session() {
    local reset_health=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reset-health)
                reset_health=true
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

    require_active_session

    local status
    status=$(read_frontmatter "$RALPH_DIR/state.md" "status")

    # Check if loop is actually running when status says "running"
    if [[ "$status" == "running" ]]; then
        local loop_running=false
        if [[ -f "$RALPH_DIR/.loop.pid" ]]; then
            local pid
            pid=$(cat "$RALPH_DIR/.loop.pid" 2>/dev/null)
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                loop_running=true
            fi
        fi
        if [[ "$loop_running" == "false" ]]; then
            status="crashed"
        fi
    fi

    case "$status" in
        running)
            log_error "Session is already running"
            exit 1
            ;;
        crashed)
            log_warn "Session crashed - resuming"
            ;;
        completed)
            log_error "Session is completed. Start a new session with 're start'."
            exit 1
            ;;
        paused|verify|aborted|initialized)
            log_info "Resuming session from status: $status"
            ;;
        *)
            log_warn "Unknown status: $status. Attempting to resume."
            ;;
    esac

    # Optionally reset health
    if [[ "$reset_health" == "true" ]]; then
        log_info "Resetting health counters"
        bb --classpath "$RE_HOME/lib" -m brain.circuit-breaker reset "$RALPH_DIR"
    fi

    # Clear urgent message if it was addressed
    if [[ -f "$RALPH_DIR/urgent.md" ]]; then
        log_info "Clearing previous urgent message"
        rm -f "$RALPH_DIR/urgent.md"
    fi

    log_success "Resuming session"

    # Start the loop
    exec bash "$RE_HOME/commands/loop.sh"
}

resume_session "$@"
