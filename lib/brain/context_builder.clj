(ns brain.context-builder
  "Build context markdown for Claude iterations"
  (:require [clojure.string :as str]
            [brain.plan-parser :as plan]))

;; Dynamic var to control iteration compression
(def ^:dynamic *compress-iterations* false)

(defn read-file-safe
  "Read a file, returning empty string if it doesn't exist"
  [path]
  (try
    (str/trim (slurp path))
    (catch Exception _ "")))

(defn format-criteria
  "Format criteria as markdown checkboxes"
  [criteria]
  (->> criteria
       (map (fn [{:keys [checked number text]}]
              (format "- [%s] %d. %s" (if checked "x" " ") number text)))
       (str/join "\n")))

(defn get-cached-summary
  "Get cached summary for an iteration file, or nil if not cached"
  [iter-file]
  (let [summary-file (str (.getPath iter-file) ".summary")]
    (when (.exists (java.io.File. summary-file))
      (str/trim (slurp summary-file)))))

(defn create-iteration-summary
  "Create summary using haiku and cache it"
  [iter-file]
  (let [content (slurp iter-file)
        summary-file (str (.getPath iter-file) ".summary")
        re-home (System/getenv "RE_HOME")]
    (try
      ;; Call provider to summarize via stdin (uses fast model)
      (let [proc (-> (ProcessBuilder.
                       ["bash" (str re-home "/lib/providers/provider.sh")
                        "summarize-iteration"])
                     (.redirectErrorStream true)
                     .start)
            ;; Write content to stdin
            _ (with-open [w (java.io.OutputStreamWriter. (.getOutputStream proc))]
                (.write w content)
                (.flush w))
            summary (str/trim (slurp (.getInputStream proc)))
            exit-code (.waitFor proc)]
        (when (zero? exit-code)
          ;; Cache the summary
          (spit summary-file summary)
          summary))
      (catch Exception e
        ;; Fallback: return truncated content
        (subs content 0 (min 500 (count content)))))))

(defn get-or-create-summary
  "Get cached summary or create one with haiku"
  [iter-file]
  (or (get-cached-summary iter-file)
      (create-iteration-summary iter-file)))

(defn format-recent-iterations
  "Load and format recent iteration files.
   Most recent iteration is included in full, older ones are summarized with haiku."
  [ralph-dir n]
  (let [iter-dir (str ralph-dir "/context/iterations")
        files (try
                (->> (java.io.File. iter-dir)
                     .listFiles
                     (filter #(and (.isFile %)
                                   (str/ends-with? (.getName %) ".md")
                                   (not (str/ends-with? (.getName %) ".summary"))))
                     (sort-by #(.getName %))
                     reverse
                     (take n)
                     vec)
                (catch Exception _ []))]
    (if (empty? files)
      "_No previous iterations_"
      (->> files
           (map-indexed
             (fn [idx file]
               (let [name (.getName file)]
                 (if (or (zero? idx) (not *compress-iterations*))
                   ;; Most recent or compression disabled: include full content
                   (str "### " name (when (zero? idx) " (latest)") "\n\n" (slurp file))
                   ;; Older with compression: use haiku summary
                   (str "### " name " (summary)\n\n" (get-or-create-summary file))))))
           (str/join "\n\n---\n\n")))))

