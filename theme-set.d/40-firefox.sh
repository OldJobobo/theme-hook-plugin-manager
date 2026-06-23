#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2154
# shellcheck source=../lib/theme-env.sh

find_default_profile() {
    [[ -f "$HOME/.mozilla/firefox/profiles.ini" ]] || return 1
    awk -F= '
        /^\[Install/ { in_install=1 }
        in_install && /^Default=/ { print $2; exit }
    ' "$HOME/.mozilla/firefox/profiles.ini"
}

default_profile="$HOME/.mozilla/firefox/$(find_default_profile)"
chrome_dir="$default_profile/chrome"
user_chrome_file="$chrome_dir/userChrome.css"
user_content_file="$chrome_dir/userContent.css"
managed_colors_file="$chrome_dir/thpm-firefox-colors.css"
managed_chrome_file="$chrome_dir/thpm-firefox-userChrome.css"
managed_content_file="$chrome_dir/thpm-firefox-userContent.css"
legacy_colors_file="$chrome_dir/colors.css"
import_start="/* THPM Firefox hook start */"
import_end="/* THPM Firefox hook end */"

is_default_profile_valid() {
    [[ -n "${default_profile##"$HOME/.mozilla/firefox/"}" && -d "$default_profile" ]]
}

backup_once() {
    local file="$1"
    local backup_file="${file}.thpm-migrated.bak"

    [[ -f "$backup_file" ]] || cp "$file" "$backup_file"
}

remove_managed_import_block() {
    local file="$1"
    local tmp_file

    [[ -f "$file" ]] || return 0
    tmp_file="${file}.thpm-tmp"
    awk -v start="$import_start" -v end="$import_end" '
        $0 == start { skip=1; next }
        $0 == end { skip=0; next }
        !skip { print }
    ' "$file" > "$tmp_file"
    mv "$tmp_file" "$file"
}

write_import_block() {
    local file="$1"
    shift
    local target

    {
        printf '%s\n' "$import_start"
        for target in "$@"; do
            printf '@import url("./%s");\n' "$target"
        done
        printf '%s\n' "$import_end"
    } > "$file"
}

has_managed_imports() {
    local file="$1"
    shift
    local target

    [[ -f "$file" ]] || return 1
    grep -Fq "$import_start" "$file" || return 1
    grep -Fq "$import_end" "$file" || return 1
    for target in "$@"; do
        grep -Fq "$target" "$file" || return 1
    done
}

ensure_managed_import_block() {
    local file="$1"
    shift
    local tmp_file

    mkdir -p "$(dirname "$file")"
    if has_managed_imports "$file" "$@"; then
        return 0
    fi

    if [[ -f "$file" ]]; then
        tmp_file="${file}.thpm-new"
        write_import_block "$tmp_file" "$@"
        printf '\n' >> "$tmp_file"
        remove_managed_import_block "$file"
        cat "$file" >> "$tmp_file"
        mv "$tmp_file" "$file"
    else
        write_import_block "$file" "$@"
    fi
}

looks_like_legacy_user_chrome() {
    local file="$1"

    [[ -f "$file" ]] || return 1
    grep -Fq '@import url("./colors.css");' "$file" || return 1
    grep -Fq -- "--panel-separator-zap-gradient" "$file" || return 1
    grep -Fq -- "--arrowpanel-background" "$file" || return 1
    grep -Fq -- "--urlbar-box-bgcolor" "$file" || return 1
}

looks_like_legacy_user_content() {
    local file="$1"

    [[ -f "$file" ]] || return 1
    grep -Fq '@import url("./colors.css");' "$file" || return 1
    grep -Fq -- "--newtab-background-color" "$file" || return 1
    grep -Fq -- "--toolbar-field-focus-background-color" "$file" || return 1
    grep -Fq ".search-inner-wrapper" "$file" || return 1
}

migrate_legacy_file_to_import() {
    local file="$1"
    local kind="$2"
    shift 2

    if [[ "$kind" == "chrome" ]] && looks_like_legacy_user_chrome "$file"; then
        backup_once "$file"
        write_import_block "$file" "$@"
    elif [[ "$kind" == "content" ]] && looks_like_legacy_user_content "$file"; then
        backup_once "$file"
        write_import_block "$file" "$@"
    fi
}

remove_empty_file() {
    local file="$1"

    [[ -f "$file" ]] || return 0
    if ! grep -q '[^[:space:]]' "$file"; then
        rm -f "$file"
    fi
}

cleanup_firefox_theme() {
    is_default_profile_valid || return 0
    remove_managed_import_block "$user_chrome_file"
    remove_managed_import_block "$user_content_file"
    remove_empty_file "$user_chrome_file"
    remove_empty_file "$user_content_file"
    rm -f "$managed_colors_file" "$managed_chrome_file" "$managed_content_file"
}

if [[ "${1:-}" == "--cleanup" ]]; then
    cleanup_firefox_theme
    exit 0
fi

source "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"

output_file="$THPM_CURRENT_THEME_DIR/firefox.css"

if ! command -v firefox >/dev/null 2>&1; then
    skipped "Firefox"
fi

is_default_profile_valid || skipped "Firefox profile"

enable_userchrome() {
    local prefs_file="$default_profile/prefs.js"
    local pref_name="toolkit.legacyUserProfileCustomizations.stylesheets"

    if [[ -f "$prefs_file" ]] && grep -q "user_pref(\"$pref_name\"" "$prefs_file"; then
        if grep -q "user_pref(\"$pref_name\", false)" "$prefs_file"; then
            sed -i.bak "s/user_pref(\"$pref_name\", false);/user_pref(\"$pref_name\", true);/" "$prefs_file"
        fi
    else
        echo "user_pref(\"$pref_name\", true);" >> "$prefs_file"
    fi
}
enable_userchrome

mkdir -p "$chrome_dir"

cat > "$output_file" << EOF
:root {
--color00: #${primary_background};
--color01: #${primary_background};
--color02: #${primary_background};
--color03: #${normal_white};
--color04: #${bright_white};
--color05: #${primary_foreground};
--color06: #${bright_white};
--color07: #${bright_white};
--color08: #${normal_red};
--color09: #${normal_yellow};
--color0A: #${bright_yellow};
--color0B: #${normal_green};
--color0C: #${normal_cyan};
--color0D: #${normal_blue};
--color0E: #${normal_magenta};
--color0F: #${bright_red};
}
EOF
cp "$output_file" "$legacy_colors_file"
cp "$output_file" "$managed_colors_file"

cat > "$managed_chrome_file" << 'EOF'
:root {
    --base00: var(--color00);
    --base01: color-mix(in srgb, var(--color00) 98%, white);
    --base02: color-mix(in srgb, var(--color00) 94%, white);
    --base03: var(--color03);
    --base04: var(--color04);
    --base05: var(--color05);
    --base06: var(--color06);
    --base07: var(--color07);
    --base08: var(--color08);
    --base09: var(--color09);
    --base0A: var(--color0A);
    --base0B: var(--color0B);
    --base0C: var(--color0C);
    --base0D: var(--color0D);
    --base0E: var(--color0E);
    --base0F: var(--color0F);
}

:root {
    --panel-background: var(--base01) !important;
    --panel-color: var(--base05) !important;
    --panel-border-color: var(--base00) !important;
    --panel-list-background-color: var(--base01) !important;
    --panel-list-color: var(--base05) !important;
    --arrowpanel-background: var(--base01) !important;
    --arrowpanel-border-color: var(--base00) !important;
    --panel-separator-zap-gradient: linear-gradient(
        90deg,
        var(--base0E) 0%,
        var(--base0F) 52.08%,
        var(--base0A) 100%
    ) !important;
    --toolbarbutton-border-radius: 6px !important;
    --toolbarbutton-icon-fill: var(--base04) !important;
    --urlbarview-separator-color: var(--base01) !important;
    --urlbarView-separator-color: var(--base01) !important;
    --urlbar-box-background-color: var(--base01) !important;
    --urlbar-box-background-color-focus: var(--base02) !important;
    --urlbar-box-background-color-hover: var(--base02) !important;
    --urlbar-box-background-color-active: var(--base00) !important;
    --urlbar-box-bgcolor: var(--base01) !important;
    --toolbar-field-background-color: var(--base01) !important;
    --toolbar-field-color: var(--base05) !important;
    --toolbar-field-border-color: var(--base00) !important;
    --toolbar-field-focus-background-color: var(--base02) !important;
    --toolbar-field-focus-color: var(--base05) !important;
    --toolbar-field-focus-border-color: var(--base00) !important;
    --color-accent-primary-active: var(--base0D) !important;
    --color-accent-primary-hover: var(--base0D) !important;
    --color-accent-primary: var(--base0D) !important;
    --focus-outline-color: var(--base00) !important;
    --icon-color-critical: var(--base08) !important;
    --icon-color-information: var(--base0D) !important;
    --icon-color-success: var(--base0B) !important;
    --icon-color-warning: var(--base0A) !important;
    --outline-color-error: var(--base08) !important;
    --tab-block-margin: 0 !important;
    --tab-border-radius: 0 !important;
    --text-color-error: var(--base08) !important;
    --toolbarbutton-border-radius: 6px !important;
    --in-content-page-background: var(--base01) !important;
    --input-text-background-color: var(--base02) !important;
}

#PopupSearchAutoComplete,
#PopupAutoComplete,
.searchmode-switcher-panel {
    --panel-background: var(--base01) !important;
    --panel-color: var(--base05) !important;
    --panel-border-color: var(--base00) !important;
    --panel-list-background-color: var(--base01) !important;
    --panel-list-color: var(--base05) !important;
    --urlbarview-separator-color: var(--base01) !important;
}

#PopupSearchAutoComplete::part(content),
#PopupAutoComplete::part(content) {
    background: var(--panel-background) !important;
    color: var(--panel-color) !important;
    border-color: var(--panel-border-color) !important;
}

