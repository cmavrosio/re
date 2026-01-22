#!/usr/bin/env bash
#
# kori plan - Build task tree from requirements (autonomous)
#

set -euo pipefail

source "$KORI_HOME/lib/common.sh"

usage() {
    cat << 'EOF'
kori plan - Build task tree from requirements

USAGE:
    kori plan [options]

OPTIONS:
    --max-depth N     Maximum tree depth (default: from config)
    --dry-run         Show what would be planned without saving
    -h, --help        Show this help

DESCRIPTION:
    Autonomously builds a hierarchical task tree from requirements.
    Claude breaks down the project into features, then tasks, then
    specific criteria that can be executed by re.

    The tree is saved to .overseer/tree.yaml with detailed node
    descriptions in .overseer/nodes/
EOF
}

plan() {
    local max_depth=""
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-depth)
                max_depth="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
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

    require_requirements
    require_claude

    # Read config
    if [[ -z "$max_depth" ]]; then
        max_depth=$(read_config max_depth 5)
    fi
    local min_criteria=$(read_config min_criteria_per_leaf 3)
    local max_criteria=$(read_config max_criteria_per_leaf 10)
    local model=$(read_config plan_model "sonnet")

    # Read the full project spec
    local goal
    goal=$(sed -n '/^# Project Goal/,/^## Created/p' "$OVERSEER_DIR/project.md" | grep -v "^# Project Goal" | grep -v "^## Created")

    if [[ -z "$goal" ]]; then
        goal=$(cat "$OVERSEER_DIR/project.md" | head -60)
    fi

    local requirements
    requirements=$(cat "$OVERSEER_DIR/requirements.md")

    log_info "Building task tree..."
    log_info "Max depth: $max_depth"
    log_info "Criteria per leaf: $min_criteria-$max_criteria"
    echo ""

    # Update state
    sed -i.bak "s/^phase:.*/phase: planning/" "$OVERSEER_DIR/state.yaml"
    rm -f "$OVERSEER_DIR/state.yaml.bak"

    # Build the planning prompt (avoid backticks which cause shell issues)
    local prompt="You are a software architect creating a hierarchical task breakdown for a project.

PROJECT GOAL:
$goal

REQUIREMENTS:
$requirements

YOUR TASK:
Create a hierarchical task tree in YAML format. The tree should:

1. Start with the root node (the entire project)
2. Break down into major components/features (depth 1)
3. Continue breaking down until leaf nodes have $min_criteria-$max_criteria specific, actionable criteria
4. Maximum depth: $max_depth levels
5. Each leaf criteria should be completable by an AI coding assistant in one focused session

YAML FORMAT (output raw YAML, no markdown code blocks):

nodes:
  root:
    title: \"Project Title\"
    description: |
      Brief description of the entire project
    status: pending
    children: [feature-1, feature-2, feature-3]

  feature-1:
    title: \"Feature Name\"
    description: |
      What this feature does
    parent: root
    status: pending
    children: [task-1a, task-1b]

  task-1a:
    title: \"Specific Task\"
    description: |
      Detailed description of this task
    parent: feature-1
    status: pending
    is_leaf: true
    criteria:
      - \"Specific verifiable outcome 1\"
      - \"Specific verifiable outcome 2\"
      - \"All tests pass\"

RULES:
- Use kebab-case for node IDs (e.g., user-auth, api-endpoints)
- Every non-root node must have a parent
- Only leaf nodes have criteria and is_leaf: true
- Criteria should be specific and verifiable
- Include a tests pass criterion for testable tasks
- Order children by logical dependency (what should be built first)
- Balance the tree (avoid one branch having 20 children while another has 2)

