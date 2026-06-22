#!/usr/bin/env bash

set -e

THPM_BRANCH="${THPM_BRANCH:-thpm}"
THPM_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Install prerequisites
if ! pacman -Qi "adw-gtk-theme" &>/dev/null; then
    if command -v gum >/dev/null 2>&1; then
        gum style --border normal --border-foreground 6 --padding "1 2" \
        "\"adw-gtk-theme\" is required to theme GTK applications."

        if gum confirm "Would you like to install \"adw-gtk-theme\"?"; then
            sudo pacman -S adw-gtk-theme
        fi
    else
        echo "\"adw-gtk-theme\" is required to theme GTK applications."
        read -r -p "Would you like to install \"adw-gtk-theme\"? [y/N] " install_adw_gtk
        case "$install_adw_gtk" in
            y|Y|yes|YES) sudo pacman -S adw-gtk-theme ;;
        esac
    fi
fi

# Remove any old temp files
rm -rf /tmp/theme-hook/

bundled_plugins=(
    00-fish.sh
    00-fzf.sh
    10-branding.sh
    10-discord.sh
    11-discord-system24.sh
    10-gtk.sh
    10-qt6ct.sh
    10-spotify.sh
    10-superfile.sh
    10-tmux.sh
    10-vicinae.sh
    10-zellij.sh
    15-typora.sh
    20-nwg-dock-hyprland.sh
    20-zed.sh
    25-swaync.sh
    26-foot-live-colors.sh
    30-cursor.sh
    30-vscode.sh
    30-windsurf.sh
    35-obsidian-terminal.sh
    40-cava.sh
    40-firefox.sh
    40-hermes.sh
    40-qutebrowser.sh
    40-steam.sh
    40-zen.sh
    50-cliamp.sh
    50-heroic.sh
)

default_disabled_plugins=(
    10-branding.sh
    11-discord-system24.sh
    10-zellij.sh
)

hidden_plugins=(
    10-tmux.sh
)

restored_enabled_plugins=(
    50-cliamp.sh
)

is_bundled_plugin() {
    local name="$1"
    local plugin

    for plugin in "${bundled_plugins[@]}"; do
        [[ "$plugin" == "$name" ]] && return 0
    done

    return 1
}

is_restored_enabled_plugin() {
    local name="$1"
    local plugin

    for plugin in "${restored_enabled_plugins[@]}"; do
        [[ "$plugin" == "$name" ]] && return 0
    done

    return 1
}