.search-panel-tree {
    background: var(--panel-background) !important;
    color: var(--panel-color) !important;
}

.searchbar-engine-one-off-item:not([selected]):hover,
.search-panel-tree > .autocomplete-richlistitem:hover {
    background-color: var(--urlbar-box-background-color-hover) !important;
}

.searchbar-engine-one-off-item[selected],
.search-panel-tree > .autocomplete-richlistitem[selected] {
    background-color: var(--urlbar-box-background-color-focus) !important;
    color: var(--base05) !important;
}

.searchmode-switcher-panel-list {
    --panel-list-background-color: var(--base01) !important;
    --panel-list-color: var(--base05) !important;
}

/* Tabs colors  */
#tabbrowser-tabs:not([movingtab])
    > #tabbrowser-arrowscrollbox
    > .tabbrowser-tab
    > .tab-stack
    > .tab-background[multiselected="true"],
#tabbrowser-tabs:not([movingtab])
    > #tabbrowser-arrowscrollbox
    > .tabbrowser-tab
    > .tab-stack
    > .tab-background[selected="true"] {
    background-image: none !important;
    background-color: var(--toolbar-bgcolor) !important;
}

/* Inactive tabs color */
#navigator-toolbox {
    background-color: var(--base00) !important;
    border: none !important;
}

