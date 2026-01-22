#!/usr/bin/env bash
#
# Common utilities for kori
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Logging
log_info() {
    echo -e "${BLUE}info:${NC} $1"
}

log_success() {
    echo -e "${GREEN}success:${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}warn:${NC} $1"
}

log_error() {
    echo -e "${RED}error:${NC} $1" >&2
}

# Directory
OVERSEER_DIR=".overseer"

require_overseer_dir() {
    if [[ ! -d "$OVERSEER_DIR" ]]; then
        log_error "No .overseer directory found. Run 'kori init <goal>' first."
        exit 1
    fi
}

require_requirements() {
    require_overseer_dir
    if [[ ! -f "$OVERSEER_DIR/requirements.md" ]]; then
        log_error "No requirements.md found. Run 'kori discover' first."
        exit 1
    fi
}

require_tree() {
    require_overseer_dir
    if [[ ! -f "$OVERSEER_DIR/tree.yaml" ]]; then
        log_error "No tree.yaml found. Run 'kori plan' first."
        exit 1
    fi
}

# Generate unique ID
generate_id() {
    local prefix="${1:-node}"
    echo "${prefix}-$(date +%s)-$(head -c 4 /dev/urandom | xxd -p)"
}

# Timestamp
timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Read YAML value (simple, for flat keys)
read_yaml() {
    local file="$1"
    local key="$2"
    local default="${3:-}"

    if [[ ! -f "$file" ]]; then
        echo "$default"
        return
    fi

    local value
    value=$(grep -E "^${key}:" "$file" 2>/dev/null | head -1 | sed "s/^${key}:[[:space:]]*//" | sed 's/^"//' | sed 's/"$//')

    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Read config value
read_config() {
    local key="$1"
    local default="${2:-}"
    read_yaml "$OVERSEER_DIR/config.yaml" "$key" "$default"
}

# Check if re is available
require_re() {
    if ! command -v re &> /dev/null; then
        log_error "re command not found. Install re first."
        exit 1
    fi
}

# Check if claude is available
require_claude() {
    if ! command -v claude &> /dev/null; then
        log_error "claude command not found. Install Claude Code CLI first."
        exit 1
    fi
}

# Check if bb (babashka) is available
require_bb() {
    if ! command -v bb &> /dev/null; then
        log_error "bb (babashka) not found. Install with: brew install borkdude/brew/babashka"
        exit 1
    fi
}
