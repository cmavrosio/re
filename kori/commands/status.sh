#!/usr/bin/env bash
#
# kori status - Show current project status
#

set -euo pipefail

source "$KORI_HOME/lib/common.sh"

usage() {
    cat << 'EOF'
kori status - Show current project status

USAGE:
    kori status [options]

OPTIONS:
    --json            Output as JSON
    -h, --help        Show this help
EOF
}

show_status() {
    local format="text"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                format="json"
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

    require_overseer_dir

    local goal=""
    local phase=""
    local completed=0
    local total=0
    local current=""
    local started=""

    # Read project goal (first non-empty line after header)
    if [[ -f "$OVERSEER_DIR/project.md" ]]; then
        goal=$(sed -n '/^# Project Goal/,/^##/p' "$OVERSEER_DIR/project.md" | grep -v "^#" | grep -v "^$" | head -1 | xargs)
    fi

    # Read state
    if [[ -f "$OVERSEER_DIR/state.yaml" ]]; then
        phase=$(read_yaml "$OVERSEER_DIR/state.yaml" "phase" "unknown")
        completed=$(read_yaml "$OVERSEER_DIR/state.yaml" "completed_leaves" "0")
        total=$(read_yaml "$OVERSEER_DIR/state.yaml" "total_leaves" "0")
        current=$(read_yaml "$OVERSEER_DIR/state.yaml" "current_node" "null")
        started=$(read_yaml "$OVERSEER_DIR/state.yaml" "started_at" "")
    fi

    if [[ "$format" == "json" ]]; then
        cat << EOF
{
  "goal": "$goal",
  "phase": "$phase",
  "completed_leaves": $completed,
  "total_leaves": $total,
  "current_node": "$current",
  "started_at": "$started"
}
EOF
        return
    fi

    # Text format
    echo -e "${BOLD}Project:${NC} $goal"
    echo -e "${BOLD}Phase:${NC} $phase"
    echo -e "${BOLD}Started:${NC} $started"
    echo ""

    if [[ "$total" -gt 0 ]]; then
        local pct=$((completed * 100 / total))
        echo -e "${BOLD}Progress:${NC} $completed / $total leaves ($pct%)"

        # Progress bar
        local bar_width=40
        local filled=$((pct * bar_width / 100))
        local empty=$((bar_width - filled))
        printf "  ["
        printf "%${filled}s" | tr ' ' '='
        printf "%${empty}s" | tr ' ' '-'
        printf "]\n"
    fi

    if [[ "$current" != "null" && -n "$current" ]]; then
        echo ""
        echo -e "${BOLD}Current:${NC} $current"
    fi

    echo ""
    echo -e "${DIM}Phase legend: initialized → discovered → planned → executing → completed${NC}"
}

show_status "$@"
