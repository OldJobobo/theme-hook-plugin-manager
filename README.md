<div align="center">

# Theme Hook Plugin Manager

**A small manager for Omarchy theme-change plugins.**

`thpm` installs and manages native Omarchy `theme-set.d` hook plugins. Omarchy runs the enabled hooks when the theme changes.

</div>

> **Independent project.** Theme Hook Plugin Manager is built for Omarchy users, but it is not affiliated with Omarchy.

## Overview

Omarchy runs `theme-set.d` hooks when the active theme changes. `thpm` manages those hook files as plugins: install them, list them, enable or disable them, and update them. When you run `thpm run`, it asks Omarchy to fire the `theme-set` hook; `thpm` does not dispatch plugin scripts itself.

Most bundled plugins translate Omarchy theme data into app-specific config files, CSS files, editor themes, or live reload actions. The same plugin model can also handle other theme-change tasks, such as restarting a helper process, syncing generated files, or adapting app-specific settings.

Color-focused plugins read the active Omarchy theme from:

```text
~/.local/state/omarchy/current/theme/colors.toml
```

Each integration is a normal shell plugin in:

```text
~/.config/omarchy/hooks/theme-set.d/
```

Enabled plugins end in `.sh`. Disabled plugins end in `.sh.sample`. Omarchy runs enabled hooks directly when the `theme-set` hook fires.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/OldJobobo/theme-hook-plugin-manager/thpm/install.sh | bash
```

The installer:

- installs the `thpm` CLI
- installs bundled plugins into Omarchy's hook directory
- preserves disabled bundled plugins as `.sample`
- keeps custom user hooks in place
- applies the current theme once setup finishes

### GTK Dependency

The GTK plugin uses Omarchy's Adwaita-compatible GTK package:

```bash
omarchy-pkg-add adw-gtk-theme
```

The installer checks for `adw-gtk-theme` and can prompt to install it.

## Requirements

- Omarchy
- An Omarchy theme with `colors.toml` for color-based plugins
- Bash and standard Unix command-line tools
- Target apps installed for the plugins you enable

Some apps also require one-time selection of the generated Omarchy theme inside their own settings.

### Zellij

The Zellij plugin writes the active Omarchy colors into a managed inline theme block in:

```text
~/.config/zellij/config.kdl
```

Enable the plugin with `thpm enable zellij` and run `thpm run`. The plugin preserves existing keybindings, layouts, and other config outside its marked block, and ensures the active theme is:

```kdl
theme "current"
```

Inline themes in `config.kdl` are hot-reloaded by Zellij. If the active Omarchy theme ships `zellij.kdl`, that theme is embedded in the managed block; otherwise the plugin generates a Zellij theme from `colors.toml`.

## Supported Plugins

**Browsers:** Firefox, Qutebrowser, Zen Browser

**Editors and writing:** Cursor, Obsidian Terminal plugin, Typora, VS Code, Windsurf, Zed, Emacs / Doom Emacs

**Desktop and UI:** Discord clients using Vencord-compatible themes, optional Discord System24 theme, GTK apps, Hermes, nwg-dock-hyprland, Omarchy branding, Qt6 apps using qt6ct, SwayNC, Vicinae

**Terminal and CLI:** cliamp, Cava, Fish, Foot live colors, fzf, Superfile, tmux, Zellij

**Games and media:** Heroic Games Launcher, Spotify using Spicetify, Steam

### Omarchy Branding

The branding plugin is installed disabled by default. Enable it with `thpm enable branding` when you want themes to manage Omarchy's Fastfetch/About and screensaver logos.

Once enabled, it syncs active-theme text logos into Omarchy's user branding files:

```text
~/.local/state/omarchy/current/theme/about.txt
~/.local/state/omarchy/current/theme/screensaver.txt
```

When present, those files are copied to `~/.config/omarchy/branding/about.txt` for Fastfetch/About and `~/.config/omarchy/branding/screensaver.txt` for the screensaver. Missing theme branding files leave the existing user branding unchanged.

`thpm disable branding` stops future syncs but does not restore or delete the current branding. `thpm remove` restores Omarchy's current source defaults from `~/.local/share/omarchy/icon.txt` and `~/.local/share/omarchy/logo.txt`.

## Commands

```bash
thpm list
thpm enable firefox
thpm disable spotify
thpm doctor
thpm run
thpm install skills
thpm open
thpm update
thpm remove
```

| Command               | What it does                                              |
| --------------------- | --------------------------------------------------------- |
| `thpm list`           | Show enabled and disabled plugins                         |
| `thpm enable <name>`  | Enable a plugin                                           |
| `thpm disable <name>` | Disable a plugin                                          |
| `thpm doctor [name]`  | Diagnose thpm setup and plugin theming issues             |
| `thpm run`            | Ask Omarchy to fire the `theme-set` hook now              |
| `thpm install skills` | Install a bundled agent skill, currently for Codex/OpenAI |
| `thpm open`           | Open the plugin directory                                 |
| `thpm update`         | Re-run the installer                                      |
| `thpm remove`         | Uninstall `thpm`                                          |

`thpm list` and `thpm help` may show a cached notice when a newer commit is available. They do not update files automatically; run `thpm update` to install updates.

## Configuration

Optional user configuration lives at:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/thpm/config.toml
```