disabled_plugins=()
enabled_plugins=()
enabled_bundled_count=0
disabled_bundled_count=0
recoverable_bundled_count=$((${#bundled_plugins[@]} - ${#restored_enabled_plugins[@]}))
recover_all_disabled=0
record_disabled_plugin() {
    local plugin="$1"
    local name

    name=$(basename "$plugin")
    name=${name%.sample}
    is_bundled_plugin "$name" || return 0
    is_restored_enabled_plugin "$name" && return 0
    disabled_plugins+=("$name")
    disabled_bundled_count=$((disabled_bundled_count + 1))
}

record_enabled_plugin() {
    local plugin="$1"
    local name

    name=$(basename "$plugin")
    is_bundled_plugin "$name" || return 0
    enabled_plugins+=("$name")
    enabled_bundled_count=$((enabled_bundled_count + 1))
}

plugin_was_enabled() {
    local name="$1"
    local plugin

    for plugin in "${enabled_plugins[@]}"; do
        [[ "$plugin" == "$name" ]] && return 0
    done

    return 1
}

if [[ -d "$HOME/.config/omarchy/hooks/theme-set.d" ]]; then
    for plugin in "$HOME"/.config/omarchy/hooks/theme-set.d/*.sh; do
        [[ -f "$plugin" ]] || continue
        record_enabled_plugin "$plugin"
    done
    for plugin in "$HOME"/.config/omarchy/hooks/theme-set.d/*.sh.sample; do
        [[ -f "$plugin" ]] || continue
        record_disabled_plugin "$plugin"
    done
fi

if [[ "$enabled_bundled_count" -eq 0 && "$disabled_bundled_count" -eq "$recoverable_bundled_count" ]]; then
    echo "All bundled plugins are disabled; treating this as update fallout and restoring defaults."
    disabled_plugins=()
    recover_all_disabled=1
fi

# Clone the Theme Hook Plugin Manager repository
echo -e "Downloading thpm.."
git clone --branch "$THPM_BRANCH" --depth 1 https://github.com/OldJobobo/theme-hook-plugin-manager.git /tmp/theme-hook > /dev/null 2>&1
install_commit=$(git -C /tmp/theme-hook rev-parse HEAD 2>/dev/null || true)

# Remove legacy aliases from previous installs
rm -f "$HOME/.local/share/omarchy/bin/theme-hook-update" > /dev/null 2>&1
rm -f "$HOME/.local/share/omarchy/bin/thctl" > /dev/null 2>&1
rm -f "$HOME/.local/share/omarchy/bin/thpm" > /dev/null 2>&1

# Install the thpm CLI
mkdir -p "$HOME/.local/bin"
mv -f /tmp/theme-hook/thpm "$HOME/.local/bin/thpm"
chmod +x "$HOME/.local/bin/thpm"

# Install shared thpm hook runtime
mkdir -p "$HOME/.local/share/thpm/lib"
mv -f /tmp/theme-hook/lib/theme-env.sh "$HOME/.local/share/thpm/lib/theme-env.sh"
rm -rf "$HOME/.local/share/thpm/skills"
if [[ -d /tmp/theme-hook/skills ]]; then
    mkdir -p "$HOME/.local/share/thpm"
    cp -R /tmp/theme-hook/skills "$HOME/.local/share/thpm/skills"
fi
cat > "$HOME/.local/share/thpm/version" <<EOF
repo=https://github.com/OldJobobo/theme-hook-plugin-manager.git
branch=$THPM_BRANCH
commit=$install_commit
EOF
rm -f "$HOME/.local/share/thpm/update-check"

# Install default user config without overwriting local edits.
mkdir -p "$THPM_CONFIG_HOME/thpm"
if [[ ! -f "$THPM_CONFIG_HOME/thpm/config.toml" ]]; then
    cat > "$THPM_CONFIG_HOME/thpm/config.toml" <<'EOF'
[paths]
hook_dir = "~/.config/omarchy/hooks/theme-set.d"
state_dir = "~/.local/share/thpm"
theme_env = "~/.local/share/thpm/lib/theme-env.sh"
colors_file = "~/.config/omarchy/current/theme/colors.toml"
skills_dir = "~/.local/share/thpm/skills"

[updates]
check = true
check_interval_seconds = 86400

[notifications]
enabled = true
backend = "auto" # auto, notify-send, stdout, off

[notifications.restart]
enabled = true
only_when_running = true
cooldown_seconds = 300
title = "Theme Hook Plugin Manager"
message = "{app} requires a restart to apply theme."

[notifications.restart.apps]
steam = true
nautilus = true
firefox = true
zen-browser = true
qutebrowser = true
code = true
cursor = true
windsurf = true
typora = true
heroic = true
spf = true
Hermes = true
EOF
fi

# Remove the old thpm dispatcher if this install previously owned it. Omarchy
# now runs theme-set.d hooks directly, so no dispatcher is needed.
if [[ -f "$HOME/.config/omarchy/hooks/theme-set" ]] && grep -Eq 'Omarchy 3\.3\+ uses colors\.toml|Compatibility shim for older thpm installs' "$HOME/.config/omarchy/hooks/theme-set"; then
    rm -f "$HOME/.config/omarchy/hooks/theme-set"
fi

# Create Omarchy theme hook directory and copy native hook scripts
mkdir -p "$HOME/.config/omarchy/hooks/theme-set.d/"
mv -f /tmp/theme-hook/theme-set.d/* "$HOME/.config/omarchy/hooks/theme-set.d/"

# Remove any new temp files
rm -rf /tmp/theme-hook

# Update permissions
chmod 644 "$HOME/.local/share/thpm/lib/theme-env.sh"
for plugin in "${bundled_plugins[@]}"; do
    [[ -f "$HOME/.config/omarchy/hooks/theme-set.d/$plugin" ]] && chmod 644 "$HOME/.config/omarchy/hooks/theme-set.d/$plugin"
    [[ -f "$HOME/.config/omarchy/hooks/theme-set.d/$plugin.sample" ]] && chmod 644 "$HOME/.config/omarchy/hooks/theme-set.d/$plugin.sample"
done

if [[ "$recover_all_disabled" -eq 1 ]]; then
    for plugin in "${bundled_plugins[@]}"; do
        rm -f "$HOME/.config/omarchy/hooks/theme-set.d/$plugin.sample"
    done
fi

for plugin in "${restored_enabled_plugins[@]}"; do
    rm -f "$HOME/.config/omarchy/hooks/theme-set.d/$plugin.sample"
done

for plugin in "${hidden_plugins[@]}"; do
    if [[ -f "$HOME/.config/omarchy/hooks/theme-set.d/$plugin" ]]; then
        mv -f "$HOME/.config/omarchy/hooks/theme-set.d/$plugin" "$HOME/.config/omarchy/hooks/theme-set.d/$plugin.sample"
    fi
done

for plugin in "${default_disabled_plugins[@]}"; do
    plugin_was_enabled "$plugin" && continue
    if [[ -f "$HOME/.config/omarchy/hooks/theme-set.d/$plugin" ]]; then
        mv -f "$HOME/.config/omarchy/hooks/theme-set.d/$plugin" "$HOME/.config/omarchy/hooks/theme-set.d/$plugin.sample"
    fi
done

for plugin in "${disabled_plugins[@]}"; do
    if [[ -f "$HOME/.config/omarchy/hooks/theme-set.d/$plugin" ]]; then
        mv -f "$HOME/.config/omarchy/hooks/theme-set.d/$plugin" "$HOME/.config/omarchy/hooks/theme-set.d/$plugin.sample"
    fi
done

# Run the theme-set hook to apply the current theme
echo "Running theme-set hook.."
omarchy-hook theme-set

omarchy-show-done
