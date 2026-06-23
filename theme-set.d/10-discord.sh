#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2154
# shellcheck source=../lib/theme-env.sh
source "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"

theme_file="$THPM_CURRENT_THEME_DIR/vencord.theme.css"
theme_name_file="$THPM_THEME_NAME_FILE"
generated_file="$THPM_STATE_DIR/discord/vencord-base16.theme.css"
possible_paths=(
    "$HOME/.config/Vencord/themes"
    "$HOME/.config/vesktop/themes"
    "$HOME/.config/Equicord/themes"
    "$HOME/.config/equibop/themes"
    "$HOME/.var/app/com.discordapp.Discord/config/Vencord/themes"
    "$HOME/.var/app/dev.vencord.Vesktop/config/vesktop/themes"
    "$HOME/.var/app/io.github.equicord.equibop/config/equibop/themes"
)

theme_source_file() {
    local theme_name
    local source_dir

    [[ -f "$theme_name_file" ]] || return 1
    IFS= read -r theme_name < "$theme_name_file"
    [[ -n "$theme_name" ]] || return 1

    for source_dir in \
        "$HOME/.config/omarchy/themes/$theme_name" \
        "${OMARCHY_PATH:-$HOME/.local/share/omarchy}/themes/$theme_name"; do
        if [[ -f "$source_dir/vencord.theme.css" ]]; then
            printf '%s\n' "$source_dir/vencord.theme.css"
            return 0
        fi
    done

    return 1
}

create_dynamic_theme() {
    mkdir -p "$(dirname "$generated_file")"

    cat > "$generated_file" << EOF
    /**
    * @name Match System
    * @author @bypass_
    * @version 0.1.0
    * @description Match your current system theme.
    * @source https://github.com/imbypass/base16-Discord
    **/
    @import url("https://imbypass.github.io/base16-discord/omarchy-discord.theme.css");

    :root {
        --color00: #${primary_background};
        --color01: #${primary_background};
        --color02: #${primary_background};
        --color03: #${normal_white};
        --color04: #${bright_white};
        --color05: #${bright_white};
        --color06: #${bright_white};
        --color07: #${bright_white};
        --color08: #${normal_red};
        --color09: #${normal_yellow};
        --color10: #${bright_yellow};
        --color11: #${normal_green};
        --color12: #${normal_cyan};
        --color13: #${normal_blue};
        --color14: #${normal_magenta};
        --color15: #${normal_yellow};
    }
EOF
}

install_theme() {
    local source_file="$1"
    local path file

    for path in "${possible_paths[@]}"; do
        if [[ -d "$path" ]]; then
            cp -f "$source_file" "$path/vencord.theme.css"

            for file in "$path"/*; do
                if [[ -f "$file" ]]; then
                    touch "$file"
                fi
            done
        fi
    done
}

source_file="$(theme_source_file || true)"

if [[ -n "$source_file" ]]; then
    cp -f "$source_file" "$theme_file"
    install_theme "$source_file"
elif [[ -f "$theme_file" ]]; then
    install_theme "$theme_file"
else
    create_dynamic_theme
    install_theme "$generated_file"
fi
success "Discord theme updated!"
exit 0
