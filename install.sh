#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# Qota installer for SwiftBar
# ─────────────────────────────────────────────────────────────────

set -eo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

print_step() { echo -e "\n${BOLD}${GREEN}▶ $1${NC}"; }
print_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_ok()   { echo -e "${GREEN}✓ $1${NC}"; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║              Qota — Installer            ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── 1. Check SwiftBar ─────────────────────────────────────────────
print_step "Checking SwiftBar..."

if [[ ! -d /Applications/SwiftBar.app ]]; then
  print_warn "SwiftBar is not installed."
  echo ""
  echo "  Install it with Homebrew:"
  echo -e "  ${BOLD}brew install --cask swiftbar${NC}"
  echo ""
  echo "  Or download it at: https://swiftbar.app"
  echo ""
  read -rp "  Already installed? Press Enter to continue or Ctrl+C to exit..."
fi

print_ok "SwiftBar found."

# ── 2. Detect SwiftBar plugin folder ─────────────────────────────
print_step "Detecting SwiftBar plugin folder..."

# SwiftBar stores the path in its preferences
PLUGIN_DIR=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)

if [[ -z "$PLUGIN_DIR" || ! -d "$PLUGIN_DIR" ]]; then
  print_warn "Could not detect automatically."
  echo ""
  echo "  Open SwiftBar → click the menu bar → 'Change Plugin Folder'"
  echo "  Then paste the path here:"
  read -rp "  Plugin folder: " PLUGIN_DIR
fi

if [[ ! -d "$PLUGIN_DIR" ]]; then
  print_error "Folder '$PLUGIN_DIR' does not exist."
  exit 1
fi

print_ok "Plugin folder: $PLUGIN_DIR"

# ── 3. Check Claude Code data ─────────────────────────────────────
print_step "Checking Claude Code data..."

FOUND_DATA=false
for p in "$HOME/.claude/projects" "$HOME/.config/claude/projects"; do
  if [[ -d "$p" ]]; then
    count=$(find "$p" -maxdepth 2 -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
    print_ok "Found: $p ($count JSONL files)"
    FOUND_DATA=true
  fi
done

if [[ "$FOUND_DATA" == "false" ]]; then
  print_warn "No Claude Code data found yet."
  echo "  The tracker will work as soon as you start using Claude Code."
fi

# ── 4. Install the plugin ─────────────────────────────────────────
print_step "Installing plugin..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SRC="$SCRIPT_DIR/claude_tokens.5m.sh"
PLUGIN_DEST="$PLUGIN_DIR/claude_tokens.5m.sh"

if [[ ! -f "$PLUGIN_SRC" ]]; then
  print_error "claude_tokens.5m.sh not found in $SCRIPT_DIR"
  exit 1
fi

cp "$PLUGIN_SRC" "$PLUGIN_DEST"
chmod +x "$PLUGIN_DEST"

print_ok "Plugin installed at: $PLUGIN_DEST"

# ── 5. Check script dependencies ─────────────────────────────────
print_step "Checking dependencies (bash, awk, bc, osascript)..."

for cmd in bash awk bc osascript date; do
  if command -v "$cmd" &>/dev/null; then
    print_ok "$cmd available"
  else
    print_warn "$cmd not found — some features may fail"
  fi
done

# ── 6. Refresh SwiftBar ───────────────────────────────────────────
print_step "Reloading SwiftBar..."
open -a SwiftBar 2>/dev/null || true
sleep 1

# Try to force refresh via URL scheme
open "swiftbar://refreshPlugin?name=claude_tokens.5m.sh" 2>/dev/null || true

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║   ✅ Installation complete                ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "  The icon will appear in your menu bar in seconds."
echo "  Notifications: every 10% of token usage."
echo ""
echo "  To uninstall:"
echo -e "  ${BOLD}rm \"$PLUGIN_DEST\"${NC}"
echo ""
