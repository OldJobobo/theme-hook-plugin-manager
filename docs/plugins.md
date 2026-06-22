# Plugin Guide

This guide is for writing local `thpm` plugins.

User setup and normal commands live in the main [README](../README.md).

## Plugin Location

Installed plugins live in:

```text
~/.config/omarchy/hooks/theme-set.d/
```

Bundled plugin source lives in this repository under:

```text
theme-set.d/
```

Plugin filenames should use a numeric prefix so their order is predictable:

```text
50-myapp.sh
```

Lower numbers run earlier. Higher numbers run later.

## Enable and Disable

Plugins use Omarchy's native hook convention. A plugin is enabled when it ends in `.sh`; it is disabled when it ends in `.sh.sample`.

Use `thpm` for normal toggling:

```bash
thpm enable myapp
thpm disable myapp
```

## Available Theme Values

Plugins run directly as Omarchy `theme-set.d` hooks. Source the shared `thpm` theme environment before using theme colors or helpers:

```bash
source "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"
```

Hex values do not include `#`.

Common values:

- `primary_background`
- `primary_foreground`
- `cursor_color`
- `selection_background`
- `selection_foreground`
- `normal_black` through `normal_white`
- `bright_black` through `bright_white`

RGB companion values are also available with an `rgb_` prefix, such as:

```bash
rgb_normal_blue
rgb_primary_background
```

RGB values are formatted as:

```text
r, g, b
```

## Helper Functions

Plugins can use these helper functions:

| Helper | Use |
| --- | --- |
| `success "message"` | Print a success message |
| `warning "message"` | Print a warning |
| `error "message"` | Print an error and stop |
| `skipped "AppName"` | Skip cleanly when an app or required file is missing |
| `hex2rgb <hex>` | Convert hex to `r, g, b` |
| `rgb2hex <r> <g> <b>` | Convert RGB values to hex |
| `change_shade <hex> <amount>` | Lighten or darken a color |
| `require_restart <process-name>` | Show a restart notification if that process is running |

Use `skipped` for missing apps or optional files. Use `error` only when the plugin actually failed.

`require_restart` is controlled by `${XDG_CONFIG_HOME:-$HOME/.config}/thpm/config.toml`. Users can turn restart notices off globally with:

```toml
[notifications.restart]
enabled = false
```

Or disable one app by process name:

```toml
[notifications.restart.apps]
steam = false
nautilus = false
```

## Example Plugin

```bash
#!/bin/bash
source "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"

if ! command -v myapp >/dev/null 2>&1; then
    skipped "myapp"
fi

config="$HOME/.config/myapp/theme.conf"
mkdir -p "$(dirname "$config")"

cat > "$config" <<EOF
background = #$primary_background
foreground = #$primary_foreground
accent = #$normal_blue
EOF

require_restart "myapp"
success "myapp theme updated!"
```

Save it as:

```text
~/.config/omarchy/hooks/theme-set.d/50-myapp.sh
```

It is enabled immediately because it ends in `.sh`. To install it disabled, save it as:

```text
~/.config/omarchy/hooks/theme-set.d/50-myapp.sh.sample
```

Then manage it by name:

```bash
thpm list
thpm enable myapp
thpm disable myapp
thpm doctor myapp
thpm run
```

## Color Source

`thpm` reads colors from:

```text
~/.config/omarchy/current/theme/colors.toml
```

This matches Omarchy 3.3+ themes.

## Theme Branding Files

The bundled branding plugin is installed disabled by default. After `thpm enable branding`, it uses these active-theme files when they exist:

```text
~/.config/omarchy/current/theme/about.txt
~/.config/omarchy/current/theme/screensaver.txt
```

`about.txt` is copied to `~/.config/omarchy/branding/about.txt` for Fastfetch/About. `screensaver.txt` is copied to `~/.config/omarchy/branding/screensaver.txt` for the Omarchy screensaver. Missing branding files are non-destructive and leave the current user branding in place.

Disabling the branding plugin only stops future syncs. Uninstalling `thpm` restores Omarchy's current source defaults from `~/.local/share/omarchy/icon.txt` and `~/.local/share/omarchy/logo.txt` when those files are present.

## Hermes Theme File

The bundled Hermes plugin generates:

```text
~/.config/Hermes/omarchy-theme.json
```

The generated theme is named `omarchy-current` and labeled `Omarchy Current`. Users should select it inside Hermes, then restart Hermes after `thpm run` or a theme change so the app reloads the generated colors.

## Zellij Theme File

The bundled Zellij plugin generates:

```text
~/.config/zellij/themes/current.kdl
```

Users should set `theme "current"` once in `~/.config/zellij/config.kdl`. The plugin only manages the generated theme file. It does not edit Zellij keybindings, layouts, or the main config.

## Doctor Checks

`thpm doctor` is read-only. It checks the Omarchy hook directory, the shared
runtime, the active `colors.toml`, enabled hook syntax, and common app-specific
requirements.

For custom plugins, doctor can diagnose more accurately when the plugin:

- uses the numeric filename convention, such as `50-myapp.sh`
- sources `${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}`
- uses `skipped "Name"` for optional missing apps or files
- keeps generated files in predictable app config paths
