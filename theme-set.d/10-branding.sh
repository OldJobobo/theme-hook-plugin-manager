#!/usr/bin/env bash
source "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"

theme_dir="$THPM_CURRENT_THEME_DIR"
branding_dir="$HOME/.config/omarchy/branding"
updated=0

copy_branding_file() {
    local source_file="$1"
    local target_file="$2"

    [[ -f "$source_file" ]] || return 1

    mkdir -p "$branding_dir"
    cp -f "$source_file" "$target_file"
    updated=1
}

copy_branding_file "$theme_dir/about.txt" "$branding_dir/about.txt" || true
copy_branding_file "$theme_dir/screensaver.txt" "$branding_dir/screensaver.txt" || true

if [[ "$updated" -eq 0 ]]; then
    skipped "Omarchy branding"
fi

success "Omarchy branding updated!"
