#!/usr/bin/env bash
# Themes cliamp on an Omarchy theme switch.
#
# cliamp's loaded-theme format has only 6 colours and hard-couples Title / Accent / SeekBar AND the
# key-hint pill background onto the single `accent` field (ui/styles.go). Mechanically reducing a
# 16-colour palette into those 6 fields looks worse than cliamp's OWN ANSI default, which maps each
# role to a distinct ANSI index — title=10, accent=11, key-bg=8 (neutral), key-fg=15 — rendered in
# the terminal's themed palette. cliamp ignores any extra keys (title/seek/key_bg have no effect),
# so a richer omarchy.toml is impossible without an upstream schema change.
#
# Therefore this hook does NOT derive a palette. It either:
#   1. installs a theme's own cliamp.toml ONLY when it opts in via the exact NATIVE_OPT_IN marker
#      (a cliamp.toml is often auto-generated, so its mere existence is not an author opt-in), or
#   2. removes our generated file and sets `theme = ""`, which cliamp treats as its ANSI default
#      (ui/model SetTheme: name=="" -> applyThemeAll(theme.Default()) — verified first-class path).

config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
theme_dir="$config_root/cliamp/themes"
config_file="$config_root/cliamp/config.toml"
target="$theme_dir/omarchy.toml"
MARKER="# thpm:cliamp-omarchy"
# Opt-in marker an author must add to a theme's cliamp.toml. A cliamp.toml is often an
# auto-generated artifact (e.g. by a palette generator committed to the theme repo), so its mere
# existence is NOT a deliberate choice to use it. Only an EXACT matching line activates native;
# without it the hook uses cliamp's (richer) ANSI default.
NATIVE_OPT_IN="# thpm:cliamp-use-native"

success() { echo -e "\e[32m[SUCCESS]\e[0m $1"; }
warning() { echo -e "\033[0;33m[WARNING]\e[0m $1"; }
error()   { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }
skipped() { echo -e "\033[0;34m[SKIPPED]\e[0m $1 not found. Skipping.."; exit 0; }

command -v cliamp >/dev/null 2>&1 || skipped "cliamp"

# ---- resolve the active theme directory (same chain thpm uses for colors_file) ----
_expand() { case "$1" in "~") printf '%s\n' "$HOME";; \~/*) printf '%s/%s\n' "$HOME" "${1#\~/}";; *) printf '%s\n' "$1";; esac; }
THPM_CONFIG_FILE="${THPM_CONFIG_FILE:-$config_root/thpm/config.toml}"
_cfg() {
    [ -f "$THPM_CONFIG_FILE" ] || return 0
    awk -v s="$1" -v k="$2" -v SQ="'" '
        function strip(x,  i,c,q,o){ q=""; o=""; for(i=1;i<=length(x);i++){ c=substr(x,i,1); if(q==""){ if(c=="\""||c==SQ){q=c;o=o c;continue} if(c=="#")break; o=o c } else { o=o c; if(c==q)q="" } } return o }
        function trim(x){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",x); return x }
        function unq(x,  f,l){ if(length(x)>=2){f=substr(x,1,1);l=substr(x,length(x),1); if((f=="\""&&l=="\"")||(f==SQ&&l==SQ))return substr(x,2,length(x)-2)} return x }
        /^[[:space:]]*\[/ { sec=$0; gsub(/[][[:space:]]/,"",sec); next }
        { lhs=$0; sub(/=.*/,"",lhs); gsub(/[[:space:]]/,"",lhs)
          if (sec==s && lhs==k) { r=$0; sub(/^[^=]*=/,"",r); print unq(trim(strip(r))); exit } }' "$THPM_CONFIG_FILE"
}
if [ -n "${THPM_COLORS_FILE:-}" ]; then colors_file="$THPM_COLORS_FILE"
else
    cf="$(_cfg paths colors_file)"
    quattro_colors_file="$HOME/.local/state/omarchy/current/theme/colors.toml"
    legacy_colors_file="$config_root/omarchy/current/theme/colors.toml"
    if [ -n "$cf" ]; then
        configured_colors_file="$(_expand "$cf")"
        if [ "$configured_colors_file" != "$legacy_colors_file" ] && [ "$configured_colors_file" != "$quattro_colors_file" ]; then
            colors_file="$configured_colors_file"
        elif [ -f "$quattro_colors_file" ]; then
            colors_file="$quattro_colors_file"
        elif [ -f "$configured_colors_file" ]; then
            colors_file="$configured_colors_file"
        elif [ -f "$legacy_colors_file" ]; then
            colors_file="$legacy_colors_file"
        else
            colors_file="$quattro_colors_file"
        fi
    elif [ -f "$quattro_colors_file" ]; then
        colors_file="$quattro_colors_file"
    elif [ -f "$legacy_colors_file" ]; then
        colors_file="$legacy_colors_file"
    else
        colors_file="$quattro_colors_file"
    fi
