(ns brain.plan-parser
  "Parse plan.md files into structured data"
  (:require [clojure.string :as str]))

(defn parse-checkbox
  "Parse a markdown checkbox line into a map"
  [line]
  (when-let [[_ checked text] (re-matches #"^\s*-\s*\[([ xX])\]\s*(.+)$" line)]
    {:checked (not= checked " ")
     :text (str/trim text)}))

(defn parse-numbered-checkbox
  "Parse a numbered checkbox like '- [x] 0. Description'"
  [line]
  (when-let [[_ checked num text] (re-matches #"^\s*-\s*\[([ xX])\]\s*(\d+)\.\s*(.+)$" line)]
    {:checked (not= checked " ")
     :number (parse-long num)
     :text (str/trim text)}))

(defn extract-section
  "Extract content between a heading and the next heading of same or higher level"
  [content heading-pattern]
  (let [lines (str/split-lines content)
        heading-level (count (re-find #"^#+" heading-pattern))
        in-section? (atom false)
        result (atom [])]
    (doseq [line lines]
      (cond
        ;; Found our heading
        (re-matches (re-pattern (str "(?i)" heading-pattern ".*")) line)
        (reset! in-section? true)

        ;; Found another heading of same or higher level
        (and @in-section?
             (re-matches #"^#{1,6}\s+.*" line)
             (<= (count (re-find #"^#+" line)) heading-level))
        (reset! in-section? false)

        ;; In section, collect content
        @in-section?
        (swap! result conj line)))
    (str/join "\n" @result)))

(defn parse-criteria
  "Extract completion criteria from plan"
  [content]
  (let [section (extract-section content "## Completion Criteria")]
    (->> (str/split-lines section)
         (keep parse-numbered-checkbox)
         (sort-by :number)
         vec)))

(defn parse-plan-steps
  "Extract implementation plan steps"
  [content]
  (let [section (extract-section content "## Implementation Plan")]
    (->> (str/split-lines section)
         (keep parse-checkbox)
         vec)))

(defn parse-task-description
  "Extract the main task description"
  [content]
  (let [section (extract-section content "# Task")]
    (-> section
        str/trim
        (str/split #"\n\n")
        first
        str/trim)))

(defn parse-context-section
  "Extract the context section"
  [content]
  (str/trim (extract-section content "## Context")))

(defn parse-backlog
  "Extract backlog/future items (blocked, needs input, future)"
  [content]
  (let [section (extract-section content "## Backlog")]
    (->> (str/split-lines section)
         (filter #(re-matches #"^\s*-\s*\[.\].*" %))
         (remove str/blank?)
         vec)))

(defn parse-plan
  "Parse a complete plan.md file"
  [content]
  {:task (parse-task-description content)
   :criteria (parse-criteria content)
   :steps (parse-plan-steps content)
   :context (parse-context-section content)
   :backlog (parse-backlog content)})

(defn criteria->markdown
  "Convert criteria back to markdown checkboxes"
  [criteria]
  (->> criteria
       (map (fn [{:keys [checked number text]}]
              (format "- [%s] %d. %s" (if checked "x" " ") number text)))
       (str/join "\n")))

(defn steps->markdown
  "Convert steps back to markdown checkboxes"
  [steps]
  (->> steps
       (map-indexed (fn [i {:keys [checked text]}]
                      (format "- [%s] Step %d: %s" (if checked "x" " ") (inc i) text)))
       (str/join "\n")))

;; CLI interface
(defn -main [& args]
  (let [file (first args)
        action (second args)]
    (when (or (nil? file) (= file "--help"))
      (println "Usage: bb plan_parser.clj <file.md> [action]")
      (println "Actions: parse, criteria, steps, task")
      (System/exit 0))

    (let [content (slurp file)
          result (case action
                   "criteria" (parse-criteria content)
                   "steps" (parse-plan-steps content)
                   "task" (parse-task-description content)
                   (parse-plan content))]
      (prn result))))
