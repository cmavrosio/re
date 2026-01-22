(ns brain.decision
  "Decision engine for determining next action"
  (:require [clojure.string :as str]
            [clojure.edn :as edn]))

(defn parse-yaml-simple
  "Simple YAML parser for flat key-value files"
  [content]
  (->> (str/split-lines content)
       (remove str/blank?)
       (remove #(str/starts-with? (str/trim %) "#"))
       (map #(str/split % #":\s*" 2))
       (filter #(= 2 (count %)))
       (map (fn [[k v]]
              [(keyword (str/replace k "_" "-"))
               (cond
                 (= v "true") true
                 (= v "false") false
                 (= v "null") nil
                 (= v "nil") nil
                 (re-matches #"-?\d+" v) (parse-long v)
                 (re-matches #"-?\d+\.\d+" v) (parse-double v)
                 (str/starts-with? v "[") (edn/read-string (str/replace v "," " "))
                 (str/starts-with? v "\"") (edn/read-string v)
                 :else v)]))
       (into {})))

(defn read-signals
  "Read signals.yaml file"
  [ralph-dir]
  (try
    (parse-yaml-simple (slurp (str ralph-dir "/signals.yaml")))
    (catch Exception _ {})))

(defn read-health
  "Read health.yaml file"
  [ralph-dir]
  (try
    (parse-yaml-simple (slurp (str ralph-dir "/health.yaml")))
    (catch Exception _
      {:consecutive-errors 0
       :consecutive-no-change 0})))

(defn read-state-frontmatter
  "Read frontmatter from state.md"
  [ralph-dir]
  (try
    (let [content (slurp (str ralph-dir "/state.md"))]
      (when-let [[_ yaml] (re-find #"(?s)^---\n(.+?)\n---" content)]
        (parse-yaml-simple yaml)))
    (catch Exception _ {})))

(defn all-criteria-complete?
  "Check if all completion criteria checkboxes are checked in state.md"
  [ralph-dir]
  (try
    (let [content (slurp (str ralph-dir "/state.md"))
          ;; Find all criteria lines (numbered checkboxes)
          criteria-lines (re-seq #"- \[[ x]\] \d+\." content)
          unchecked (filter #(str/includes? % "[ ]") criteria-lines)]
      (and (seq criteria-lines)  ;; Must have at least one criterion
           (empty? unchecked)))  ;; All must be checked
    (catch Exception _ false)))

(defn read-config
  "Read config.yaml"
  [ralph-dir]
  (try
    (parse-yaml-simple (slurp (str ralph-dir "/config.yaml")))
    (catch Exception _
      {:max-iterations 50
       :max-tokens 500000})))

(defn check-budget
  "Check if budget limits are exceeded"
  [{:keys [iteration tokens max-iterations max-tokens]}]
  (cond
    (>= iteration max-iterations)
    {:exceeded true :reason (str "Max iterations (" max-iterations ") reached")}

    (and max-tokens tokens (>= tokens max-tokens))
    {:exceeded true :reason (str "Max tokens (" max-tokens ") reached")}

    :else
    {:exceeded false}))

(defn check-health
  "Check health/circuit breaker status"
  [health]
  (let [{:keys [consecutive-errors consecutive-no-change]} health]
    (cond
      (>= (or consecutive-errors 0) 3)
      {:healthy false :reason "Too many consecutive errors (3+)"}

      (>= (or consecutive-no-change 0) 5)
      {:healthy false :reason "No changes detected for 5+ iterations"}

      :else
      {:healthy true})))

(defn make-decision
  "Make a decision based on signals, health, and budget"
  [{:keys [signals health budget iteration config all-criteria-complete]}]
  (let [max-iterations (or (:max-iterations config) 50)
        max-tokens (or (:max-tokens config) 500000)
        budget-check (check-budget {:iteration iteration
                                    :tokens (:tokens budget)
                                    :max-iterations max-iterations
                                    :max-tokens max-tokens})
        health-check (check-health health)]
    (cond
      ;; All criteria must be checked before we can complete
      ;; (exit-signal alone is not enough - Claude might be wrong)
      (and all-criteria-complete (:exit-signal signals))
      {:action "complete"
       :reason "TASK_COMPLETE signal and all criteria verified"
       :confidence "high"}

      ;; All criteria marked complete (even without explicit signal)
      all-criteria-complete
      {:action "complete"
       :reason "All completion criteria satisfied"
       :confidence "high"}

      ;; Exit signal but criteria not all checked
      ;; If Claude made no tool calls, it's stuck - pause for human
      ;; If Claude made changes, continue and let it mark criteria
      (and (:exit-signal signals)
           (zero? (get-in signals [:tool-calls :total] 0)))
      {:action "pause"
       :reason "TASK_COMPLETE with no tool calls but criteria unchecked - needs human verification"
       :requires-human true
       :confidence "high"}

      ;; Exit signal with tool calls but criteria not checked - continue
      (:exit-signal signals)
      {:action "continue"
       :reason "TASK_COMPLETE signal but criteria not all checked - continuing"
       :warning "Claude claimed complete but unchecked criteria remain"
       :confidence "medium"}

      ;; Stuck signal
      (:stuck-signal signals)
      {:action "pause"
       :reason (or (:stuck-reason signals) "Claude reported being stuck")
       :requires-human true
       :confidence "high"}

      ;; Health check failed
      (not (:healthy health-check))
      {:action "abort"
       :reason (:reason health-check)
       :confidence "high"}

      ;; Budget exceeded
      (:exceeded budget-check)
      {:action "abort"
       :reason (:reason budget-check)
       :confidence "high"}

      ;; High completion score without explicit signal
      (>= (or (:completion-score signals) 0) 3)
      {:action "verify"
       :reason "High completion confidence - needs verification"
       :confidence "medium"}

      ;; Test-only loop detected
      (:test-only-loop signals)
      {:action "continue"
       :reason "Test-only loop detected - may need intervention soon"
       :warning "Possible test-only loop"
       :confidence "medium"}

      ;; Default: continue
      :else
      {:action "continue"
       :reason "Continuing iteration"
       :confidence "high"})))

(defn decision->yaml
  "Convert decision to YAML format"
  [decision]
  (str/join "\n"
            [(str "action: " (:action decision))
             (str "reason: " (pr-str (:reason decision)))
             (str "confidence: " (:confidence decision))
             (when (:requires-human decision)
               "requires_human: true")
             (when (:warning decision)
               (str "warning: " (pr-str (:warning decision))))]))

;; CLI interface
(defn -main [& args]
  (let [ralph-dir (or (first args) ".ralph")
        signals (read-signals ralph-dir)
        health (read-health ralph-dir)
        state (read-state-frontmatter ralph-dir)
        config (read-config ralph-dir)
        iteration (or (:iteration state) 0)
        ;; TODO: Parse actual budget from tokens/usage.md
        budget {:tokens 0}
        all-complete (all-criteria-complete? ralph-dir)
        decision (make-decision {:signals signals
                                 :health health
                                 :budget budget
                                 :iteration iteration
                                 :config config
                                 :all-criteria-complete all-complete})]
    (println (decision->yaml decision))))
