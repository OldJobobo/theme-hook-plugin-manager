#!/usr/bin/env bash

# Shared runtime for thpm theme hooks. Omarchy runs hooks in
# ~/.config/omarchy/hooks/theme-set.d directly, so every bundled plugin
# sources this file to load the current theme colors and helper functions.
THPM_CONFIG_FILE="${THPM_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/thpm/config.toml}"

thpm_config_get() {
    local section="$1"
    local key="$2"

    [[ -f "$THPM_CONFIG_FILE" ]] || return 1
    awk -v wanted_section="$section" -v wanted_key="$key" '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
        }
        function strip_comment(value,    i, char, quote, escaped, out) {
            quote = ""
            escaped = 0
            out = ""
            for (i = 1; i <= length(value); i++) {
                char = substr(value, i, 1)
                if (escaped) {
                    out = out char
                    escaped = 0
                    continue
                }
                if (char == "\\") {
                    out = out char
                    escaped = 1
                    continue
                }
                if ((char == "\"" || char == "'\''") && quote == "") {
                    quote = char
                } else if (char == quote) {
                    quote = ""
                }
                if (char == "#" && quote == "") {
                    break
                }
                out = out char
            }
            return out
        }
        {
            line = trim(strip_comment($0))
            if (line == "") next
            if (line ~ /^\[[A-Za-z0-9_.-]+\]$/) {
                current_section = substr(line, 2, length(line) - 2)
                next
            }
            split_at = index(line, "=")
            if (split_at == 0 || current_section != wanted_section) next
            current_key = trim(substr(line, 1, split_at - 1))
            if (current_key != wanted_key) next
            value = trim(substr(line, split_at + 1))
            if ((substr(value, 1, 1) == "\"" && substr(value, length(value), 1) == "\"") ||
                (substr(value, 1, 1) == "'\''" && substr(value, length(value), 1) == "'\''")) {
                value = substr(value, 2, length(value) - 2)
            }
            print value
            found = 1
            exit
        }
        END { exit found ? 0 : 1 }
    ' "$THPM_CONFIG_FILE"
}

