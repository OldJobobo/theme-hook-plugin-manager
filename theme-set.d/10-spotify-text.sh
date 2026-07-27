#!/usr/bin/env bash
source "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"

# Applies the spicetify "text" theme (a minimal, spotify-tui style look from
# https://github.com/spicetify/spicetify-themes/tree/master/text) with the
# current Omarchy colors. Alternative to the bundled spotify plugin — enable
# one or the other, not both.

THEME_DIR="$HOME/.config/spicetify/Themes/text"
USER_CSS_URL="https://raw.githubusercontent.com/spicetify/spicetify-themes/master/text/user.css"

if ! command -v spicetify >/dev/null 2>&1; then
    skipped "Spicetify"
fi

ensure_text_theme() {
    mkdir -p "$THEME_DIR"
    if [ ! -f "$THEME_DIR/user.css" ]; then
        curl -fsSL -o "$THEME_DIR/user.css" "$USER_CSS_URL" || skipped "text theme user.css (download failed)"
    fi
}

create_dynamic_scheme() {
    local accent
    accent=$(extract_color "accent")
    [ -n "$accent" ] || accent=$normal_magenta

cat > "$THEME_DIR/color.ini" << EOF
[omarchy]
accent             = ${accent}
accent-active      = ${accent}
accent-inactive    = ${primary_background}
banner             = ${accent}
border-active      = ${accent}
border-inactive    = ${normal_black}
header             = ${bright_black}
highlight          = ${normal_black}
main               = ${primary_background}
notification       = ${normal_blue}
notification-error = ${normal_red}
subtext            = ${normal_white}
text               = ${primary_foreground}
EOF
}

change_spicetify_theme() {
    spicetify config current_theme text > /dev/null
    spicetify config color_scheme omarchy > /dev/null
}

spotify_was_running=false
if pgrep -x "spotify" > /dev/null 2>&1; then
    spotify_was_running=true
fi

ensure_text_theme
create_dynamic_scheme
change_spicetify_theme

if [ "$spotify_was_running" = true ]; then
    spicetify apply > /dev/null 2>&1 &
else
    setsid bash -c '
        spicetify apply > /dev/null 2>&1 &

        for i in {1..250}; do
            if pgrep -x "spotify" > /dev/null 2>&1; then
                sleep 0.2
                killall -9 spotify > /dev/null 2>&1
                exit 0
            fi
            sleep 0.1
        done
    ' > /dev/null 2>&1 < /dev/null &
fi

success "Spotify text theme updated!"
exit 0
