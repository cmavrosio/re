(ns brain.budget
  "Token budget tracking"
  (:require [clojure.string :as str]))

(defn parse-usage-table
  "Parse the markdown table in tokens/usage.md"
  [content]
  (let [lines (str/split-lines content)
        ;; Skip header rows (title, header, separator)
        data-lines (->> lines
                        (drop-while #(not (str/starts-with? % "|")))
                        (drop 2) ;; Skip header and separator
                        (filter #(str/starts-with? % "|")))]
    (->> data-lines
         (map (fn [line]
                (let [cells (->> (str/split line #"\|")
                                 (map str/trim)
                                 (filter #(not (str/blank? %))))]
                  (when (>= (count cells) 5)
                    {:iteration (parse-long (nth cells 0))
                     :input (parse-long (nth cells 1))
                     :output (parse-long (nth cells 2))
                     :total (parse-long (nth cells 3))
                     :cumulative (parse-long (nth cells 4))}))))
         (filter some?)
         vec)))

(defn read-usage
  "Read current token usage"
  [ralph-dir]
  (try
    (let [content (slurp (str ralph-dir "/tokens/usage.md"))
          entries (parse-usage-table content)]
      {:entries entries
       :total-tokens (or (:cumulative (last entries)) 0)
       :iterations (count entries)})
    (catch Exception _
      {:entries []
       :total-tokens 0
       :iterations 0})))

(defn add-usage-entry
  "Add a new usage entry to the table"
  [ralph-dir iteration input-tokens output-tokens]
  (let [current (read-usage ralph-dir)
        total (+ input-tokens output-tokens)
        cumulative (+ (:total-tokens current) total)
        new-line (format "| %d | %d | %d | %d | %d |"
                         iteration input-tokens output-tokens total cumulative)
        file-path (str ralph-dir "/tokens/usage.md")
        content (slurp file-path)]
    (spit file-path (str content "\n" new-line))
    {:iteration iteration
     :input input-tokens
     :output output-tokens
     :total total
     :cumulative cumulative}))

(defn check-budget
  "Check if budget is exceeded"
  [ralph-dir max-tokens max-iterations]
  (let [usage (read-usage ralph-dir)]
    {:within-budget (and (< (:total-tokens usage) max-tokens)
                         (< (:iterations usage) max-iterations))
     :total-tokens (:total-tokens usage)
     :iterations (:iterations usage)
     :tokens-remaining (- max-tokens (:total-tokens usage))
     :iterations-remaining (- max-iterations (:iterations usage))
     :percent-tokens-used (* 100.0 (/ (:total-tokens usage) max-tokens))
     :percent-iterations-used (* 100.0 (/ (:iterations usage) max-iterations))}))

(defn format-budget-status
  "Format budget status for display"
  [status]
  (str/join "\n"
            [(str "Tokens: " (:total-tokens status) " / "
                  (+ (:total-tokens status) (:tokens-remaining status))
                  " (" (format "%.1f" (:percent-tokens-used status)) "%)")
             (str "Iterations: " (:iterations status) " / "
                  (+ (:iterations status) (:iterations-remaining status))
                  " (" (format "%.1f" (:percent-iterations-used status)) "%)")
             (str "Within budget: " (:within-budget status))]))

;; CLI interface
(defn -main [& args]
  (let [action (first args)
        ralph-dir (or (second args) ".ralph")]
    (case action
      "status"
      (let [max-tokens (parse-long (or (nth args 2) "500000"))
            max-iters (parse-long (or (nth args 3) "50"))
            status (check-budget ralph-dir max-tokens max-iters)]
        (println (format-budget-status status))
        (System/exit (if (:within-budget status) 0 1)))

      "add"
      (let [iteration (parse-long (nth args 2))
            input-tokens (parse-long (nth args 3))
            output-tokens (parse-long (nth args 4))
            result (add-usage-entry ralph-dir iteration input-tokens output-tokens)]
        (println (str "Added: iteration " iteration ", total " (:total result) ", cumulative " (:cumulative result))))

      "total"
      (let [usage (read-usage ralph-dir)]
        (println (:total-tokens usage)))

      ;; Default
      (do
        (println "Usage: bb budget.clj <action> [ralph-dir] [args...]")
        (println "Actions:")
        (println "  status [max-tokens] [max-iterations] - Check budget status")
        (println "  add <iteration> <input> <output>     - Add usage entry")
        (println "  total                                 - Get total tokens used")))))
