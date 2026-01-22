#!/usr/bin/env bash
#
# re watch - Live monitoring of session progress
#

set -uo pipefail
# Note: Not using -e since watch should continue even if commands fail

source "$RE_HOME/lib/orchestration/common.sh"

RALPH_DIR=".ralph"

# Terminal colors and formatting
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
NC='\033[0m'

usage() {
    cat << 'EOF'
re watch - Live monitoring of session progress

USAGE:
    re watch [options]

OPTIONS:
    --once          Show status once and exit (no loop)
    --interval N    Refresh interval in seconds (default: 10)
    -h, --help      Show this help

DESCRIPTION:
    Displays a live dashboard showing:
    - Current iteration and token usage
    - Which criterion is being worked on
    - Files edited with timestamps and diff preview
    - Progress checklist
    - Test results
EOF
}

# Get current working criterion (first unchecked)
get_current_criterion() {
    if [[ -f "$RALPH_DIR/state.md" ]]; then
        grep -E "^- \[ \] [0-9]+\." "$RALPH_DIR/state.md" | head -1 | sed 's/^- \[ \] //'
    fi
}

# Get last action from response or iteration
get_last_action() {
    # Check for response.json and extract last tool use
    if [[ -f "$RALPH_DIR/response.json" ]]; then
        local response_age=$(get_file_age "$RALPH_DIR/response.json")

        # Try to extract tool calls from response
        local tools=$(cat "$RALPH_DIR/response.json" 2>/dev/null | grep -oE '"(Read|Edit|Write|Bash|Glob|Grep)"' | tail -3 | tr -d '"' | tr '\n' ' ')

        if [[ -n "$tools" ]]; then
            echo "$tools($response_age)"
            return
        fi
    fi

    # Fallback: check latest iteration file
    local latest_iter=$(ls -t "$RALPH_DIR/context/iterations/"*.md 2>/dev/null | head -1)
    if [[ -n "$latest_iter" && -f "$latest_iter" ]]; then
        local iter_name=$(basename "$latest_iter" .md)
        local iter_age=$(get_file_age "$latest_iter")

        # Look for tool mentions in iteration
        local tools=$(grep -oE '(Read|Edit|Write|Bash|Glob|Grep)' "$latest_iter" 2>/dev/null | sort -u | head -3 | tr '\n' ' ')
        if [[ -n "$tools" ]]; then
            echo "$tools(iter $iter_name, $iter_age)"
            return
        fi
    fi

    echo "waiting..."
}

# Get test results summary
get_test_summary() {
    if [[ -f "$RALPH_DIR/tests/latest.md" ]]; then
        local status=$(grep -E "^## Status:" "$RALPH_DIR/tests/latest.md" 2>/dev/null | head -1)
        local passed=$(grep -oE '[0-9]+ passed' "$RALPH_DIR/tests/latest.md" 2>/dev/null | head -1 || echo "")
        local failed=$(grep -oE '[0-9]+ failed' "$RALPH_DIR/tests/latest.md" 2>/dev/null | head -1 || echo "")

        if [[ -n "$passed" || -n "$failed" ]]; then
            echo "$passed${failed:+, $failed}"
        else
            echo "$status" | sed 's/## Status: //'
        fi
    else
        echo "No test results"
    fi
}

# Get files changed (uncommitted only)
get_changed_files() {
    # Show uncommitted changes only (staged + unstaged + untracked)
    {
        git diff --name-only 2>/dev/null
        git diff --name-only --cached 2>/dev/null
        git ls-files --others --exclude-standard 2>/dev/null
    } | grep -v "^\.ralph" | sort -u | head -10
}

# Check if file has uncommitted changes
is_uncommitted() {
    local file="$1"
    git diff --name-only 2>/dev/null | grep -q "^$file$" && return 0
    git diff --name-only --cached 2>/dev/null | grep -q "^$file$" && return 0
    git ls-files --others --exclude-standard 2>/dev/null | grep -q "^$file$" && return 0
    return 1
}

# Get time since file was modified
get_file_age() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local mod_time=$(stat -f "%m" "$file" 2>/dev/null || stat -c "%Y" "$file" 2>/dev/null)
        local now=$(date +%s)
        local diff=$((now - mod_time))

        if [[ $diff -lt 60 ]]; then
            echo "${diff}s ago"
        elif [[ $diff -lt 3600 ]]; then
            echo "$((diff / 60))m ago"
        else
            echo "$((diff / 3600))h ago"
        fi
    else
        echo "deleted"
    fi
}

# Get short diff for a file (additions/deletions summary + preview)
get_file_diff_preview() {
    local file="$1"

    # Get stats from uncommitted changes
    local stats=$(git diff --stat -- "$file" 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | tr '\n' ' ')

    # Get first few changed lines
    local preview=$(git diff -- "$file" 2>/dev/null | grep -E "^\+" | grep -v "^+++" | head -3 | sed 's/^+//' | cut -c1-50)

    echo "$stats"
    if [[ -n "$preview" ]]; then
        echo "$preview"
    fi
}

# Count past sessions from archive
get_session_number() {
    local archive_count=0
    if [[ -d "$RALPH_DIR/archive" ]]; then
        archive_count=$(ls -1 "$RALPH_DIR/archive" 2>/dev/null | wc -l | tr -d ' ')
    fi
    echo $((archive_count + 1))
}

