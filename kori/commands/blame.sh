#!/usr/bin/env bash
#
# kori blame - Show total project status
#
# "Who's responsible for this mess?" - Shows what's done, in progress, pending
#

set -euo pipefail

source "$KORI_HOME/lib/common.sh"

usage() {
    cat << 'EOF'
kori blame - Show total project status

USAGE:
    kori blame [options]

OPTIONS:
    --verbose         Show criteria for each leaf
    --json            Output as JSON
    -h, --help        Show this help

DESCRIPTION:
    Shows a comprehensive overview of project progress:
    - Completed leaves and their criteria
    - In-progress leaves
    - Pending leaves
    - Overall statistics
EOF
}

blame() {
    local verbose=false
    local json_output=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v)
                verbose=true
                shift
                ;;
            --json)
                json_output=true
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

    if [[ "$json_output" == "true" ]]; then
        output_json
    else
        output_pretty "$verbose"
    fi
}

output_json() {
    require_bb

    bb -e "
(require '[clj-yaml.core :as yaml]
         '[clojure.data.json :as json])

(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      nodes (get tree :nodes {})

      leaves (->> nodes
                  (filter (fn [[k v]] (:is_leaf v))))

      completed (->> leaves (filter (fn [[k v]] (= (:status v) \"completed\"))))
      in-progress (->> leaves (filter (fn [[k v]] (= (:status v) \"in_progress\"))))
      pending (->> leaves (filter (fn [[k v]] (= (:status v) \"pending\"))))

      result {:total_leaves (count leaves)
              :completed (count completed)
              :in_progress (count in-progress)
              :pending (count pending)
              :percentage (if (pos? (count leaves))
                           (int (* 100 (/ (count completed) (count leaves))))
                           0)
              :completed_leaves (mapv (fn [[k v]] {:id (name k) :title (:title v)}) completed)
              :in_progress_leaves (mapv (fn [[k v]] {:id (name k) :title (:title v)}) in-progress)
              :pending_leaves (mapv (fn [[k v]] {:id (name k) :title (:title v)}) pending)}]
  (println (json/write-str result)))
" 2>/dev/null
}

output_pretty() {
    local verbose="$1"

    require_bb

    # Get stats
    local stats
    stats=$(bb -e "
(require '[clj-yaml.core :as yaml])

(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      nodes (get tree :nodes {})

      leaves (->> nodes (filter (fn [[k v]] (:is_leaf v))))
      completed (->> leaves (filter (fn [[k v]] (= (:status v) \"completed\"))))
      in-progress (->> leaves (filter (fn [[k v]] (= (:status v) \"in_progress\"))))
      pending (->> leaves (filter (fn [[k v]] (= (:status v) \"pending\"))))]

  (println (count leaves))
  (println (count completed))
  (println (count in-progress))
  (println (count pending)))
" 2>/dev/null)

    local total=$(echo "$stats" | sed -n '1p')
    local completed=$(echo "$stats" | sed -n '2p')
    local in_progress=$(echo "$stats" | sed -n '3p')
    local pending=$(echo "$stats" | sed -n '4p')
    local percentage=$((completed * 100 / total))

    # Header
    echo ""
    echo -e "${BOLD}╭─────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${BOLD}│  KORI PROJECT STATUS                                        │${NC}"
    echo -e "${BOLD}╰─────────────────────────────────────────────────────────────╯${NC}"
    echo ""

    # Progress bar
    local bar_width=40
    local filled=$((percentage * bar_width / 100))
    local empty=$((bar_width - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    echo -e "  ${BOLD}Progress:${NC} [${GREEN}${bar}${NC}] ${percentage}%"
    echo ""
    echo -e "  ${GREEN}✓ Completed:${NC}   $completed"
    echo -e "  ${YELLOW}◐ In Progress:${NC} $in_progress"
    echo -e "  ${DIM}○ Pending:${NC}     $pending"
    echo -e "  ${BOLD}Total:${NC}         $total leaves"
    echo ""

    # Completed leaves
    echo -e "${GREEN}━━━ Completed ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    bb -e "
(require '[clj-yaml.core :as yaml])

(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      nodes (get tree :nodes {})

      completed (->> nodes
                     (filter (fn [[k v]] (and (:is_leaf v) (= (:status v) \"completed\"))))
                     (sort-by first))]

  (doseq [[k v] completed]
    (println (str \"  ✓ \" (:title v)))))
" 2>/dev/null
    echo ""

    # In progress leaves
    if [[ "$in_progress" -gt 0 ]]; then
        echo -e "${YELLOW}━━━ In Progress ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        bb -e "
(require '[clj-yaml.core :as yaml])

(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      nodes (get tree :nodes {})]

  (doseq [[k v] nodes]
    (when (and (:is_leaf v) (= (:status v) \"in_progress\"))
      (println (str \"  ◐ \" (:title v)))
      (when $verbose
        (doseq [c (:criteria v)]
          (println (str \"      - \" c)))))))
" 2>/dev/null
        echo ""
    fi

    # Pending leaves (just count by parent)
    echo -e "${DIM}━━━ Pending ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    bb -e "
(require '[clj-yaml.core :as yaml])

(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      nodes (get tree :nodes {})

      pending (->> nodes
                   (filter (fn [[k v]] (and (:is_leaf v) (= (:status v) \"pending\"))))
                   (group-by (fn [[k v]] (:parent v))))]

  (doseq [[parent leaves] (sort-by first pending)]
    (let [parent-title (get-in nodes [(keyword parent) :title] (name parent))]
      (println (str \"  \" parent-title \": \" (count leaves) \" tasks\")))))
" 2>/dev/null
    echo ""
}

blame "$@"
