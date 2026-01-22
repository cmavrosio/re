#!/usr/bin/env bash
#
# re status - Show current session status
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh"

RALPH_DIR=".ralph"

usage() {
    cat << 'EOF'
re status - Show current session status

USAGE:
    re status [options]

OPTIONS:
    --json          Output as JSON
    --brief         Show only status line
    -h, --help      Show this help
EOF
}

show_status() {
    local format="full"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                format="json"
                shift
                ;;
            --brief)
                format="brief"
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
        if [[ "$format" == "brief" ]]; then
            echo "no session"
        elif [[ "$format" == "json" ]]; then
            echo '{"status": "no_session"}'
        else
            echo "No active session."
            echo "Run 're start' to begin a new task."
        fi
        exit 0
    fi

    # Read state
    local session_id
    session_id=$(read_frontmatter "$RALPH_DIR/state.md" "session_id")
    local status
    status=$(read_frontmatter "$RALPH_DIR/state.md" "status")
    local iteration
    iteration=$(read_frontmatter "$RALPH_DIR/state.md" "iteration")
    local started_at
    started_at=$(read_frontmatter "$RALPH_DIR/state.md" "started_at")

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

    # Count criteria
    local total_criteria
    total_criteria=$(grep -cE "^- \[[ x]\] [0-9]+\." "$RALPH_DIR/state.md" 2>/dev/null || echo "0")
    local completed_criteria
    completed_criteria=$(grep -cE "^- \[x\] [0-9]+\." "$RALPH_DIR/state.md" 2>/dev/null || echo "0")

    # Get budget info
    local max_iterations
    max_iterations=$(read_config max_iterations 50)
    local max_tokens
    max_tokens=$(read_config max_tokens 500000)
    local total_tokens=0
    if [[ -f "$RALPH_DIR/tokens/usage.md" ]]; then
        total_tokens=$(bb --classpath "$RE_HOME/lib" -m brain.budget total "$RALPH_DIR" 2>/dev/null || echo "0")
    fi

    # Get health status
    local health_status="healthy"
    if bb --classpath "$RE_HOME/lib" -m brain.circuit-breaker check "$RALPH_DIR" > /dev/null 2>&1; then
        health_status="healthy"
    else
        health_status="tripped"
    fi

    case "$format" in
        brief)
            echo "$status (iteration $iteration, $completed_criteria/$total_criteria criteria)"
            ;;
        json)
            cat << EOF
{
  "session_id": "$session_id",
  "status": "$status",
  "iteration": $iteration,
  "started_at": "$started_at",
  "criteria": {
    "completed": $completed_criteria,
    "total": $total_criteria
  },
  "budget": {
    "iterations": $iteration,
    "max_iterations": $max_iterations,
    "tokens": $total_tokens,
    "max_tokens": $max_tokens
  },
  "health": "$health_status"
}
EOF
            ;;
        full)
            echo ""
            echo -e "${BOLD}Session:${NC} $session_id"
            echo -e "${BOLD}Status:${NC} $status"
            if [[ "$status" == "crashed" ]]; then
                echo -e "${DIM}  (loop exited unexpectedly - run 're resume' to continue)${NC}"
            fi
            echo -e "${BOLD}Started:${NC} $started_at"
            echo ""
            echo -e "${BOLD}Progress:${NC}"
            echo "  Iteration: $iteration / $max_iterations"
            echo "  Criteria:  $completed_criteria / $total_criteria complete"
            echo "  Tokens:    $total_tokens / $max_tokens"
            echo ""
            echo -e "${BOLD}Health:${NC} $health_status"

            # Show recent decision if available
            if [[ -f "$RALPH_DIR/decision.yaml" ]]; then
                echo ""
                echo -e "${BOLD}Last Decision:${NC}"
                cat "$RALPH_DIR/decision.yaml" | sed 's/^/  /'
            fi

            # Show criteria
            echo ""
            echo -e "${BOLD}Completion Criteria:${NC}"
            grep -E "^- \[[ x]\] [0-9]+\." "$RALPH_DIR/state.md" 2>/dev/null | sed 's/^/  /' || echo "  (none)"
            ;;
    esac
}

show_status "$@"
