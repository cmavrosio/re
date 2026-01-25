(ns brain.circuit-breaker
  "Circuit breaker for detecting and preventing runaway loops"
  (:require [clojure.string :as str]))

(def default-thresholds
  {:max-consecutive-errors 3
   :max-consecutive-no-change 5
   :max-consecutive-test-only 3
   :max-consecutive-test-failures 5  ;; 5 attempts to fix tests before circuit break
   :error-reset-on-success true})

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
                 :else v)]))
       (into {})))

(defn read-health
  "Read current health state"
  [ralph-dir]
  (try
    (parse-yaml-simple (slurp (str ralph-dir "/health.yaml")))
    (catch Exception _
      {:consecutive-errors 0
       :consecutive-no-change 0
       :consecutive-test-only 0
       :consecutive-test-failures 0
       :last-error nil
       :last-success nil})))

(defn truncate-str
  "Truncate string to max length"
  [s max-len]
  (if (and (string? s) (> (count s) max-len))
    (str (subs s 0 max-len) "...")
    s))

(defn safe-str
  "Convert value to safe string for YAML, truncating if needed"
  [v]
  (let [s (if (string? v) v (pr-str v))]
    (truncate-str (or s "null") 200)))

(defn write-health
  "Write health state to file"
  [ralph-dir health]
  (let [yaml-str (str/join "\n"
                           [(str "consecutive_errors: " (or (:consecutive-errors health) 0))
                            (str "consecutive_no_change: " (or (:consecutive-no-change health) 0))
                            (str "consecutive_test_only: " (or (:consecutive-test-only health) 0))
                            (str "consecutive_test_failures: " (or (:consecutive-test-failures health) 0))
                            (str "last_error: " (safe-str (:last-error health)))
                            (str "last_success: " (safe-str (:last-success health)))
                            (str "tripped: " (boolean (:tripped health)))
                            (str "trip_reason: " (safe-str (:trip-reason health)))])]
    (spit (str ralph-dir "/health.yaml") yaml-str)))

(defn check-tripped
  "Check if circuit breaker should trip"
  [health thresholds]
  (let [{:keys [consecutive-errors consecutive-no-change consecutive-test-only consecutive-test-failures]} health
        {:keys [max-consecutive-errors max-consecutive-no-change max-consecutive-test-only max-consecutive-test-failures]} thresholds]
    (cond
      (>= (or consecutive-errors 0) max-consecutive-errors)
      {:tripped true :reason (str "Too many consecutive errors (" consecutive-errors ")")}

      (>= (or consecutive-no-change 0) max-consecutive-no-change)
      {:tripped true :reason (str "No changes for " consecutive-no-change " iterations")}

      (>= (or consecutive-test-only 0) max-consecutive-test-only)
      {:tripped true :reason (str "Test-only loop for " consecutive-test-only " iterations")}

      (>= (or consecutive-test-failures 0) max-consecutive-test-failures)
      {:tripped true :reason (str "Tests failing for " consecutive-test-failures " iterations (CI/tests not passing)")}

      :else
      {:tripped false})))

(defn update-health
  "Update health state based on iteration result"
  [health result]
  (let [{:keys [success has-changes test-only error-message criterion-completed tests-passed]} result
        ;; Criterion completion counts as progress even without git changes
        has-progress (or has-changes criterion-completed)
        now (str (java.time.Instant/now))]
    (cond-> health
      ;; On success, reset error counter
      success
      (-> (assoc :consecutive-errors 0)
          (assoc :last-success now))

      ;; On error, increment counter
      (not success)
      (-> (update :consecutive-errors (fnil inc 0))
          (assoc :last-error now)
          (assoc :last-error-message error-message))

      ;; Track no-change iterations (only if no progress at all)
      (and success (not has-progress))
      (update :consecutive-no-change (fnil inc 0))

      ;; Reset no-change on actual progress (changes OR criterion completion)
      (and success has-progress)
      (assoc :consecutive-no-change 0)

      ;; Track test-only iterations
      test-only
      (update :consecutive-test-only (fnil inc 0))

      ;; Reset test-only on non-test-only
      (and success (not test-only))
      (assoc :consecutive-test-only 0)

      ;; Track test failures (CI or local tests)
      (false? tests-passed)
      (update :consecutive-test-failures (fnil inc 0))

      ;; Reset test failures when tests pass
      (true? tests-passed)
      (assoc :consecutive-test-failures 0))))

(defn reset-health
  "Reset health state to initial values"
  []
  {:consecutive-errors 0
   :consecutive-no-change 0
   :consecutive-test-only 0
   :consecutive-test-failures 0
   :last-error nil
   :last-success nil
   :tripped false
   :trip-reason nil})

;; CLI interface
(defn -main [& args]
  (let [action (first args)
        ralph-dir (or (second args) ".ralph")]
    (case action
      "check"
      (let [health (read-health ralph-dir)
            status (check-tripped health default-thresholds)]
        (println (str "tripped: " (:tripped status)))
        (when (:tripped status)
          (println (str "reason: " (:reason status))))
        (System/exit (if (:tripped status) 1 0)))

      "update"
      (let [health (read-health ralph-dir)
            ;; Read result from stdin as simple key=value pairs
            input (slurp *in*)
            result (parse-yaml-simple input)
            new-health (update-health health result)
            status (check-tripped new-health default-thresholds)]
        (write-health ralph-dir (merge new-health status))
        (println (str "tripped: " (:tripped status)))
        (System/exit (if (:tripped status) 1 0)))

      "reset"
      (do
        (write-health ralph-dir (reset-health))
        (println "Health state reset"))

      "status"
      (let [health (read-health ralph-dir)]
        (println (str "consecutive_errors: " (:consecutive-errors health)))
        (println (str "consecutive_no_change: " (:consecutive-no-change health)))
        (println (str "consecutive_test_only: " (:consecutive-test-only health)))
        (println (str "consecutive_test_failures: " (:consecutive-test-failures health)))
        (println (str "tripped: " (:tripped health))))

      ;; Default: show usage
      (do
        (println "Usage: bb circuit_breaker.clj <action> [ralph-dir]")
        (println "Actions: check, update, reset, status")))))