(defn build-context
  "Build the context markdown for a Claude iteration"
  [{:keys [ralph-dir iteration task criteria summary diff test-results urgent rules backlog docs]}]
  (let [template (read-file-safe (str (System/getenv "RE_HOME") "/templates/context.template.md"))
        recent-iters (format-recent-iterations ralph-dir 3)]
    (-> template
        (str/replace "{{ITERATION}}" (str iteration))
        (str/replace "{{TASK}}" (or task "_No task defined_"))
        (str/replace "{{CRITERIA}}" (or (format-criteria criteria) "_No criteria_"))
        (str/replace "{{SUMMARY}}" (or summary "_No summary yet_"))
        (str/replace "{{RECENT_ITERATIONS}}" recent-iters)
        (str/replace "{{DIFF}}" (or diff "_No changes_"))
        (str/replace "{{TEST_RESULTS}}" (or test-results "_No test results_"))
        ;; Handle optional rules section
        (str/replace #"\{\{#RULES\}\}[\s\S]*?\{\{/RULES\}\}"
                     (if (and rules (not (str/blank? rules)))
                       (str "## Rules\n\n" rules)
                       ""))
        ;; Handle optional urgent section
        (str/replace #"\{\{#URGENT\}\}[\s\S]*?\{\{/URGENT\}\}"
                     (if (and urgent (not (str/blank? urgent)))
                       (str "## URGENT\n\n" urgent)
                       ""))
        ;; Handle optional backlog section
        (str/replace #"\{\{#BACKLOG\}\}[\s\S]*?\{\{/BACKLOG\}\}"
                     (if (and backlog (seq backlog))
                       (str "## Backlog (DO NOT work on these)\n\nThese items need more input or are blocked. For reference only:\n\n"
                            (str/join "\n" backlog))
                       ""))
        ;; Handle optional docs section
        (str/replace #"\{\{#DOCS\}\}[\s\S]*?\{\{/DOCS\}\}"
                     (if (and docs (not (str/blank? docs)))
                       (str "## Documentation Requirements\n\n" docs)
                       "")))))

(defn build-continue-context
  "Build lightweight continuation context for hybrid mode (same session)"
  [{:keys [iteration criteria diff test-results urgent progress-update]}]
  (let [template (read-file-safe (str (System/getenv "RE_HOME") "/templates/context.continue.template.md"))]
    (-> template
        (str/replace "{{ITERATION}}" (str iteration))
        (str/replace "{{PROGRESS_UPDATE}}" (or progress-update "_Continuing from previous iteration_"))
        (str/replace "{{CRITERIA}}" (or (format-criteria criteria) "_No criteria_"))
        (str/replace "{{DIFF}}" (or diff "_No changes_"))
        (str/replace "{{TEST_RESULTS}}" (or test-results "_No test results_"))
        ;; Handle optional urgent section
        (str/replace #"\{\{#URGENT\}\}[\s\S]*?\{\{/URGENT\}\}"
                     (if (and urgent (not (str/blank? urgent)))
                       (str "## URGENT\n\n" urgent)
                       "")))))

(defn build-from-state
  "Build context from state.md and related files"
  ([ralph-dir] (build-from-state ralph-dir :full))
  ([ralph-dir mode]
   (let [state-content (read-file-safe (str ralph-dir "/state.md"))
         ;; Parse YAML frontmatter for iteration number
         frontmatter (when-let [[_ yaml] (re-find #"(?s)^---\n(.+?)\n---" state-content)]
                       (->> (str/split-lines yaml)
                            (map #(str/split % #":\s*" 2))
                            (filter #(= 2 (count %)))
                            (into {})))
         iteration (parse-long (get frontmatter "iteration" "0"))
         ;; Parse task and criteria from state
         parsed (plan/parse-plan state-content)
         ;; Common fields
         criteria (:criteria parsed)
         diff (read-file-safe (str ralph-dir "/diff/current.md"))
         test-results (read-file-safe (str ralph-dir "/tests/latest.md"))
         urgent (read-file-safe (str ralph-dir "/urgent.md"))]
     (if (= mode :continue)
       ;; Lightweight continuation context
       (let [done-count (count (filter :checked criteria))
             total-count (count criteria)]
         (build-continue-context
          {:iteration (inc iteration)
           :criteria criteria
           :diff diff
           :test-results test-results
           :urgent urgent
           :progress-update (format "Completed %d/%d criteria so far." done-count total-count)}))
       ;; Full context rebuild
       (build-context
        {:ralph-dir ralph-dir
         :iteration (inc iteration)
         :task (:task parsed)
         :criteria criteria
         :backlog (:backlog parsed)
         :summary (read-file-safe (str ralph-dir "/context/summary.md"))
         :diff diff
         :test-results test-results
         :urgent urgent
         :rules (read-file-safe (str ralph-dir "/rules.md"))
         :docs (read-file-safe (str ralph-dir "/docs.md"))})))))

;; CLI interface
(defn -main [& args]
  (let [ralph-dir (or (first args) ".ralph")
        flags (set (rest args))
        mode (if (contains? flags "--continue") :continue :full)
        compress? (contains? flags "--compress")]
    (binding [*compress-iterations* compress?]
      (println (build-from-state ralph-dir mode)))))
