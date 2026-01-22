#!/usr/bin/env bash
#
# kori tree - Display the task tree
#

set -euo pipefail

source "$KORI_HOME/lib/common.sh"

usage() {
    cat << 'EOF'
kori tree - Display the task tree

USAGE:
    kori tree [options]

OPTIONS:
    --node <id>       Show details for a specific node
    --leaves          Show only leaf nodes
    --pending         Show only pending leaves
    -h, --help        Show this help
EOF
}

show_tree() {
    local specific_node=""
    local leaves_only=false
    local pending_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --node)
                specific_node="$2"
                shift 2
                ;;
            --leaves)
                leaves_only=true
                shift
                ;;
            --pending)
                pending_only=true
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

    if [[ -n "$specific_node" ]]; then
        # Show specific node details
        bb -e "
(require '[clj-yaml.core :as yaml])

(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      node (get-in tree [:nodes (keyword \"$specific_node\")])]

  (if node
    (do
      (println \"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\")
      (println (str \"Node: $specific_node\"))
      (println (str \"Title: \" (:title node)))
      (println (str \"Status: \" (:status node)))
      (when (:parent node)
        (println (str \"Parent: \" (name (:parent node)))))
      (when (:children node)
        (println (str \"Children: \" (clojure.string/join \", \" (map name (:children node))))))
      (println \"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\")
      (println)
      (println \"Description:\")
      (println (:description node))
      (when (:criteria node)
        (println)
        (println \"Criteria:\")
        (doseq [[i c] (map-indexed vector (:criteria node))]
          (println (str \"  \" i \". \" c)))))
    (println \"Node not found: $specific_node\")))
" 2>/dev/null
        return
    fi

    if [[ "$leaves_only" == "true" || "$pending_only" == "true" ]]; then
        # Show leaves
        bb -e "
(require '[clj-yaml.core :as yaml])

(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      nodes (get tree :nodes {})
      leaves (->> nodes
                  (filter (fn [[k v]] (:is_leaf v)))
                  (filter (fn [[k v]]
                           (if $pending_only
                             (= (:status v) \"pending\")
                             true))))]

  (println \"Leaves:\")
  (println)
  (doseq [[id node] leaves]
    (let [status (:status node)
          icon (case status
                 \"completed\" \"✓\"
                 \"in_progress\" \"●\"
                 \"pending\" \"○\"
                 \"?\")]
      (println (str \"  \" icon \" \" (name id) \": \" (:title node)))))
  (println)
  (println (str \"Total: \" (count leaves))))
" 2>/dev/null
        return
    fi

    # Show full tree
    bb -e "
(require '[clj-yaml.core :as yaml])

(let [content (slurp \"$OVERSEER_DIR/tree.yaml\")
      tree (yaml/parse-string content)
      nodes (get tree :nodes {})]

  (defn status-icon [status is-leaf]
    (case status
      \"completed\" \"✓\"
      \"in_progress\" \"●\"
      \"pending\" (if is-leaf \"○\" \"◇\")
      \"?\"))

  (defn print-node [id depth]
    (let [node (get nodes (keyword id))
          indent (apply str (repeat depth \"  \"))
          icon (status-icon (:status node) (:is_leaf node))
          title (:title node)
          children (:children node)]

      (println (str indent icon \" \" (name id) \": \" title))

      (when children
        (doseq [child children]
          (print-node (name child) (inc depth))))))

  (println \"Task Tree:\")
  (println)
  (print-node \"root\" 0)
  (println)

  ; Stats
  (let [total (count nodes)
        leaves (count (filter #(:is_leaf (val %)) nodes))
        completed (count (filter #(= \"completed\" (:status (val %))) nodes))]
    (println (str \"Nodes: \" total \" | Leaves: \" leaves \" | Completed: \" completed))))
" 2>/dev/null
}

show_tree "$@"
