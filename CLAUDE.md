# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project context

`thpm` (Theme Hook Plugin Manager) is a public fork of [imbypass/omarchy-theme-hook](https://github.com/imbypass/omarchy-theme-hook), reframed from "a theme hook" into "a plugin manager for Omarchy's existing theme-set hook." It is **not** affiliated with Omarchy.

The fork's primary trunk is the `thpm` branch (also the GitHub default branch). The local `main` branch is kept as a clean mirror of `upstream/main` so upstream fixes can be pulled and rebased onto `thpm`. Two remotes:

- `origin` → `OldJobobo/theme-hook-plugin-manager`
- `upstream` → `imbypass/omarchy-theme-hook`

Workflow when pulling upstream changes:
```
git checkout main && git pull upstream main && git push origin main
git checkout thpm && git rebase main
```

## Architecture

The project ships three pieces of bash that get installed into Omarchy's hook tree:

```
omarchy-hook theme-set                      ← Omarchy fires this on theme change
        ↓
~/.config/omarchy/hooks/theme-set           ← dispatcher (this repo's `theme-set`)
        ↓ reads colors.toml, exports color vars + helpers
~/.config/omarchy/hooks/theme-set.d/*.sh    ← plugins (this repo's `theme-set.d/`)
```

Plus the user-facing CLI `thpm` (this repo's `thpm` script), installed to `~/.local/bin/thpm`.

**Source of theme colors:** `~/.local/state/omarchy/current/theme/colors.toml` on Omarchy 4 / Quattro. The previous source `alacritty.toml` is gone — it's now a generated artifact and may contain unrendered Jinja-style placeholders. Always read from `colors.toml`.

**Plugin contract** (defined by `theme-set` lines ~75-141, exported before iterating plugins):

- Color env vars (hex, no `#`): `primary_background`, `primary_foreground`, `cursor_color`, `selection_background`, `selection_foreground`, `normal_black`…`normal_white`, `bright_black`…`bright_white`. Each has an `rgb_`-prefixed companion returning `r, g, b`.
- Helper functions (exported with `export -f`): `success`, `warning`, `error`, `skipped`, `hex2rgb`, `rgb2hex`, `change_shade`, `require_restart <process-name>`.
- A plugin signals "this app's executable isn't installed, abort early without error" by calling `skipped "AppName"` (which `exit 0`s). Do **not** use `error` for missing-app conditions — `error` exit-1's and the dispatcher will report the plugin as failed.
- `require_restart "<process>"` accumulates names in a tmpfile; the dispatcher checks `pgrep -x` for each at the end and surfaces a single `notify-send` listing apps that need restarting.

**Plugin ordering:** Plugins in `theme-set.d/` run in lexicographic order via `for hook in ~/.config/omarchy/hooks/theme-set.d/*.sh`. Names use a `NN-app.sh` numeric prefix to control ordering. Existing prefixes: `00-` (shell prerequisites like fish, fzf), `10-` (basic CLI/desktop apps), `20-` (editors-class-1), `30-` (VS Code family), `40-` (heavier integrations: Cava, Firefox, Steam), `50-` (highest — Heroic). Pick a prefix that fits this gradient when adding plugins.

**Enable/disable mechanism:** "Enabled" = file is executable; "disabled" = not executable. The `thpm enable/disable` commands are wrappers around `chmod +x` / `chmod -x`. The dispatcher's `for` loop only runs `[[ -f "$hook" && -x "$hook" ]]` files. Some plugins have `post_enable`/`post_disable` side-effects defined in `thpm` itself (e.g. `gtk` toggles `gsettings`, `spotify` runs `spicetify apply`, `steam` re-runs the adwaita installer). When adding such side-effects, edit the `post_enable`/`post_disable` case statements in `thpm`.

## Common commands

```bash
# Syntax-check all shell scripts (fast sanity pass before commit)
bash -n thpm install.sh uninstall.sh theme-set
for f in theme-set.d/*.sh; do bash -n "$f" || echo "FAIL: $f"; done

# Install thpm from this working copy (overwrites any installed version)
./install.sh

# Run the theme-set hook immediately (uses currently-applied Omarchy theme)
omarchy-hook theme-set
# or, after install:
thpm run

# Test a single plugin in isolation against the current theme
source theme-set    # exports color vars + helpers, then runs all plugins;
                    # to avoid the loop, copy the export block into a test wrapper

# List plugins and their enabled/disabled state
thpm list

# Open the installed plugin directory
thpm open
```

There is no test suite, linter, or formatter configured — the code is pure bash. Validation is `bash -n` plus running `omarchy-hook theme-set` on a real Omarchy install.

## Hardcoded URLs that must stay in sync

Three places hardcode `OldJobobo/theme-hook-plugin-manager` on the `thpm` branch. If the repo or branch is renamed, update **all three**:

- `install.sh` — `git clone --branch thpm --depth 1 https://github.com/OldJobobo/theme-hook-plugin-manager.git`
- `thpm` (the script) — `th_install` and `th_uninstall` curl `raw.githubusercontent.com/OldJobobo/theme-hook-plugin-manager/thpm/{install,uninstall}.sh`
- `README.md` — install/uninstall curl commands

These use `raw.githubusercontent.com`, **not** `imbypass.github.io`. GitHub's repo-rename redirect covers `git clone` URLs but does not cover `raw.githubusercontent.com` URLs — those would silently 404, so always update them when renaming.

## CI

`.github/workflows/deploy-pages.yml` is inherited from upstream. It deploys `install.sh` and `uninstall.sh` to GitHub Pages on pushes to `main` only. This fork's install URLs use `raw.githubusercontent.com`, not Pages — so the workflow currently has no functional effect here. If you ever switch this fork's install URLs to Pages, change the workflow trigger from `main` to `thpm`.

## Style guard-rails

- Never re-introduce `extract_color "alacritty"` patterns. Stick to `colors.toml`.
- When adding a new bundled plugin, do all of: drop the script in `theme-set.d/` with the right numeric prefix, add a row to the README's "Bundled plugins" list, and (if applicable) add `post_enable`/`post_disable` cases in `thpm` and an unapply step in `uninstall.sh`.
- Prefer `chmod -x` over deleting a plugin file when toggling — keeps user-disabled state recoverable.
- "Hooklette" is upstream's term. This fork uses "plugin" everywhere user-facing.
