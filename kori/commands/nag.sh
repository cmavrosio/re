#!/usr/bin/env bash
#
# kori nag - Nag re to execute leaves (autonomous)
#
# Like Lisa nagging Ralph to do his homework
#

set -euo pipefail

source "$KORI_HOME/lib/common.sh"

usage() {
    cat << 'EOF'
kori nag - Nag re to execute leaves

USAGE:
    kori nag [options]

OPTIONS:
    --leaf <id>       Nag re about a specific leaf only
    --continue        Continue nagging from where we left off
    --dry-run         Show what we'd nag about without actually nagging
    -h, --help        Show this help

DESCRIPTION:
    Nags re to execute leaf tasks one by one:
    1. Picks the next unexecuted leaf (respecting dependencies)
    2. Generates plan.md from the leaf's criteria
    3. Nags re to start ('re start')
    4. On completion, marks leaf done and moves to next
    5. Continues nagging until all leaves are complete
EOF
}

# Get next leaf to execute (in_progress first, then pending)
get_next_leaf() {
    require_bb

    bb -e "
(require '[clj-yaml.core :as yaml])

(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      nodes (get tree :nodes {})

      ; First check for in_progress leaves (resume these first)
      in-progress-leaves (->> nodes
                              (filter (fn [[k v]]
                                        (and (:is_leaf v)
                                             (= (:status v) \"in_progress\"))))
                              (map first))

      ; Then find pending leaves
      pending-leaves (->> nodes
                         (filter (fn [[k v]]
                                   (and (:is_leaf v)
                                        (= (:status v) \"pending\"))))
                         (map first))

      ; Prioritize in_progress, then pending
      next-leaf (or (first in-progress-leaves) (first pending-leaves))]

  (when next-leaf
    (println (name next-leaf))))
" 2>/dev/null
}

# Check if leaf is in_progress
is_leaf_in_progress() {
    local leaf_id="$1"

    require_bb

    local status
    status=$(bb -e "
(require '[clj-yaml.core :as yaml])
(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      leaf (get-in tree [:nodes (keyword \"$leaf_id\")])]
  (println (:status leaf)))
" 2>/dev/null)

    [[ "$status" == "in_progress" ]]
}

# Generate plan.md from leaf
generate_plan() {
    local leaf_id="$1"

    require_bb

    bb -e "
(require '[clj-yaml.core :as yaml])

(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      nodes (get tree :nodes {})
      leaf (get nodes (keyword \"$leaf_id\"))

      title (:title leaf)
      description (:description leaf)
      criteria (:criteria leaf)]

  (println \"# Task\")
  (println)
  (println description)
  (println)
  (println \"## Completion Criteria\")
  (println)
  (doseq [[i c] (map-indexed vector criteria)]
    (println (str \"- [ ] \" i \". \" c)))
  (println)
  (println \"## Context\")
  (println)
  (println \"This task is part of the kori project tree.\")
  (println (str \"Node ID: $leaf_id\"))
  (println (str \"Title: \" title)))
" 2>/dev/null
}

# Mark leaf as in-progress
mark_in_progress() {
    local leaf_id="$1"

    require_bb

    bb -e "
(require '[clj-yaml.core :as yaml])

(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      updated (assoc-in tree [:nodes (keyword \"$leaf_id\") :status] \"in_progress\")]
  (spit \"$OVERSEER_DIR/tree.yaml\" (yaml/generate-string updated)))
" 2>/dev/null
}

# Mark leaf as completed
mark_completed() {
    local leaf_id="$1"

    require_bb

    bb -e "
(require '[clj-yaml.core :as yaml])

(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      updated (assoc-in tree [:nodes (keyword \"$leaf_id\") :status] \"completed\")]
  (spit \"$OVERSEER_DIR/tree.yaml\" (yaml/generate-string updated)))
" 2>/dev/null

    # Update completed count in state
    local completed
    completed=$(grep "^completed_leaves:" "$OVERSEER_DIR/state.yaml" | cut -d' ' -f2)
    completed=$((completed + 1))
    sed -i.bak "s/^completed_leaves:.*/completed_leaves: $completed/" "$OVERSEER_DIR/state.yaml"
    rm -f "$OVERSEER_DIR/state.yaml.bak"
}

# Get leaf title
get_leaf_title() {
    local leaf_id="$1"

    require_bb

    bb -e "
(require '[clj-yaml.core :as yaml])

(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      leaf (get-in tree [:nodes (keyword \"$leaf_id\")])]
  (println (:title leaf)))
" 2>/dev/null
}

nag_re() {
    local specific_leaf=""
    local continue_run=false
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --leaf)
                specific_leaf="$2"
                shift 2
                ;;
            --continue)
                continue_run=true
                shift
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

    require_tree
    require_re

    # Update state
    sed -i.bak "s/^phase:.*/phase: executing/" "$OVERSEER_DIR/state.yaml"
    rm -f "$OVERSEER_DIR/state.yaml.bak"

    # If specific leaf, run just that one
    if [[ -n "$specific_leaf" ]]; then
        run_leaf "$specific_leaf" "$dry_run"
        return
    fi

    # Otherwise, loop through all pending leaves
    log_info "Starting execution loop..."
    echo ""

    while true; do
        local next_leaf
        next_leaf=$(get_next_leaf)

        if [[ -z "$next_leaf" ]]; then
            log_success "All leaves completed!"
            sed -i.bak "s/^phase:.*/phase: completed/" "$OVERSEER_DIR/state.yaml"
            rm -f "$OVERSEER_DIR/state.yaml.bak"
            break
        fi

        run_leaf "$next_leaf" "$dry_run"

        if [[ "$dry_run" == "true" ]]; then
            log_info "Dry run - stopping after first leaf"
            break
        fi
    done
}

run_leaf() {
    local leaf_id="$1"
    local dry_run="${2:-false}"

    local title
    title=$(get_leaf_title "$leaf_id")

    local is_resuming=false
    if is_leaf_in_progress "$leaf_id"; then
        is_resuming=true
    fi

    if [[ "$is_resuming" == "true" ]]; then
        echo -e "${BOLD}╭─────────────────────────────────────────────────────────────╮${NC}"
        echo -e "${BOLD}│  Resuming: $title${NC}"
        echo -e "${BOLD}│  Leaf ID: $leaf_id${NC}"
        echo -e "${BOLD}╰─────────────────────────────────────────────────────────────╯${NC}"
    else
        echo -e "${BOLD}╭─────────────────────────────────────────────────────────────╮${NC}"
        echo -e "${BOLD}│  Executing: $title${NC}"
        echo -e "${BOLD}│  Leaf ID: $leaf_id${NC}"
        echo -e "${BOLD}╰─────────────────────────────────────────────────────────────╯${NC}"
    fi
    echo ""

    if [[ "$dry_run" == "true" ]]; then
        echo -e "${DIM}Generated plan.md:${NC}"
        generate_plan "$leaf_id"
        echo ""
        return
    fi

    # Check if .ralph exists, init if not
    if [[ ! -d ".ralph" ]]; then
        log_info "Initializing re..."
        re init
    fi

    # Determine whether to start or resume
    local re_command="start"
    if [[ "$is_resuming" == "true" && -f ".ralph/state.md" ]]; then
        local re_status
        re_status=$(grep "^status:" ".ralph/state.md" | head -1 | cut -d' ' -f2)
        case "$re_status" in
            paused|crashed|aborted)
                re_command="resume"
                log_info "Resuming re (status: $re_status)..."
                ;;
            running)
                log_warn "re is already running - attaching..."
                re_command="resume"
                ;;
            completed)
                log_info "re already completed this task"
                mark_completed "$leaf_id"
                re merge --force 2>/dev/null || true
                return
                ;;
            *)
                # Generate fresh plan and start
                log_info "Generating plan.md from leaf criteria..."
                generate_plan "$leaf_id" > ".ralph/plan.md"
                re_command="start"
                ;;
        esac
    else
        # Fresh start - generate plan
        log_info "Generating plan.md from leaf criteria..."
        generate_plan "$leaf_id" > ".ralph/plan.md"
        # Clear archive to avoid false warnings about previous leaf's criteria
        rm -rf ".ralph/archive" 2>/dev/null || true
    fi

    # Mark as in-progress (if not already)
    if [[ "$is_resuming" != "true" ]]; then
        mark_in_progress "$leaf_id"
    fi
    sed -i.bak "s/^current_node:.*/current_node: $leaf_id/" "$OVERSEER_DIR/state.yaml"
    rm -f "$OVERSEER_DIR/state.yaml.bak"

    # Run re
    if [[ "$re_command" == "resume" ]]; then
        log_info "Resuming re..."
    else
        log_info "Starting re..."
    fi
    echo ""

    if re $re_command; then
        log_success "Leaf completed: $leaf_id"
        mark_completed "$leaf_id"

        # Merge to plan.md
        re merge --force 2>/dev/null || true
    else
        log_warn "re exited with non-zero status"
        log_info "Check the status and run 'kori nag' to resume"
        exit 1
    fi

    echo ""
}

nag_re "$@"
