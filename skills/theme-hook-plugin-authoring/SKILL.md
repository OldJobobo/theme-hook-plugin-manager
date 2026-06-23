---
name: theme-hook-plugin-authoring
description: Author, review, or update Theme Hook Plugin Manager (thpm) plugins for Omarchy theme changes. Use when creating scripts under theme-set.d/, diagnosing custom thpm hooks, adding bundled plugin behavior, documenting plugin API usage, or translating Omarchy colors.toml values into app-specific config, CSS, JSON, TOML, shell, or live-reload integration files.
---

# Theme Hook Plugin Authoring

Use this skill to create or audit `thpm` plugins. A plugin is a Bash script run by Omarchy's native `theme-set.d` hook system when the active theme changes.

## First Read

When working inside the `theme-hook-plugin-manager` repo, prefer these source files:

- `docs/plugins.md`: public plugin API and examples.
- `lib/theme-env.sh`: authoritative runtime for color variables and helper functions.
- `theme-set.d/*.sh`: bundled plugin patterns.
- `tests/run.sh`: behavioral expectations and portability guards.
- `README.md`: user-facing install, command, and troubleshooting language.

Treat generated app theme files as outputs, not inputs. Theme data comes from the active theme colors file resolved by `lib/theme-env.sh`, preferring `~/.local/state/omarchy/current/theme/colors.toml`.

## Plugin Contract

Install location:

```text
~/.config/omarchy/hooks/theme-set.d/
```

Bundled source location in the repo:

```text
theme-set.d/
```

Use filenames like `50-myapp.sh`. The numeric prefix controls lexicographic order:

- `00-`: shell prerequisites and base terminal helpers.
- `10-`: basic CLI, desktop, and low-risk app integrations.
- `20-30`: editors and medium-weight integrations.
- `40-50`: browsers, games, media, heavier integrations, or late-running app hooks.

Enabled plugins end in `.sh`. Disabled plugins end in `.sh.sample`. Use `thpm enable <name>` and `thpm disable <name>` instead of hand-renaming when operating on an installed system.

Every color-aware plugin should source the shared runtime before reading colors or helper functions:

```bash
source "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"
```

The runtime exits with an error if `colors.toml` is missing or invalid, so plugin code can assume the exported colors exist after sourcing.

## Available Values

Hex values have no leading `#`:

```text
primary_background
primary_foreground
cursor_color
selection_background
selection_foreground
normal_black normal_red normal_green normal_yellow normal_blue normal_magenta normal_cyan normal_white
bright_black bright_red bright_green bright_yellow bright_blue bright_magenta bright_cyan bright_white
```

RGB companions use an `rgb_` prefix and are formatted as `r, g, b`, for example `rgb_primary_background` or `rgb_normal_blue`.

Helpers from `lib/theme-env.sh`:

```text
success "message"
warning "message"
error "message"
skipped "AppName"
hex2rgb <hex>
rgb2hex <r> <g> <b>
change_shade <hex> <amount>
require_restart <process-name> [Display Name]
```

Use `skipped` for missing apps, missing optional files, or unmet optional dependencies. Use `error` only for a real plugin failure. `skipped` exits 0; `error` exits 1.

`require_restart` respects `${XDG_CONFIG_HOME:-$HOME/.config}/thpm/config.toml`, including global notification settings, per-app restart settings, running-process checks, and cooldowns.

## Authoring Workflow

1. Inspect similar plugins in `theme-set.d/` before adding a new pattern.
2. Choose the numeric prefix and plugin name. The CLI strips the prefix and `.sh`/`.sh.sample`, so `40-qutebrowser.sh` is managed as `qutebrowser`.
3. Start with the template below. Keep paths under `$HOME` and quote expansions.
4. Guard optional commands and files with `command -v`, `[[ -f ]]`, or `[[ -d ]]`; skip cleanly when the target app is absent.
5. Generate app config into predictable user config paths or current-theme output files. Preserve unrelated user content.
6. Add reload/restart behavior only when the app needs it. Prefer app-native reload commands; otherwise call `require_restart`.
7. If the plugin needs enable/disable side effects, add a narrowly scoped `post_enable` or `post_disable` case in `thpm`.
8. If bundled, update `README.md` and `docs/plugins.md` when user-facing behavior or setup requirements change.
9. Add or update focused tests in `tests/run.sh` for generated files, preserved user content, missing-dependency skips, installer state, and doctor behavior.

## Plugin Template

```bash
#!/usr/bin/env bash
source "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"

if ! command -v myapp >/dev/null 2>&1; then
    skipped "myapp"
fi

config="$HOME/.config/myapp/theme.conf"
mkdir -p "$(dirname "$config")"

cat > "$config" <<EOF
background = #${primary_background}
foreground = #${primary_foreground}
accent = #${normal_blue}
selection = rgb(${rgb_selection_background})
EOF

require_restart "myapp" "MyApp"
success "myapp theme updated!"
```

Save active custom plugins as:

```text
~/.config/omarchy/hooks/theme-set.d/50-myapp.sh
```

Save disabled custom plugins as:

```text
~/.config/omarchy/hooks/theme-set.d/50-myapp.sh.sample
```

## Portability Rules

Use Bash, not zsh or fish. Keep scripts compatible with the standard tools available on an Omarchy system. Avoid GNU-only assumptions when a portable alternative is easy; existing tests specifically guard against patterns such as `grep -P` in bundled hooks.

Do not assume an app exists just because its config directory exists. Guard both the executable and any required config/data files that the plugin reads.

Do not treat app-generated theme outputs, such as terminal/editor rendered theme files, as the source of Omarchy colors unless the plugin is intentionally syncing or live-updating that app's current rendered output. For color-based plugins, read the runtime variables sourced from `colors.toml`.

When editing user-owned files, prefer a managed block or a dedicated generated file over replacing the full file. Preserve user content outside the managed block.

Use environment overrides already supported by the repo when tests or users need alternate paths:

```text
THPM_THEME_ENV
THPM_COLORS_FILE
THPM_HOOK_DIR
THPM_STATE_DIR
THPM_CONFIG_FILE
```

## Bundled Plugin Checklist

For a new bundled plugin:

- Add `theme-set.d/NN-name.sh`.
- Add tests in `tests/run.sh`.
- Add README support/setup notes if users must install an app, choose a generated theme, restart, or run a command.
- Update `docs/plugins.md` if the public authoring contract changes.
- Add plugin-specific `thpm doctor` checks when missing commands/files can be diagnosed.
- Add `post_enable`/`post_disable` in `thpm` only for real state changes outside normal hook execution.
- Add uninstall cleanup in `uninstall.sh` when the plugin creates persistent generated integration files outside the hook directory.
- If it should ship disabled, add it to `default_disabled_plugins` in `install.sh`.

## Validation

Run syntax checks:

```bash
bash -n thpm install.sh uninstall.sh lib/theme-env.sh theme-set theme-set.d/*.sh
```

Run the behavioral suite before finishing repo changes:

```bash
bash tests/run.sh
```

When available, run ShellCheck:

```bash
shellcheck theme-set.d/*.sh lib/theme-env.sh thpm install.sh uninstall.sh
```

Use `thpm doctor [name]` on an installed system to diagnose hook directory setup, shared runtime availability, `colors.toml`, plugin syntax, runtime sourcing, and app-specific requirements.
