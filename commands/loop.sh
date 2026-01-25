#!/usr/bin/env bash
#
# re loop - Main iteration loop
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh"

RALPH_DIR=".ralph"

usage() {
    cat << 'EOF'
re loop - Run the main iteration loop

USAGE:
    re loop [options]

OPTIONS:
    --max-iterations N    Override max iterations
    --single              Run only one iteration
    -h, --help            Show this help

DESCRIPTION:
    This is the core loop that:
    1. Builds context from current state
    2. Calls Claude
    3. Analyzes the response
    4. Updates state
    5. Checks circuit breaker
    6. Makes decision to continue/stop

    Usually called by 're start' or 're resume'.
EOF
}

# Show progress after each iteration
show_progress() {
    echo ""
    echo -e "${BOLD}────────────────────────────────────────────────────────────${NC}"

    # Current criterion
    local current
    current=$(grep -E "^- \[ \] [0-9]+\." "$RALPH_DIR/state.md" 2>/dev/null | head -1 | sed 's/^- \[ \] //')
    if [[ -n "$current" ]]; then
        echo -e " ${CYAN}Next:${NC} $current"
    fi

    # Tests added (look for new test functions in uncommitted changes)
    local new_tests
    new_tests=$(git diff 2>/dev/null | grep -E "^\+.*def test_" | sed 's/^+.*def //' | sed 's/(.*$//' | tail -5 || true)
    if [[ -n "$new_tests" ]]; then
        echo -e " ${GREEN}Tests added:${NC}"
        echo "$new_tests" | while read -r t; do
            echo -e "   + $t"
        done
    fi

    # Completed criteria count
    local done_count
    done_count=$(grep -cE "^- \[x\] [0-9]+\." "$RALPH_DIR/state.md" 2>/dev/null || echo "0")
    local total_count
    total_count=$(grep -cE "^- \[[ x]\] [0-9]+\." "$RALPH_DIR/state.md" 2>/dev/null || echo "0")
    echo -e " ${DIM}Progress: $done_count/$total_count criteria${NC}"

    echo -e "${BOLD}────────────────────────────────────────────────────────────${NC}"
    echo ""
}

# Session state for hybrid mode
SESSION_ID=""
SESSION_START_ITERATION=0
RULES_MTIME=""
URGENT_MTIME=""

# Get file modification time (cross-platform)
get_mtime() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat -f "%m" "$file" 2>/dev/null || stat -c "%Y" "$file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Check if we need to refresh the session (hybrid mode)
should_refresh() {
    local iteration="$1"
    local session_mode
    session_mode=$(read_config session_mode "hybrid")

    # Stateless mode: always refresh
    if [[ "$session_mode" == "stateless" ]]; then
        return 0
    fi

    # First iteration: always refresh
    if [[ -z "$SESSION_ID" || "$iteration" -eq 1 ]]; then
        return 0
    fi

    # Check refresh interval
    local refresh_interval
    refresh_interval=$(read_config refresh_interval 5)
    local iterations_since_refresh=$((iteration - SESSION_START_ITERATION))
    if [[ $iterations_since_refresh -ge $refresh_interval ]]; then
        log_debug "Refresh: interval reached ($iterations_since_refresh >= $refresh_interval)"
        return 0
    fi

    # Check if rules.md changed (steering file)
    if [[ "$(read_config refresh_on_rules true)" == "true" ]]; then
        local current_rules_mtime
        current_rules_mtime=$(get_mtime "$RALPH_DIR/rules.md")
        if [[ "$current_rules_mtime" != "$RULES_MTIME" && -n "$RULES_MTIME" ]]; then
            log_debug "Refresh: rules.md changed"
            return 0
        fi
    fi

    # Check if urgent.md exists (injection)
    if [[ "$(read_config refresh_on_inject true)" == "true" ]]; then
        if [[ -f "$RALPH_DIR/urgent.md" && -s "$RALPH_DIR/urgent.md" ]]; then
            local current_urgent_mtime
            current_urgent_mtime=$(get_mtime "$RALPH_DIR/urgent.md")
            if [[ "$current_urgent_mtime" != "$URGENT_MTIME" ]]; then
                log_debug "Refresh: urgent.md changed (injection)"
                return 0
            fi
        fi
    fi

    # Check if last iteration had CRITERION_DONE
    if [[ "$(read_config refresh_on_criterion false)" == "true" ]]; then
        if [[ -f "$RALPH_DIR/signals.yaml" ]]; then
            local criteria_done
            criteria_done=$(grep "criteria_done:" "$RALPH_DIR/signals.yaml" 2>/dev/null | grep -v "\[\]" || true)
            if [[ -n "$criteria_done" ]]; then
                log_debug "Refresh: criterion completed"
                return 0
            fi
        fi
    fi

    # No refresh needed
    return 1
}

