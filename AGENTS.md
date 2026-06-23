# Repository Guidelines

## Project Structure & Module Organization

This repository is a small shell-based Omarchy plugin manager.

- `thpm` is the user-facing CLI for listing, enabling, disabling, running, updating, and uninstalling plugins.
- `install.sh` and `uninstall.sh` manage installation, bundled hooks, and cleanup.
- `theme-set` is a compatibility shim for older installs.
- `lib/theme-env.sh` loads Omarchy `colors.toml` values and shared helper functions.
- `theme-set.d/*.sh` contains bundled app plugins. Use numeric prefixes, for example `40-firefox.sh`.
- `tests/run.sh` is the test harness. `tests/omarchy-defaults.contract` records Omarchy path assumptions.
- `docs/plugins.md` documents the plugin API and authoring expectations.

## Build, Test, and Development Commands

There is no build step; scripts run directly.

```bash
bash tests/run.sh
```

Runs the full behavioral test suite.

```bash
bash -n thpm install.sh uninstall.sh lib/theme-env.sh theme-set theme-set.d/*.sh
```

Checks shell syntax.

```bash
shellcheck theme-set.d/*.sh lib/theme-env.sh thpm install.sh uninstall.sh
```

Runs static analysis when `shellcheck` is available. Expect sourced theme variables to need context.

## Coding Style & Naming Conventions

Write POSIX-adjacent Bash with `#!/usr/bin/env bash`. Use 4-space indentation in top-level scripts and match nearby style in existing plugins. Quote paths and variables unless intentional word splitting is required. Plugins should skip missing apps or optional dependencies with `skipped "Name"` rather than failing noisily.

Plugin filenames must use a numeric ordering prefix and `.sh` suffix, such as `10-spotify.sh` or `40-qutebrowser.sh`. Disabled installed plugins use `.sh.sample`.

## Testing Guidelines

Add or update tests in `tests/run.sh` for behavior changes, installer assumptions, and portability fixes. Prefer isolated fake `$HOME` directories and stub commands in temporary `bin` directories. Keep tests behavioral: assert generated files, preserved user content, skipped paths, and command invocations.

Always run `bash tests/run.sh` before committing.

## Commit & Pull Request Guidelines

Recent commits use concise imperative subjects, sometimes with a `fix:` prefix, for example `Harden hook plugin portability` or `fix: change Omarchyy to Omarchy`.

Pull requests should include:

- A short summary of user-visible behavior.
- Tests run, especially `bash tests/run.sh`.
- Any changed Omarchy assumptions, plugin paths, or new external command dependencies.
- README or `docs/plugins.md` updates for new plugins or setup requirements.

## Omarchy Compatibility Notes

Theme data must come from the active colors file resolved by `lib/theme-env.sh`, preferring `~/.local/state/omarchy/current/theme/colors.toml`. Do not treat generated app theme files as source of truth. If Omarchy defaults change, update `tests/omarchy-defaults.contract` and the related tests with the code change.
