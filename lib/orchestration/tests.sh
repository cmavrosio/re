#!/usr/bin/env bash
#
# Test runner wrapper for re
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh" 2>/dev/null || {
    log_error() { echo "error: $1" >&2; }
    log_info() { echo "info: $1"; }
    log_warn() { echo "warn: $1"; }
    RALPH_DIR=".ralph"
}

# Run tests and capture results
run_tests() {
    local test_command="$1"
    local output_file="${2:-$RALPH_DIR/tests/latest.md}"
    local timeout="${3:-300}"  # 5 minute default timeout

    if [[ -z "$test_command" ]]; then
        log_warn "No test command configured"
        echo "# Test Results" > "$output_file"
        echo "" >> "$output_file"
        echo "_No test command configured_" >> "$output_file"
        return 0
    fi

    log_info "Running tests: $test_command"

    local start_time=$(date +%s)
    local exit_code=0
    local test_output

    # Run tests with timeout
    if test_output=$(timeout "$timeout" bash -c "$test_command" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Write results to markdown
    {
        echo "# Test Results"
        echo ""
        echo "**Command:** \`$test_command\`"
        echo "**Exit Code:** $exit_code"
        echo "**Duration:** ${duration}s"
        echo "**Timestamp:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo ""
        if [[ $exit_code -eq 0 ]]; then
            echo "## Status: PASSED"
        else
            echo "## Status: FAILED"
        fi
        echo ""
        echo "## Output"
        echo ""
        echo '```'
        echo "$test_output" | tail -100  # Limit output
        echo '```'
    } > "$output_file"

    return $exit_code
}

# Compare test results to baseline
compare_to_baseline() {
    local current="$RALPH_DIR/tests/latest.md"
    local baseline="$RALPH_DIR/tests/baseline.md"

    if [[ ! -f "$baseline" ]]; then
        log_info "No baseline to compare against"
        return 0
    fi

    local current_status=$(grep -E "^## Status:" "$current" | head -1 || echo "UNKNOWN")
    local baseline_status=$(grep -E "^## Status:" "$baseline" | head -1 || echo "UNKNOWN")

    if [[ "$current_status" == *"PASSED"* && "$baseline_status" == *"FAILED"* ]]; then
        echo "improved"
        return 0
    elif [[ "$current_status" == *"FAILED"* && "$baseline_status" == *"PASSED"* ]]; then
        echo "regressed"
        return 1
    elif [[ "$current_status" == "$baseline_status" ]]; then
        echo "unchanged"
        return 0
    else
        echo "unknown"
        return 0
    fi
}

# Save current results as baseline
save_baseline() {
    local current="$RALPH_DIR/tests/latest.md"
    local baseline="$RALPH_DIR/tests/baseline.md"

    if [[ -f "$current" ]]; then
        cp "$current" "$baseline"
        log_info "Saved test baseline"
    else
        log_error "No test results to save as baseline"
        return 1
    fi
}

# Check if tests are passing
tests_passing() {
    local results_file="${1:-$RALPH_DIR/tests/latest.md}"

    if [[ ! -f "$results_file" ]]; then
        return 1
    fi

    grep -q "## Status: PASSED" "$results_file"
}

# Extract test counts if available (basic parsing)
extract_test_counts() {
    local results_file="${1:-$RALPH_DIR/tests/latest.md}"

    if [[ ! -f "$results_file" ]]; then
        echo "passed=0 failed=0 total=0"
        return
    fi

    local content=$(cat "$results_file")

    # Try to extract counts from common test output formats
    # Jest: Tests: X passed, Y failed, Z total
    # pytest: X passed, Y failed
    # etc.

    local passed=$(echo "$content" | grep -oE '[0-9]+ pass(ed|ing)?' | head -1 | grep -oE '[0-9]+' || echo "0")
    local failed=$(echo "$content" | grep -oE '[0-9]+ fail(ed|ing|ure)?' | head -1 | grep -oE '[0-9]+' || echo "0")
    local total=$((passed + failed))

    echo "passed=$passed failed=$failed total=$total"
}

# CLI interface
case "${1:-}" in
    run)
        run_tests "${2:-}" "${3:-}" "${4:-}"
        ;;
    compare)
        compare_to_baseline
        ;;
    baseline)
        save_baseline
        ;;
    passing)
        if tests_passing "${2:-}"; then
            echo "true"
            exit 0
        else
            echo "false"
            exit 1
        fi
        ;;
    counts)
        extract_test_counts "${2:-}"
        ;;
    *)
        echo "Usage: tests.sh <command> [args...]"
        echo "Commands:"
        echo "  run <command> [output-file] [timeout]  - Run tests"
        echo "  compare                                 - Compare to baseline"
        echo "  baseline                                - Save current as baseline"
        echo "  passing [results-file]                  - Check if tests pass"
        echo "  counts [results-file]                   - Extract test counts"
        ;;
esac
