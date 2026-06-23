#!/usr/bin/env bash
source "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"
set -u

LOG_FILE="/tmp/foot-theme-hook.log"
FOOT_THEME_FILE="$THPM_CURRENT_THEME_DIR/foot.ini"
FOOT_BASE_CONFIG="$HOME/.config/foot/foot.ini"
OMARCHY_COLORS_FILE="$THPM_CURRENT_THEME_DIR/colors.toml"
ENABLED="${FOOT_LIVE_THEME:-1}"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

normalize_hex() {
  local value="${1:-}"
  value="${value#\#}"
  value="${value,,}"
  if [[ "$value" =~ ^[0-9a-f]{6}$ ]]; then
    printf '%s' "$value"
    return 0
  fi
  return 1
}

normalize_alpha() {
  local value="${1:-}"
  value="${value//[[:space:]]/}"
  value="${value,,}"
  if [[ "$value" =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]]; then
    printf '%s' "$value"
    return 0
  fi
  return 1
}

alpha_to_hex() {
  local value
  if ! value="$(normalize_alpha "${1:-}" 2>/dev/null)"; then
    return 1
  fi

  awk -v alpha="$value" 'BEGIN {
    channel = int((alpha * 255) + 0.5)
    if (channel < 0) channel = 0
    if (channel > 255) channel = 255
    printf "%02x", channel
  }'
}

format_rgb_spec() {
  local value
  if ! value="$(normalize_hex "${1:-}" 2>/dev/null)"; then
    return 1
  fi

  printf 'rgb:%s/%s/%s' "${value:0:2}" "${value:2:2}" "${value:4:2}"
}

format_rgba_spec() {
  local rgb_value alpha_hex
  if ! rgb_value="$(normalize_hex "${1:-}" 2>/dev/null)"; then
    return 1
  fi
  if ! alpha_hex="$(normalize_hex "${2:-}" 2>/dev/null)"; then
    return 1
  fi

  printf 'rgba:%s/%s/%s/%s' "${rgb_value:0:2}" "${rgb_value:2:2}" "${rgb_value:4:2}" "${alpha_hex:0:2}"
}

parse_omarchy_color() {
  local key="$1"
  local file_path="${2:-$OMARCHY_COLORS_FILE}"
  awk -F= -v wanted="$key" '
    $1 ~ /^[[:space:]]*#/ {
      next
    }
    {
      k = $1
      gsub(/[[:space:]]/, "", k)
      if (k == wanted && match($0, /#([0-9A-Fa-f]{6})/)) {
        print substr($0, RSTART + 1, 6)
        exit
      }
    }
  ' "$file_path" 2>/dev/null
}