Set `THPM_CONFIG_FILE=/path/to/config.toml` to use a different file. Existing environment overrides still take priority over config values, including `THPM_HOOK_DIR`, `THPM_STATE_DIR`, `THPM_THEME_ENV`, `THPM_COLORS_FILE`, and `THPM_SKILLS_DIR`.

Example:

```toml
[paths]
hook_dir = "~/.config/omarchy/hooks/theme-set.d"
state_dir = "~/.local/share/thpm"
theme_env = "~/.local/share/thpm/lib/theme-env.sh"
colors_file = "~/.local/state/omarchy/current/theme/colors.toml"
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
```

Restart notification app keys match the process name passed by a plugin to `require_restart`, for example `steam`, `nautilus`, or `zen-browser`.

## Custom Plugins

Put custom plugins in:

```text
~/.config/omarchy/hooks/theme-set.d/
```

Use a numeric prefix for predictable ordering:

```text
50-myapp.sh
```

`thpm` discovers plugins from that directory. A new file like `50-myapp.sh` appears as `myapp` in `thpm list`; `50-myapp.sh.sample` appears as disabled and can be enabled with `thpm enable myapp`.

Color-aware plugins should source the shared runtime before reading theme values or helper functions:

```bash
source "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"
```

For available variables, helper functions, and an example plugin, see [docs/plugins.md](docs/plugins.md).

## Updating

```bash
thpm update
```

Updating replaces bundled plugin files with the latest versions. Custom hooks are preserved. If you want to customize a bundled plugin, copy it to a new filename before editing it.

## Uninstall

```bash
thpm remove
```

Or run:

```bash
curl -fsSL https://raw.githubusercontent.com/OldJobobo/theme-hook-plugin-manager/thpm/uninstall.sh | bash
```

The uninstaller removes `thpm`, bundled plugins, the shared runtime, and generated integration files it knows how to clean up. Custom Omarchy hooks are preserved. Omarchy branding is restored from the current Omarchy source defaults when those default files are available.

## Troubleshooting

### A plugin is not changing an app

Run the doctor first:

```bash
thpm doctor
```

For a single plugin:

```bash
thpm doctor firefox
```

Check that the plugin is enabled:

```bash
thpm list
```

Then ask Omarchy to reapply the theme hook:

```bash
thpm run
```

Some apps require selecting the generated Omarchy theme in their own settings.

### Hermes is not changing

The Hermes plugin writes the current Omarchy theme to:

```text
~/.config/Hermes/omarchy-theme.json
```

Select the generated `Omarchy Current` theme inside Hermes, then restart Hermes after `thpm run` or a theme change.

### `colors.toml not found`

Use an Omarchy theme with `colors.toml`. `thpm` reads:

```text
~/.local/state/omarchy/current/theme/colors.toml
```

Generated terminal or app theme files are not treated as the source of truth.

### Firefox or Zen Browser is not changing

Open `about:config`, set `toolkit.legacyUserProfileCustomizations.stylesheets` to `true`, and restart the browser. The plugin also needs a valid browser profile directory. The Zen plugin writes managed `thpm-zen-*.css` files and a marked import block; `thpm disable zen` removes those managed imports but does not change unrelated user CSS.

For Zen-specific issues, run:

```bash
thpm update
thpm run
thpm doctor zen
```

`thpm doctor zen` checks the active Zen profile, the managed import block, the generated `thpm-zen-*.css` files, and whether the generated browser chrome stylesheet includes current Zen frame/topbar rules. If doctor reports stale frame CSS, run `thpm run` again and fully restart Zen.

If doctor is clean but Zen is still only partially themed, open `about:profiles` in Zen and confirm the active profile path matches the profile shown by `thpm doctor zen`. If the paths match, the remaining unthemed area is likely a Zen UI surface outside Firefox userChrome CSS, such as native window decoration.

### Discord is not changing

Use a Vencord-compatible client, such as Vesktop or Equibop, then enable the generated theme in that client's theme settings.

`discord-system24` is installed disabled by default as an alternative to `discord`. Enable only one Discord plugin at a time because both install the active client theme as `vencord.theme.css`.

### Spotify is not changing

Make sure Spicetify is installed and configured. If Spotify changed after an update, run:

```bash
spicetify restore backup apply
thpm run
```

### Obsidian Terminal is not changing

The plugin reads Obsidian's vault registry and common vault directories. For unusual layouts, pass the vault or plugin data file explicitly:

```bash
OBSIDIAN_VAULT_PATH="$HOME/path/to/vault" thpm run
OBSIDIAN_TERMINAL_DATA_JSON="$HOME/path/to/vault/.obsidian/plugins/terminal/data.json" thpm run
```

### Old hook errors after updating

Current plugins are native Omarchy `theme-set.d` hooks and source `~/.local/share/thpm/lib/theme-env.sh`. If logs mention older dispatcher behavior, update `thpm` and remove stale custom copies of old bundled hooks.

## Development

Run the test suite before submitting changes:

```bash
bash tests/run.sh
```

Contributor notes live in [AGENTS.md](AGENTS.md), and plugin authoring details live in [docs/plugins.md](docs/plugins.md).

## Attribution

Theme Hook Plugin Manager is an independent Omarchy-focused project. Earlier work in this space includes [imbypass/omarchy-theme-hook](https://github.com/imbypass/omarchy-theme-hook), credited here for project history.
