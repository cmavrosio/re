#!/usr/bin/env bash
#
# kori init - Initialize a new project
#

set -euo pipefail

source "$KORI_HOME/lib/common.sh"

usage() {
    cat << 'EOF'
kori init - Initialize a new project

USAGE:
    kori init <goal> [options]
    kori init -f <file>
    cat spec.md | kori init -

ARGUMENTS:
    <goal>            High-level project goal (in quotes)

OPTIONS:
    -f, --file FILE   Read goal/spec from a file
    -                 Read goal/spec from stdin
    -h, --help        Show this help

EXAMPLES:
    kori init "Build a CRM system for sales teams"
    kori init -f project-spec.md
    cat requirements.txt | kori init -
EOF
}

init_project() {
    local goal=""
    local from_file=""
    local from_stdin=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -f|--file)
                from_file="$2"
                shift 2
                ;;
            -)
                from_stdin=true
                shift
                ;;
            *)
                if [[ -z "$goal" ]]; then
                    goal="$1"
                else
                    goal="$goal $1"
                fi
                shift
                ;;
        esac
    done

    # Read from file if specified
    if [[ -n "$from_file" ]]; then
        if [[ ! -f "$from_file" ]]; then
            log_error "File not found: $from_file"
            exit 1
        fi
        goal=$(cat "$from_file")
    fi

    # Read from stdin if specified
    if [[ "$from_stdin" == "true" ]]; then
        goal=$(cat)
    fi

    if [[ -z "$goal" ]]; then
        log_error "No goal provided"
        echo ""
        usage
        exit 1
    fi

    # Check if already initialized
    if [[ -d "$OVERSEER_DIR" ]]; then
        log_warn ".overseer directory already exists"
        read -p "Reinitialize? This will reset everything. [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
        rm -rf "$OVERSEER_DIR"
    fi

    # Create directory structure
    log_info "Creating .overseer directory..."
    mkdir -p "$OVERSEER_DIR"/{nodes,logs}

    # Create project.md
    cat > "$OVERSEER_DIR/project.md" << EOF
# Project Goal

$goal

## Created

$(timestamp)

## Status

initialized
EOF

    # Create config
    cat > "$OVERSEER_DIR/config.yaml" << 'EOF'
# kori configuration

# Maximum tree depth (root = 0)
max_depth: 5

# Minimum criteria per leaf (before considered ready)
min_criteria_per_leaf: 3

# Maximum criteria per leaf
max_criteria_per_leaf: 10

# Claude model for discovery
discover_model: sonnet

# Claude model for planning
plan_model: sonnet

# Auto-run re after planning
auto_run: false

# Parallel leaf execution (number of concurrent re sessions)
parallel_leaves: 1
EOF

    # Create empty state
    cat > "$OVERSEER_DIR/state.yaml" << EOF
# kori state
phase: initialized
current_node: null
completed_leaves: 0
total_leaves: 0
started_at: $(timestamp)
EOF

    # Create .gitignore if not exists
    if [[ ! -f "$OVERSEER_DIR/.gitignore" ]]; then
        cat > "$OVERSEER_DIR/.gitignore" << 'EOF'
logs/
*.log
EOF
    fi

    log_success "Initialized project: $goal"
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo "  1. Run 'kori discover' to answer Claude's questions"
    echo "  2. Run 'kori plan' to generate the task tree"
    echo "  3. Run 'kori nag' to nag re to execute"
}

init_project "$@"
