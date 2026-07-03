#!/bin/bash
set -euo pipefail

# Run from the directory of this script so relative `cp ghpr` / `cp ghpr.sh`
# work regardless of the caller's cwd.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Installing ghpr tool..."

# Check if gh is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed${NC}"
    echo "Please install it from: https://cli.github.com/"
    exit 1
fi

# Create ~/.local/bin if it doesn't exist
mkdir -p "$HOME/.local/bin"

# Copy ghpr script
echo "Copying ghpr script to ~/.local/bin/ghpr..."
cp ghpr "$HOME/.local/bin/ghpr"
chmod +x "$HOME/.local/bin/ghpr"

# Add ~/.local/bin to PATH if not already there
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo -e "${YELLOW}Note: ~/.local/bin is not in your PATH${NC}"
    echo "Add the following to your shell config file:"
    echo '  export PATH="$HOME/.local/bin:$PATH"'
fi

# Function to add shell function to config file
add_shell_function() {
    local config_file="$1"
    local shell_name="$2"

    if [ ! -f "$config_file" ]; then
        echo -e "${YELLOW}${config_file} not found, skipping...${NC}"
        return
    fi

    # Check if function already exists
    if grep -q "^ghpr()" "$config_file" || grep -q "^ghpr ()" "$config_file"; then
        echo -e "${YELLOW}ghpr function already exists in ${config_file}, skipping...${NC}"
        return
    fi

    echo "Adding ghpr shell function to ${config_file}..."
    cat >> "$config_file" <<'EOF'

# ghpr: GitHub PR checkout tool
# Usage: ghpr <pr-number> <owner/repo> OR ghpr <github-pr-url>
source "$HOME/.local/bin/ghpr.sh"
EOF

    echo -e "${GREEN}Added ghpr function to ${config_file}${NC}"
}

# Copy shell function file
echo "Copying shell function to ~/.local/bin/ghpr.sh..."
cp ghpr.sh "$HOME/.local/bin/ghpr.sh"

# Add to shell config files
if [ -n "${BASH_VERSION:-}" ] || [ -f "$HOME/.bashrc" ]; then
    add_shell_function "$HOME/.bashrc" "bash"
fi

if [ -f "$HOME/.zshrc" ]; then
    add_shell_function "$HOME/.zshrc" "zsh"
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "To start using ghpr:"
echo "  1. Reload your shell config: source ~/.zshrc (or ~/.bashrc)"
echo "  2. Try: ghpr <pr-number> <owner/repo>"
echo "  3. Or:  ghpr https://github.com/owner/repo/pull/<number>"
echo ""
echo "Example:"
echo "  ghpr 125 octocat/Hello-World"
echo "  ghpr https://github.com/octocat/Hello-World/pull/125"
