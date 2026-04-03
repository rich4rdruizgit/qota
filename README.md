# Qota 🤖

macOS menu bar widget that monitors your Claude Code token usage **without accessing your conversation content**.

## What does it do exactly?

It reads only the numeric fields (`input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`) and the model name from Claude Code's local JSONL files at `~/.claude/projects/`. **It never reads the content of your messages or responses.**

---

## Requirements

- macOS 12+
- [SwiftBar](https://swiftbar.app) installed
- Claude Code in use (generates JSONL files automatically)

---

## Installation

```bash
# 1. Install SwiftBar (if you don't have it)
brew install --cask swiftbar

# 2. Clone or download this repository
# 3. Run the installer
chmod +x install.sh
./install.sh
```

The installer:
- Automatically detects the SwiftBar plugin folder
- Copies the script with the correct permissions
- Refreshes SwiftBar

---

## What you'll see

### In the menu bar
```
🟢 23% [██░░░░░░░░]
```

### In the dropdown menu
```
🤖 Active model: Sonnet
📊 Detected plan: Max 5x
─────────────────────────
Tokens used:   20,240 / 88,000
├─ Input:      15,100
├─ Output:      4,800
├─ Cache read:    340
└─ Cache write:     0
─────────────────────────
⏱ Session expires in: ~187 min
─────────────────────────
🔄 Refresh now
📁 View logs
```

### Notifications
You'll receive a native macOS notification at every 10% of usage:
- **10% – 70%** → Quiet info with remaining tokens
- **80% – 90%** → Warning ⚠️
- **95%+**       → Critical alert ⛔

---

## Plan auto-detection

The script detects your plan by comparing the historical maximum usage:
- If you never exceeded 44k tokens → assumes **Pro**
- If you exceeded 44k but not 88k → assumes **Max 5x**
- If you exceeded 88k → assumes **Max 20x**

To force a plan manually, edit `claude_tokens.5m.sh` and change the line:
```bash
TOKEN_LIMIT=$LIMIT_MAX5   # Change to LIMIT_PRO or LIMIT_MAX20
```

---

## Update frequency

The filename `claude_tokens.5m.sh` controls the frequency:
- `5m` → every 5 minutes (default)
- `1m` → every 1 minute
- `30s` → every 30 seconds

Simply rename the file in your SwiftBar plugin folder.

---

## Privacy

- ✅ Everything runs locally on your Mac
- ✅ No internet connection
- ✅ No telemetry or external tracking
- ✅ The code is ~100 lines of pure Bash, auditable in seconds
- ✅ Only reads numeric fields, never conversation content

---

## Uninstall

```bash
rm "$SWIFTBAR_PLUGIN_DIR/claude_tokens.5m.sh"
rm ~/.claude_tracker_state
rm ~/.claude_tracker_max
```
