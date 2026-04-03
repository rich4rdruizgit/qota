#!/usr/bin/env bash
# <swiftbar.title>Qota</swiftbar.title>
# <swiftbar.version>1.0.0</swiftbar.version>
# <swiftbar.author>Doubler</swiftbar.author>
# <swiftbar.desc>Qota — monitors Claude Code tokens per session (only reads counts, never content)</swiftbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>

# ─── CONFIGURATION ────────────────────────────────────────────────────────────
umask 077                                  # Restrict state file permissions to owner only
SESSION_HOURS=5                            # Claude Code session duration
STATE_FILE="$HOME/.claude_tracker_state"  # Saves notification state
CLAUDE_PATHS=(
  "$HOME/.claude/projects"
  "$HOME/.config/claude/projects"
)

# Limits per plan (tokens)
LIMIT_PRO=44000
LIMIT_MAX5=88000
LIMIT_MAX20=220000
# ──────────────────────────────────────────────────────────────────────────────

# ─── READ JSONL: ONLY NUMERIC FIELDS AND MODEL ───────────────────────────────
now_ts=$(date +%s)
[[ "$now_ts" =~ ^[0-9]+$ ]] || { echo "date error | color=red"; exit 1; }
session_cutoff=$((now_ts - SESSION_HOURS * 3600))

# Single Python3 process handles all JSONL parsing — no per-line forks
result=$(QOTA_CUTOFF="$session_cutoff" \
         QOTA_PATH_0="${CLAUDE_PATHS[0]}" \
         QOTA_PATH_1="${CLAUDE_PATHS[1]}" \
         python3 - << 'PYEOF'
import json, os
from datetime import datetime

session_cutoff = int(os.environ.get('QOTA_CUTOFF', 0))
paths = [os.environ.get('QOTA_PATH_0', ''), os.environ.get('QOTA_PATH_1', '')]

total_input = total_output = total_cache_read = total_cache_write = 0
active_model = ''
seen_ids = set()

def parse_ts(ts_raw):
    try:
        ts_str = ts_raw.split('.')[0].rstrip('Z')
        return int(datetime.strptime(ts_str, '%Y-%m-%dT%H:%M:%S').timestamp())
    except Exception:
        return 0

def safe_int(v):
    try:
        return min(int(v or 0), 9_999_999_999)
    except Exception:
        return 0

for base in paths:
    if not base or not os.path.isdir(base):
        continue
    for root, dirs, files in os.walk(base):
        if root[len(base):].count(os.sep) >= 3:
            dirs.clear()
            continue
        for fname in files:
            if not fname.endswith('.jsonl'):
                continue
            fpath = os.path.join(root, fname)
            if os.path.islink(fpath):
                continue
            try:
                with open(fpath, 'r', errors='ignore') as f:
                    for i, line in enumerate(f):
                        if i >= 100000:
                            break
                        if len(line) > 65536:
                            continue
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            obj = json.loads(line)
                        except Exception:
                            continue
                        # timestamp filter
                        ts_raw = str(obj.get('timestamp', ''))
                        if not ts_raw or len(ts_raw) > 30:
                            continue
                        if parse_ts(ts_raw) < session_cutoff:
                            continue
                        # dedup by id
                        msg_id = str(obj.get('id', ''))[:64]
                        if msg_id and msg_id in seen_ids:
                            continue
                        if msg_id:
                            seen_ids.add(msg_id)
                        # model
                        model = str(obj.get('model', ''))
                        if model and model != 'null':
                            active_model = model
                        # usage — try nested 'usage' dict, fall back to top-level
                        usage = obj.get('usage')
                        usage = usage if isinstance(usage, dict) else obj
                        total_input      += safe_int(usage.get('input_tokens'))
                        total_output     += safe_int(usage.get('output_tokens'))
                        total_cache_read  += safe_int(usage.get('cache_read_input_tokens'))
                        total_cache_write += safe_int(usage.get('cache_creation_input_tokens'))
            except Exception:
                pass

print(f'{total_input} {total_output} {total_cache_read} {total_cache_write} {active_model}')
PYEOF
)
read -r total_input total_output total_cache_read total_cache_write active_model <<< "$result"
[[ "$total_input"      =~ ^[0-9]+$ ]] || total_input=0
[[ "$total_output"     =~ ^[0-9]+$ ]] || total_output=0
[[ "$total_cache_read" =~ ^[0-9]+$ ]] || total_cache_read=0
[[ "$total_cache_write" =~ ^[0-9]+$ ]] || total_cache_write=0

# Total tokens consumed in active session (all types count toward the rate limit)
total_tokens=$((total_input + total_output + total_cache_read + total_cache_write))

# ─── AUTO-DETECTION OF PLAN ──────────────────────────────────────────────────
# Calculate historical max tokens in a single 5h session
# If exceeds 44k → Max5, if exceeds 88k → Max20
max_historical_file="$HOME/.claude_tracker_max"
current_max=0
[[ -f "$max_historical_file" ]] && current_max=$(head -c 20 "$max_historical_file")
[[ "$current_max" =~ ^[0-9]+$ ]] || current_max=0

if [[ "$total_tokens" -gt "$current_max" ]]; then
  [[ ! -L "$max_historical_file" ]] && echo "$total_tokens" > "$max_historical_file"
  current_max=$total_tokens
fi

if [[ "$current_max" -gt "$LIMIT_MAX5" ]]; then
  TOKEN_LIMIT=$LIMIT_MAX20
  plan_name="Max 20x"
