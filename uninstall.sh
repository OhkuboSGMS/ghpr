#!/bin/bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Uninstalling ghpr tool..."

# Remove scripts
if [ -f "$HOME/.local/bin/ghpr" ]; then
    echo "Removing ~/.local/bin/ghpr..."
    rm "$HOME/.local/bin/ghpr"
    echo -e "${GREEN}Removed ghpr script${NC}"
else
    echo -e "${YELLOW}ghpr script not found${NC}"
fi

if [ -f "$HOME/.local/bin/ghpr.sh" ]; then
    echo "Removing ~/.local/bin/ghpr.sh..."
    rm "$HOME/.local/bin/ghpr.sh"
    echo -e "${GREEN}Removed ghpr.sh${NC}"
else
    echo -e "${YELLOW}ghpr.sh not found${NC}"
fi

# Function to remove shell function from config file
remove_shell_function() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        return
    fi

    # Check if function exists
    if ! grep -q "source.*ghpr.sh" "$config_file"; then
        return
    fi

    echo "Removing ghpr function from ${config_file}..."

    # Create backup
    cp "$config_file" "${config_file}.ghpr.bak"

    # Remove the lines (comment and source line)
    sed -i.tmp '/# ghpr: GitHub PR checkout tool/,/source.*ghpr\.sh/d' "$config_file"
    rm "${config_file}.tmp"

    echo -e "${GREEN}Removed ghpr function from ${config_file}${NC}"
    echo -e "${YELLOW}Backup saved to ${config_file}.ghpr.bak${NC}"
}

# Remove from shell config files
if [ -f "$HOME/.bashrc" ]; then
    remove_shell_function "$HOME/.bashrc"
fi

if [ -f "$HOME/.zshrc" ]; then
    remove_shell_function "$HOME/.zshrc"
fi

# Note about work directory
echo ""
echo -e "${YELLOW}Note: PR work directories in ~/work/prs/ were not removed${NC}"
echo "To clean them up manually, run:"
echo "  rm -rf ~/work/prs/"
echo ""
echo -e "${GREEN}Uninstallation complete!${NC}"
echo "Please reload your shell or start a new terminal session."
