#!/usr/bin/env bash
#
# OpenAI Codex CLI provider for re
#
# Requires: npm i -g @openai/codex
# Auth: CODEX_API_KEY environment variable
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh" 2>/dev/null || {
    log_error() { echo "error: $1" >&2; }
    log_info() { echo "info: $1"; }
    log_debug() { [[ "${RE_VERBOSE:-false}" == "true" ]] && echo "debug: $1"; }
}

# Default model
DEFAULT_MODEL="gpt-5.2"

# Execute codex with context
# Args: context_file output_file [model] [session_id] [continue]
execute_codex() {
    local context_file="$1"
    local output_file="$2"
    local model="${3:-$DEFAULT_MODEL}"
    local session_id="${4:-}"
    local continue_session="${5:-false}"

    log_debug "Executing codex with context from $context_file (continue=$continue_session)"

    # Build codex command
    # --full-auto: Allow edits without approval
    # --sandbox danger-full-access: Full system access (use in trusted dirs only)
    # --json: Output JSON Lines format for parsing
    local codex_args=("exec" "--full-auto" "--sandbox" "danger-full-access" "--json")

    # Add model if specified
    if [[ -n "$model" && "$model" != "default" ]]; then
        codex_args+=("--model" "$model")
    fi

    # Add session continuation if resuming
    if [[ "$continue_session" == "true" && -n "$session_id" ]]; then
        codex_args+=("--resume" "$session_id")
        log_debug "Resuming session: $session_id"
    fi

    # Codex takes prompt as argument, not stdin
    local prompt
    prompt=$(cat "$context_file")

    # Execute and capture output
    # Codex outputs JSON Lines to stdout, progress to stderr
    if ! codex "${codex_args[@]}" "$prompt" > "$output_file" 2>&1; then
        log_error "Codex execution failed"
        return 1
    fi

    log_debug "Codex output written to $output_file"
}

# Extract session ID from JSON Lines response
# Codex includes session_id in thread.started event
extract_session_id() {
    local json_file="$1"

    if command -v jq &> /dev/null; then
        # Find thread.started event and extract session_id
        jq -rs '[.[] | select(.type == "thread.started")] | .[0].session_id // empty' "$json_file" 2>/dev/null || echo ""
    else
        # Fallback: grep for session_id pattern
        grep -o '"session_id":"[^"]*"' "$json_file" 2>/dev/null | head -1 | sed 's/"session_id":"//' | sed 's/"$//' || echo ""
    fi
}

# Execute codex with prompt string (for quick operations)
execute_prompt() {
    local prompt="$1"
    local model="${2:-$DEFAULT_MODEL}"

    local codex_args=("exec" "--full-auto")

    if [[ -n "$model" && "$model" != "default" ]]; then
        codex_args+=("--model" "$model")
    fi

    codex "${codex_args[@]}" "$prompt"
}

# Analyze diff using fast model
analyze_diff() {
    local diff_content="$1"

    local prompt="Analyze this git diff and provide a brief summary of the changes.
Focus on:
1. What files were changed
2. What type of changes (new features, bug fixes, refactoring, tests)
3. Any potential issues or concerns

Keep the summary under 200 words.

Diff:
$diff_content"

    execute_prompt "$prompt" "gpt-4o-mini"
}

# Summarize iteration transcript using fast model
summarize_iteration() {
    local iteration_content="$1"

    local prompt="Summarize this AI agent iteration transcript in 3-5 bullet points.
Focus on:
- What task/criterion was worked on
- Key actions taken (files modified, commands run)
- Outcome (completed, blocked, error)
- Any important context for future iterations

Keep it under 150 words. Use past tense.

Transcript:
$iteration_content"

    execute_prompt "$prompt" "gpt-4o-mini"
}

# Extract token usage from JSON Lines response
# Codex includes usage in turn.completed events
extract_tokens() {
    local json_file="$1"

    if command -v jq &> /dev/null; then
        # Sum up tokens from all turn.completed events
        local input_tokens=$(jq -rs '[.[] | select(.type == "turn.completed") | .usage.input_tokens // 0] | add // 0' "$json_file" 2>/dev/null || echo "0")
        local output_tokens=$(jq -rs '[.[] | select(.type == "turn.completed") | .usage.output_tokens // 0] | add // 0' "$json_file" 2>/dev/null || echo "0")
        echo "$input_tokens $output_tokens"
    else
        # Fallback: return zeros (token tracking less reliable without jq)
        echo "0 0"
    fi
}

# Extract response text from JSON Lines
# Get the final message content from the last item.completed event
extract_response() {
    local json_file="$1"

    if command -v jq &> /dev/null; then
        # Get content from last item.completed event, or concatenate all message contents
        jq -rs '
            [.[] | select(.type == "item.completed" and .item.type == "message") | .item.content[].text // empty]
            | join("\n")
        ' "$json_file" 2>/dev/null || cat "$json_file"
    else
        # Fallback: try to extract text content with grep/sed
        grep -o '"text":"[^"]*"' "$json_file" 2>/dev/null | sed 's/"text":"//' | sed 's/"$//' | tr '\n' ' ' || cat "$json_file"
    fi
}

# Check if codex is available
check_codex() {
    if ! command -v codex &> /dev/null; then
        log_error "codex CLI not found"
        log_error "Install: npm i -g @openai/codex"
        return 1
    fi

    if [[ -z "${CODEX_API_KEY:-}" ]]; then
        log_warn "CODEX_API_KEY not set - codex may fail to authenticate"
    fi

    log_info "codex CLI available"
    return 0
}

# CLI interface
case "${1:-}" in
    execute)
        # execute <context-file> <output-file> [model] [session_id] [continue]
        execute_codex "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-false}"
        ;;
    prompt)
        execute_prompt "${2:-}" "${3:-}"
        ;;
    analyze-diff)
        analyze_diff "${2:-$(cat)}"
        ;;
    summarize-iteration)
        summarize_iteration "${2:-$(cat)}"
        ;;
    extract-tokens)
        extract_tokens "${2:-}"
        ;;
    extract-response)
        extract_response "${2:-}"
        ;;
    extract-session-id)
        extract_session_id "${2:-}"
        ;;
    check)
        check_codex
        ;;
    *)
        echo "Usage: codex.sh <command> [args...]"
        echo ""
        echo "OpenAI Codex CLI provider for re"
        echo "Requires: npm i -g @openai/codex"
        echo "Auth: Set CODEX_API_KEY environment variable"
        echo ""
        echo "Commands:"
        echo "  execute <context-file> <output-file> [model] [session_id] [continue]"
        echo "  prompt <prompt> [model]                       - Execute with prompt"
        echo "  analyze-diff <diff>                           - Analyze diff"
        echo "  summarize-iteration <content>                 - Summarize iteration"
        echo "  extract-tokens <json-file>                    - Extract token usage"
        echo "  extract-response <json-file>                  - Extract response text"
        echo "  extract-session-id <json-file>                - Extract session ID"
        echo "  check                                         - Check codex availability"
        ;;
esac
