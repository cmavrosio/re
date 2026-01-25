#!/usr/bin/env bash
#
# Claude Code CLI provider for re
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh" 2>/dev/null || {
    log_error() { echo "error: $1" >&2; }
    log_info() { echo "info: $1"; }
    log_debug() { [[ "${RE_VERBOSE:-false}" == "true" ]] && echo "debug: $1"; }
}

# Default model
DEFAULT_MODEL="sonnet"

# Execute claude with context
# Args: context_file output_file [model] [session_id] [continue]
execute_claude() {
    local context_file="$1"
    local output_file="$2"
    local model="${3:-$DEFAULT_MODEL}"
    local session_id="${4:-}"
    local continue_session="${5:-false}"

    log_debug "Executing claude with context from $context_file (continue=$continue_session)"

    # Build claude command
    # Note: --dangerously-skip-permissions is needed for autonomous operation
    # Only use in trusted directories
    local claude_args=("--print" "--output-format" "json" "--dangerously-skip-permissions")

    # Add model if specified
    case "$model" in
        opus)
            claude_args+=("--model" "opus")
            ;;
        haiku)
            claude_args+=("--model" "haiku")
            ;;
        sonnet|*)
            # Default is sonnet, no flag needed
            ;;
    esac

    # Add session continuation if resuming
    if [[ "$continue_session" == "true" && -n "$session_id" ]]; then
        claude_args+=("--continue")
        log_debug "Continuing previous session"
    fi

    # Execute and capture output
    if ! claude "${claude_args[@]}" < "$context_file" > "$output_file" 2>&1; then
        log_error "Claude execution failed"
        return 1
    fi

    log_debug "Claude output written to $output_file"
}

# Extract session ID from response JSON
extract_session_id() {
    local json_file="$1"

    if command -v jq &> /dev/null; then
        jq -r '.session_id // empty' "$json_file" 2>/dev/null || echo ""
    else
        bb -e "(let [data (json/parse-string (slurp \"$json_file\") true)]
                (or (:session_id data) \"\"))" 2>/dev/null || echo ""
    fi
}

# Execute claude with prompt string
execute_prompt() {
    local prompt="$1"
    local model="${2:-$DEFAULT_MODEL}"

    local claude_args=("--print")

    case "$model" in
        opus)
            claude_args+=("--model" "opus")
            ;;
        haiku)
            claude_args+=("--model" "haiku")
            ;;
    esac

    echo "$prompt" | claude "${claude_args[@]}"
}

# Analyze diff using haiku (cheap model for categorization)
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

    execute_prompt "$prompt" "haiku"
}

# Summarize iteration transcript using haiku
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

    execute_prompt "$prompt" "haiku"
}

# Extract token usage from JSON response
extract_tokens() {
    local json_file="$1"

    if command -v jq &> /dev/null; then
        local input_tokens=$(jq -r '.usage.input_tokens // 0' "$json_file" 2>/dev/null || echo "0")
        local output_tokens=$(jq -r '.usage.output_tokens // 0' "$json_file" 2>/dev/null || echo "0")
        echo "$input_tokens $output_tokens"
    else
        # Fallback: use bb
        bb -e "(let [data (json/parse-string (slurp \"$json_file\") true)]
                (println (get-in data [:usage :input_tokens] 0)
                         (get-in data [:usage :output_tokens] 0)))"
    fi
}

# Extract response text from JSON
extract_response() {
    local json_file="$1"

    if command -v jq &> /dev/null; then
        jq -r '.result // .content // .message // .' "$json_file" 2>/dev/null
    else
        bb -e "(let [data (json/parse-string (slurp \"$json_file\") true)]
                (or (:result data) (:content data) (:message data) (pr-str data)))"
    fi
}

# Check if claude is available
check_claude() {
    if ! command -v claude &> /dev/null; then
        log_error "claude CLI not found"
        log_error "Install: https://docs.anthropic.com/en/docs/claude-code"
        return 1
    fi
    log_info "claude CLI available"
    return 0
}

# CLI interface
case "${1:-}" in
    execute)
        # execute <context-file> <output-file> [model] [session_id] [continue]
        execute_claude "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-false}"
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
        check_claude
        ;;
    *)
        echo "Usage: claude.sh <command> [args...]"
        echo "Commands:"
        echo "  execute <context-file> <output-file> [model] [session_id] [continue]"
        echo "  prompt <prompt> [model]                       - Execute with prompt"
        echo "  analyze-diff <diff>                           - Analyze diff with haiku"
        echo "  summarize-iteration <content>                 - Summarize with haiku"
        echo "  extract-tokens <json-file>                    - Extract token usage"
        echo "  extract-response <json-file>                  - Extract response text"
        echo "  extract-session-id <json-file>                - Extract session ID"
        echo "  check                                         - Check claude availability"
        ;;
esac
