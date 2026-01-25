#!/usr/bin/env bash
#
# Provider dispatcher - routes to claude or codex based on config
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$RE_HOME/lib/orchestration/common.sh" 2>/dev/null || {
    log_error() { echo "error: $1" >&2; }
    log_info() { echo "info: $1"; }
    log_debug() { [[ "${RE_VERBOSE:-false}" == "true" ]] && echo "debug: $1"; }
    read_config() { echo "${2:-}"; }
}

# Get configured provider (default: claude)
get_provider() {
    read_config provider "claude"
}

# Map generic model names to provider-specific ones
map_model() {
    local provider="$1"
    local model="$2"

    case "$provider" in
        claude)
            # Claude uses: opus, sonnet, haiku
            case "$model" in
                fast) echo "haiku" ;;
                smart) echo "opus" ;;
                default|sonnet) echo "sonnet" ;;
                opus|haiku) echo "$model" ;;
                *) echo "sonnet" ;;
            esac
            ;;
        codex)
            # Codex uses: gpt-5.2, gpt-4o-mini, etc.
            case "$model" in
                fast) echo "gpt-4o-mini" ;;
                smart|default|sonnet|opus) echo "gpt-5.2" ;;
                haiku) echo "gpt-4o-mini" ;;
                *) echo "gpt-5.2" ;;
            esac
            ;;
        *)
            echo "$model"
            ;;
    esac
}

# Route command to appropriate provider
route_command() {
    local command="$1"
    shift

    local provider
    provider=$(get_provider)

    local provider_script="$SCRIPT_DIR/${provider}.sh"

    if [[ ! -f "$provider_script" ]]; then
        log_error "Provider not found: $provider (looking for $provider_script)"
        exit 1
    fi

    bash "$provider_script" "$command" "$@"
}

# Execute with model mapping
execute_with_mapping() {
    local context_file="$1"
    local output_file="$2"
    local model="$3"
    local session_id="${4:-}"
    local continue_flag="${5:-false}"

    local provider
    provider=$(get_provider)

    local mapped_model
    mapped_model=$(map_model "$provider" "$model")

    log_debug "Provider: $provider, Model: $model -> $mapped_model"

    route_command execute "$context_file" "$output_file" "$mapped_model" "$session_id" "$continue_flag"
}

# CLI interface
case "${1:-}" in
    execute)
        # execute <context-file> <output-file> [model] [session_id] [continue]
        execute_with_mapping "${2:-}" "${3:-}" "${4:-sonnet}" "${5:-}" "${6:-false}"
        ;;
    prompt)
        # prompt <text> [model] - for quick prompts (summaries, etc.)
        local provider
        provider=$(get_provider)
        local mapped_model
        mapped_model=$(map_model "$provider" "${3:-haiku}")
        route_command prompt "${2:-}" "$mapped_model"
        ;;
    extract-response)
        route_command extract-response "${2:-}"
        ;;
    extract-tokens)
        route_command extract-tokens "${2:-}"
        ;;
    extract-session-id)
        route_command extract-session-id "${2:-}"
        ;;
    analyze-diff)
        route_command analyze-diff "${2:-}"
        ;;
    summarize-iteration)
        route_command summarize-iteration "${2:-}"
        ;;
    check)
        route_command check
        ;;
    get-provider)
        get_provider
        ;;
    map-model)
        map_model "${2:-claude}" "${3:-sonnet}"
        ;;
    *)
        echo "Usage: provider.sh <command> [args...]"
        echo ""
        echo "Provider dispatcher - routes to configured provider (claude or codex)"
        echo ""
        echo "Commands:"
        echo "  execute <context-file> <output-file> [model] [session_id] [continue]"
        echo "  prompt <prompt> [model]                       - Execute with prompt"
        echo "  analyze-diff <diff>                           - Analyze diff (uses fast model)"
        echo "  summarize-iteration <content>                 - Summarize iteration (uses fast model)"
        echo "  extract-tokens <json-file>                    - Extract token usage"
        echo "  extract-response <json-file>                  - Extract response text"
        echo "  extract-session-id <json-file>                - Extract session ID"
        echo "  check                                         - Check provider availability"
        echo "  get-provider                                  - Show configured provider"
        echo "  map-model <provider> <model>                  - Map model name"
        ;;
esac
