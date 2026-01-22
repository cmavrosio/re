(ns brain.diff-categorizer
  "Categorize file changes from git diff"
  (:require [clojure.string :as str]))

(def file-categories
  "Map of file patterns to categories"
  {:test [#"test" #"spec" #"__tests__" #"\.test\." #"\.spec\."]
   :config [#"config" #"\.json$" #"\.yaml$" #"\.yml$" #"\.toml$" #"\.env"]
   :docs [#"\.md$" #"README" #"CHANGELOG" #"docs/"]
   :source [#"\.ts$" #"\.tsx$" #"\.js$" #"\.jsx$" #"\.py$" #"\.rb$" #"\.go$" #"\.rs$" #"\.clj$"]
   :styles [#"\.css$" #"\.scss$" #"\.less$" #"\.styled\."]
   :build [#"package\.json$" #"Cargo\.toml$" #"build\." #"Makefile" #"\.lock$"]})

(defn categorize-file
  "Determine the category of a file based on its path"
  [filepath]
  (let [lower-path (str/lower-case filepath)]
    (or (first (for [[category patterns] file-categories
                     :when (some #(re-find % lower-path) patterns)]
                 category))
        :other)))

(defn parse-diff-stat
  "Parse git diff --stat output"
  [stat-output]
  (->> (str/split-lines stat-output)
       (butlast) ;; Remove summary line
       (map (fn [line]
              (when-let [[_ file changes] (re-find #"^\s*(.+?)\s*\|\s*(\d+)" line)]
                {:file (str/trim file)
                 :changes (parse-long changes)
                 :category (categorize-file file)})))
       (filter some?)
       vec))

(defn parse-diff-numstat
  "Parse git diff --numstat output"
  [numstat-output]
  (->> (str/split-lines numstat-output)
       (map (fn [line]
              (let [[added removed file] (str/split line #"\t")]
                (when (and added removed file)
                  {:file file
                   :added (if (= added "-") 0 (parse-long added))
                   :removed (if (= removed "-") 0 (parse-long removed))
                   :category (categorize-file file)}))))
       (filter some?)
       vec))

(defn summarize-by-category
  "Summarize changes by category"
  [files]
  (->> files
       (group-by :category)
       (map (fn [[category files]]
              [category {:count (count files)
                         :added (reduce + (map :added files))
                         :removed (reduce + (map :removed files))
                         :files (mapv :file files)}]))
       (into {})))

(defn format-diff-summary
  "Format diff summary as markdown"
  [summary]
  (str/join "\n"
            (concat
             ["## Changes by Category" ""]
             (for [[category {:keys [count added removed files]}] (sort-by first summary)]
               (str "### " (name category) " (" count " files, +" added "/-" removed ")\n"
                    (str/join "\n" (map #(str "- " %) files))
                    "\n")))))

(defn has-meaningful-changes?
  "Check if there are meaningful code changes (not just tests/docs)"
  [summary]
  (let [source-changes (get-in summary [:source :count] 0)
        config-changes (get-in summary [:config :count] 0)
        build-changes (get-in summary [:build :count] 0)]
    (or (pos? source-changes)
        (pos? config-changes)
        (pos? build-changes))))

(defn is-test-only?
  "Check if changes are test-only"
  [summary]
  (let [test-changes (get-in summary [:test :count] 0)
        source-changes (get-in summary [:source :count] 0)
        config-changes (get-in summary [:config :count] 0)]
    (and (pos? test-changes)
         (zero? source-changes)
         (zero? config-changes))))

;; CLI interface
(defn -main [& args]
  (let [action (first args)]
    (case action
      "categorize"
      ;; Read numstat from stdin
      (let [input (slurp *in*)
            files (parse-diff-numstat input)
            summary (summarize-by-category files)]
        (println (format-diff-summary summary)))

      "check"
      ;; Check for meaningful changes
      (let [input (slurp *in*)
            files (parse-diff-numstat input)
            summary (summarize-by-category files)]
        (println (str "meaningful_changes: " (has-meaningful-changes? summary)))
        (println (str "test_only: " (is-test-only? summary)))
        (println (str "total_files: " (count files)))
        (System/exit (if (has-meaningful-changes? summary) 0 1)))

      ;; Default: show usage
      (do
        (println "Usage: bb diff_categorizer.clj <action>")
        (println "Actions:")
        (println "  categorize - Read git diff --numstat from stdin, output summary")
        (println "  check      - Check if changes are meaningful (exit 0) or test-only (exit 1)")))))
