#!/usr/bin/env bash
#
# re start - Start a new task session
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh"

RALPH_DIR=".ralph"

usage() {
    cat << 'EOF'
re start - Start a new task session

USAGE:
    re start [options]

OPTIONS:
    -h, --help      Show this help

DESCRIPTION:
    Starts a new task session from .ralph/plan.md:
    1. Initializes state.md from plan.md
    2. Runs initial tests as baseline
    3. Starts the iteration loop

PREREQUISITES:
    - .ralph/ directory must exist (run 're init' first)
    - .ralph/plan.md must be filled out with your task
EOF
}

start_session() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
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

    # Ensure repo has at least one commit (for fresh repos)
    bash "$RE_HOME/lib/orchestration/git.sh" ensure-initial-commit

    # Check if session already exists
    if [[ -f "$RALPH_DIR/state.md" ]]; then
        local status
        status=$(read_frontmatter "$RALPH_DIR/state.md" "status")

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

        case "$status" in
            running)
                log_error "A session is already running"
                echo "Use 're resume' to continue or 're abort' to stop it."
                exit 1
                ;;
            paused|crashed)
                log_error "A session exists (status: $status)"
                echo "Use 're resume' to continue or 're abort' to stop it."
                exit 1
                ;;
            completed|aborted)
                log_warn "Previous session found (status: $status)"
                echo "Starting a new session will archive the previous state."
                # Archive old state
                local old_session_id
                old_session_id=$(read_frontmatter "$RALPH_DIR/state.md" "session_id" 2>/dev/null || echo "unknown")
                local archive_dir="$RALPH_DIR/archive/$(date +%Y%m%d_%H%M%S)_${old_session_id}"
                mkdir -p "$archive_dir"
                mv "$RALPH_DIR/state.md" "$archive_dir/"
                mv "$RALPH_DIR/context/iterations" "$archive_dir/" 2>/dev/null || true
                mv "$RALPH_DIR/tokens" "$archive_dir/" 2>/dev/null || true
                mkdir -p "$RALPH_DIR/context/iterations"
                mkdir -p "$RALPH_DIR/tokens"
                ;;
        esac
    fi

    # Check plan.md exists and has content
    if [[ ! -f "$RALPH_DIR/plan.md" ]]; then
        log_error "No plan.md found. Create .ralph/plan.md with your task definition."
        exit 1
    fi

    # Check for unmerged completed work from previous sessions
    if [[ -d "$RALPH_DIR/archive" ]]; then
        local latest_archive=$(ls -t "$RALPH_DIR/archive" 2>/dev/null | head -1)
        if [[ -n "$latest_archive" && -f "$RALPH_DIR/archive/$latest_archive/state.md" ]]; then
            local archived_done
            archived_done=$(grep -cE "^- \[x\] [0-9]+\." "$RALPH_DIR/archive/$latest_archive/state.md" 2>/dev/null | tr -d '\n' || echo "0")
            [[ -z "$archived_done" ]] && archived_done=0
            local plan_done
            plan_done=$(grep -cE "^- \[x\] [0-9]+\." "$RALPH_DIR/plan.md" 2>/dev/null | tr -d '\n' || echo "0")
            [[ -z "$plan_done" ]] && plan_done=0

            if [[ "$archived_done" -gt 0 && "$plan_done" -lt "$archived_done" ]]; then
                log_warn "Previous session had $archived_done completed criteria, but plan.md only has $plan_done checked."
                echo ""
                echo "This may cause Claude to loop because it sees completed work but criteria are unchecked."
                echo ""
                echo "Options:"
                echo "  1. Run 're merge --from-archive' to sync completed criteria to plan.md"
                echo "  2. Manually mark completed criteria as [x] in plan.md"
                echo "  3. Continue anyway (may cause issues)"
                echo ""
                read -p "Continue starting new session? [y/N] " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "Aborted. Run 're merge --from-archive' or update plan.md first."
                    exit 0
                fi
            fi
        fi
    fi

    # Run pre-start checks if configured
    local pre_start_checks
    pre_start_checks=$(read_config pre_start_checks "")
    if [[ -n "$pre_start_checks" && "$pre_start_checks" != "nil" ]]; then
        log_info "Running pre-start checks..."

        # Split by semicolon and run each check
        IFS=';' read -ra checks <<< "$pre_start_checks"
        for check in "${checks[@]}"; do
            check=$(echo "$check" | xargs)  # trim whitespace
            if [[ -n "$check" ]]; then
                log_info "  Running: $check"
                if ! eval "$check"; then
                    log_error "Pre-start check failed: $check"
                    echo ""
                    echo "Fix the issue or remove the check from config:"
                    echo "  re config set pre_start_checks \"\""
                    exit 1
                fi
            fi
        done
        log_success "All pre-start checks passed"
    fi

    # Parse plan
    log_info "Parsing plan.md..."

    # Generate session ID
    local session_id
    session_id=$(generate_session_id)

    # Get config
    local max_iterations
    max_iterations=$(read_config max_iterations 50)
    local max_tokens
    max_tokens=$(read_config max_tokens 500000)

    # Create state.md from plan
    log_info "Creating state.md..."
    local started_at
    started_at=$(timestamp)

    # Extract task, criteria, and steps from plan using bb
    bb --classpath "$RE_HOME/lib" -e "
        (require '[brain.plan-parser :as p]
                 '[clojure.string :as str])
        (let [content (slurp \"$RALPH_DIR/plan.md\")
              parsed (p/parse-plan content)
              criteria (:criteria parsed)
              steps (:steps parsed)]
          (println \"---\")
          (println \"session_id: $session_id\")
          (println \"started_at: $started_at\")
          (println \"iteration: 0\")
          (println \"status: initialized\")
          (println \"---\")
          (println)
          (println \"# Task\")
          (println)
          (println (:task parsed))
          (println)
          (println \"## Completion Criteria\")
          (println)
          (if (empty? criteria)
            (println \"- [ ] 0. Define completion criteria\")
            (doseq [{:keys [checked number text]} criteria]
              (println (str \"- [\" (if checked \"x\" \" \") \"] \" number \". \" text))))
          (println)
          (println \"## Implementation Plan\")
          (println)
          (if (empty? steps)
            (println \"_No steps defined_\")
            (doseq [[i {:keys [checked text]}] (map-indexed vector steps)]
              (println (str \"- [\" (if checked \"x\" \" \") \"] Step \" (inc i) \": \" text))))
          (println)
          (println \"## Budget\")
          (println)
          (println \"| Metric | Current | Maximum |\")
          (println \"|--------|---------|---------|\" )
          (println \"| Iterations | 0 | $max_iterations |\")
          (println \"| Tokens | 0 | $max_tokens |\"))" > "$RALPH_DIR/state.md"

    # Reset health
    bb --classpath "$RE_HOME/lib" -m brain.circuit-breaker reset "$RALPH_DIR"

    # Clear previous context
    rm -f "$RALPH_DIR/context/summary.md"
    touch "$RALPH_DIR/context/summary.md"
    rm -f "$RALPH_DIR/diff/current.md"
    rm -f "$RALPH_DIR/urgent.md"
    rm -f "$RALPH_DIR/signals.yaml"
    rm -f "$RALPH_DIR/decision.yaml"
    rm -f "$RALPH_DIR/.pause_requested"

    # Reset token usage
    cat > "$RALPH_DIR/tokens/usage.md" << 'EOF'
# Token Usage

| Iteration | Input | Output | Total | Cumulative |
|-----------|-------|--------|-------|------------|
EOF

    # Run initial tests as baseline
    local test_command
    test_command=$(read_config test_command "")
    if [[ -n "$test_command" ]]; then
        log_info "Running baseline tests..."
        bash "$RE_HOME/lib/orchestration/tests.sh" run "$test_command" || true
        bash "$RE_HOME/lib/orchestration/tests.sh" baseline
    fi

    log_success "Session $session_id started"
    echo ""

    # Start the loop
    log_info "Starting iteration loop..."
    exec bash "$RE_HOME/commands/loop.sh"
}

start_session "$@"