fi
theme_src="$(dirname "$colors_file")"

mkdir -p "$theme_dir"

# ---- atomic top-level `theme = "$1"` in config.toml (before first [table]; preserves other keys) ----
_set_theme() {
    local val="$1" ctmp
    if [ ! -f "$config_file" ]; then printf 'theme = "%s"\n' "$val" > "$config_file" || error "failed creating $config_file"; return; fi
    ctmp="$(dirname "$config_file")/.config.$$"
    awk -v val="$val" '
        BEGIN { done=0; seen=0 }
        /^[[:space:]]*\[/ { if (!done && !seen) { printf "theme = \"%s\"\n", val; done=1 } seen=1; print; next }
        (!seen && $0 ~ /^[[:space:]]*theme[[:space:]]*=/) { if (!done) { printf "theme = \"%s\"\n", val; done=1 } next }
        { print } END { if (!done) printf "theme = \"%s\"\n", val }' "$config_file" > "$ctmp" \
        || { rm -f "$ctmp"; error "failed updating $config_file"; }
    mv -f "$ctmp" "$config_file" || { rm -f "$ctmp"; error "failed updating $config_file"; }
}
_remove_marker_file() { [ -f "$target" ] && head -n1 "$target" | tr -d '\r' | grep -qxF "$MARKER" && rm -f "$target"; }

# comment/quote-safe TOML value extractor: $1=file $2=key -> normalised #RRGGBB (3-digit expanded)
# or empty. Older cliamp builds may reject inline comments, so we canonicalise before install.
_toml_hex() {
    awk -v k="$2" -v SQ="'" '
        function strip_comment(s,  i,c,q,o){ q=""; o=""; for(i=1;i<=length(s);i++){ c=substr(s,i,1); if(q==""){ if(c=="\""||c==SQ){q=c;o=o c;continue} if(c=="#")break; o=o c } else { o=o c; if(c==q)q="" } } return o }
        function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); return s }
        function unq(s,  f,l){ if(length(s)>=2){f=substr(s,1,1);l=substr(s,length(s),1); if((f=="\""&&l=="\"")||(f==SQ&&l==SQ))return substr(s,2,length(s)-2)} return s }
        { l=$0; sub(/=.*/,"",l); gsub(/[[:space:]]/,"",l)
          if (l==k) { r=$0; sub(/^[^=]*=/,"",r); v=unq(trim(strip_comment(r)))
            if (v ~ /^#[0-9A-Fa-f]{6}$/) { print toupper(v); exit }
            if (v ~ /^#[0-9A-Fa-f]{3}$/) { v=toupper(v); printf "#%s%s%s%s%s%s\n", substr(v,2,1),substr(v,2,1),substr(v,3,1),substr(v,3,1),substr(v,4,1),substr(v,4,1); exit }
            exit } }' "$1"
}

# ===== 1. theme ships a cliamp.toml AND opts in via the exact NATIVE_OPT_IN line -> CANONICALISE
#          its 6 colours (drop inline comments, which older cliamp builds may fold into the value
#          and reject; normalise hex) and install. No opt-in marker -> ANSI default. =====
native="$theme_src/cliamp.toml"
if [ -f "$native" ] && tr -d '\r' < "$native" | grep -qxF "$NATIVE_OPT_IN"; then
    declare -A NV; usable=1
    for k in accent bright_fg fg green yellow red; do
        v=$(_toml_hex "$native" "$k")
        if [ -n "$v" ]; then
            NV[$k]="$v"
        else
            usable=0
            break
        fi
    done
    if [ "$usable" = 1 ]; then
        tmp="$theme_dir/.omarchy.toml.$$"
        {
            echo "$MARKER"
            echo "# Installed by thpm from the theme's own cliamp.toml (canonicalised) — do not edit."
            echo
            printf 'accent    = "%s"\n' "${NV[accent]}"
            printf 'bright_fg = "%s"\n' "${NV[bright_fg]}"
            printf 'fg        = "%s"\n' "${NV[fg]}"
            printf 'green     = "%s"\n' "${NV[green]}"
            printf 'yellow    = "%s"\n' "${NV[yellow]}"
            printf 'red       = "%s"\n' "${NV[red]}"
        } > "$tmp" || { rm -f "$tmp"; error "failed installing cliamp.toml"; }
        mv -f "$tmp" "$target" || { rm -f "$tmp"; error "failed installing cliamp.toml"; }
        _set_theme omarchy
        success "cliamp themed from the theme's own cliamp.toml."
        exit 0
    fi
    warning "theme's cliamp.toml is incomplete/invalid — using cliamp's ANSI default instead."
fi

# ===== 2. no usable native theme -> theme="" so cliamp uses its (richer) ANSI default =====
# theme="" alone activates ANSI regardless of any file; we also drop our marker-owned file to stay tidy.
_remove_marker_file
_set_theme ""
success "cliamp set to its ANSI default (no palette reduction — richer per-role mapping)."
exit 0
