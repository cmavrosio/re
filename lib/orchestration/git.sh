#!/usr/bin/env bash
#
# Git operations for re
#

set -euo pipefail

source "$RE_HOME/lib/orchestration/common.sh" 2>/dev/null || {
    log_error() { echo "error: $1" >&2; }
    log_info() { echo "info: $1"; }
}

# Check if repo has any commits
has_commits() {
    git rev-parse HEAD >/dev/null 2>&1
}

# Ensure repo has an initial commit (for fresh repos)
ensure_initial_commit() {
    if has_commits; then
        return 0
    fi

    log_info "Fresh repo detected, creating initial commit..."

    # Stage all files
    git add -A

    # Create initial commit
    git commit -m "chore: initial commit

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"

    log_info "Created initial commit"
}

# Create a new work branch
create_branch() {
    local branch_name="$1"
    local base_branch="${2:-$(git rev-parse --abbrev-ref HEAD)}"

    log_info "Creating branch $branch_name from $base_branch" >&2

    # Ensure we're on the base branch
    git checkout "$base_branch" >/dev/null 2>&1 || true

    # Create and checkout the new branch
    git checkout -b "$branch_name" >/dev/null 2>&1

    echo "$branch_name"
}

# Commit current changes
commit_changes() {
    local message="$1"
    local iteration="${2:-}"
    local auto_push="${3:-false}"

    # Ensure repo has at least one commit
    ensure_initial_commit

    # Stage all changes
    git add -A

    # Check if there are changes to commit
    if git diff --cached --quiet; then
        log_info "No changes to commit"
        return 1
    fi

    # Create commit message (conventional commit format for commitlint compatibility)
    local full_message
    if [[ -n "$iteration" ]]; then
        full_message="chore(re): $message (iteration $iteration)"
    else
        full_message="chore(re): $message"
    fi

    git commit -m "$full_message"
    log_info "Committed: $full_message"

    # Push if auto_push is enabled
    if [[ "$auto_push" == "true" ]]; then
        push_changes
    fi
}

# Push current branch to remote
push_changes() {
    local branch
    branch=$(current_branch)

    # Check if remote exists
    if ! git remote | grep -q .; then
        log_info "No remote configured, skipping push"
        return 0
    fi

    # Push with upstream tracking
    if git push -u origin "$branch" 2>/dev/null; then
        log_info "Pushed to origin/$branch"
    else
        log_info "Push failed or already up to date"
    fi
}

# Get diff since base branch
get_diff() {
    local base_branch="${1:-main}"
    local format="${2:-stat}"

    case "$format" in
        stat)
            git diff --stat "$base_branch"...HEAD
            ;;
        numstat)
            git diff --numstat "$base_branch"...HEAD
            ;;
        full)
            git diff "$base_branch"...HEAD
            ;;
        names)
            git diff --name-only "$base_branch"...HEAD
            ;;
    esac
}

# Get diff of uncommitted changes
get_uncommitted_diff() {
    local format="${1:-stat}"

    case "$format" in
        stat)
            git diff --stat
            git diff --stat --cached
            ;;
        numstat)
            git diff --numstat
            git diff --numstat --cached
            ;;
        full)
            git diff
            git diff --cached
            ;;
        names)
            git diff --name-only
            git diff --name-only --cached
            ;;
    esac
}

# Check if there are uncommitted changes
has_uncommitted_changes() {
    ! git diff --quiet || ! git diff --cached --quiet
}

# Get current branch name
current_branch() {
    git rev-parse --abbrev-ref HEAD
}

# Get base branch from state
get_base_branch() {
    local ralph_dir="${1:-.ralph}"
    if [[ -f "$ralph_dir/state.md" ]]; then
        grep -E "^base_branch:" "$ralph_dir/state.md" | cut -d' ' -f2 || echo "main"
    else
        echo "main"
    fi
}

# Rollback to a specific commit or N commits back
rollback() {
    local target="${1:-1}"

    if [[ "$target" =~ ^[0-9]+$ ]]; then
        # Rollback N commits
        log_info "Rolling back $target commits"
        git reset --hard "HEAD~$target"
    else
        # Rollback to specific commit
        log_info "Rolling back to commit $target"
        git reset --hard "$target"
    fi
}

# Stash current changes
stash_changes() {
    local message="${1:-re auto-stash}"
    git stash push -m "$message"
}

# Pop stashed changes
pop_stash() {
    git stash pop
}

# Get commit count since base
commit_count() {
    local base_branch="${1:-main}"
    git rev-list --count "$base_branch"..HEAD
}

# Get last commit hash
last_commit() {
    git rev-parse HEAD
}

# Get last commit message
last_commit_message() {
    git log -1 --pretty=%B
}

# CLI interface
case "${1:-}" in
    create-branch)
        create_branch "${2:-}" "${3:-}"
        ;;
    commit)
        commit_changes "${2:-Auto-commit}" "${3:-}" "${4:-false}"
        ;;
    push)
        push_changes
        ;;
    diff)
        get_diff "${2:-main}" "${3:-stat}"
        ;;
    uncommitted-diff)
        get_uncommitted_diff "${2:-stat}"
        ;;
    has-changes)
        if has_uncommitted_changes; then
            echo "true"
            exit 0
        else
            echo "false"
            exit 1
        fi
        ;;
    current-branch)
        current_branch
        ;;
    base-branch)
        get_base_branch "${2:-.ralph}"
        ;;
    rollback)
        rollback "${2:-1}"
        ;;
    stash)
        stash_changes "${2:-}"
        ;;
    pop-stash)
        pop_stash
        ;;
    commit-count)
        commit_count "${2:-main}"
        ;;
    last-commit)
        last_commit
        ;;
    last-message)
        last_commit_message
        ;;
    has-commits)
        if has_commits; then
            echo "true"
            exit 0
        else
            echo "false"
            exit 1
        fi
        ;;
    ensure-initial-commit)
        ensure_initial_commit
        ;;
    *)
        echo "Usage: git.sh <command> [args...]"
        echo "Commands:"
        echo "  create-branch <name> [base]  - Create new branch"
        echo "  commit <message> [iteration] - Commit changes"
        echo "  diff [base] [format]         - Get diff since base"
        echo "  uncommitted-diff [format]    - Get uncommitted changes"
        echo "  has-changes                  - Check for uncommitted changes"
        echo "  current-branch               - Get current branch"
        echo "  base-branch [ralph-dir]      - Get base branch from state"
        echo "  rollback [target]            - Rollback commits"
        echo "  stash [message]              - Stash changes"
        echo "  pop-stash                    - Pop stashed changes"
        echo "  commit-count [base]          - Count commits since base"
        echo "  last-commit                  - Get last commit hash"
        echo "  last-message                 - Get last commit message"
        ;;
esac
