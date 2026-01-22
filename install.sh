#!/usr/bin/env bash
#
# re & kori installer
#
# Installs re to ~/.local/share/re and kori to ~/.local/share/kori
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${BLUE}info:${NC} $1"; }
log_success() { echo -e "${GREEN}success:${NC} $1"; }
log_warn() { echo -e "${YELLOW}warn:${NC} $1"; }
log_error() { echo -e "${RED}error:${NC} $1" >&2; }

INSTALL_DIR="${RE_INSTALL_DIR:-$HOME/.local/share/re}"
KORI_INSTALL_DIR="${KORI_INSTALL_DIR:-$HOME/.local/share/kori}"
BIN_DIR="${RE_BIN_DIR:-$HOME/.local/bin}"

usage() {
    cat << 'EOF'
re installer

USAGE:
    ./install.sh [options]

OPTIONS:
    --prefix DIR    Install to DIR instead of ~/.local/share/re
    --bin DIR       Link binary to DIR instead of ~/.local/bin
    --uninstall     Remove re installation
    -h, --help      Show this help

REQUIREMENTS:
    - Babashka (bb) - install with: brew install borkdude/brew/babashka
    - git
    - claude CLI
EOF
}

check_dependencies() {
    local missing=()

    if ! command -v bb &> /dev/null; then
        missing+=("babashka (bb)")
    fi

    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi

    if ! command -v claude &> /dev/null; then
        missing+=("claude CLI")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies:"
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        echo ""
        echo "Install babashka with: brew install borkdude/brew/babashka"
        exit 1
    fi

    log_success "All dependencies found"
}

install_re() {
    log_info "Installing re to $INSTALL_DIR"

    # Create directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BIN_DIR"

    # If we're running from the install directory, we're already installed
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ "$script_dir" == "$INSTALL_DIR" ]]; then
        log_info "Already installed in $INSTALL_DIR"
    else
        # Copy files
        log_info "Copying files..."
        cp -r "$script_dir"/* "$INSTALL_DIR/"
    fi

    # Make scripts executable
    chmod +x "$INSTALL_DIR/bin/re"
    chmod +x "$INSTALL_DIR/commands/"*.sh
    chmod +x "$INSTALL_DIR/lib/orchestration/"*.sh

    # Create symlink in bin directory
    if [[ -L "$BIN_DIR/re" ]]; then
        rm "$BIN_DIR/re"
    fi
    ln -s "$INSTALL_DIR/bin/re" "$BIN_DIR/re"

    log_success "Installed re to $INSTALL_DIR"
    log_success "Linked re to $BIN_DIR/re"
}

install_kori() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Check if kori exists in source
    if [[ ! -d "$script_dir/kori" ]]; then
        log_info "kori not found in source, skipping"
        return
    fi

    log_info "Installing kori to $KORI_INSTALL_DIR"

    # Create directories
    mkdir -p "$KORI_INSTALL_DIR"

    # Copy kori files
    if [[ "$script_dir/kori" != "$KORI_INSTALL_DIR" ]]; then
        cp -r "$script_dir/kori"/* "$KORI_INSTALL_DIR/"
    fi

    # Make scripts executable
    chmod +x "$KORI_INSTALL_DIR/bin/kori"
    chmod +x "$KORI_INSTALL_DIR/commands/"*.sh 2>/dev/null || true
    chmod +x "$KORI_INSTALL_DIR/lib/"*.sh 2>/dev/null || true

    # Create symlink in bin directory
    if [[ -L "$BIN_DIR/kori" ]]; then
        rm "$BIN_DIR/kori"
    fi
    ln -s "$KORI_INSTALL_DIR/bin/kori" "$BIN_DIR/kori"

    log_success "kori installed"
    log_success "Linked kori to $BIN_DIR/kori"
}

finish_install() {
    # Check if BIN_DIR is in PATH
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        log_warn "$BIN_DIR is not in your PATH"
        echo ""
        echo "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
        echo ""
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
    fi

    echo ""
    log_success "Installation complete!"
    echo ""
    echo "Quick start (re):"
    echo "  1. cd your-project"
    echo "  2. re init"
    echo "  3. Edit .ralph/plan.md with your task"
    echo "  4. re start"
    echo ""
    echo "Quick start (kori):"
    echo "  1. cd your-project"
    echo "  2. kori init \"Build something awesome\""
    echo "  3. kori discover"
    echo "  4. kori plan && kori nag"
    echo ""
    echo "For help: re --help | kori help"
}

uninstall_re() {
    log_info "Uninstalling re and kori..."

    if [[ -L "$BIN_DIR/re" ]]; then
        rm "$BIN_DIR/re"
        log_info "Removed $BIN_DIR/re"
    fi

    if [[ -L "$BIN_DIR/kori" ]]; then
        rm "$BIN_DIR/kori"
        log_info "Removed $BIN_DIR/kori"
    fi

    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        log_info "Removed $INSTALL_DIR"
    fi

    if [[ -d "$KORI_INSTALL_DIR" ]]; then
        rm -rf "$KORI_INSTALL_DIR"
        log_info "Removed $KORI_INSTALL_DIR"
    fi

    log_success "Uninstalled re and kori"
}

main() {
    local uninstall=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --bin)
                BIN_DIR="$2"
                shift 2
                ;;
            --uninstall)
                uninstall=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    echo ""
    echo -e "${BOLD}re - Ralph Enhanced${NC}"
    echo -e "${BOLD}kori - Hierarchical Planner${NC}"
    echo "AI task automation with planning"
    echo ""

    if [[ "$uninstall" == "true" ]]; then
        uninstall_re
    else
        check_dependencies
        install_re
        install_kori
        finish_install
    fi
}

main "$@"