# Get token breakdown from usage.md
get_token_info() {
    if [[ -f "$RALPH_DIR/tokens/usage.md" ]]; then
        # Count API calls (data rows in table - lines starting with | and a number)
        local api_calls=$(grep -cE '^\| [0-9]' "$RALPH_DIR/tokens/usage.md" 2>/dev/null || echo "0")

        # Get cumulative tokens from last column of last data row
        # Format: | Iteration | Input | Output | Total | Cumulative |
        local total_tokens=$(grep -E '^\| [0-9]' "$RALPH_DIR/tokens/usage.md" 2>/dev/null | tail -1 | awk -F'|' '{print $(NF-1)}' | tr -d ' ' || echo "0")
        [[ -z "$total_tokens" ]] && total_tokens=0

        echo "$api_calls $total_tokens"
    else
        echo "0 0"
    fi
}

# Draw the dashboard - compact 10-line version
# Pass "noclear" as first arg to skip clearing (for smooth refresh)
draw_dashboard() {
    if [[ "${1:-}" != "noclear" ]]; then
        clear
    fi

    # Check if session exists
    if [[ ! -f "$RALPH_DIR/state.md" ]]; then
        echo -e "${RED}No active session${NC} - run 're start' to begin"
        return
    fi

    # Read state
    local status=$(read_frontmatter "$RALPH_DIR/state.md" "status" 2>/dev/null || echo "unknown")
    local iteration=$(read_frontmatter "$RALPH_DIR/state.md" "iteration" 2>/dev/null || echo "0")

    # Check if loop is actually running
    if [[ "$status" == "running" ]]; then
        if [[ -f "$RALPH_DIR/.loop.pid" ]]; then
            local pid=$(cat "$RALPH_DIR/.loop.pid" 2>/dev/null)
            if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
                status="crashed"
            fi
        else
            status="crashed"
        fi
    fi

    # Get counts (tr -d removes any whitespace/newlines)
    local done_count=$(grep -cE "^- \[x\] [0-9]+\." "$RALPH_DIR/state.md" 2>/dev/null | tr -d '[:space:]')
    local todo_count=$(grep -cE "^- \[ \] [0-9]+\." "$RALPH_DIR/state.md" 2>/dev/null | tr -d '[:space:]')
    [[ -z "$done_count" ]] && done_count=0
    [[ -z "$todo_count" ]] && todo_count=0
    local total=$((done_count + todo_count))
    local token_info=$(get_token_info)
    local total_tokens=$(echo "$token_info" | cut -d' ' -f2)
    local file_count=$(get_changed_files | wc -l | tr -d ' ')

    # Status icon and color
    local status_icon="●" status_color="$BLUE"
    case "$status" in
        running)   status_icon="▶" status_color="$GREEN" ;;
        paused)    status_icon="⏸" status_color="$YELLOW" ;;
        completed) status_icon="✓" status_color="$GREEN" ;;
        aborted|crashed) status_icon="✗" status_color="$RED" ;;
    esac

    # Line 1: Status bar
    echo -e "${status_color}${status_icon}${NC} ${BOLD}$status${NC} │ iter ${BOLD}$iteration${NC} │ ${GREEN}✓$done_count${NC}/${total} │ ${CYAN}${total_tokens}tok${NC} │ ${YELLOW}${file_count} files${NC}"

    # Line 2: Current task (truncated)
    local current=$(grep -E "^- \[ \] [0-9]+\." "$RALPH_DIR/state.md" 2>/dev/null | head -1 | sed 's/^- \[ \] //' | cut -c1-70)
    if [[ -n "$current" ]]; then
        echo -e "${YELLOW}▸${NC} ${current}"
    else
        echo -e "${GREEN}▸ All criteria complete${NC}"
    fi

    # Line 3-5: Recent files (max 3)
    local files=$(get_changed_files | head -3)
    if [[ -n "$files" ]]; then
        echo "$files" | while read -r file; do
            local stats=$(git diff --numstat -- "$file" 2>/dev/null | awk '{print "+"$1"/-"$2}')
            [[ -z "$stats" ]] && stats="+new"
            printf "  ${DIM}%-50s %s${NC}\n" "$(echo $file | cut -c1-50)" "$stats"
        done
    fi

    # Line 6-7: Last completed (max 2)
    local recent=$(grep -E "^- \[x\] [0-9]+\." "$RALPH_DIR/state.md" 2>/dev/null | tail -2)
    if [[ -n "$recent" ]]; then
        echo "$recent" | while read -r line; do
            echo -e "  ${GREEN}✓${NC} ${DIM}$(echo "${line#- \[x\] }" | cut -c1-65)${NC}"
        done
    fi

    # Line 8: Test status (if available)
    if [[ -f "$RALPH_DIR/tests/latest.md" ]]; then
        local test_status=$(grep -E "passed|failed" "$RALPH_DIR/tests/latest.md" 2>/dev/null | head -1 | cut -c1-60)
        [[ -n "$test_status" ]] && echo -e "  ${DIM}Tests: $test_status${NC}"
    fi

    # Line 10: Help hint
    echo -e "${DIM}─────────────────────────────────────────────────────────────────${NC}"
    echo -e "${DIM}re pause│re inject \"msg\"│re abort│Ctrl+C exit${NC}"
}

watch_session() {
    local interval=10
    local once=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --once)
                once=true
                shift
                ;;
            --interval)
                interval="$2"
                shift 2
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

    if [[ "$once" == "true" ]]; then
        draw_dashboard
    else
        # Hide cursor
        tput civis 2>/dev/null || true
        trap 'tput cnorm 2>/dev/null; exit' INT TERM

        # Initial draw with clear
        draw_dashboard

        while true; do
            sleep "$interval"
            # Move cursor to top instead of clear to reduce flicker
            tput cup 0 0 2>/dev/null || clear
            draw_dashboard "noclear"
            # Clear any leftover lines from previous longer output
            tput ed 2>/dev/null || true
        done
    fi
}

watch_session "$@"