# Update session tracking after refresh
update_session_tracking() {
    local iteration="$1"
    SESSION_START_ITERATION=$iteration
    RULES_MTIME=$(get_mtime "$RALPH_DIR/rules.md")
    URGENT_MTIME=$(get_mtime "$RALPH_DIR/urgent.md")
}

# Run a single iteration
run_iteration() {
    local iteration="$1"

    log_info "Starting iteration $iteration"
    log_to_file "Iteration $iteration started"

    # Determine if we need full refresh or can continue session
    local do_refresh=false
    local session_mode
    session_mode=$(read_config session_mode "hybrid")

    if [[ "$session_mode" == "stateless" ]] || should_refresh "$iteration"; then
        do_refresh=true
        log_info "Building full context (refresh)..."
    else
        log_info "Building continue context (same session)..."
    fi

    # 1. Build context
    local context_file="$RALPH_DIR/context/current.md"
    local compress_flag=""
    if [[ "$(read_config compress_iterations true)" == "true" ]]; then
        compress_flag="--compress"
    fi

    if [[ "$do_refresh" == "true" ]]; then
        bb --classpath "$RE_HOME/lib" -m brain.context-builder "$RALPH_DIR" $compress_flag > "$context_file"
        update_session_tracking "$iteration"
        SESSION_ID=""  # Clear session ID to start fresh
    else
        bb --classpath "$RE_HOME/lib" -m brain.context-builder "$RALPH_DIR" --continue $compress_flag > "$context_file"
    fi

    # 2. Execute Claude
    log_info "Calling Claude..."
    local response_file="$RALPH_DIR/response.json"
    local model
    model=$(read_config model sonnet)
    local continue_flag="false"
    if [[ "$do_refresh" == "false" && -n "$SESSION_ID" ]]; then
        continue_flag="true"
    fi

    if ! bash "$RE_HOME/lib/providers/provider.sh" execute "$context_file" "$response_file" "$model" "$SESSION_ID" "$continue_flag"; then
        log_error "Claude execution failed"
        # Update health with error
        echo "success: false" | bb --classpath "$RE_HOME/lib" -m brain.circuit-breaker update "$RALPH_DIR"
        return 1
    fi

    # Extract and save session ID for continuation
    local new_session_id
    new_session_id=$(bash "$RE_HOME/lib/providers/provider.sh" extract-session-id "$response_file")
    if [[ -n "$new_session_id" ]]; then
        SESSION_ID="$new_session_id"
        echo "$SESSION_ID" > "$RALPH_DIR/.session_id"
    fi

    # 3. Extract response and tokens
    local response_text
    response_text=$(bash "$RE_HOME/lib/providers/provider.sh" extract-response "$response_file")

    local tokens
    tokens=$(bash "$RE_HOME/lib/providers/provider.sh" extract-tokens "$response_file")
    local input_tokens=$(echo "$tokens" | cut -d' ' -f1)
    local output_tokens=$(echo "$tokens" | cut -d' ' -f2)

    # Track tokens
    bb --classpath "$RE_HOME/lib" -m brain.budget add "$RALPH_DIR" "$iteration" "$input_tokens" "$output_tokens"

    # 4. Analyze response
    log_info "Analyzing response..."
    echo "$response_text" | bb --classpath "$RE_HOME/lib" -m brain.response-analyzer analyze - > "$RALPH_DIR/signals.yaml"

    # Save iteration record
    local iter_file=$(printf "$RALPH_DIR/context/iterations/%03d.md" "$iteration")
    {
        echo "# Iteration $iteration"
        echo ""
        echo "**Timestamp:** $(timestamp)"
        echo "**Tokens:** $input_tokens in / $output_tokens out"
        echo ""
        echo "## Response Summary"
        echo ""
        echo "$response_text" | head -50
        echo ""
        echo "## Signals"
        echo ""
        echo '```yaml'
        cat "$RALPH_DIR/signals.yaml"
        echo '```'
    } > "$iter_file"

    # 5. Track diff changes
    log_info "Checking changes..."

    if bash "$RE_HOME/lib/orchestration/git.sh" has-changes 2>/dev/null; then
        # Get and categorize diff
        bash "$RE_HOME/lib/orchestration/git.sh" uncommitted-diff numstat | \
            bb --classpath "$RE_HOME/lib" -m brain.diff-categorizer categorize > "$RALPH_DIR/diff/current.md"
        local has_changes=true
    else
        echo "_No uncommitted changes_" > "$RALPH_DIR/diff/current.md"
        local has_changes=false
    fi

    # 6. Run tests if configured
    local test_command
    test_command=$(read_config test_command "")
    local tests_passed=true
    if [[ -n "$test_command" ]]; then
        log_info "Running tests..."
        if ! bash "$RE_HOME/lib/orchestration/tests.sh" run "$test_command"; then
            tests_passed=false
            log_warn "Tests failed"

            # Inject urgent message to focus Claude on fixing tests
            local current_failures
            current_failures=$(grep "consecutive_test_failures:" "$RALPH_DIR/health.yaml" 2>/dev/null | cut -d' ' -f2 || echo "0")
            current_failures=$((current_failures + 1))
            local remaining=$((5 - current_failures))

            cat > "$RALPH_DIR/urgent.md" << URGENT_EOF
## TESTS ARE FAILING - FIX BEFORE CONTINUING

The test suite is failing. You MUST fix these test failures before continuing with other work.

**Attempt $current_failures of 5** - $remaining attempts remaining before circuit break.

Review the test output in the Test Results section below and fix the issues.
Common fixes:
- Type errors: Check function signatures and return types
- Import errors: Verify all imports exist and are correct
- Runtime errors: Check for null/undefined access

Focus ONLY on fixing the failing tests. Do not continue with new features until tests pass.
URGENT_EOF
            log_warn "Injected urgent.md to focus on test fixes (attempt $current_failures/5)"
        else
            # Tests passed - remove test fix urgent message if it exists
            if [[ -f "$RALPH_DIR/urgent.md" ]] && grep -q "TESTS ARE FAILING" "$RALPH_DIR/urgent.md" 2>/dev/null; then
                rm -f "$RALPH_DIR/urgent.md"
                log_info "Tests passing - removed test fix urgent message"
            fi
        fi
    fi

    # 7. Check for test-only loop
    local test_only=false
    if grep -q "test_only_loop: true" "$RALPH_DIR/signals.yaml" 2>/dev/null; then
        test_only=true
    fi

    # 8. Check for criteria completion (before health update)
    local criteria_done criterion_completed=false
    criteria_done=$(grep "criteria_done:" "$RALPH_DIR/signals.yaml" | sed 's/criteria_done: \[//' | sed 's/\]//' | tr ',' '\n' | tr -d ' ')
    for num in $criteria_done; do
        if [[ -n "$num" ]]; then
            log_info "Marking criterion $num as complete"
            # Update checkbox in state.md
            sed -i.bak "s/- \[ \] $num\./- [x] $num./" "$RALPH_DIR/state.md"
            rm -f "$RALPH_DIR/state.md.bak"
            criterion_completed=true
        fi
    done

    # 9. Update health (now includes criterion_completed flag and test status)
    {
        echo "success: true"
        echo "has_changes: $has_changes"
        echo "test_only: $test_only"
        echo "criterion_completed: $criterion_completed"
        echo "tests_passed: $tests_passed"
    } | bb --classpath "$RE_HOME/lib" -m brain.circuit-breaker update "$RALPH_DIR"

    # 10. Auto-commit if configured
    local auto_commit_interval
    auto_commit_interval=$(read_config auto_commit_interval 5)
    local auto_push
    auto_push=$(read_config auto_push false)
    if [[ "$auto_commit_interval" -gt 0 ]] && [[ $((iteration % auto_commit_interval)) -eq 0 ]]; then
        if bash "$RE_HOME/lib/orchestration/git.sh" has-changes 2>/dev/null; then
            log_info "Auto-committing (iteration $iteration)..."
            bash "$RE_HOME/lib/orchestration/git.sh" commit "auto-commit" "$iteration" "$auto_push" || true
        fi
    fi

    # 11. Update iteration count in state.md
    sed -i.bak "s/^iteration: .*/iteration: $iteration/" "$RALPH_DIR/state.md"
    rm -f "$RALPH_DIR/state.md.bak"

    log_to_file "Iteration $iteration completed"
    return 0
}

