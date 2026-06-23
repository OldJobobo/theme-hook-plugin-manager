#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2154
# shellcheck source=../lib/theme-env.sh
source "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"

output_file="$THPM_CURRENT_THEME_DIR/vencord-system24.theme.css"
possible_paths=(
    "$HOME/.config/Vencord/themes"
    "$HOME/.config/vesktop/themes"
    "$HOME/.config/Equicord/themes"
    "$HOME/.config/equibop/themes"
    "$HOME/.var/app/com.discordapp.Discord/config/Vencord/themes"
    "$HOME/.var/app/dev.vencord.Vesktop/config/vesktop/themes"
    "$HOME/.var/app/io.github.equicord.equibop/config/equibop/themes"
)

create_dynamic_theme() {
    local bg_1 bg_2 bg_3 bg_4
    local text_4 text_5 accent_1 accent_2 accent_4 accent_5
    local red_1 red_2 red_3 green_1 green_2 green_3 blue_1 blue_2 blue_3 yellow_1 yellow_2 yellow_3 purple_1 purple_2 purple_3
    local red_4 red_5 green_4 green_5 blue_4 blue_5 yellow_4 yellow_5 purple_4 purple_5
    local online dnd idle streaming offline

    color_luma() {
        local hex_input="$1"
        local r=$((16#${hex_input:0:2}))
        local g=$((16#${hex_input:2:2}))
        local b=$((16#${hex_input:4:2}))

        echo $(((299 * r + 587 * g + 114 * b) / 1000))
    }

    ensure_min_luma() {
        local hex_input="$1"
        local min_luma="$2"
        local luma

        luma="$(color_luma "$hex_input")"
        if (( luma < min_luma )); then
            change_shade "$hex_input" $((min_luma - luma))
        else
            echo "$hex_input"
        fi
    }

    visible_color() {
        local base="$1"
        local fallback="$2"
        local min_luma="$3"

        if (( $(color_luma "$base") < min_luma && $(color_luma "$fallback") > $(color_luma "$base") )); then
            ensure_min_luma "$fallback" "$min_luma"
        else
            ensure_min_luma "$base" "$min_luma"
        fi
    }

    bg_1="$(change_shade "$primary_background" 30)"
    bg_2="$(change_shade "$primary_background" 18)"
    bg_3="$(change_shade "$primary_background" 8)"
    bg_4="$primary_background"
    text_4="$(visible_color "$(change_shade "$bright_black" -20)" "$bright_black" 100)"
    text_5="$(visible_color "$(change_shade "$bright_black" -45)" "$bright_black" 78)"
    accent_1="$(visible_color "$bright_blue" "$normal_blue" 150)"
    accent_2="$(visible_color "$normal_blue" "$bright_blue" 115)"
    accent_4="$(visible_color "$bright_blue" "$normal_blue" 125)"
    accent_5="$(visible_color "$(change_shade "$normal_blue" -25)" "$bright_blue" 92)"
    online="$(visible_color "$normal_green" "$bright_green" 120)"
    dnd="$(visible_color "$normal_red" "$bright_red" 120)"
    idle="$(visible_color "$normal_yellow" "$bright_yellow" 130)"
    streaming="$(visible_color "$normal_magenta" "$bright_magenta" 120)"
    offline="$text_4"
    red_1="$(visible_color "$bright_red" "$normal_red" 140)"
    red_2="$(visible_color "$normal_red" "$bright_red" 120)"
    red_3="$red_2"
    red_4="$(visible_color "$(change_shade "$normal_red" -18)" "$bright_red" 100)"
    red_5="$(visible_color "$(change_shade "$normal_red" -34)" "$bright_red" 86)"
    green_1="$(visible_color "$bright_green" "$normal_green" 140)"
    green_2="$(visible_color "$normal_green" "$bright_green" 120)"
    green_3="$green_2"
    green_4="$(visible_color "$(change_shade "$normal_green" -18)" "$bright_green" 100)"
    green_5="$(visible_color "$(change_shade "$normal_green" -34)" "$bright_green" 86)"
    blue_1="$(visible_color "$bright_blue" "$normal_blue" 140)"
    blue_2="$(visible_color "$normal_blue" "$bright_blue" 115)"
    blue_3="$blue_2"
    blue_4="$(visible_color "$(change_shade "$normal_blue" -18)" "$bright_blue" 100)"
    blue_5="$(visible_color "$(change_shade "$normal_blue" -34)" "$bright_blue" 86)"
    yellow_1="$(visible_color "$bright_yellow" "$normal_yellow" 150)"
    yellow_2="$(visible_color "$normal_yellow" "$bright_yellow" 130)"
    yellow_3="$yellow_2"
    yellow_4="$(visible_color "$(change_shade "$normal_yellow" -18)" "$bright_yellow" 108)"
    yellow_5="$(visible_color "$(change_shade "$normal_yellow" -34)" "$bright_yellow" 92)"
    purple_1="$(visible_color "$bright_magenta" "$normal_magenta" 140)"
    purple_2="$(visible_color "$normal_magenta" "$bright_magenta" 120)"
    purple_3="$purple_2"
    purple_4="$(visible_color "$(change_shade "$normal_magenta" -18)" "$bright_magenta" 100)"
    purple_5="$(visible_color "$(change_shade "$normal_magenta" -34)" "$bright_magenta" 86)"

    cat > "$output_file" << EOF
/**
 * @name Omarchy System24
 * @description System24 Discord theme using the current Omarchy colors.toml palette.
 * @author OldJobobo, refact0r
 * @version 0.1.0
 * @website https://github.com/refact0r/system24
 * @source https://github.com/refact0r/system24
 */

@import url("https://refact0r.github.io/system24/build/system24.css");

body {
    --font: 'DM Mono';
    --code-font: 'DM Mono';
    font-weight: 300;
    letter-spacing: 0;

    --gap: 12px;
    --divider-thickness: 4px;
    --border-thickness: 2px;
    --border-hover-transition: 0.2s ease;

    --animations: on;
    --list-item-transition: 0.2s ease;
    --dms-icon-svg-transition: 0.4s ease;

    --top-bar-height: var(--gap);
    --top-bar-button-position: titlebar;
    --top-bar-title-position: off;
    --subtle-top-bar-title: off;

    --custom-window-controls: off;
    --window-control-size: 14px;

    --custom-dms-icon: hide;
    --dms-icon-svg-url: url('');
    --dms-icon-svg-size: 90%;
    --dms-icon-color-before: var(--icon-subtle);
    --dms-icon-color-after: var(--white);
    --custom-dms-background: color;
    --dms-background-image-url: url('');
    --dms-background-image-size: cover;
    --dms-background-color: linear-gradient(70deg, var(--blue-2), var(--purple-2), var(--red-2));

    --background-image: off;
    --background-image-url: url('');

    --transparency-tweaks: off;
    --remove-bg-layer: off;
    --panel-blur: off;
    --blur-amount: 12px;
    --bg-floating: var(--bg-3);

    --small-user-panel: on;
    --unrounding: on;
    --custom-spotify-bar: on;
    --ascii-titles: on;
    --ascii-loader: system24;

    --panel-labels: on;
    --label-color: var(--text-muted);
    --label-font-weight: 500;
}

:root {
    --colors: on;

    --text-0: #${primary_background};
    --text-1: #${bright_white};
    --text-2: #${primary_foreground};
    --text-3: #${normal_white};
    --text-4: #${text_4};
    --text-5: #${text_5};

    --bg-1: #${bg_1};
    --bg-2: #${bg_2};
    --bg-3: #${bg_3};
    --bg-4: #${bg_4};
    --hover: rgba(${rgb_bright_black}, 0.12);
    --active: rgba(${rgb_bright_black}, 0.22);
    --active-2: rgba(${rgb_bright_black}, 0.32);
    --message-hover: rgba(${rgb_normal_black}, 0.18);

    --accent-1: #${accent_1};
    --accent-2: #${accent_2};
    --accent-3: #${accent_2};
    --accent-4: #${accent_4};
    --accent-5: #${accent_5};
    --accent-new: var(--red-2);
    --mention: linear-gradient(to right, color-mix(in hsl, var(--accent-2), transparent 90%) 40%, transparent);
    --mention-hover: linear-gradient(to right, color-mix(in hsl, var(--accent-2), transparent 95%) 40%, transparent);
    --reply: linear-gradient(to right, color-mix(in hsl, var(--text-3), transparent 90%) 40%, transparent);
    --reply-hover: linear-gradient(to right, color-mix(in hsl, var(--text-3), transparent 95%) 40%, transparent);

    --online: #${online};
    --dnd: #${dnd};
    --idle: #${idle};
    --streaming: #${streaming};
    --offline: #${offline};

    --text-normal: var(--text-2);
    --text-muted: var(--text-5);
    --header-primary: var(--text-1);
    --header-secondary: var(--text-3);
    --interactive-normal: var(--text-4);
    --interactive-hover: var(--text-2);
    --interactive-active: var(--text-1);
    --interactive-muted: var(--text-5);
    --channels-default: var(--text-5);
    --channel-icon: var(--text-5);
    --background-primary: var(--bg-4);
    --background-secondary: var(--bg-3);
    --background-secondary-alt: var(--bg-2);
    --background-tertiary: var(--bg-1);

    --border-light: var(--hover);
    --border: var(--active);
    --border-hover: var(--accent-2);
    --button-border: rgba(${rgb_bright_white}, 0.1);

    --red-1: #${red_1};
    --red-2: #${red_2};
    --red-3: #${red_3};
    --red-4: #${red_4};
    --red-5: #${red_5};

    --green-1: #${green_1};
    --green-2: #${green_2};
    --green-3: #${green_3};
    --green-4: #${green_4};
    --green-5: #${green_5};

    --blue-1: #${blue_1};
    --blue-2: #${blue_2};
    --blue-3: #${blue_3};
    --blue-4: #${blue_4};
    --blue-5: #${blue_5};

    --yellow-1: #${yellow_1};
    --yellow-2: #${yellow_2};
    --yellow-3: #${yellow_3};
    --yellow-4: #${yellow_4};
    --yellow-5: #${yellow_5};

    --purple-1: #${purple_1};
    --purple-2: #${purple_2};
    --purple-3: #${purple_3};
    --purple-4: #${purple_4};
    --purple-5: #${purple_5};
}

:is([class*="containerDefault_"], [class*="containerDragAfter_"], [class*="containerDragBefore_"])
    [class*="wrapper_"]:not([class*="modeUnread"]):not([class*="modeSelected"]):not([class*="modeConnected"]):not(:hover)
    :is([class*="name_"], [class*="icon_"]) {
    color: var(--text-5) !important;
}
EOF
}

install_theme() {
    local path file

    for path in "${possible_paths[@]}"; do
        if [[ -d "$path" ]]; then
            cp -f "$output_file" "$path/vencord.theme.css"

            for file in "$path"/*; do
                if [[ -f "$file" ]]; then
                    touch "$file"
                fi
            done
        fi
    done
}

create_dynamic_theme
install_theme
success "Discord System24 theme updated!"
exit 0