/* Window colors  */
:root {
    --toolbar-bgcolor: var(--base01) !important;
    --tabs-border-color: var(--base01) !important;
    --lwt-sidebar-background-color: var(--base00) !important;
    --lwt-toolbar-field-focus: var(--base01) !important;
}

/* Sidebar color  */
#sidebar-box,
.sidebar-placesTree {
    background-color: var(--base00) !important;
}

.tab-background {
    border-radius: 6px !important;
    border: 0px solid rgba(0, 0, 0, 0) !important;
}
.tab-background[selected] {
    background-color: var(--base02) !important;
}

#tabbrowser-tabs {
    margin-left: 1px;
    margin-top: 3px;
    margin-bottom: 3px;
}

.tabbrowser-tab[last-visible-tab="true"] {
    border: 0px solid rgba(0, 0, 0, 0) !important;
}

toolbarbutton {
    border-radius: 6px !important;
}

/* Url Bar  */
#urlbar-input {
    accent-color: var(--base0D) !important;
}
#urlbar-input-container {
    background-color: var(--base01) !important;
    border: 0px solid rgba(0, 0, 0, 0) !important;
}

#urlbar[focused="true"] > #urlbar-background {
    box-shadow: none !important;
}

#urlbar-background {
    border-radius: 6px !important;
}

