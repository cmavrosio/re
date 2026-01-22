(ns brain.response-analyzer
  "Analyze Claude responses to extract signals and patterns"
  (:require [clojure.string :as str]
            [clojure.edn :as edn]))

;; Completion patterns that indicate task is likely done
(def completion-patterns
  [#"(?i)all\s+(tasks?|criteria)\s+(are\s+)?(now\s+)?(complete|done|finished)"
   #"(?i)implementation\s+(is\s+)?(now\s+)?complete"
   #"(?i)all\s+tests?\s+(are\s+)?(now\s+)?passing"
   #"(?i)successfully\s+(completed|implemented|finished)"
   #"(?i)task\s+(is\s+)?(now\s+)?(complete|done|finished)"
   #"(?i)everything\s+(is\s+)?(now\s+)?(working|complete|done)"])

;; Error patterns that indicate problems
(def error-patterns
  [#"(?i)error:|Error:|ERROR:"
   #"(?i)failed|Failed|FAILED"
   #"(?i)exception|Exception|EXCEPTION"
   #"(?i)cannot\s+find"
   #"(?i)not\s+found"
   #"(?i)permission\s+denied"])

;; Stuck patterns
(def stuck-patterns
  [#"(?i)i('m|\s+am)\s+stuck"
   #"(?i)i('m|\s+am)\s+unable\s+to"
   #"(?i)i\s+need\s+(help|assistance|guidance)"
   #"(?i)cannot\s+proceed"
   #"(?i)blocked\s+by"
   #"(?i)waiting\s+for\s+(human|user|input)"])

(defn count-pattern-matches
  "Count how many patterns match the text"
  [patterns text]
  (count (filter #(re-find % text) patterns)))

(defn extract-criterion-done
  "Extract CRITERION_DONE signals with their numbers"
  [text]
  (->> (re-seq #"CRITERION_DONE:\s*(\d+)" text)
       (mapv (comp parse-long second))
       distinct
       sort
       vec))

(defn extract-step-done
  "Extract STEP_DONE signals"
  [text]
  (->> (re-seq #"STEP_DONE:\s*(\d+)" text)
       (mapv (comp parse-long second))
       distinct
       sort
       vec))

(defn detect-task-complete
  "Check if TASK_COMPLETE signal is present"
  [text]
  (boolean (re-find #"TASK_COMPLETE" text)))

(defn detect-stuck
  "Check if stuck signal is present"
  [text]
  (or (boolean (re-find #"STUCK:" text))
      (pos? (count-pattern-matches stuck-patterns text))))

(defn extract-stuck-reason
  "Extract the reason from STUCK: signal if present"
  [text]
  (when-let [[_ reason] (re-find #"STUCK:\s*(.+?)(?:\n|$)" text)]
    (str/trim reason)))

(defn detect-test-only-loop
  "Detect if Claude is stuck in a test-only loop (running tests but not making changes)"
  [text]
  (let [has-test-mention (re-find #"(?i)tests?\s+(pass|passing|passed|run|running)" text)
        has-change-mention (re-find #"(?i)(created?|modified?|changed?|updated?|added?|wrote)" text)]
    (and has-test-mention (not has-change-mention))))

(defn extract-tool-calls
  "Extract tool calls from the response (basic detection)"
  [text]
  (let [edit-calls (count (re-seq #"(?i)(Edit|Write|NotebookEdit)" text))
        bash-calls (count (re-seq #"(?i)Bash" text))
        read-calls (count (re-seq #"(?i)(Read|Glob|Grep)" text))]
    {:edit edit-calls
     :bash bash-calls
     :read read-calls
     :total (+ edit-calls bash-calls read-calls)}))

(defn analyze-response
  "Analyze a Claude response and extract all signals"
  [text]
  {:exit-signal (detect-task-complete text)
   :criteria-done (extract-criterion-done text)
   :steps-done (extract-step-done text)
   :stuck-signal (detect-stuck text)
   :stuck-reason (extract-stuck-reason text)
   :completion-score (count-pattern-matches completion-patterns text)
   :error-score (count-pattern-matches error-patterns text)
   :test-only-loop (detect-test-only-loop text)
   :tool-calls (extract-tool-calls text)})

(defn signals->yaml
  "Convert signals to YAML string for writing"
  [signals]
  (str/join "\n"
            [(str "exit_signal: " (:exit-signal signals))
             (str "criteria_done: [" (str/join ", " (:criteria-done signals)) "]")
             (str "steps_done: [" (str/join ", " (:steps-done signals)) "]")
             (str "stuck_signal: " (:stuck-signal signals))
             (str "stuck_reason: " (pr-str (:stuck-reason signals)))
             (str "completion_score: " (:completion-score signals))
             (str "error_score: " (:error-score signals))
             (str "test_only_loop: " (:test-only-loop signals))
             (str "tool_calls:")
             (str "  edit: " (get-in signals [:tool-calls :edit]))
             (str "  bash: " (get-in signals [:tool-calls :bash]))
             (str "  read: " (get-in signals [:tool-calls :read]))
             (str "  total: " (get-in signals [:tool-calls :total]))]))

;; CLI interface
(defn -main [& args]
  (let [action (first args)]
    (case action
      "--help"
      (do
        (println "Usage: bb response_analyzer.clj <action> [args]")
        (println "Actions:")
        (println "  analyze <file>  - Analyze response from file")
        (println "  analyze -       - Analyze response from stdin")
        (System/exit 0))

      "analyze"
      (let [input (second args)
            text (if (= input "-")
                   (slurp *in*)
                   (slurp input))
            signals (analyze-response text)]
        (println (signals->yaml signals)))

      ;; Default: read from stdin
      (let [text (slurp *in*)
            signals (analyze-response text)]
        (println (signals->yaml signals))))))
