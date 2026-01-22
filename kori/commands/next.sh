#!/usr/bin/env bash
#
# kori next - Show next actionable leaf
#

set -euo pipefail

source "$KORI_HOME/lib/common.sh"

usage() {
    cat << 'EOF'
kori next - Show next actionable leaf

USAGE:
    kori next [options]

OPTIONS:
    --start           Start execution on the next leaf
    -h, --help        Show this help
EOF
}

show_next() {
    local start_execution=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --start)
                start_execution=true
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
    require_bb

    # Find next pending leaf
    local next_leaf
    next_leaf=$(bb -e "
(require '[clj-yaml.core :as yaml])

(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      nodes (get tree :nodes {})
      pending-leaves (->> nodes
                         (filter (fn [[k v]]
                                   (and (:is_leaf v)
                                        (= (:status v) \"pending\"))))
                         (map first))]
  (when-let [next (first pending-leaves)]
    (println (name next))))
" 2>/dev/null)

    if [[ -z "$next_leaf" ]]; then
        log_success "No pending leaves - all done!"
        return
    fi

    # Get leaf details
    bb -e "
(require '[clj-yaml.core :as yaml])

(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      node (get-in tree [:nodes (keyword \"$next_leaf\")])]

  (println \"Next leaf:\")
  (println)
  (println (str \"  ID:    $next_leaf\"))
  (println (str \"  Title: \" (:title node)))
  (println)
  (println \"  Criteria:\")
  (doseq [[i c] (map-indexed vector (:criteria node))]
    (println (str \"    \" i \". \" c))))
" 2>/dev/null

    echo ""

    if [[ "$start_execution" == "true" ]]; then
        exec bash "$KORI_HOME/commands/nag.sh" --leaf "$next_leaf"
    else
        echo -e "${DIM}Run 'kori nag --leaf $next_leaf' to nag re about this leaf${NC}"
        echo -e "${DIM}Or 'kori nag' to nag re about all remaining leaves${NC}"
    fi
}

show_next "$@"