Generate the complete YAML content now. Output ONLY raw YAML starting with 'nodes:', no markdown, no explanations."

    # Call Claude to generate the tree
    log_info "Calling Claude to generate tree..."
    local tree_content
    tree_content=$(echo "$prompt" | claude --model "$model" --print 2>/dev/null)

    # Clean up response - remove any markdown code blocks if present
    tree_content=$(echo "$tree_content" | sed '/^```/d')

    # Ensure it starts with nodes:
    if ! echo "$tree_content" | grep -q "^nodes:"; then
        # Try to extract from after any preamble
        tree_content=$(echo "$tree_content" | sed -n '/^nodes:/,$p')
    fi

    if [[ -z "$tree_content" ]]; then
        log_error "Failed to generate tree"
        exit 1
    fi

    if [[ "$dry_run" == "true" ]]; then
        echo -e "${BOLD}Generated tree (dry run):${NC}"
        echo "$tree_content"
        exit 0
    fi

    # Save tree
    echo "$tree_content" > "$OVERSEER_DIR/tree.yaml"
    log_success "Tree saved to .overseer/tree.yaml"

    # Count nodes and leaves using jq-style parsing with yq or simple grep
    local node_count leaf_count
    node_count=$(grep -c "^  [a-z]" "$OVERSEER_DIR/tree.yaml" 2>/dev/null || echo "?")
    leaf_count=$(grep -c "is_leaf: true" "$OVERSEER_DIR/tree.yaml" 2>/dev/null || echo "?")

    echo ""
    echo -e "${BOLD}Tree Statistics:${NC}"
    echo "  Nodes: $node_count"
    echo "  Leaves: $leaf_count"

    # Update state with leaf count
    if [[ "$leaf_count" != "?" ]]; then
        sed -i.bak "s/^total_leaves:.*/total_leaves: $leaf_count/" "$OVERSEER_DIR/state.yaml"
        rm -f "$OVERSEER_DIR/state.yaml.bak"
    fi

    # Update phase
    sed -i.bak "s/^phase:.*/phase: planned/" "$OVERSEER_DIR/state.yaml"
    rm -f "$OVERSEER_DIR/state.yaml.bak"

    # Generate setup instructions
    log_info "Generating setup instructions..."
    generate_setup "$requirements" "$model"

    echo ""
    echo -e "${BOLD}Next step:${NC} Run 'kori tree' to view, or 'kori nag' to execute"
}

generate_setup() {
    local requirements="$1"
    local model="$2"

    local setup_prompt="Based on the project requirements below, output a setup guide in markdown format.

REQUIREMENTS:
$requirements

IMPORTANT: Output ONLY the raw markdown content. Do NOT describe what you will create. Do NOT ask questions. Just output the markdown starting with the # header.

# Project Setup Guide

## Prerequisites
- List required accounts (GitHub, Supabase, Cloudflare, etc.)
- Required CLI tools to install

## Environment Variables
List ALL required environment variables in a table:
| Variable | Description | Where to get it |
|----------|-------------|-----------------|
| SUPABASE_URL | Supabase project URL | Supabase Dashboard > Settings > API |
| ... | ... | ... |

## Local Development Setup
Step-by-step instructions to run locally:
1. Clone repo
2. Install dependencies
3. Set up .env.local
4. Run database migrations (if applicable)
5. Start dev server

## Supabase Setup
- How to create project
- Database schema setup
- Row Level Security policies needed
- Auth configuration

## Cloudflare Pages Setup
- How to connect repo
- Build settings
- Environment variables to add in Cloudflare dashboard

## GitHub Setup
- Required secrets for CI/CD (if any)
- Branch protection rules (optional)

## Testing the Setup
How to verify everything works:
- Health check endpoints
- Test user creation
- etc.

Be specific to the tech stack mentioned in requirements. Include exact paths in dashboards where secrets are found.

OUTPUT THE MARKDOWN NOW. Start with '# Project Setup Guide' - no preamble, no questions, just the markdown content."

    echo "$setup_prompt" | claude --model "$model" --print > "$OVERSEER_DIR/setup.md" 2>/dev/null

    if [[ -f "$OVERSEER_DIR/setup.md" ]]; then
        echo ""
        echo -e "${BOLD}Setup guide saved to:${NC} .overseer/setup.md"
        echo ""
        echo -e "${DIM}Preview:${NC}"
        head -40 "$OVERSEER_DIR/setup.md"
        echo -e "${DIM}...${NC}"
    fi
}

plan "$@"