.urlbarView-url {
    color: var(--base05) !important;
}

#star-button {
    --toolbarbutton-icon-fill-attention: var(--base0D) !important;
}

#vertical-tabs.customization-target {
    background-color: var(--base00) !important;
}
splitter#sidebar-tools-and-extensions-splitter {
    display: none !important;
}
.tools-and-extensions[aria-orientation="vertical"] {
    background-color: var(--base00) !important;
}
.tools-and-extensions.actions-list {
    background-color: var(--base00) !important;
}
#identity-box,
#trust-icon-container,
#tracking-protection-icon-container {
    fill: var(--base04) !important;
}

.logo-and-wordmark {
    display: none !important;
}
.search-inner-wrapper {
    margin-top: 10% !important;
}

.urlbar-input::placeholder,
.searchbar-textbox::placeholder {
    opacity: 1;
    color: var(--base03) !important;
}

.urlbar-input {
    color: var(--base05) !important;
}
EOF

cat > "$managed_content_file" << 'EOF'
:root {
    --base00: var(--color00);
    --base01: color-mix(in srgb, var(--color00) 98%, white);
    --base02: color-mix(in srgb, var(--color00) 94%, white);
    --base03: var(--color03);
    --base04: var(--color04);
    --base05: var(--color05);
    --base06: var(--color06);
    --base07: var(--color07);
    --base08: var(--color08);
    --base09: var(--color09);
    --base0A: var(--color0A);
    --base0B: var(--color0B);
    --base0C: var(--color0C);
    --base0D: var(--color0D);
    --base0E: var(--color0E);
    --base0F: var(--color0F);
}

:root {
    --color-accent-primary-active: var(--base0D) !important;
    --color-accent-primary-hover: var(--base0D) !important;
    --color-accent-primary: var(--base0D) !important;
    --focus-outline-color: var(--base00) !important;
    --icon-color-critical: var(--base08) !important;
    --icon-color-information: var(--base0D) !important;
    --icon-color-success: var(--base0B) !important;
    --icon-color-warning: var(--base0A) !important;
    --in-content-page-background: var(--base00) !important;
    --input-text-background-color: var(--base02) !important;
    --newtab-background-color-secondary: var(--base02) !important;
    --newtab-background-color: var(--base01) !important;
    --newtab-text-primary-color: var(--base05) !important;
    --newtab-text-secondary-text: var(--base04) !important;
    --newtab-wallpaper-color: var(--base01) !important;
    --outline-color-error: var(--base08) !important;
    --tab-block-margin: 0 !important;
    --tab-border-radius: 0 !important;
    --text-color-error: var(--base08) !important;
    --toolbar-field-border-color: var(--base01) !important;
    --toolbar-field-focus-background-color: var(--base02) !important;
    --toolbar-field-focus-border-color: var(--base01) !important;
    --toolbarbutton-border-radius: 6px !important;
}

body {
    border: none;
}

.logo-and-wordmark {
    display: none !important;
}
.search-inner-wrapper {
    margin-top: 10% !important;
}
EOF

migrate_legacy_file_to_import "$user_chrome_file" chrome "thpm-firefox-colors.css" "thpm-firefox-userChrome.css"
migrate_legacy_file_to_import "$user_content_file" content "thpm-firefox-colors.css" "thpm-firefox-userContent.css"
ensure_managed_import_block "$user_chrome_file" "thpm-firefox-colors.css" "thpm-firefox-userChrome.css"
ensure_managed_import_block "$user_content_file" "thpm-firefox-colors.css" "thpm-firefox-userContent.css"

require_restart "firefox"
success "Firefox theme updated!"
exit 0
