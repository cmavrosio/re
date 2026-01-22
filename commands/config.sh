#!/usr/bin/env bash
#
# re config - View or modify configuration
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh"

RALPH_DIR=".ralph"

usage() {
    cat << 'EOF'
re config - View or modify configuration

USAGE:
    re config [command] [key] [value]

COMMANDS:
    show              Show all configuration (default)
    get <key>         Get a specific value
    set <key> <value> Set a configuration value
    edit              Open config.yaml in editor

CONFIGURATION KEYS:
    max_iterations        Maximum iterations before auto-abort (default: 50)
    max_tokens           Maximum tokens before auto-abort (default: 500000)
    auto_commit_interval Auto-commit every N iterations (default: 5)
    auto_push            Push to remote after commits (default: false)
    test_command         Test command to run (default: empty)
    model                Claude model: sonnet, opus, haiku (default: sonnet)
    verbose              Enable verbose logging (default: false)
    require_completion_approval  Require human approval (default: true)
    pre_start_checks     Commands to run before starting (semicolon-separated)
    post_complete_checks Commands to run after task completes (semicolon-separated)

EXAMPLES:
    re config                           # Show all config
    re config get max_iterations        # Get specific value
    re config set max_iterations 100    # Set value
    re config edit                      # Open in editor
EOF
}

show_config() {
    require_ralph_dir

    if [[ ! -f "$RALPH_DIR/config.yaml" ]]; then
        log_error "No config.yaml found"
        exit 1
    fi

    echo -e "${BOLD}Configuration:${NC}"
    echo ""
    cat "$RALPH_DIR/config.yaml"
}

get_config() {
    local key="$1"

    require_ralph_dir

    local value
    value=$(read_config "$key" "")

    if [[ -z "$value" || "$value" == "nil" ]]; then
        log_error "Key not found: $key"
        exit 1
    fi

    echo "$value"
}

set_config() {
    local key="$1"
    local value="$2"

    require_ralph_dir

    if [[ ! -f "$RALPH_DIR/config.yaml" ]]; then
        log_error "No config.yaml found"
        exit 1
    fi

    # Check if key exists
    if grep -q "^${key}:" "$RALPH_DIR/config.yaml"; then
        # Update existing key
        sed -i.bak "s/^${key}:.*/${key}: ${value}/" "$RALPH_DIR/config.yaml"
        rm -f "$RALPH_DIR/config.yaml.bak"
        log_success "Updated $key = $value"
    else
        # Add new key
        echo "${key}: ${value}" >> "$RALPH_DIR/config.yaml"
        log_success "Added $key = $value"
    fi
}

edit_config() {
    require_ralph_dir

    local editor="${EDITOR:-vim}"

    if [[ ! -f "$RALPH_DIR/config.yaml" ]]; then
        log_error "No config.yaml found"
        exit 1
    fi

    "$editor" "$RALPH_DIR/config.yaml"
}

config_command() {
    local cmd="${1:-show}"

    case "$cmd" in
        -h|--help)
            usage
            exit 0
            ;;
        show)
            show_config
            ;;
        get)
            if [[ -z "${2:-}" ]]; then
                log_error "Missing key argument"
                exit 1
            fi
            get_config "$2"
            ;;
        set)
            if [[ -z "${2:-}" || -z "${3:-}" ]]; then
                log_error "Missing key or value argument"
                exit 1
            fi
            set_config "$2" "$3"
            ;;
        edit)
            edit_config
            ;;
        *)
            # Treat as "get" if it looks like a key
            get_config "$cmd"
            ;;
    esac
}

config_command "$@"
