#!/usr/bin/env bash
#
# re inject - Inject an urgent message for next iteration
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh"

RALPH_DIR=".ralph"

usage() {
    cat << 'EOF'
re inject - Inject an urgent message for next iteration

USAGE:
    re inject [options] <message>

OPTIONS:
    --file FILE    Read message from file
    --clear        Clear any existing urgent message
    --show         Show current urgent message
    -h, --help     Show this help

DESCRIPTION:
    Injects an urgent message that will be included in the context
    for the next Claude iteration. Use this to provide guidance,
    corrections, or focus the AI on specific issues.

EXAMPLES:
    re inject "Focus on fixing the authentication bug first"
    re inject --file feedback.md
    re inject --clear
    re inject --show
EOF
}

inject_message() {
    local message=""
    local from_file=""
    local clear=false
    local show=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)
                from_file="$2"
                shift 2
                ;;
            --clear)
                clear=true
                shift
                ;;
            --show)
                show=true
                shift
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
                # Collect remaining args as message
                message="$*"
                break
                ;;
        esac
    done

    require_ralph_dir

    local urgent_file="$RALPH_DIR/urgent.md"

    if [[ "$show" == "true" ]]; then
        if [[ -f "$urgent_file" ]]; then
            echo -e "${BOLD}Current urgent message:${NC}"
            echo ""
            cat "$urgent_file"
        else
            echo "No urgent message set."
        fi
        exit 0
    fi

    if [[ "$clear" == "true" ]]; then
        rm -f "$urgent_file"
        log_success "Urgent message cleared"
        exit 0
    fi

    # Get message content
    local content=""
    if [[ -n "$from_file" ]]; then
        if [[ ! -f "$from_file" ]]; then
            log_error "File not found: $from_file"
            exit 1
        fi
        content=$(cat "$from_file")
    elif [[ -n "$message" ]]; then
        content="$message"
    else
        # Read from stdin if no message provided
        if [[ -t 0 ]]; then
            log_error "No message provided. Use: re inject \"message\" or pipe input"
            exit 1
        fi
        content=$(cat)
    fi

    if [[ -z "$content" ]]; then
        log_error "Empty message"
        exit 1
    fi

    # Write urgent message
    {
        echo "**Injected at:** $(timestamp)"
        echo ""
        echo "$content"
    } > "$urgent_file"

    log_success "Urgent message injected"
    echo ""
    echo "Message will be included in the next iteration context."
    echo "To view: re inject --show"
    echo "To clear: re inject --clear"
}

inject_message "$@"