elif [[ "$current_max" -gt "$LIMIT_PRO" ]]; then
  TOKEN_LIMIT=$LIMIT_MAX5
  plan_name="Max 5x"
else
  TOKEN_LIMIT=$LIMIT_MAX5   # Default to Max5 per your current plan
  plan_name="Max 5x"
fi

# ─── PERCENTAGE CALCULATION ────────────────────────────────────────────────────
pct=0
[[ "$TOKEN_LIMIT" -gt 0 ]] && pct=$((total_tokens * 100 / TOKEN_LIMIT))
[[ "$pct" -gt 100 ]] && pct=100

# ─── FRIENDLY MODEL NAME ───────────────────────────────────────────────────────
friendly_model="—"
case "$active_model" in
  *opus*)    friendly_model="Opus" ;;
  *sonnet*)  friendly_model="Sonnet" ;;
  *haiku*)   friendly_model="Haiku" ;;
  *"claude-3-5"*) friendly_model="Claude 3.5" ;;
  "") friendly_model="—" ;;
  *) friendly_model=$(printf '%s\n' "$active_model" | sed 's/claude-//;s/-[0-9].*//') ;;
esac

# ─── STATUS EMOJI ──────────────────────────────────────────────────────────────
if [[ "$pct" -ge 95 ]]; then
  status_icon="🔴"
elif [[ "$pct" -ge 80 ]]; then
  status_icon="🟡"
elif [[ "$pct" -ge 50 ]]; then
  status_icon="🟠"
else
  status_icon="🟢"
fi

# ─── PROGRESS BAR (text) ────────────────────────────────────────────────────────
bar_len=10
filled=$(( pct * bar_len / 100 ))
empty=$(( bar_len - filled ))
bar=""
for ((i=0; i<filled; i++)); do bar+="█"; done
for ((i=0; i<empty; i++)); do bar+="░"; done

# ─── NOTIFICATIONS EVERY 10% ──────────────────────────────────────────────────
# Persistent state: last notified percentage
last_notified=0
[[ -f "$STATE_FILE" ]] && last_notified=$(head -c 20 "$STATE_FILE")
[[ "$last_notified" =~ ^[0-9]+$ ]] || last_notified=0

# Current threshold: multiple of 10 reached
threshold=$(( (pct / 10) * 10 ))

if [[ "$threshold" -gt "$last_notified" && "$threshold" -gt 0 ]]; then
  remaining=$((TOKEN_LIMIT - total_tokens))
  [[ "$remaining" -lt 0 ]] && remaining=0
  remaining_k=$(echo "scale=1; $remaining/1000" | bc 2>/dev/null || echo "$((remaining/1000))")

  if [[ "$pct" -ge 95 ]]; then
    notif_title="⛔ Qota — ${pct}% used"
    notif_body="Only ~${remaining_k}k tokens left. Close the session soon."
  elif [[ "$pct" -ge 80 ]]; then
    notif_title="⚠️ Qota — ${pct}% used"
    notif_body="~${remaining_k}k tokens remaining in this session (${plan_name})."
  else
    notif_title="📊 Qota — ${pct}% used"
    notif_body="Tokens remaining: ~${remaining_k}k | Model: ${friendly_model}"
  fi

  NOTIF_BODY="$notif_body" NOTIF_TITLE="$notif_title" \
    osascript -e 'display notification (system attribute "NOTIF_BODY") with title (system attribute "NOTIF_TITLE") sound name "Funk"' 2>/dev/null
  [[ ! -L "$STATE_FILE" ]] && echo "$threshold" > "$STATE_FILE"
fi

# Reset state if tokens dropped (new session)
if [[ "$pct" -lt "$last_notified" && "$pct" -lt 5 ]]; then
  [[ ! -L "$STATE_FILE" ]] && echo "0" > "$STATE_FILE"
fi

# ─── OUTPUT FOR SWIFTBAR ─────────────────────────────────────────────────────
# Line 1: appears in menu bar
echo "${status_icon} ${pct}% [${bar}] | font=Menlo size=12"

# Separator
echo "---"

# Dropdown menu
echo "🤖 Active model: ${friendly_model} | size=13 bash=/usr/bin/true terminal=false"
echo "📊 Detected plan: ${plan_name} | size=13 bash=/usr/bin/true terminal=false"
echo "---"
echo "Tokens used:      $(printf "%'d" "$total_tokens") / $(printf "%'d" "$TOKEN_LIMIT") | font=Menlo size=12 bash=/usr/bin/true terminal=false"
echo "├─ Input:         $(printf "%'d" "$total_input") | font=Menlo size=11 bash=/usr/bin/true terminal=false"
echo "├─ Output:        $(printf "%'d" "$total_output") | font=Menlo size=11 bash=/usr/bin/true terminal=false"
echo "├─ Cache read:    $(printf "%'d" "$total_cache_read") | font=Menlo size=11 bash=/usr/bin/true terminal=false"
echo "└─ Cache write:   $(printf "%'d" "$total_cache_write") | font=Menlo size=11 bash=/usr/bin/true terminal=false"
echo "---"

if [[ "$total_tokens" -gt 0 ]]; then
  echo "⏱ Active session (last ${SESSION_HOURS}h) | size=12 bash=/usr/bin/true terminal=false"
else
  echo "⏱ No active session | size=12 bash=/usr/bin/true terminal=false"
fi

echo "---"
echo "🔄 Refresh now | refresh=true"
# Note: SwiftBar param values don't support spaces — breaks if $HOME contains spaces (known SwiftBar limitation)
echo "📁 View logs (~/.claude/projects) | bash=open param1=$HOME/.claude/projects terminal=false"