parse_foot_color() {
  local key="$1"
  local file_path="${2:-$FOOT_THEME_FILE}"
  awk -F= -v wanted="$key" '
    BEGIN { in_colors = 0; seen_dark = 0 }
    /^[[:space:]]*\[/ {
      if ($0 ~ /^[[:space:]]*\[colors-dark\][[:space:]]*$/) {
        in_colors = 1
        seen_dark = 1
      } else if ($0 ~ /^[[:space:]]*\[colors\][[:space:]]*$/ && !seen_dark) {
        in_colors = 1
      } else {
        in_colors = 0
      }
      next
    }
    in_colors {
      k = $1
      gsub(/[[:space:]]/, "", k)
      if (k == wanted) {
        v = $2
        sub(/^[[:space:]]+/, "", v)
        sub(/[[:space:]]+$/, "", v)
        print v
        exit
      }
    }
  ' "$file_path" 2>/dev/null
}

read_cursor_fallback() {
  local raw
  raw="$(parse_foot_color "cursor")"
  raw="${raw#\#}"
  raw="${raw%% *}"
  normalize_hex "$raw" || true
}

read_alpha_fallback() {
  local raw
  raw="$(parse_foot_color "alpha" "$FOOT_BASE_CONFIG")"
  if ! raw="$(normalize_alpha "$raw" 2>/dev/null)"; then
    raw="$(parse_foot_color "alpha" "$FOOT_THEME_FILE")"
  fi
  normalize_alpha "$raw" || true
}

load_color() {
  local var_name="$1"
  local colors_key="$2"
  local foot_key="${3:-$colors_key}"
  local current="${!var_name:-}"

  if current="$(normalize_hex "$current" 2>/dev/null)"; then
    printf -v "$var_name" '%s' "$current"
    return 0
  fi

  local parsed
  # Foot live updates should prefer the rendered Foot palette so existing
  # terminals match new Foot windows even when Omarchy's template output
  # intentionally diverges from colors.toml for terminal-specific tuning.
  parsed="$(parse_foot_color "$foot_key")"
  if ! parsed="$(normalize_hex "$parsed" 2>/dev/null)"; then
    parsed="$(parse_omarchy_color "$colors_key")"
  fi
  parsed="${parsed#\#}"
  parsed="${parsed%% *}"
  if parsed="$(normalize_hex "$parsed" 2>/dev/null)"; then
    printf -v "$var_name" '%s' "$parsed"
    return 0
  fi
  return 1
}

collect_foot_ttys() {
  ps -eo pid=,ppid=,tty=,comm= | awk '
    {
      pid = $1
      ppid[pid] = $2
      tty[pid] = $3
      comm[pid] = $4
      pids[++n] = pid
    }
    END {
      for (i = 1; i <= n; i++) {
        p = pids[i]
        t = tty[p]
        if (t == "?" || t == "" || t !~ /^pts\//) {
          continue
        }
        q = p
        is_foot = 0
        while (q != "" && q != "0") {
          c = comm[q]
          if (c == "foot" || c == "footclient") {
            is_foot = 1
            break
          }
          q = ppid[q]
        }
        if (is_foot) {
          print "/dev/" t
        }
      }
    }
  ' | sort -u
}

if [[ "$ENABLED" == "0" ]]; then
  log "disabled via FOOT_LIVE_THEME=0"
  exit 0
fi

if [[ ! -f "$FOOT_THEME_FILE" ]]; then
  log "missing theme file: $FOOT_THEME_FILE"
  exit 0
fi

if ! load_color primary_background "background"; then
  log "missing background color"
  exit 0
fi
if ! load_color primary_foreground "foreground"; then
  log "missing foreground color"
  exit 0
fi
if ! load_color cursor_color "cursor"; then
  cursor_color="$(read_cursor_fallback)"
fi
if ! cursor_color="$(normalize_hex "${cursor_color:-}" 2>/dev/null)"; then
  cursor_color="$primary_foreground"
fi
if ! load_color selection_background "selection_background" "selection-background"; then
  selection_background="$primary_foreground"
fi
if ! load_color selection_foreground "selection_foreground" "selection-foreground"; then
  selection_foreground="$primary_background"
fi

primary_alpha="$(read_alpha_fallback)"
if ! primary_alpha="$(normalize_alpha "${primary_alpha:-}" 2>/dev/null)"; then
  primary_alpha="1.0"
fi
if ! primary_alpha_hex="$(alpha_to_hex "$primary_alpha" 2>/dev/null)"; then
  primary_alpha_hex="ff"
fi

declare -a palette=()
for idx in $(seq 0 15); do
  var_name=""
  if (( idx < 8 )); then
    case "$idx" in
      0) var_name="normal_black" ;;
      1) var_name="normal_red" ;;
      2) var_name="normal_green" ;;
      3) var_name="normal_yellow" ;;
      4) var_name="normal_blue" ;;
      5) var_name="normal_magenta" ;;
      6) var_name="normal_cyan" ;;
      7) var_name="normal_white" ;;
    esac
    foot_key="regular$idx"
  else
    case "$idx" in
      8) var_name="bright_black" ;;
      9) var_name="bright_red" ;;
      10) var_name="bright_green" ;;
      11) var_name="bright_yellow" ;;
      12) var_name="bright_blue" ;;
      13) var_name="bright_magenta" ;;
      14) var_name="bright_cyan" ;;
      15) var_name="bright_white" ;;
    esac
    foot_key="bright$((idx-8))"
  fi

  value=""
  if [[ -n "$var_name" ]]; then
    value="${!var_name:-}"
  fi
  if ! value="$(normalize_hex "$value" 2>/dev/null)"; then
    parsed="$(parse_foot_color "$foot_key")"
    if ! value="$(normalize_hex "$parsed" 2>/dev/null)"; then
      parsed="$(parse_omarchy_color "color$idx")"
      parsed="${parsed#\#}"
      parsed="${parsed%% *}"
      if value="$(normalize_hex "$parsed" 2>/dev/null)"; then
        :
      else
        value="$primary_foreground"
      fi
    fi
  fi
  palette[idx]="$value"
done

payload=""
osc_end=$'\e\\'
payload+=$'\e]10;'"$(format_rgb_spec "$primary_foreground")""$osc_end"
payload+=$'\e]11;'"$(format_rgb_spec "$primary_background")""$osc_end"
payload+=$'\e]12;'"$(format_rgb_spec "$cursor_color")""$osc_end"
payload+=$'\e]17;'"$(format_rgb_spec "$selection_background")""$osc_end"
payload+=$'\e]19;'"$(format_rgb_spec "$selection_foreground")""$osc_end"
for idx in $(seq 0 15); do
  payload+=$'\e]4;'"$idx"';'"$(format_rgb_spec "${palette[idx]}")""$osc_end"
done

updated=0
attempted=0
while IFS= read -r tty; do
  [[ -n "$tty" ]] || continue
  attempted=$((attempted + 1))
  if [[ ! -w "$tty" ]]; then
    log "cannot write to $tty"
    continue
  fi
  if { printf '%b' "$payload" > "$tty"; } 2>/dev/null; then
    updated=$((updated + 1))
  else
    log "write failed: $tty"
  fi
done < <(collect_foot_ttys)

if (( updated > 0 )); then
  log "updated $updated/$attempted foot tty(s)"
  if declare -f success >/dev/null 2>&1; then
    success "Foot live colors updated!"
  fi
else
  log "no foot tty updates applied (attempted=$attempted)"
fi

exit 0
