#!/usr/bin/env bash
#
# kori setup - Generate setup instructions
#

set -euo pipefail

source "$KORI_HOME/lib/common.sh"

usage() {
    cat << 'EOF'
kori setup - Generate setup instructions

USAGE:
    kori setup [options]

OPTIONS:
    -h, --help        Show this help

DESCRIPTION:
    Generates .overseer/setup.md with:
    - Required environment variables and where to find them
    - Local development setup steps
    - Supabase, Cloudflare Pages, GitHub setup guides
    - Testing instructions

    Requires requirements.md to exist (run 'kori discover' first).
EOF
}

setup() {
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

    require_overseer_dir
    require_claude

    if [[ ! -f "$OVERSEER_DIR/requirements.md" ]]; then
        log_error "No requirements.md found. Run 'kori discover' first."
        exit 1
    fi

    local requirements
    requirements=$(cat "$OVERSEER_DIR/requirements.md")

    local model
    model=$(read_config plan_model "sonnet")

    log_info "Generating setup instructions..."

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

    if [[ -f "$OVERSEER_DIR/setup.md" ]] && [[ -s "$OVERSEER_DIR/setup.md" ]]; then
        echo ""
        log_success "Setup guide saved to .overseer/setup.md"
        echo ""
        echo -e "${DIM}Preview:${NC}"
        head -50 "$OVERSEER_DIR/setup.md"
        echo -e "${DIM}...${NC}"
    else
        log_error "Failed to generate setup.md"
        exit 1
    fi
}

setup "$@"
