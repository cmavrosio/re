#!/usr/bin/env bash
#
# kori discover - Structured Q&A to gather requirements
#

set -euo pipefail

source "$KORI_HOME/lib/common.sh"

usage() {
    cat << 'EOF'
kori discover - Structured Q&A to gather requirements

USAGE:
    kori discover [options]

OPTIONS:
    --resume          Resume from existing conversation
    -h, --help        Show this help

DESCRIPTION:
    Claude analyzes your project spec and asks clarifying questions.
    Questions are presented one at a time with structured answers.
    When done, requirements.md is generated.
EOF
}

discover() {
    local resume=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --resume)
                resume=true
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

    require_overseer_dir
    require_claude

    # Check for jq
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for JSON parsing. Install with: brew install jq"
        exit 1
    fi

    # Read the full project spec
    local spec
    spec=$(sed -n '/^# Project Goal/,/^## Created/p' "$OVERSEER_DIR/project.md" | grep -v "^# Project Goal" | grep -v "^## Created")

    if [[ -z "$spec" ]]; then
        spec=$(cat "$OVERSEER_DIR/project.md" | head -60)
    fi

    if [[ -z "$spec" ]]; then
        log_error "Could not read project spec from project.md"
        exit 1
    fi

    # Initialize conversation log
    mkdir -p "$OVERSEER_DIR/logs"

    echo ""
    echo -e "${BOLD}╭─────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${BOLD}│  KORI - Project Discovery                                   │${NC}"
    echo -e "${BOLD}│  Claude will ask clarifying questions about your project    │${NC}"
    echo -e "${BOLD}╰─────────────────────────────────────────────────────────────╯${NC}"
    echo ""

    # Update state
    sed -i.bak "s/^phase:.*/phase: discovering/" "$OVERSEER_DIR/state.yaml"
    rm -f "$OVERSEER_DIR/state.yaml.bak"

    local conversation=""
    local round=0
    local max_rounds=10
    local model
    model=$(read_config discover_model "sonnet")

    while [[ $round -lt $max_rounds ]]; do
        round=$((round + 1))

        log_info "Round $round: Analyzing project..."

        # Build prompt for Claude
        local prompt
        prompt="You are helping gather requirements for a software project. Analyze the spec and conversation history, then either ask clarifying questions OR indicate you have enough information.

PROJECT SPEC:
$spec

CONVERSATION SO FAR:
$conversation

INSTRUCTIONS:
1. If you need more information, respond with 1-3 questions in this JSON format:
{
  \"status\": \"need_more_info\",
  \"questions\": [
    {
      \"id\": \"q1\",
      \"question\": \"Your question here?\",
      \"context\": \"Brief explanation of why this matters\"
    }
  ]
}

2. If you have enough information to create a comprehensive task breakdown, respond with:
{
  \"status\": \"ready\",
  \"summary\": \"Brief summary of what you understood\"
}

Focus on questions about:
- Technical stack and architecture decisions
- Specific feature details that are unclear
- Priority and MVP scope
- Integration requirements
- Deployment and infrastructure

Do NOT ask about things already clearly specified in the spec.
Respond ONLY with valid JSON, no markdown code blocks, no other text."

        # Get Claude's response
        local response
        response=$(echo "$prompt" | claude --model "$model" --print 2>/dev/null || echo "")

        if [[ -z "$response" ]]; then
            log_error "No response from Claude"
            break
        fi

        # Debug: show raw response
        # echo "DEBUG: $response"

        # Extract JSON - try to find JSON object in response
        local json
        json=$(echo "$response" | grep -o '{.*}' | head -1 || echo "")

        # If that didn't work, try the whole response
        if [[ -z "$json" ]] || ! echo "$json" | jq . >/dev/null 2>&1; then
            json="$response"
        fi

        # Validate JSON
        if ! echo "$json" | jq . >/dev/null 2>&1; then
            log_error "Failed to parse Claude response as JSON"
            echo "Response was:"
            echo "$response"
            break
        fi

        # Parse status
        local status
        status=$(echo "$json" | jq -r '.status // empty')

        if [[ "$status" == "ready" ]]; then
            local summary
            summary=$(echo "$json" | jq -r '.summary // "Ready to proceed"')

            echo ""
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}  Claude has enough information to proceed!${NC}"
            echo ""
            echo -e "${DIM}  $summary${NC}"
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            break
        fi

        # Extract questions
        local num_questions
        num_questions=$(echo "$json" | jq '.questions | length')

        if [[ "$num_questions" == "0" ]] || [[ -z "$num_questions" ]]; then
            log_warn "No questions in response, ending discovery"
            break
        fi

        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}  Questions (Round $round)${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""

        # Display and collect answers for each question
        local answers=""
        for i in $(seq 0 $((num_questions - 1))); do
            local q_text q_context
            q_text=$(echo "$json" | jq -r ".questions[$i].question")
            q_context=$(echo "$json" | jq -r ".questions[$i].context // empty")

            echo -e "${BOLD}Q$((i + 1)): $q_text${NC}"
            if [[ -n "$q_context" ]]; then
                echo -e "${DIM}    $q_context${NC}"
            fi
            echo ""
            echo -n -e "${YELLOW}Your answer: ${NC}"
            local answer
            read -r answer
            echo ""

            answers="${answers}Q: $q_text
A: $answer

"
        done

        # Add to conversation history
        conversation="${conversation}

--- Round $round ---
$answers"

    done

    # Generate requirements.md
    log_info "Generating requirements.md..."
    generate_requirements "$spec" "$conversation" "$model"

    # Update state
    sed -i.bak "s/^phase:.*/phase: discovered/" "$OVERSEER_DIR/state.yaml"
    rm -f "$OVERSEER_DIR/state.yaml.bak"

    echo ""
    log_success "Discovery complete!"
    echo ""
    echo -e "${BOLD}Next step:${NC} Run 'kori plan' to generate the task tree"
}

generate_requirements() {
    local spec="$1"
    local conversation="$2"
    local model="$3"

    local prompt="Based on the project spec and discovery conversation, create a structured requirements document.

PROJECT SPEC:
$spec

DISCOVERY CONVERSATION:
$conversation

Create a markdown document with these sections:
# Project Requirements

## Overview
[One paragraph summary]

## Target Users
[User types and their needs]

## Core Features (MVP)
[Bullet list of must-have features]

## Technical Stack
[Technologies and architecture decisions]

## Data Model
[Key entities and relationships]

## Integrations
[External services, APIs]

## Non-Functional Requirements
[Performance, security, scalability]

## Out of Scope
[What is explicitly NOT included]

## Open Questions
[Any remaining uncertainties]

Be comprehensive but concise. This will drive the task breakdown."

    echo "$prompt" | claude --model "$model" --print > "$OVERSEER_DIR/requirements.md" 2>/dev/null

    if [[ -f "$OVERSEER_DIR/requirements.md" ]]; then
        echo ""
        echo -e "${BOLD}Requirements saved to:${NC} .overseer/requirements.md"
        echo ""
        echo -e "${DIM}Preview:${NC}"
        head -30 "$OVERSEER_DIR/requirements.md"
        echo -e "${DIM}...${NC}"
    fi
}

discover "$@"
