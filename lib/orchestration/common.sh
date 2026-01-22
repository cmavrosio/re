#!/usr/bin/env bash
#
# Common utilities for re
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Logging functions
log_error() { echo -e "${RED}error:${NC} $1" >&2; }
log_info() { echo -e "${BLUE}info:${NC} $1"; }
log_success() { echo -e "${GREEN}success:${NC} $1"; }
log_warn() { echo -e "${YELLOW}warn:${NC} $1"; }
log_debug() {
    if [[ "${RE_VERBOSE:-false}" == "true" ]]; then
        echo -e "${CYAN}debug:${NC} $1"
    fi
}

# File paths
RALPH_DIR=".ralph"

# Check if .ralph directory exists
require_ralph_dir() {
    if [[ ! -d "$RALPH_DIR" ]]; then
        log_error "No .ralph/ directory found. Run 're init' first."
        exit 1
    fi
}

# Check if a session is active
require_active_session() {
    require_ralph_dir
    if [[ ! -f "$RALPH_DIR/state.md" ]]; then
        log_error "No active session. Run 're start' first."
        exit 1
    fi
}

# Read YAML front matter from markdown file
# Usage: read_frontmatter file.md key
read_frontmatter() {
    local file="$1"
    local key="$2"
    bb -e "(println (-> (slurp \"$file\")
            (clojure.string/split #\"---\" 3)
            second
            (clojure.string/trim)
            (->> (clojure.string/split-lines)
                 (some #(when (clojure.string/starts-with? % \"$key:\")
                          (-> % (subs (inc (count \"$key:\"))) clojure.string/trim))))))"
}

# Read config value from config.yaml
# Usage: read_config key [default]
read_config() {
    local key="$1"
    local default="${2:-}"
    local value

    if [[ -f "$RALPH_DIR/config.yaml" ]]; then
        value=$(bb -e "(println (-> (slurp \"$RALPH_DIR/config.yaml\")
                         (yaml/parse-string)
                         (get (keyword \"$key\"))))" 2>/dev/null || echo "")
    fi

    if [[ -z "$value" || "$value" == "nil" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Generate a short session ID
generate_session_id() {
    uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' | cut -d'-' -f1-2 || \
    head -c 8 /dev/urandom | xxd -p
}

# Get current timestamp in ISO format
timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Get current git branch
current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main"
}

# Safely write to log file
log_to_file() {
    local message="$1"
    local logfile="$RALPH_DIR/logs/re.log"
    if [[ -f "$logfile" ]] || [[ -d "$RALPH_DIR/logs" ]]; then
        echo "[$(timestamp)] $message" >> "$logfile"
    fi
}

# Run babashka with the brain modules in the classpath
run_brain() {
    local module="$1"
    shift
    bb --classpath "$RE_HOME/lib" -m "brain.$module" "$@"
}

# Export functions
export -f log_error log_info log_success log_warn log_debug
export -f require_ralph_dir require_active_session
export -f read_frontmatter read_config
export -f generate_session_id timestamp current_branch
export -f log_to_file run_brain
export RED GREEN YELLOW BLUE CYAN BOLD DIM NC
export RALPH_DIR
