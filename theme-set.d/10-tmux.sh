#!/usr/bin/env bash
source "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"

if ! command -v tmux >/dev/null 2>&1; then
    skipped "tmux"
fi

source_file="$THPM_CURRENT_THEME_DIR/tmux.conf"
target_file="$HOME/.config/tmux/omarchy-theme.conf"
source_line="source-file ~/.config/tmux/omarchy-theme.conf"

if [[ -f "$HOME/.config/tmux/tmux.conf" ]]; then
    config_file="$HOME/.config/tmux/tmux.conf"
elif [[ -f "$HOME/.tmux.conf" ]]; then
    config_file="$HOME/.tmux.conf"
else
    config_file="$HOME/.config/tmux/tmux.conf"
fi

if [[ ! -f "$source_file" ]]; then
    if [[ -f "$config_file" ]] && grep -Fxq "$source_line" "$config_file"; then
        sed -i "\|^${source_line}$|d" "$config_file"
        tmux source-file "$config_file" >/dev/null 2>&1 || true
    fi
    rm -f "$target_file"
    skipped "tmux.conf"
fi

mkdir -p "$(dirname "$target_file")"
install -m 600 "$source_file" "$target_file"

if [[ ! -f "$config_file" ]]; then
    mkdir -p "$(dirname "$config_file")"
    touch "$config_file"
fi

if ! grep -Fxq "$source_line" "$config_file"; then
    printf '\n%s\n' "$source_line" >> "$config_file"
fi

tmux source-file "$target_file" >/dev/null 2>&1 || true

success "tmux theme updated!"