# Make a decision about next action
make_decision() {
    local decision
    decision=$(bb --classpath "$RE_HOME/lib" -m brain.decision "$RALPH_DIR")

    local action
    action=$(echo "$decision" | grep "^action:" | cut -d' ' -f2)

    echo "$decision" > "$RALPH_DIR/decision.yaml"

    echo "$action"
}

# Check if all criteria are complete
all_criteria_complete() {
    if [[ ! -f "$RALPH_DIR/state.md" ]]; then
        return 1
    fi

    # Check if there are any unchecked criteria
    if grep -E "^- \[ \] [0-9]+\." "$RALPH_DIR/state.md" > /dev/null 2>&1; then
        return 1
    fi

    return 0
}

# Main loop
main_loop() {
    local max_iterations
    max_iterations=$(read_config max_iterations 50)
    local single_iteration=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-iterations)
                max_iterations="$2"
                shift 2
                ;;
            --single)
                single_iteration=true
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

    # Write PID file for abort/pause to find us
    echo $$ > "$RALPH_DIR/.loop.pid"

    # Cleanup PID file on exit
    cleanup_pid() {
        rm -f "$RALPH_DIR/.loop.pid"
    }
    trap cleanup_pid EXIT

    # Get current iteration
    local iteration
    iteration=$(read_frontmatter "$RALPH_DIR/state.md" "iteration")
    iteration=$((iteration + 1))

    # Update status to running
    sed -i.bak "s/^status: .*/status: running/" "$RALPH_DIR/state.md"
    rm -f "$RALPH_DIR/state.md.bak"

    log_info "Starting loop at iteration $iteration (max: $max_iterations)"

    while [[ $iteration -le $max_iterations ]]; do
        # Run iteration
        if ! run_iteration "$iteration"; then
            log_error "Iteration $iteration failed"
            # Decision will handle this via health check
        fi

        # Check if all criteria are complete
        if all_criteria_complete; then
            log_success "All criteria complete!"
            sed -i.bak "s/^status: .*/status: completed/" "$RALPH_DIR/state.md"
            rm -f "$RALPH_DIR/state.md.bak"
            exit 0
        fi

        # Make decision
        local action
        action=$(make_decision)

        case "$action" in
            continue)
                if [[ "$single_iteration" == "true" ]]; then
                    log_info "Single iteration complete"
                    exit 0
                fi
                # Check for pause request
                if [[ -f "$RALPH_DIR/.pause_requested" ]]; then
                    rm -f "$RALPH_DIR/.pause_requested"
                    log_warn "Pause requested by user"
                    sed -i.bak "s/^status: .*/status: paused/" "$RALPH_DIR/state.md"
                    rm -f "$RALPH_DIR/state.md.bak"
                    exit 0
                fi
                # Show progress
                show_progress
                iteration=$((iteration + 1))
                ;;
            complete)
                log_success "Task completed!"
                sed -i.bak "s/^status: .*/status: completed/" "$RALPH_DIR/state.md"
                rm -f "$RALPH_DIR/state.md.bak"
                # Final commit and push
                if bash "$RE_HOME/lib/orchestration/git.sh" has-changes 2>/dev/null; then
                    local final_auto_push
                    final_auto_push=$(read_config auto_push false)
                    bash "$RE_HOME/lib/orchestration/git.sh" commit "task completed" "$iteration" "$final_auto_push" || true
                fi

                # Run post-completion checks if configured
                local post_complete_checks
                post_complete_checks=$(read_config post_complete_checks "")
                if [[ -n "$post_complete_checks" && "$post_complete_checks" != "nil" ]]; then
                    log_info "Running post-completion checks..."

                    IFS=';' read -ra checks <<< "$post_complete_checks"
                    for check in "${checks[@]}"; do
                        check=$(echo "$check" | xargs)
                        if [[ -n "$check" ]]; then
                            log_info "  Running: $check"
                            if ! eval "$check"; then
                                log_warn "Post-completion check failed: $check"
                                log_warn "Task is complete but check failed - manual review needed"
                            fi
                        fi
                    done
                fi
                exit 0
                ;;
            verify)
                log_warn "High completion confidence - please verify"
                sed -i.bak "s/^status: .*/status: verify/" "$RALPH_DIR/state.md"
                rm -f "$RALPH_DIR/state.md.bak"
                exit 0
                ;;
            pause)
                local reason
                reason=$(grep "^reason:" "$RALPH_DIR/decision.yaml" | cut -d'"' -f2)
                log_warn "Paused: $reason"
                sed -i.bak "s/^status: .*/status: paused/" "$RALPH_DIR/state.md"
                rm -f "$RALPH_DIR/state.md.bak"
                exit 0
                ;;
            abort)
                local reason
                reason=$(grep "^reason:" "$RALPH_DIR/decision.yaml" | cut -d'"' -f2)
                log_error "Aborted: $reason"
                sed -i.bak "s/^status: .*/status: aborted/" "$RALPH_DIR/state.md"
                rm -f "$RALPH_DIR/state.md.bak"
                exit 1
                ;;
        esac
    done

    # Check if task is actually complete before aborting
    local total_criteria completed_criteria
    total_criteria=$(grep -c "^- \[" "$RALPH_DIR/state.md" 2>/dev/null || echo "0")
    completed_criteria=$(grep -c "^- \[x\]" "$RALPH_DIR/state.md" 2>/dev/null || echo "0")

    if [[ "$total_criteria" -gt 0 && "$completed_criteria" -eq "$total_criteria" ]]; then
        log_success "Max iterations reached but task is complete!"
        sed -i.bak "s/^status: .*/status: completed/" "$RALPH_DIR/state.md"
        rm -f "$RALPH_DIR/state.md.bak"
        if bash "$RE_HOME/lib/orchestration/git.sh" has-changes 2>/dev/null; then
            local final_auto_push
            final_auto_push=$(read_config auto_push false)
            bash "$RE_HOME/lib/orchestration/git.sh" commit "task completed (max iterations)" "$iteration" "$final_auto_push" || true
        fi
        exit 0
    fi

    log_error "Max iterations reached ($completed_criteria/$total_criteria criteria done)"
    sed -i.bak "s/^status: .*/status: aborted/" "$RALPH_DIR/state.md"
    rm -f "$RALPH_DIR/state.md.bak"
    exit 1
}

main_loop "$@"