thpm_expand_path() {
    local path="$1"

    case "$path" in
        "~") printf '%s\n' "$HOME" ;;
        \~/*) printf '%s/%s\n' "$HOME" "${path#\~/}" ;;
        *) printf '%s\n' "$path" ;;
    esac
}

thpm_config_path() {
    local section="$1"
    local key="$2"
    local default="$3"
    local value

    value="$(thpm_config_get "$section" "$key" 2>/dev/null || true)"
    thpm_expand_path "${value:-$default}"
}

thpm_config_value() {
    local section="$1"
    local key="$2"
    local default="$3"
    local value

    value="$(thpm_config_get "$section" "$key" 2>/dev/null || true)"
    printf '%s\n' "${value:-$default}"
}

thpm_truthy() {
    case "$1" in
        1|true|TRUE|True|yes|YES|Yes|on|ON|On) return 0 ;;
        *) return 1 ;;
    esac
}

THPM_STATE_DIR="${THPM_STATE_DIR:-$(thpm_config_path paths state_dir "$HOME/.local/share/thpm")}"
THPM_NOTIFICATION_ENABLED="$(thpm_config_value notifications enabled true)"
THPM_NOTIFICATION_BACKEND="$(thpm_config_value notifications backend auto)"
THPM_RESTART_NOTIFICATION_ENABLED="$(thpm_config_value notifications.restart enabled true)"
THPM_RESTART_NOTIFICATION_ONLY_RUNNING="$(thpm_config_value notifications.restart only_when_running true)"
THPM_RESTART_NOTIFICATION_COOLDOWN="$(thpm_config_value notifications.restart cooldown_seconds 300)"
THPM_RESTART_NOTIFICATION_TITLE="$(thpm_config_value notifications.restart title "Theme Hook Plugin Manager")"
THPM_RESTART_NOTIFICATION_MESSAGE="$(thpm_config_value notifications.restart message "{app} requires a restart to apply theme.")"

THPM_QUATTRO_COLORS_FILE="$HOME/.local/state/omarchy/current/theme/colors.toml"
THPM_LEGACY_COLORS_FILE="$HOME/.config/omarchy/current/theme/colors.toml"

thpm_resolve_colors_file() {
    local configured_colors_file
    local configured_colors_file_expanded

    if [[ -n "${THPM_COLORS_FILE:-}" ]]; then
        thpm_expand_path "$THPM_COLORS_FILE"
        return 0
    fi

    configured_colors_file="$(thpm_config_get paths colors_file 2>/dev/null || true)"
    if [[ -n "$configured_colors_file" ]]; then
        configured_colors_file_expanded="$(thpm_expand_path "$configured_colors_file")"
        if [[ "$configured_colors_file_expanded" != "$THPM_LEGACY_COLORS_FILE" &&
              "$configured_colors_file_expanded" != "$THPM_QUATTRO_COLORS_FILE" ]]; then
            printf '%s\n' "$configured_colors_file_expanded"
            return 0
        fi
    fi

    if [[ -f "$THPM_QUATTRO_COLORS_FILE" ]]; then
        printf '%s\n' "$THPM_QUATTRO_COLORS_FILE"
    elif [[ -n "${configured_colors_file_expanded:-}" && -f "$configured_colors_file_expanded" ]]; then
        printf '%s\n' "$configured_colors_file_expanded"
    elif [[ -f "$THPM_LEGACY_COLORS_FILE" ]]; then
        printf '%s\n' "$THPM_LEGACY_COLORS_FILE"
    else
        printf '%s\n' "$THPM_QUATTRO_COLORS_FILE"
    fi
}

input_file="$(thpm_resolve_colors_file)"
THPM_COLORS_FILE_RESOLVED="$input_file"
THPM_CURRENT_THEME_DIR="${THPM_COLORS_FILE_RESOLVED%/*}"
THPM_THEME_NAME_FILE="${THPM_CURRENT_THEME_DIR%/*}/theme.name"
THPM_LIGHT_MODE_FILE="$THPM_CURRENT_THEME_DIR/light.mode"
export THPM_COLORS_FILE_RESOLVED THPM_CURRENT_THEME_DIR THPM_THEME_NAME_FILE THPM_LIGHT_MODE_FILE

success() {
    echo -e "\e[32m[SUCCESS]\e[0m $1"
}

skipped() {
    echo -e "\033[0;34m[SKIPPED]\e[0m $1 not found. Skipping.."
    exit 0
}

warning() {
    echo -e "\033[0;33m[WARNING]\e[0m $1"
}

error() {
    echo -e "\e[31m[ERROR]\e[0m $1"
    exit 1
}

if [[ ! -f "$input_file" ]]; then
    error "colors.toml not found at $input_file. Ensure your theme is compatible with Omarchy and includes colors.toml."
fi

extract_color() {
    local color_name="$1"
    awk -v color="$color_name" '
        $1 == color && /=/ {
            if (match($0, /#([0-9a-fA-F]{6})/)) {
                print substr($0, RSTART + 1, 6)
                exit
            }
        }
    ' "$input_file"
}

hex2rgb() {
    local hex_input=$1

    [[ -n "$hex_input" ]] || {
        echo "0, 0, 0"
        return 0
    }

    local r=$((16#${hex_input:0:2}))
    local g=$((16#${hex_input:2:2}))
    local b=$((16#${hex_input:4:2}))
    echo "$r, $g, $b"
}

rgb2hex() {
    local r=$1
    local g=$2
    local b=$3
    printf "%02x%02x%02x" "$r" "$g" "$b"
}

clamp_rgb() {
    local value=$1
    if (( value < 0 )); then
        echo 0
    elif (( value > 255 )); then
        echo 255
    else
        echo "$value"
    fi
}

change_shade() {
    local hex_input=$1
    local shade=$2
    local r=$((16#${hex_input:0:2}))
    local g=$((16#${hex_input:2:2}))
    local b=$((16#${hex_input:4:2}))

    r=$(clamp_rgb $((r + shade)))
    g=$(clamp_rgb $((g + shade)))
    b=$(clamp_rgb $((b + shade)))

    rgb2hex "$r" "$g" "$b"
}

require_restart() {
    local process_name="$1"
    local display_name="${2:-${process_name^}}"
    local app_enabled
    local message
    local cooldown_file
    local now
    local last_notified

    thpm_truthy "$THPM_NOTIFICATION_ENABLED" || return 0
    thpm_truthy "$THPM_RESTART_NOTIFICATION_ENABLED" || return 0

    app_enabled="$(thpm_config_value notifications.restart.apps "$process_name" true)"
    thpm_truthy "$app_enabled" || return 0

    if thpm_truthy "$THPM_RESTART_NOTIFICATION_ONLY_RUNNING"; then
        command -v pgrep >/dev/null 2>&1 || return 0
        pgrep -x "$process_name" >/dev/null || return 0
    fi

    if [[ "$THPM_RESTART_NOTIFICATION_COOLDOWN" =~ ^[0-9]+$ ]] && (( THPM_RESTART_NOTIFICATION_COOLDOWN > 0 )); then
        cooldown_file="$THPM_STATE_DIR/restart-notified-${process_name//[^A-Za-z0-9_.-]/_}"
        now=$(date +%s)
        if [[ -f "$cooldown_file" ]]; then
            last_notified="$(cat "$cooldown_file" 2>/dev/null || true)"
            if [[ "$last_notified" =~ ^[0-9]+$ ]] && (( now - last_notified < THPM_RESTART_NOTIFICATION_COOLDOWN )); then
                return 0
            fi
        fi
        mkdir -p "$THPM_STATE_DIR" 2>/dev/null || true
        printf '%s\n' "$now" > "$cooldown_file" 2>/dev/null || true
    fi

    message="${THPM_RESTART_NOTIFICATION_MESSAGE//\{app\}/$display_name}"
    case "$THPM_NOTIFICATION_BACKEND" in
        off)
            return 0
            ;;
        stdout)
            warning "$message"
            ;;
        notify-send)
            if command -v notify-send >/dev/null 2>&1; then
                notify-send "$THPM_RESTART_NOTIFICATION_TITLE" "$message"
            else
                warning "$message"
            fi
            ;;
        auto|*)
            if command -v notify-send >/dev/null 2>&1; then
                notify-send "$THPM_RESTART_NOTIFICATION_TITLE" "$message"
            else
                warning "$message"
            fi
            ;;
    esac
}

primary_foreground=$(extract_color "foreground")
primary_background=$(extract_color "background")
cursor_color=$(extract_color "cursor")
selection_foreground=$(extract_color "selection_foreground")
selection_background=$(extract_color "selection_background")
normal_black=$(extract_color "color0")
normal_red=$(extract_color "color1")
normal_green=$(extract_color "color2")
normal_yellow=$(extract_color "color3")
normal_blue=$(extract_color "color4")
normal_magenta=$(extract_color "color5")
normal_cyan=$(extract_color "color6")
normal_white=$(extract_color "color7")
bright_black=$(extract_color "color8")
bright_red=$(extract_color "color9")
bright_green=$(extract_color "color10")
bright_yellow=$(extract_color "color11")
bright_blue=$(extract_color "color12")
bright_magenta=$(extract_color "color13")
bright_cyan=$(extract_color "color14")
bright_white=$(extract_color "color15")

export primary_background primary_foreground cursor_color selection_foreground selection_background
export normal_black normal_red normal_green normal_yellow normal_blue normal_magenta normal_cyan normal_white
export bright_black bright_red bright_green bright_yellow bright_blue bright_magenta bright_cyan bright_white

rgb_primary_foreground=$(hex2rgb "$primary_foreground")
rgb_primary_background=$(hex2rgb "$primary_background")
rgb_cursor_color=$(hex2rgb "$cursor_color")
rgb_selection_foreground=$(hex2rgb "$selection_foreground")
rgb_selection_background=$(hex2rgb "$selection_background")
rgb_normal_black=$(hex2rgb "$normal_black")
rgb_normal_red=$(hex2rgb "$normal_red")
rgb_normal_green=$(hex2rgb "$normal_green")
rgb_normal_yellow=$(hex2rgb "$normal_yellow")
rgb_normal_blue=$(hex2rgb "$normal_blue")
rgb_normal_magenta=$(hex2rgb "$normal_magenta")
rgb_normal_cyan=$(hex2rgb "$normal_cyan")
rgb_normal_white=$(hex2rgb "$normal_white")
rgb_bright_black=$(hex2rgb "$bright_black")
rgb_bright_red=$(hex2rgb "$bright_red")
rgb_bright_green=$(hex2rgb "$bright_green")
rgb_bright_yellow=$(hex2rgb "$bright_yellow")
rgb_bright_blue=$(hex2rgb "$bright_blue")
rgb_bright_magenta=$(hex2rgb "$bright_magenta")
rgb_bright_cyan=$(hex2rgb "$bright_cyan")
rgb_bright_white=$(hex2rgb "$bright_white")

export rgb_primary_foreground rgb_primary_background rgb_cursor_color rgb_selection_foreground rgb_selection_background
export rgb_normal_black rgb_normal_red rgb_normal_green rgb_normal_yellow rgb_normal_blue rgb_normal_magenta rgb_normal_cyan rgb_normal_white
export rgb_bright_black rgb_bright_red rgb_bright_green rgb_bright_yellow rgb_bright_blue rgb_bright_magenta rgb_bright_cyan rgb_bright_white
