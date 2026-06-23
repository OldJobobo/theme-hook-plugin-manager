#!/usr/bin/env bash
source "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"

# Intended live destination:
# ~/.config/omarchy/hooks/theme-set.d/25-swaync.sh

set -euo pipefail

SOURCE_DIR="$THPM_CURRENT_THEME_DIR"
TARGET_DIR="$HOME/.config/swaync"
THEME_NAME_FILE="$THPM_THEME_NAME_FILE"
THEME_STORE_DIR="$HOME/.config/omarchy/themes"

if ! command -v swaync >/dev/null 2>&1 || ! command -v swaync-client >/dev/null 2>&1; then
    exit 0
fi

theme_name=""
theme_dir=""

if [[ -f "$THEME_NAME_FILE" ]]; then
    theme_name="$(<"$THEME_NAME_FILE")"
    theme_dir="$THEME_STORE_DIR/$theme_name"
fi

style_source="$SOURCE_DIR/swaync.style.css"
config_source="$SOURCE_DIR/swaync.config.json"
colors_source="$SOURCE_DIR/colors.css"

if [[ -n "$theme_dir" && -f "$theme_dir/swaync.style.css" ]]; then
    style_source="$theme_dir/swaync.style.css"
fi

if [[ -n "$theme_dir" && -f "$theme_dir/swaync.config.json" ]]; then
    config_source="$theme_dir/swaync.config.json"
fi

required_files=(
    "$style_source"
    "$config_source"
    "$colors_source"
)

for file in "${required_files[@]}"; do
    [[ -f "$file" ]] || exit 0
done

mkdir -p "$TARGET_DIR"

install -m 600 "$style_source" "$TARGET_DIR/style.css"
install -m 600 "$config_source" "$TARGET_DIR/config.json"
install -m 600 "$colors_source" "$TARGET_DIR/colors.css"

swaync-client --reload-config -sw >/dev/null 2>&1 || true
swaync-client --reload-css -sw >/dev/null 2>&1 || true
