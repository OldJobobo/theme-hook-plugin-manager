#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
TEST_FAILURES=0
TEST_ASSERTIONS=0
OMARCHY_CONTRACT_FILE="$ROOT_DIR/tests/omarchy-defaults.contract"

unset XDG_CONFIG_HOME
unset THPM_CONFIG_FILE

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1"
  TEST_ASSERTIONS=$((TEST_ASSERTIONS + 1))
  TEST_FAILURES=$((TEST_FAILURES + 1))
}

pass() {
  printf 'ok - %s\n' "$1"
  TEST_ASSERTIONS=$((TEST_ASSERTIONS + 1))
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "$expected" == "$actual" ]]; then
    pass "$message"
  else
    fail "$message"
    printf '  expected: %q\n' "$expected"
    printf '  actual:   %q\n' "$actual"
  fi
}

assert_success() {
  local status="$1"
  local message="$2"

  if [[ "$status" -eq 0 ]]; then
    pass "$message"
  else
    fail "$message"
    printf '  exit status: %s\n' "$status"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$message"
  else
    fail "$message"
    printf '  missing: %q\n' "$needle"
    printf '  output:  %s\n' "$haystack"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$message"
  else
    fail "$message"
    printf '  unexpected: %q\n' "$needle"
    printf '  output:     %s\n' "$haystack"
  fi
}

assert_file_exists() {
  local file="$1"
  local message="$2"

  if [[ -f "$file" ]]; then
    pass "$message"
  else
    fail "$message"
    printf '  missing file: %s\n' "$file"
  fi
}

assert_file_missing() {
  local file="$1"
  local message="$2"

  if [[ ! -e "$file" ]]; then
    pass "$message"
  else
    fail "$message"
    printf '  file should not exist: %s\n' "$file"
  fi
}

assert_file_executable() {
  local file="$1"
  local message="$2"

  if [[ -x "$file" ]]; then
    pass "$message"
  else
    fail "$message"
    printf '  file is not executable: %s\n' "$file"
  fi
}

assert_file_not_executable() {
  local file="$1"
  local message="$2"

  if [[ -f "$file" && ! -x "$file" ]]; then
    pass "$message"
  else
    fail "$message"
    printf '  file is executable or missing: %s\n' "$file"
  fi
}

contract_value() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$OMARCHY_CONTRACT_FILE"
}

write_colors_fixture() {
  local home_dir="$1"
  local theme_dir="$home_dir/.local/state/omarchy/current/theme"

  mkdir -p "$theme_dir"
  cat > "$theme_dir/colors.toml" <<'EOF'
background = "#101112"
foreground = "#f1f2f3"
cursor = "#abcdef"
selection_background = "#222222"
selection_foreground = "#eeeeee"
color0 = "#000000"
color1 = "#111111"
color2 = "#222222"
color3 = "#333333"
color4 = "#444444"
color5 = "#555555"
color6 = "#666666"
color7 = "#777777"
color8 = "#888888"
color9 = "#999999"
color10 = "#aaaaaa"
color11 = "#bbbbbb"
color12 = "#cccccc"
color13 = "#dddddd"
color14 = "#eeeeee"
color15 = "#ffffff"
EOF
}

make_stub_bin() {
  local bin_dir="$1"
  local name="$2"
  local body="$3"

  cat > "$bin_dir/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
  chmod +x "$bin_dir/$name"
}

make_install_git_stub() {
  local bin_dir="$1"

  cat > "$bin_dir/git" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-C" && "\${3:-}" == "rev-parse" && "\${4:-}" == "HEAD" ]]; then
  printf '%s\n' "local-install-commit"
  exit 0
fi
printf '%s\n' "\$*" > "$TMP_ROOT/install-git-args.log"
if [[ "\$1" == "clone" ]]; then
  shift
fi
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --branch)
      printf '%s\n' "\$2" > "$TMP_ROOT/install-git-branch.log"
      shift 2
      ;;
    --depth)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p /tmp/theme-hook
cp "$ROOT_DIR/thpm" /tmp/theme-hook/thpm
cp "$ROOT_DIR/theme-set" /tmp/theme-hook/theme-set
cp -R "$ROOT_DIR/skills" /tmp/theme-hook/skills
mkdir -p /tmp/theme-hook/lib
cp "$ROOT_DIR/lib/theme-env.sh" /tmp/theme-hook/lib/theme-env.sh
mkdir -p /tmp/theme-hook/theme-set.d
cp "$ROOT_DIR"/theme-set.d/*.sh /tmp/theme-hook/theme-set.d/
EOF
  chmod +x "$bin_dir/git"
}

install_git_branch() {
  if [[ -f "$TMP_ROOT/install-git-branch.log" ]]; then
    cat "$TMP_ROOT/install-git-branch.log"
  fi
}

install_git_args() {
  if [[ -f "$TMP_ROOT/install-git-args.log" ]]; then
    cat "$TMP_ROOT/install-git-args.log"
  fi
}

run_theme_hooks() {
  local home_dir="$1"
  shift || true

  HOME="$home_dir" "$ROOT_DIR/theme-set" "$@"
  if [[ -d "$home_dir/.config/omarchy/hooks/theme-set.d" ]]; then
    local hook
    for hook in "$home_dir"/.config/omarchy/hooks/theme-set.d/*; do
      [[ -f "$hook" ]] || continue
      [[ "$hook" == *.sample ]] && continue
      THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" bash "$hook" "$@" || echo "Hook failed: $hook"
    done
  fi
}

run_thpm() {
  local home_dir="$1"
  shift
  HOME="$home_dir" XDG_CONFIG_HOME="$home_dir/.config" "$ROOT_DIR/thpm" "$@" 2>&1
}

run_thpm_with_path() {
  local home_dir="$1"
  local bin_dir="$2"
  shift 2
  PATH="$bin_dir:$PATH" HOME="$home_dir" XDG_CONFIG_HOME="$home_dir/.config" "$ROOT_DIR/thpm" "$@" 2>&1
}

test_shell_syntax() {
  local script
  local failed=0

  for script in "$ROOT_DIR/thpm" "$ROOT_DIR/theme-set" "$ROOT_DIR/install.sh" "$ROOT_DIR/uninstall.sh" "$ROOT_DIR/lib/theme-env.sh" "$ROOT_DIR"/theme-set.d/*.sh; do
    if ! bash -n "$script"; then
      failed=1
    fi
  done

  assert_eq "0" "$failed" "all shell scripts pass bash -n"
}

test_installer_bundled_plugin_inventory_matches_hooks() {
  local actual
  local declared

  actual="$(cd "$ROOT_DIR/theme-set.d" && printf '%s\n' *.sh | sort)"
  declared="$(awk '
    /^bundled_plugins=\(/ { in_list = 1; next }
    in_list && /^\)/ { in_list = 0 }
    in_list {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      if ($0 != "") print $0
    }
  ' "$ROOT_DIR/install.sh" | sort)"

  assert_eq "$actual" "$declared" "install bundled plugin inventory matches theme-set.d hooks"
}

test_project_omarchy_default_contract() {
  local hook_dir
  local theme_dir
  local colors_file
  local light_mode_file
  local theme_name_file
  local theme_store_dir
  local hook_name
  local legacy_dispatcher
  local legacy_bin_dir
  local shared_runtime

  hook_dir="$(contract_value HOOK_DIR)"
  theme_dir="$(contract_value THEME_DIR)"
  colors_file="$(contract_value COLORS_FILE)"
  light_mode_file="$(contract_value LIGHT_MODE_FILE)"
  theme_name_file="$(contract_value THEME_NAME_FILE)"
  theme_store_dir="$(contract_value THEME_STORE_DIR)"
  hook_name="$(contract_value HOOK_NAME)"
  legacy_dispatcher="$(contract_value LEGACY_DISPATCHER)"
  legacy_bin_dir="$(contract_value LEGACY_BIN_DIR)"
  shared_runtime="$(contract_value SHARED_RUNTIME)"

  assert_file_exists "$OMARCHY_CONTRACT_FILE" "Omarchy defaults contract file exists"
  assert_contains "$(cat "$ROOT_DIR/thpm")" "thpm_config_path paths hook_dir \"\$HOME/$hook_dir\"" "thpm default hook directory matches Omarchy contract"
  assert_contains "$(cat "$ROOT_DIR/thpm")" "omarchy-hook \"$hook_name\"" "thpm run invokes contracted Omarchy hook"
  assert_contains "$(cat "$ROOT_DIR/install.sh")" "\$HOME/$hook_dir" "install writes hooks to contracted Omarchy hook directory"
  assert_contains "$(cat "$ROOT_DIR/install.sh")" "omarchy-hook $hook_name" "install reapplies contracted Omarchy hook"
  assert_contains "$(cat "$ROOT_DIR/install.sh")" "\$HOME/$legacy_dispatcher" "install only targets contracted legacy dispatcher path"
  assert_contains "$(cat "$ROOT_DIR/install.sh")" "\$HOME/$legacy_bin_dir/thpm" "install removes contracted legacy thpm bin path"
  assert_contains "$(cat "$ROOT_DIR/uninstall.sh")" "\$HOME/$hook_dir" "uninstall removes hooks from contracted Omarchy hook directory"
  assert_contains "$(cat "$ROOT_DIR/uninstall.sh")" "\$HOME/$legacy_dispatcher" "uninstall removes contracted legacy dispatcher path"
  assert_contains "$(cat "$ROOT_DIR/uninstall.sh")" "\$HOME/$legacy_bin_dir/thpm" "uninstall removes contracted legacy thpm bin path"
  assert_contains "$(cat "$ROOT_DIR/lib/theme-env.sh")" "\$HOME/$colors_file" "theme env reads contracted Omarchy colors file"
  assert_contains "$(cat "$ROOT_DIR/theme-set")" "$hook_dir/* directly" "compatibility shim documents direct Omarchy hook execution"
  assert_contains "$(cat "$ROOT_DIR/docs/plugins.md")" "~/$hook_dir/" "plugin docs show contracted Omarchy hook directory"
  assert_contains "$(cat "$ROOT_DIR/docs/plugins.md")" "~/$colors_file" "plugin docs show contracted Omarchy colors file"
  assert_contains "$(cat "$ROOT_DIR/README.md")" "~/$hook_dir/" "README shows contracted Omarchy hook directory"
  assert_contains "$(cat "$ROOT_DIR/README.md")" "native Omarchy \`$hook_name.d\` hooks" "README documents direct Omarchy hook model"
  assert_contains "$(cat "$ROOT_DIR/theme-set.d/10-gtk.sh")" "\$THPM_LIGHT_MODE_FILE" "GTK plugin uses resolved Omarchy light mode marker"
  assert_contains "$(cat "$ROOT_DIR/theme-set.d/25-swaync.sh")" "\$THPM_THEME_NAME_FILE" "SwayNC plugin uses resolved Omarchy theme name file"
  assert_contains "$(cat "$ROOT_DIR/theme-set.d/25-swaync.sh")" "\$HOME/$theme_store_dir" "SwayNC plugin uses contracted Omarchy theme store"
  assert_contains "$(cat "$ROOT_DIR/theme-set.d/35-obsidian-terminal.sh")" "\${THPM_THEME_ENV:-\$HOME/$shared_runtime}" "direct-run plugin fallback uses contracted shared runtime"
  assert_contains "$(cat "$ROOT_DIR/lib/theme-env.sh")" "includes colors.toml" "theme env error explains colors.toml requirement"
}

test_thpm_help() {
  local home_dir="$TMP_ROOT/help-home"
  local output

  mkdir -p "$home_dir"
  output="$(run_thpm "$home_dir" help)"

  assert_contains "$output" "Usage: thpm [command] [plugin]" "thpm help prints usage"
  assert_contains "$output" "doctor" "thpm help lists doctor command"
  assert_contains "$output" "enable" "thpm help lists enable command"
  assert_contains "$output" "disable" "thpm help lists disable command"
  assert_contains "$output" "install skills" "thpm help lists skill installer command"
}

test_thpm_cli_uses_terminal_palette_roles() {
  local source

  source="$(cat "$ROOT_DIR/thpm")"
  assert_contains "$source" "tput \"\$@\"" "thpm CLI colors use terminal capabilities"
  assert_contains "$source" "thpm_color" "thpm CLI centralizes color rendering"
  assert_not_contains "$source" 'dot "green"' "thpm CLI does not hard-code green dot role"
  assert_not_contains "$source" 'dot "red"' "thpm CLI does not hard-code red dot role"
  assert_not_contains "$source" 'dot "yellow"' "thpm CLI does not hard-code yellow dot role"
  assert_not_contains "$source" '\e[31m' "thpm CLI avoids raw red ANSI escape"
  assert_not_contains "$source" '\033[90m' "thpm CLI avoids raw muted ANSI escape"
}

test_thpm_install_skills_prompts_and_installs_codex_skill() {
  local home_dir="$TMP_ROOT/skills-install-home"
  local output
  local installed_skill="$home_dir/.codex/skills/theme-hook-plugin-authoring/SKILL.md"

  mkdir -p "$home_dir"

  output="$(printf '1\n1\n' | THPM_SKILLS_DIR="$ROOT_DIR/skills" HOME="$home_dir" XDG_CONFIG_HOME="$home_dir/.config" "$ROOT_DIR/thpm" install skills 2>&1)"

  assert_contains "$output" "Available Skills:" "thpm install skills prompts for bundled skill"
  assert_contains "$output" "theme-hook-plugin-authoring" "thpm install skills lists bundled skill"
  assert_contains "$output" "Available Agents:" "thpm install skills prompts for agent"
  assert_contains "$output" "Codex (OpenAI)" "thpm install skills lists Codex agent"
  assert_contains "$output" "Installed skill: theme-hook-plugin-authoring" "thpm install skills reports installed skill"
  assert_file_exists "$installed_skill" "thpm install skills installs SKILL.md into Codex skills"
}

test_thpm_install_skills_accepts_explicit_skill_and_agent() {
  local home_dir="$TMP_ROOT/skills-install-explicit-home"
  local codex_home="$home_dir/custom-codex"
  local output
  local installed_skill="$codex_home/skills/theme-hook-plugin-authoring/SKILL.md"

  mkdir -p "$home_dir"

  output="$(THPM_SKILLS_DIR="$ROOT_DIR/skills" CODEX_HOME="$codex_home" HOME="$home_dir" XDG_CONFIG_HOME="$home_dir/.config" "$ROOT_DIR/thpm" install skills theme-hook-plugin-authoring codex 2>&1)"

  assert_contains "$output" "Installed skill: theme-hook-plugin-authoring" "thpm install skills accepts explicit skill"
  assert_contains "$output" "Target: $codex_home/skills/theme-hook-plugin-authoring" "thpm install skills reports explicit Codex target"
  assert_file_exists "$installed_skill" "thpm install skills respects CODEX_HOME"
}

test_thpm_enable_disable_and_list() {
  local home_dir="$TMP_ROOT/thpm-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output

  mkdir -p "$hook_dir"
  printf '#!/usr/bin/env bash\n' > "$hook_dir/10-fzf.sh.sample"

  output="$(run_thpm "$home_dir" list)"
  assert_contains "$output" "Disabled Plugins:" "thpm list shows disabled section"
  assert_contains "$output" "fzf" "thpm list includes disabled plugin name"

  output="$(run_thpm "$home_dir" enable fzf)"
  assert_contains "$output" "Plugin Enabled: fzf" "thpm enable reports enabled plugin"
  assert_file_exists "$hook_dir/10-fzf.sh" "thpm enable restores .sh hook"
  assert_file_missing "$hook_dir/10-fzf.sh.sample" "thpm enable removes .sample suffix"

  output="$(run_thpm "$home_dir" disable fzf)"
  assert_contains "$output" "Plugin Disabled: fzf" "thpm disable reports disabled plugin"
  assert_file_exists "$hook_dir/10-fzf.sh.sample" "thpm disable adds .sample suffix"
  assert_file_missing "$hook_dir/10-fzf.sh" "thpm disable removes active .sh hook"

  output="$(run_thpm "$home_dir" enable missing-plugin)"
  assert_contains "$output" "Plugin not found: missing-plugin" "thpm enable reports missing plugin"
}

test_thpm_hides_tmux_but_keeps_cliamp_visible() {
  local home_dir="$TMP_ROOT/thpm-hidden-home"
  local bin_dir="$TMP_ROOT/thpm-hidden-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  printf '#!/usr/bin/env bash\nsource "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"\n' > "$hook_dir/10-tmux.sh"
  printf '#!/usr/bin/env bash\nsource "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"\n' > "$hook_dir/50-cliamp.sh.sample"
  printf '#!/usr/bin/env bash\nsource "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"\n' > "$hook_dir/30-vscode.sh"
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'

  output="$(run_thpm "$home_dir" list)"
  assert_contains "$output" "vscode" "thpm list still shows visible plugins"
  assert_not_contains "$output" "tmux" "thpm list hides tmux"
  assert_contains "$output" "cliamp" "thpm list keeps cliamp visible"
  assert_file_exists "$hook_dir/10-tmux.sh.sample" "thpm list disables hidden active tmux hook"
  assert_file_missing "$hook_dir/10-tmux.sh" "thpm list removes active hidden tmux hook"

  output="$(run_thpm "$home_dir" enable tmux)"
  assert_contains "$output" "Plugin not found: tmux" "thpm enable cannot enable hidden tmux plugin"
  assert_file_exists "$hook_dir/10-tmux.sh.sample" "thpm enable leaves hidden tmux disabled"

  output="$(run_thpm "$home_dir" enable cliamp)"
  assert_contains "$output" "Plugin Enabled: cliamp" "thpm enable can restore visible cliamp plugin"
  assert_file_exists "$hook_dir/50-cliamp.sh" "thpm enable restores cliamp hook"

  output="$(PATH="$bin_dir:$PATH" THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" "$ROOT_DIR/thpm" doctor tmux 2>&1 || true)"
  assert_contains "$output" "plugin not found: tmux" "thpm doctor treats hidden tmux plugin as missing"
  assert_not_contains "$output" "tmux command" "thpm doctor skips hidden tmux checks"
}

test_thpm_discord_plugins_are_mutually_exclusive() {
  local home_dir="$TMP_ROOT/thpm-discord-mutual-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output

  mkdir -p "$hook_dir"
  cp "$ROOT_DIR/theme-set.d/10-discord.sh" "$hook_dir/10-discord.sh"
  cp "$ROOT_DIR/theme-set.d/11-discord-system24.sh" "$hook_dir/11-discord-system24.sh.sample"

  output="$(run_thpm "$home_dir" enable discord-system24)"
  assert_contains "$output" "Plugin Enabled: discord-system24" "thpm enables discord system24 plugin"
  assert_contains "$output" "Disabled conflicting Discord plugin: discord" "thpm disables plain discord when enabling system24"
  assert_file_exists "$hook_dir/10-discord.sh.sample" "thpm moves plain discord to sample when system24 is enabled"
  assert_file_exists "$hook_dir/11-discord-system24.sh" "thpm enables discord system24 hook"

  output="$(run_thpm "$home_dir" enable discord)"
  assert_contains "$output" "Plugin Enabled: discord" "thpm enables plain discord plugin"
  assert_contains "$output" "Disabled conflicting Discord plugin: discord-system24" "thpm disables system24 when enabling plain discord"
  assert_file_exists "$hook_dir/10-discord.sh" "thpm enables plain discord hook"
  assert_file_exists "$hook_dir/11-discord-system24.sh.sample" "thpm moves discord system24 to sample when plain discord is enabled"
}

test_thpm_manages_custom_hooks() {
  local home_dir="$TMP_ROOT/thpm-custom-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output

  mkdir -p "$hook_dir"
  printf '#!/usr/bin/env bash\n' > "$hook_dir/05-local.sh"
  printf '#!/usr/bin/env bash\n' > "$hook_dir/99-custom-widget.sh.sample"

  output="$(run_thpm "$home_dir" list)"
  assert_contains "$output" "local" "thpm list includes enabled custom hook"
  assert_contains "$output" "custom-widget" "thpm list includes disabled custom hook"

  output="$(run_thpm "$home_dir" enable custom-widget)"
  assert_contains "$output" "Plugin Enabled: custom-widget" "thpm enables custom hook by suffix name"
  assert_file_exists "$hook_dir/99-custom-widget.sh" "thpm restores custom hook .sh suffix"
  assert_file_missing "$hook_dir/99-custom-widget.sh.sample" "thpm removes custom hook .sample suffix"

  output="$(run_thpm "$home_dir" disable custom-widget)"
  assert_contains "$output" "Plugin Disabled: custom-widget" "thpm disables custom hook by suffix name"
  assert_file_exists "$hook_dir/99-custom-widget.sh.sample" "thpm adds custom hook .sample suffix"
  assert_file_missing "$hook_dir/99-custom-widget.sh" "thpm removes active custom hook file"
}

test_thpm_reads_hook_dir_from_config() {
  local home_dir="$TMP_ROOT/thpm-config-home"
  local config_dir="$home_dir/.config/thpm"
  local hook_dir="$home_dir/custom-hooks"
  local output

  mkdir -p "$config_dir" "$hook_dir"
  cat > "$config_dir/config.toml" <<'EOF'
[paths]
hook_dir = "~/custom-hooks"
EOF
  printf '#!/usr/bin/env bash\n' > "$hook_dir/10-configured.sh"

  output="$(HOME="$home_dir" XDG_CONFIG_HOME="$home_dir/.config" "$ROOT_DIR/thpm" list 2>&1)"

  assert_contains "$output" "configured" "thpm reads hook directory from config.toml"
}

test_thpm_env_hook_dir_overrides_config() {
  local home_dir="$TMP_ROOT/thpm-env-config-home"
  local config_dir="$home_dir/.config/thpm"
  local configured_hook_dir="$home_dir/configured-hooks"
  local env_hook_dir="$home_dir/env-hooks"
  local output

  mkdir -p "$config_dir" "$configured_hook_dir" "$env_hook_dir"
  cat > "$config_dir/config.toml" <<'EOF'
[paths]
hook_dir = "~/configured-hooks"
EOF
  printf '#!/usr/bin/env bash\n' > "$configured_hook_dir/10-configured.sh"
  printf '#!/usr/bin/env bash\n' > "$env_hook_dir/10-env.sh"

  output="$(HOME="$home_dir" XDG_CONFIG_HOME="$home_dir/.config" THPM_HOOK_DIR="$env_hook_dir" "$ROOT_DIR/thpm" list 2>&1)"

  assert_contains "$output" "env" "THPM_HOOK_DIR overrides configured hook directory"
  assert_not_contains "$output" "configured" "config hook directory is ignored when THPM_HOOK_DIR is set"
}

test_thpm_list_reports_available_update() {
  local home_dir="$TMP_ROOT/thpm-update-home"
  local bin_dir="$TMP_ROOT/thpm-update-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local version_file="$home_dir/.local/share/thpm/version"
  local output

  mkdir -p "$hook_dir" "$bin_dir" "$(dirname "$version_file")"
  printf '#!/usr/bin/env bash\n' > "$hook_dir/10-fzf.sh"
  cat > "$version_file" <<'EOF'
repo=https://github.com/OldJobobo/theme-hook-plugin-manager.git
branch=thpm
commit=local-commit
EOF
  cat > "$bin_dir/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "ls-remote" ]]; then
  printf '%s\t%s\n' "remote-commit" "refs/heads/thpm"
fi
EOF
  chmod +x "$bin_dir/git"

  output="$(run_thpm_with_path "$home_dir" "$bin_dir" list)"

  assert_contains "$output" "Update available: run thpm update" "thpm list reports available update"
  assert_contains "$(cat "$home_dir/.local/share/thpm/update-check")" "status=update_available" "thpm caches update availability"
}

test_thpm_help_reports_cached_update_without_network() {
  local home_dir="$TMP_ROOT/thpm-help-update-home"
  local bin_dir="$TMP_ROOT/thpm-help-update-bin"
  local version_file="$home_dir/.local/share/thpm/version"
  local cache_file="$home_dir/.local/share/thpm/update-check"
  local output
  local now

  now=$(date +%s)
  mkdir -p "$bin_dir" "$(dirname "$version_file")"
  cat > "$version_file" <<'EOF'
repo=https://github.com/OldJobobo/theme-hook-plugin-manager.git
branch=thpm
commit=local-commit
EOF
  cat > "$cache_file" <<EOF
checked_at=$now
status=update_available
remote_commit=remote-commit
EOF
  make_stub_bin "$bin_dir" git 'printf "git should not be called when cache is fresh\n" >&2; exit 1'

  output="$(run_thpm_with_path "$home_dir" "$bin_dir" help)"

  assert_contains "$output" "Update available: run thpm update" "thpm help reports cached update"
}

test_thpm_aliases() {
  local home_dir="$TMP_ROOT/alias-home"
  local bin_dir="$TMP_ROOT/alias-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output

  mkdir -p "$hook_dir" "$bin_dir"
  printf '#!/usr/bin/env bash\n' > "$hook_dir/10-fzf.sh.sample"
  make_stub_bin "$bin_dir" omarchy-hook 'printf "omarchy-hook %s\n" "$*"'
  make_stub_bin "$bin_dir" curl 'printf "curl %s\n" "$*"'

  output="$(run_thpm "$home_dir" l)"
  assert_contains "$output" "Disabled Plugins:" "thpm l aliases list"

  output="$(run_thpm "$home_dir" e fzf)"
  assert_contains "$output" "Plugin Enabled: fzf" "thpm e aliases enable"

  output="$(run_thpm "$home_dir" d fzf)"
  assert_contains "$output" "Plugin Disabled: fzf" "thpm d aliases disable"

  output="$(run_thpm_with_path "$home_dir" "$bin_dir" r)"
  assert_contains "$output" "omarchy-hook theme-set" "thpm r aliases run"

  output="$(run_thpm_with_path "$home_dir" "$bin_dir" up)"
  assert_contains "$output" "raw.githubusercontent.com/OldJobobo/theme-hook-plugin-manager/thpm/install.sh" "thpm up aliases update"

  output="$(run_thpm_with_path "$home_dir" "$bin_dir" rm)"
  assert_contains "$output" "raw.githubusercontent.com/OldJobobo/theme-hook-plugin-manager/thpm/uninstall.sh" "thpm rm aliases uninstall"
}

test_thpm_doctor_reports_missing_colors() {
  local home_dir="$TMP_ROOT/doctor-missing-colors-home"
  local bin_dir="$TMP_ROOT/doctor-missing-colors-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output
  local status

  mkdir -p "$hook_dir" "$bin_dir"
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'

  set +e
  output="$(PATH="$bin_dir:$PATH" THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" "$ROOT_DIR/thpm" doctor 2>&1)"
  status=$?
  set +e

  assert_eq "1" "$status" "thpm doctor exits non-zero when colors.toml is missing"
  assert_contains "$output" "THPM Doctor" "thpm doctor prints report title"
  assert_contains "$output" "colors.toml missing" "thpm doctor reports missing colors.toml"
}

test_thpm_doctor_warns_for_missing_plugin_command() {
  local home_dir="$TMP_ROOT/doctor-plugin-command-home"
  local bin_dir="$TMP_ROOT/doctor-plugin-command-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output
  local status

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  printf '#!/usr/bin/env bash\nsource "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"\n' > "$hook_dir/10-spotify.sh"
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'

  set +e
  output="$(PATH="$bin_dir:$PATH" THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" "$ROOT_DIR/thpm" doctor 2>&1)"
  status=$?
  set +e

  assert_eq "0" "$status" "thpm doctor exits successfully with warnings only"
  assert_contains "$output" "spotify:" "thpm doctor checks enabled spotify plugin"
  assert_contains "$output" "Spicetify command missing" "thpm doctor warns about missing plugin command"
  assert_contains "$output" "0 error(s)" "thpm doctor summarizes warnings without errors"
}

test_thpm_doctor_reports_broken_hook_syntax() {
  local home_dir="$TMP_ROOT/doctor-broken-hook-home"
  local bin_dir="$TMP_ROOT/doctor-broken-hook-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output
  local status

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  printf '#!/usr/bin/env bash\nif true\n' > "$hook_dir/99-broken.sh"
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'

  set +e
  output="$(PATH="$bin_dir:$PATH" THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" "$ROOT_DIR/thpm" doctor 2>&1)"
  status=$?
  set +e

  assert_eq "1" "$status" "thpm doctor exits non-zero for broken hook syntax"
  assert_contains "$output" "broken:" "thpm doctor names broken hook"
  assert_contains "$output" "shell syntax fails" "thpm doctor reports hook syntax failure"
}

test_thpm_doctor_reports_firefox_profile_issue() {
  local home_dir="$TMP_ROOT/doctor-firefox-home"
  local bin_dir="$TMP_ROOT/doctor-firefox-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/40-firefox.sh" "$hook_dir/40-firefox.sh"
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" firefox 'exit 0'

  output="$(PATH="$bin_dir:$PATH" THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" "$ROOT_DIR/thpm" doctor firefox 2>&1)"

  assert_contains "$output" "firefox:" "thpm doctor checks requested firefox plugin"
  assert_contains "$output" "Firefox profiles.ini missing" "thpm doctor reports missing firefox profile"
}

test_thpm_doctor_zen_reports_missing_generated_files() {
  local home_dir="$TMP_ROOT/doctor-zen-missing-files-home"
  local bin_dir="$TMP_ROOT/doctor-zen-missing-files-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local profile_dir="$home_dir/.zen/default"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$profile_dir"
  cp "$ROOT_DIR/theme-set.d/40-zen.sh" "$hook_dir/40-zen.sh"
  cat > "$home_dir/.zen/profiles.ini" <<'EOF'
[Install123]
Default=default
EOF
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" zen-browser 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'

  output="$(PATH="$bin_dir:$PATH" THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" "$ROOT_DIR/thpm" doctor zen 2>&1)"

  assert_contains "$output" "Zen managed colors stylesheet missing" "thpm doctor zen reports missing generated colors"
  assert_contains "$output" "Zen userChrome.css missing" "thpm doctor zen reports missing userChrome import file"
  assert_contains "$output" "run thpm run" "thpm doctor zen suggests rerunning theme hook"
}

test_thpm_doctor_zen_reports_late_import_overrides() {
  local home_dir="$TMP_ROOT/doctor-zen-late-import-home"
  local bin_dir="$TMP_ROOT/doctor-zen-late-import-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local profile_dir="$home_dir/.zen/default"
  local chrome_dir="$profile_dir/chrome"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$chrome_dir"
  cp "$ROOT_DIR/theme-set.d/40-zen.sh" "$hook_dir/40-zen.sh"
  cat > "$home_dir/.zen/profiles.ini" <<'EOF'
[Install123]
Default=default
EOF
  printf '/* colors */\n' > "$chrome_dir/thpm-zen-colors.css"
  printf '/* chrome */\n' > "$chrome_dir/thpm-zen-userChrome.css"
  printf '/* content */\n' > "$chrome_dir/thpm-zen-userContent.css"
  cat > "$chrome_dir/userChrome.css" <<'EOF'
/* THPM Zen hook start */
@import url("./thpm-zen-colors.css");
@import url("./thpm-zen-userChrome.css");
/* THPM Zen hook end */
@import url("./custom.css");
EOF
  cat > "$chrome_dir/userContent.css" <<'EOF'
/* THPM Zen hook start */
@import url("./thpm-zen-colors.css");
@import url("./thpm-zen-userContent.css");
/* THPM Zen hook end */
EOF
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" zen-browser 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'

  output="$(PATH="$bin_dir:$PATH" THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" "$ROOT_DIR/thpm" doctor zen 2>&1)"

  assert_contains "$output" "Zen managed colors stylesheet found" "thpm doctor zen reports generated colors"
  assert_contains "$output" "Zen userChrome.css has THPM managed import block" "thpm doctor zen reports import block"
  assert_contains "$output" "may override Zen theme CSS" "thpm doctor zen warns about later imports"
}

test_thpm_doctor_zen_accepts_existing_import_variants() {
  local home_dir="$TMP_ROOT/doctor-zen-import-variant-home"
  local bin_dir="$TMP_ROOT/doctor-zen-import-variant-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local profile_dir="$home_dir/.zen/default"
  local chrome_dir="$profile_dir/chrome"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$chrome_dir"
  cp "$ROOT_DIR/theme-set.d/40-zen.sh" "$hook_dir/40-zen.sh"
  cat > "$home_dir/.zen/profiles.ini" <<'EOF'
[Install123]
Default=default
EOF
  printf '/* colors */\n' > "$chrome_dir/thpm-zen-colors.css"
  printf '/* chrome */\n' > "$chrome_dir/thpm-zen-userChrome.css"
  printf '/* content */\n' > "$chrome_dir/thpm-zen-userContent.css"
  cat > "$chrome_dir/userChrome.css" <<'EOF'
/* THPM Zen hook start */
@import url("thpm-zen-colors.css");
@import url("thpm-zen-userChrome.css");
/* THPM Zen hook end */
EOF
  cat > "$chrome_dir/userContent.css" <<'EOF'
/* THPM Zen hook start */
@import url('thpm-zen-colors.css');
@import url('thpm-zen-userContent.css');
/* THPM Zen hook end */
EOF
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" zen-browser 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'

  output="$(PATH="$bin_dir:$PATH" THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" "$ROOT_DIR/thpm" doctor zen 2>&1)"

  assert_contains "$output" "Zen userChrome.css imports THPM Zen stylesheets" "thpm doctor zen accepts import syntax variants in userChrome"
  assert_contains "$output" "Zen userContent.css imports THPM Zen stylesheets" "thpm doctor zen accepts import syntax variants in userContent"
  assert_not_contains "$output" "does not reference thpm-zen-colors.css" "thpm doctor zen avoids false import warning for syntax variants"
}

test_thpm_doctor_zen_reports_stale_frame_rules() {
  local home_dir="$TMP_ROOT/doctor-zen-stale-frame-home"
  local bin_dir="$TMP_ROOT/doctor-zen-stale-frame-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local profile_dir="$home_dir/.zen/default"
  local chrome_dir="$profile_dir/chrome"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$chrome_dir"
  cp "$ROOT_DIR/theme-set.d/40-zen.sh" "$hook_dir/40-zen.sh"
  cat > "$home_dir/.zen/profiles.ini" <<'EOF'
[Install123]
Default=default
EOF
  printf '/* colors */\n' > "$chrome_dir/thpm-zen-colors.css"
  printf '#navigator-toolbox { background: var(--base00); }\n' > "$chrome_dir/thpm-zen-userChrome.css"
  printf '/* content */\n' > "$chrome_dir/thpm-zen-userContent.css"
  cat > "$chrome_dir/userChrome.css" <<'EOF'
/* THPM Zen hook start */
@import url("./thpm-zen-colors.css");
@import url("./thpm-zen-userChrome.css");
/* THPM Zen hook end */
EOF
  cat > "$chrome_dir/userContent.css" <<'EOF'
/* THPM Zen hook start */
@import url("./thpm-zen-colors.css");
@import url("./thpm-zen-userContent.css");
/* THPM Zen hook end */
EOF
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" zen-browser 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'

  output="$(PATH="$bin_dir:$PATH" THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" "$ROOT_DIR/thpm" doctor zen 2>&1)"

  assert_contains "$output" "Zen managed browser chrome stylesheet is stale" "thpm doctor zen reports stale frame rules"
  assert_contains "$output" "run thpm run" "thpm doctor zen suggests regenerating stale frame rules"
}

test_thpm_doctor_limits_plugin_specific_checks() {
  local home_dir="$TMP_ROOT/doctor-specific-home"
  local bin_dir="$TMP_ROOT/doctor-specific-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  printf '#!/usr/bin/env bash\nsource "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"\n' > "$hook_dir/10-spotify.sh"
  printf '#!/usr/bin/env bash\nsource "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"\n' > "$hook_dir/40-firefox.sh"
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'

  output="$(PATH="$bin_dir:$PATH" THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" "$ROOT_DIR/thpm" doctor spotify 2>&1)"

  assert_contains "$output" "spotify:" "thpm doctor checks requested plugin"
  assert_not_contains "$output" "firefox:" "thpm doctor does not check unrelated plugins when a plugin is requested"
}

test_thpm_doctor_warns_when_runtime_source_is_only_commented() {
  local home_dir="$TMP_ROOT/doctor-commented-source-home"
  local bin_dir="$TMP_ROOT/doctor-commented-source-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cat > "$hook_dir/99-commented-source.sh" <<'EOF'
#!/usr/bin/env bash
# source "${THPM_THEME_ENV:-$HOME/.local/share/thpm/lib/theme-env.sh}"
printf 'not actually sourced\n'
EOF
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'

  output="$(PATH="$bin_dir:$PATH" THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" "$ROOT_DIR/thpm" doctor commented-source 2>&1)"

  assert_contains "$output" "commented-source:" "thpm doctor checks hook with commented source line"
  assert_contains "$output" "does not appear to source shared thpm runtime" "thpm doctor ignores commented runtime source references"
  assert_not_contains "$output" "sources shared thpm runtime" "thpm doctor does not accept comments as runtime sourcing"
}

test_thpm_open_uses_xdg_open_for_hook_dir() {
  local home_dir="$TMP_ROOT/open-home"
  local bin_dir="$TMP_ROOT/open-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local open_log="$TMP_ROOT/xdg-open.log"

  mkdir -p "$hook_dir" "$bin_dir"
  cat > "$bin_dir/xdg-open" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$open_log"
EOF
  chmod +x "$bin_dir/xdg-open"

  run_thpm_with_path "$home_dir" "$bin_dir" open >/dev/null
  for _ in $(seq 1 20); do
    [[ -f "$open_log" ]] && break
    sleep 0.05
  done

  assert_file_exists "$open_log" "thpm open calls xdg-open when hook directory exists"
  assert_eq "$hook_dir" "$(cat "$open_log")" "thpm open passes hook directory to xdg-open"
}

test_thpm_gtk_post_enable_disable_updates_gsettings() {
  local home_dir="$TMP_ROOT/gtk-home"
  local bin_dir="$TMP_ROOT/gtk-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local gsettings_log="$TMP_ROOT/gsettings.log"

  mkdir -p "$hook_dir" "$bin_dir" "$home_dir/.local/state/omarchy/current/theme"
  printf '#!/usr/bin/env bash\n' > "$hook_dir/10-gtk.sh.sample"
  cat > "$bin_dir/gsettings" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$gsettings_log"
EOF
  chmod +x "$bin_dir/gsettings"

  run_thpm_with_path "$home_dir" "$bin_dir" enable gtk >/dev/null
  run_thpm_with_path "$home_dir" "$bin_dir" disable gtk >/dev/null

  assert_contains "$(cat "$gsettings_log")" "set org.gnome.desktop.interface gtk-theme adw-gtk3-tmp-dark" "gtk enable sets temporary dark theme"
  assert_contains "$(cat "$gsettings_log")" "set org.gnome.desktop.interface gtk-theme adw-gtk3-dark" "gtk enable sets dark theme"
  assert_contains "$(cat "$gsettings_log")" "set org.gnome.desktop.interface gtk-theme Adwaita-dark" "gtk disable restores dark theme"
}

test_theme_set_exports_colors_and_runs_enabled_hooks() {
  local home_dir="$TMP_ROOT/theme-set-home"
  local bin_dir="$TMP_ROOT/bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output_file="$TMP_ROOT/hook-output"
  local skipped_file="$TMP_ROOT/skipped-output"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'printf "notify-send should not be called\n" >&2; exit 1'

  cat > "$hook_dir/10-capture.sh" <<EOF
#!/usr/bin/env bash
source "$ROOT_DIR/lib/theme-env.sh"
{
  printf 'primary_background=%s\n' "\$primary_background"
  printf 'primary_foreground=%s\n' "\$primary_foreground"
  printf 'cursor_color=%s\n' "\$cursor_color"
  printf 'rgb_primary_background=%s\n' "\$rgb_primary_background"
  printf 'rgb_cursor_color=%s\n' "\$rgb_cursor_color"
  printf 'rgb_selection_background=%s\n' "\$rgb_selection_background"
  printf 'rgb_selection_foreground=%s\n' "\$rgb_selection_foreground"
  printf 'normal_red=%s\n' "\$normal_red"
  printf 'bright_white=%s\n' "\$bright_white"
} > "$output_file"
require_restart nonexistent-app
EOF

  cat > "$hook_dir/20-disabled.sh" <<EOF
#!/usr/bin/env bash
printf 'disabled hook ran\n' > "$skipped_file"
EOF
  mv "$hook_dir/20-disabled.sh" "$hook_dir/20-disabled.sh.sample"

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir"

  assert_contains "$(cat "$output_file")" "primary_background=101112" "theme-set exports background color"
  assert_contains "$(cat "$output_file")" "primary_foreground=f1f2f3" "theme-set exports foreground color"
  assert_contains "$(cat "$output_file")" "cursor_color=abcdef" "theme-set exports cursor color"
  assert_contains "$(cat "$output_file")" "rgb_primary_background=16, 17, 18" "theme-set exports rgb background"
  assert_contains "$(cat "$output_file")" "rgb_cursor_color=171, 205, 239" "theme-set exports rgb cursor color"
  assert_contains "$(cat "$output_file")" "rgb_selection_background=34, 34, 34" "theme-set exports rgb selection background"
  assert_contains "$(cat "$output_file")" "rgb_selection_foreground=238, 238, 238" "theme-set exports rgb selection foreground"
  assert_contains "$(cat "$output_file")" "normal_red=111111" "theme-set exports normal palette color"
  assert_contains "$(cat "$output_file")" "bright_white=ffffff" "theme-set exports bright palette color"

  if [[ -e "$skipped_file" ]]; then
    fail "theme-set skips .sample hooks"
  else
    pass "theme-set skips .sample hooks"
  fi
}

test_theme_set_handles_commented_palette_color() {
  local home_dir="$TMP_ROOT/commented-palette-home"
  local bin_dir="$TMP_ROOT/commented-palette-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output_file="$TMP_ROOT/commented-palette-output"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'
  sed -i 's/^color0 =/# color0 =/' "$home_dir/.local/state/omarchy/current/theme/colors.toml"

  cat > "$hook_dir/10-capture.sh" <<EOF
#!/usr/bin/env bash
source "$ROOT_DIR/lib/theme-env.sh"
{
  printf 'normal_black=%s\n' "\$normal_black"
  printf 'rgb_normal_black=%s\n' "\$rgb_normal_black"
} > "$output_file"
EOF

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir"

  assert_contains "$(cat "$output_file")" "normal_black=" "theme-set leaves missing commented palette color empty"
  assert_contains "$(cat "$output_file")" "rgb_normal_black=0, 0, 0" "theme-set defaults missing commented palette rgb to black"
}

test_theme_env_errors_without_colors_file() {
  local home_dir="$TMP_ROOT/missing-colors-home"
  local output
  local status

  mkdir -p "$home_dir"
  cat > "$home_dir/missing-colors-hook.sh" <<EOF
#!/usr/bin/env bash
source "$ROOT_DIR/lib/theme-env.sh"
EOF
  set +e
  output="$(HOME="$home_dir" bash "$home_dir/missing-colors-hook.sh" 2>&1)"
  status=$?
  set +e

  assert_eq "1" "$status" "theme env exits non-zero without colors.toml"
  assert_contains "$output" "colors.toml not found" "theme env explains missing colors.toml"
}

test_theme_set_reports_hook_failure() {
  local home_dir="$TMP_ROOT/failing-hook-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output
  local status

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir"
  cat > "$hook_dir/10-fail.sh" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF

  set +e
  output="$(run_theme_hooks "$home_dir" 2>&1)"
  status=$?
  set +e

  assert_eq "0" "$status" "theme hook runner continues when an enabled hook fails"
  assert_contains "$output" "Hook failed: $hook_dir/10-fail.sh" "theme hook runner names failed hook"
}

test_theme_set_sends_restart_notification() {
  local home_dir="$TMP_ROOT/restart-home"
  local bin_dir="$TMP_ROOT/restart-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local notify_log="$TMP_ROOT/notify.log"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  make_stub_bin "$bin_dir" pgrep '[[ "$2" == "sampleapp" ]]'
  cat > "$bin_dir/notify-send" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$notify_log"
EOF
  chmod +x "$bin_dir/notify-send"

  cat > "$hook_dir/10-restart.sh" <<'EOF'
#!/usr/bin/env bash
source "$THPM_THEME_ENV"
require_restart sampleapp
EOF

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir"

  assert_file_exists "$notify_log" "theme-set sends notification for running restart target"
  assert_contains "$(cat "$notify_log")" "Theme Hook Plugin Manager" "restart notification has title"
  assert_contains "$(cat "$notify_log")" "Sampleapp" "restart notification lists running app"
}

test_theme_env_reads_colors_file_from_config() {
  local home_dir="$TMP_ROOT/theme-env-config-colors-home"
  local config_dir="$home_dir/.config/thpm"
  local colors_file="$home_dir/custom-colors.toml"
  local output_file="$TMP_ROOT/config-colors-output"

  mkdir -p "$config_dir"
  write_colors_fixture "$home_dir/default"
  cp "$home_dir/default/.local/state/omarchy/current/theme/colors.toml" "$colors_file"
  cat > "$config_dir/config.toml" <<'EOF'
[paths]
colors_file = "~/custom-colors.toml"
EOF
  cat > "$home_dir/config-colors-hook.sh" <<EOF
#!/usr/bin/env bash
source "$ROOT_DIR/lib/theme-env.sh"
printf '%s\n' "\$primary_background" > "$output_file"
EOF

  HOME="$home_dir" XDG_CONFIG_HOME="$home_dir/.config" bash "$home_dir/config-colors-hook.sh"

  assert_eq "101112" "$(cat "$output_file")" "theme env reads colors_file from config.toml"
}

test_theme_env_prefers_quattro_theme_with_legacy_default_config() {
  local home_dir="$TMP_ROOT/theme-env-quattro-default-home"
  local config_dir="$home_dir/.config/thpm"
  local output_file="$TMP_ROOT/quattro-default-output"

  write_colors_fixture "$home_dir"
  mkdir -p "$config_dir"
  cat > "$config_dir/config.toml" <<'EOF'
[paths]
colors_file = "~/.config/omarchy/current/theme/colors.toml"
EOF
  cat > "$home_dir/quattro-default-hook.sh" <<EOF
#!/usr/bin/env bash
source "$ROOT_DIR/lib/theme-env.sh"
printf '%s|%s\n' "\$primary_background" "\$THPM_CURRENT_THEME_DIR" > "$output_file"
EOF

  HOME="$home_dir" XDG_CONFIG_HOME="$home_dir/.config" bash "$home_dir/quattro-default-hook.sh"

  assert_eq "101112|$home_dir/.local/state/omarchy/current/theme" "$(cat "$output_file")" "theme env prefers Quattro theme over legacy default config path"
}

test_theme_env_falls_back_to_legacy_theme_dir() {
  local home_dir="$TMP_ROOT/theme-env-legacy-fallback-home"
  local legacy_theme_dir="$home_dir/.config/omarchy/current/theme"
  local output_file="$TMP_ROOT/legacy-fallback-output"

  write_colors_fixture "$home_dir/source"
  mkdir -p "$legacy_theme_dir"
  cp "$home_dir/source/.local/state/omarchy/current/theme/colors.toml" "$legacy_theme_dir/colors.toml"
  cat > "$home_dir/legacy-fallback-hook.sh" <<EOF
#!/usr/bin/env bash
source "$ROOT_DIR/lib/theme-env.sh"
printf '%s|%s\n' "\$primary_background" "\$THPM_CURRENT_THEME_DIR" > "$output_file"
EOF

  HOME="$home_dir" XDG_CONFIG_HOME="$home_dir/.config" bash "$home_dir/legacy-fallback-hook.sh"

  assert_eq "101112|$legacy_theme_dir" "$(cat "$output_file")" "theme env falls back to legacy Omarchy theme directory"
}

test_thpm_doctor_uses_quattro_theme_with_legacy_default_config() {
  local home_dir="$TMP_ROOT/doctor-quattro-default-home"
  local config_dir="$home_dir/.config/thpm"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local runtime_dir="$home_dir/.local/share/thpm/lib"
  local output
  local status

  write_colors_fixture "$home_dir"
  mkdir -p "$config_dir" "$hook_dir" "$runtime_dir"
  cp "$ROOT_DIR/lib/theme-env.sh" "$runtime_dir/theme-env.sh"
  cat > "$config_dir/config.toml" <<'EOF'
[paths]
colors_file = "~/.config/omarchy/current/theme/colors.toml"
EOF

  set +e
  output="$(run_thpm "$home_dir" doctor 2>&1)"
  status=$?
  set +e

  assert_success "$status" "thpm doctor succeeds with Quattro theme and legacy default config path"
  assert_contains "$output" "colors.toml found: $home_dir/.local/state/omarchy/current/theme/colors.toml" "thpm doctor reports resolved Quattro colors path"
  assert_not_contains "$output" "colors.toml missing" "thpm doctor does not report missing legacy colors path"
}

test_restart_notification_can_be_disabled_globally() {
  local home_dir="$TMP_ROOT/restart-global-disabled-home"
  local bin_dir="$TMP_ROOT/restart-global-disabled-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local notify_log="$TMP_ROOT/restart-global-disabled-notify.log"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$home_dir/.config/thpm"
  cat > "$home_dir/.config/thpm/config.toml" <<'EOF'
[notifications.restart]
enabled = false
EOF
  make_stub_bin "$bin_dir" pgrep '[[ "$2" == "steam" ]]'
  cat > "$bin_dir/notify-send" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$notify_log"
EOF
  chmod +x "$bin_dir/notify-send"
  cat > "$hook_dir/10-restart.sh" <<'EOF'
#!/usr/bin/env bash
source "$THPM_THEME_ENV"
require_restart steam
EOF

  XDG_CONFIG_HOME="$home_dir/.config" PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir"

  assert_file_missing "$notify_log" "restart notification can be disabled globally"
}

test_restart_notification_can_be_disabled_for_app() {
  local home_dir="$TMP_ROOT/restart-app-disabled-home"
  local bin_dir="$TMP_ROOT/restart-app-disabled-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local notify_log="$TMP_ROOT/restart-app-disabled-notify.log"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$home_dir/.config/thpm"
  cat > "$home_dir/.config/thpm/config.toml" <<'EOF'
[notifications.restart.apps]
nautilus = false
EOF
  make_stub_bin "$bin_dir" pgrep '[[ "$2" == "nautilus" ]]'
  cat > "$bin_dir/notify-send" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$notify_log"
EOF
  chmod +x "$bin_dir/notify-send"
  cat > "$hook_dir/10-restart.sh" <<'EOF'
#!/usr/bin/env bash
source "$THPM_THEME_ENV"
require_restart nautilus
EOF

  XDG_CONFIG_HOME="$home_dir/.config" PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir"

  assert_file_missing "$notify_log" "restart notification can be disabled for one app"
}

test_restart_notification_supports_stdout_and_not_running() {
  local home_dir="$TMP_ROOT/restart-stdout-home"
  local bin_dir="$TMP_ROOT/restart-stdout-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$home_dir/.config/thpm"
  cat > "$home_dir/.config/thpm/config.toml" <<'EOF'
[notifications]
backend = "stdout"

[notifications.restart]
only_when_running = false
message = "Restart {app} after theming."
cooldown_seconds = 0
EOF
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  cat > "$hook_dir/10-restart.sh" <<'EOF'
#!/usr/bin/env bash
source "$THPM_THEME_ENV"
require_restart steam Steam
EOF

  output="$(XDG_CONFIG_HOME="$home_dir/.config" PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" 2>&1)"

  assert_contains "$output" "Restart Steam after theming." "restart notification can use stdout without a running process"
}

test_branding_plugin_copies_theme_branding() {
  local home_dir="$TMP_ROOT/branding-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local theme_dir="$home_dir/.local/state/omarchy/current/theme"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir"
  printf 'about from theme\n' > "$theme_dir/about.txt"
  printf 'screensaver from theme\n' > "$theme_dir/screensaver.txt"
  cp "$ROOT_DIR/theme-set.d/10-branding.sh" "$hook_dir/10-branding.sh"

  run_theme_hooks "$home_dir" >/dev/null

  assert_eq "about from theme" "$(cat "$home_dir/.config/omarchy/branding/about.txt")" "branding plugin copies theme about.txt"
  assert_eq "screensaver from theme" "$(cat "$home_dir/.config/omarchy/branding/screensaver.txt")" "branding plugin copies theme screensaver.txt"
}

test_branding_plugin_preserves_missing_sources() {
  local home_dir="$TMP_ROOT/branding-partial-home"
  local theme_dir="$home_dir/.local/state/omarchy/current/theme"
  local branding_dir="$home_dir/.config/omarchy/branding"

  write_colors_fixture "$home_dir"
  mkdir -p "$branding_dir"
  printf 'old about\n' > "$branding_dir/about.txt"
  printf 'old screensaver\n' > "$branding_dir/screensaver.txt"
  printf 'new about\n' > "$theme_dir/about.txt"

  THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" bash "$ROOT_DIR/theme-set.d/10-branding.sh" >/dev/null

  assert_eq "new about" "$(cat "$branding_dir/about.txt")" "branding plugin updates available source"
  assert_eq "old screensaver" "$(cat "$branding_dir/screensaver.txt")" "branding plugin preserves missing screensaver source target"
}

test_branding_plugin_skips_without_theme_branding() {
  local home_dir="$TMP_ROOT/branding-missing-home"
  local branding_dir="$home_dir/.config/omarchy/branding"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$branding_dir"
  printf 'old about\n' > "$branding_dir/about.txt"
  printf 'old screensaver\n' > "$branding_dir/screensaver.txt"

  output="$(THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" bash "$ROOT_DIR/theme-set.d/10-branding.sh" 2>&1)"

  assert_contains "$output" "Omarchy branding not found. Skipping.." "branding plugin skips when theme has no branding files"
  assert_eq "old about" "$(cat "$branding_dir/about.txt")" "branding plugin preserves about target when skipping"
  assert_eq "old screensaver" "$(cat "$branding_dir/screensaver.txt")" "branding plugin preserves screensaver target when skipping"
}

test_branding_plugin_disable_stops_sync_until_enabled() {
  local home_dir="$TMP_ROOT/branding-disable-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local theme_dir="$home_dir/.local/state/omarchy/current/theme"
  local branding_dir="$home_dir/.config/omarchy/branding"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir"
  cp "$ROOT_DIR/theme-set.d/10-branding.sh" "$hook_dir/10-branding.sh"
  printf 'about v1\n' > "$theme_dir/about.txt"
  printf 'screensaver v1\n' > "$theme_dir/screensaver.txt"
  run_theme_hooks "$home_dir" >/dev/null

  output="$(run_thpm "$home_dir" disable branding)"
  assert_contains "$output" "Plugin Disabled: branding" "thpm disable branding reports disabled plugin"
  assert_file_exists "$hook_dir/10-branding.sh.sample" "thpm disable branding creates sample hook"
  assert_file_missing "$hook_dir/10-branding.sh" "thpm disable branding removes active hook"

  printf 'about v2\n' > "$theme_dir/about.txt"
  printf 'screensaver v2\n' > "$theme_dir/screensaver.txt"
  run_theme_hooks "$home_dir" >/dev/null

  assert_eq "about v1" "$(cat "$branding_dir/about.txt")" "disabled branding plugin leaves about target unchanged"
  assert_eq "screensaver v1" "$(cat "$branding_dir/screensaver.txt")" "disabled branding plugin leaves screensaver target unchanged"

  output="$(run_thpm "$home_dir" enable branding)"
  assert_contains "$output" "Plugin Enabled: branding" "thpm enable branding reports enabled plugin"
  run_theme_hooks "$home_dir" >/dev/null

  assert_eq "about v2" "$(cat "$branding_dir/about.txt")" "re-enabled branding plugin updates about target"
  assert_eq "screensaver v2" "$(cat "$branding_dir/screensaver.txt")" "re-enabled branding plugin updates screensaver target"
}

test_hook_plugins_use_portable_assumption_guards() {
  assert_not_contains "$(cat "$ROOT_DIR/theme-set.d/10-discord.sh")" 'themes",' "discord plugin has no comma-suffixed Flatpak path"
  assert_contains "$(cat "$ROOT_DIR/theme-set.d/10-discord.sh")" '$HOME/.var/app/com.discordapp.Discord/config/Vencord/themes' "discord plugin checks user Flatpak Discord path"
  assert_not_contains "$(cat "$ROOT_DIR/theme-set.d/11-discord-system24.sh")" 'themes",' "discord system24 plugin has no comma-suffixed Flatpak path"
  assert_contains "$(cat "$ROOT_DIR/theme-set.d/11-discord-system24.sh")" '$HOME/.var/app/com.discordapp.Discord/config/Vencord/themes' "discord system24 plugin checks user Flatpak Discord path"
  assert_contains "$(cat "$ROOT_DIR/theme-set.d/30-vscode.sh")" "command -v jq" "vscode plugin guards jq dependency"
  assert_contains "$(cat "$ROOT_DIR/theme-set.d/30-cursor.sh")" "command -v jq" "cursor plugin guards jq dependency"
  assert_contains "$(cat "$ROOT_DIR/theme-set.d/30-windsurf.sh")" "command -v jq" "windsurf plugin guards jq dependency"
  assert_contains "$(cat "$ROOT_DIR/theme-set.d/30-vscode.sh")" 'skipped "VS Code Base16 Tinted Themes extension directory"' "vscode plugin skips missing extension directory"
  assert_contains "$(cat "$ROOT_DIR/theme-set.d/30-cursor.sh")" 'skipped "Cursor Base16 Tinted Themes extension directory"' "cursor plugin skips missing extension directory"
  assert_contains "$(cat "$ROOT_DIR/theme-set.d/40-steam.sh")" "command -v git" "steam plugin guards git dependency"
  assert_not_contains "$(cat "$ROOT_DIR/theme-set.d/40-steam.sh")" "fc-list" "steam plugin does not probe unused fontconfig path"
  assert_not_contains "$(cat "$ROOT_DIR/theme-set.d/40-steam.sh")" "omarchy-font-current" "steam plugin does not assume omarchy-font-current"
  assert_not_contains "$(cat "$ROOT_DIR/theme-set.d/40-qutebrowser.sh")" "grep -oP" "qutebrowser plugin avoids grep -P dependency"
  assert_contains "$(cat "$ROOT_DIR/theme-set.d/35-obsidian-terminal.sh")" "command -v python3" "obsidian terminal plugin guards python3 dependency"
  assert_not_contains "$(cat "$ROOT_DIR/theme-set.d/20-nwg-dock-hyprland.sh")" "eval" "nwg dock plugin avoids eval when restarting dock"
}

test_discord_system24_plugin_writes_theme_and_installs_existing_clients() {
  local home_dir="$TMP_ROOT/discord-system24-home"
  local theme_dir="$home_dir/.local/state/omarchy/current/theme"
  local vencord_dir="$home_dir/.config/Vencord/themes"
  local vesktop_dir="$home_dir/.config/vesktop/themes"
  local missing_dir="$home_dir/.config/Equicord/themes"
  local output
  local generated
  local installed

  write_colors_fixture "$home_dir"
  mkdir -p "$vencord_dir" "$vesktop_dir"
  printf 'old theme\n' > "$vencord_dir/vencord.theme.css"
  printf 'other theme\n' > "$vesktop_dir/other.theme.css"

  output="$(THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" bash "$ROOT_DIR/theme-set.d/11-discord-system24.sh" 2>&1)"
  generated="$theme_dir/vencord-system24.theme.css"
  installed="$vencord_dir/vencord.theme.css"

  assert_contains "$output" "Discord System24 theme updated!" "discord system24 plugin reports success"
  assert_file_exists "$generated" "discord system24 plugin writes generated theme"
  assert_contains "$(cat "$generated")" '@import url("https://refact0r.github.io/system24/build/system24.css");' "discord system24 plugin imports upstream system24 build"
  assert_contains "$(cat "$generated")" "--bg-4: #101112;" "discord system24 plugin uses Omarchy background"
  assert_contains "$(cat "$generated")" "--text-2: #f1f2f3;" "discord system24 plugin uses Omarchy foreground"
  assert_contains "$(cat "$generated")" "--accent-2: #cccccc;" "discord system24 plugin lifts low-contrast blue accent"
  assert_contains "$(cat "$generated")" "--online: #aaaaaa;" "discord system24 plugin lifts low-contrast status colors"
  assert_contains "$(cat "$generated")" "--text-4: #747474;" "discord system24 plugin keeps muted text dim"
  assert_contains "$(cat "$generated")" "--text-5: #5b5b5b;" "discord system24 plugin keeps read channel text dim"
  assert_contains "$(cat "$generated")" "--text-muted: var(--text-5);" "discord system24 plugin maps native Discord muted text to dim role"
  assert_contains "$(cat "$generated")" "--channels-default: var(--text-5);" "discord system24 plugin keeps read channels dim"
  assert_contains "$(cat "$generated")" ':not([class*="modeUnread"]):not([class*="modeSelected"]):not([class*="modeConnected"]):not(:hover)' "discord system24 plugin only dims read channel rows"
  assert_contains "$(cat "$generated")" 'color: var(--text-5) !important;' "discord system24 plugin forces dim read channel text"
  assert_contains "$(cat "$generated")" "--background-primary: var(--bg-4);" "discord system24 plugin maps native Discord background"
  assert_contains "$(cat "$generated")" "--blue-2: #cccccc;" "discord system24 plugin lifts System24 color family roles"
  assert_eq "$(cat "$generated")" "$(cat "$installed")" "discord system24 plugin installs Vencord theme file"
  assert_eq "$(cat "$generated")" "$(cat "$vesktop_dir/vencord.theme.css")" "discord system24 plugin installs Vesktop theme file"
  assert_file_exists "$vesktop_dir/other.theme.css" "discord system24 plugin preserves other theme files"
  assert_file_missing "$missing_dir" "discord system24 plugin does not create missing client theme directories"
}

test_discord_plugin_installs_theme_css_when_switching_back() {
  local home_dir="$TMP_ROOT/discord-plain-switchback-home"
  local theme_dir="$home_dir/.local/state/omarchy/current/theme"
  local state_dir="$home_dir/.local/share/thpm"
  local vesktop_dir="$home_dir/.config/vesktop/themes"
  local theme_css
  local generated
  local installed

  write_colors_fixture "$home_dir"
  mkdir -p "$vesktop_dir"
  theme_css="$theme_dir/vencord.theme.css"
  generated="$state_dir/discord/vencord-base16.theme.css"
  installed="$vesktop_dir/vencord.theme.css"
  printf '/* theme supplied vencord css */\n.theme-marker { color: #123456; }\n' > "$theme_css"
  printf '@import url("https://refact0r.github.io/system24/build/system24.css");\n' > "$installed"

  THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" THPM_STATE_DIR="$state_dir" HOME="$home_dir" bash "$ROOT_DIR/theme-set.d/10-discord.sh" >/dev/null 2>&1

  assert_contains "$(cat "$theme_css")" "theme supplied vencord css" "discord plugin preserves current theme Vencord source"
  assert_file_missing "$generated" "discord plugin skips Base16 fallback when theme Vencord CSS exists"
  assert_not_contains "$(cat "$installed")" "system24" "discord plugin replaces stale System24 client theme"
  assert_eq "$(cat "$theme_css")" "$(cat "$installed")" "discord plugin installs current theme Vencord CSS when switching back"
}

test_discord_plugin_repairs_stale_current_css_from_theme_source() {
  local home_dir="$TMP_ROOT/discord-stale-current-home"
  local theme_dir="$home_dir/.local/state/omarchy/current/theme"
  local source_dir="$home_dir/.config/omarchy/themes/noir"
  local state_dir="$home_dir/.local/share/thpm"
  local vesktop_dir="$home_dir/.config/vesktop/themes"
  local source_css
  local current_css
  local generated
  local installed

  write_colors_fixture "$home_dir"
  mkdir -p "$source_dir" "$vesktop_dir"
  printf 'noir\n' > "$home_dir/.local/state/omarchy/current/theme.name"
  source_css="$source_dir/vencord.theme.css"
  current_css="$theme_dir/vencord.theme.css"
  generated="$state_dir/discord/vencord-base16.theme.css"
  installed="$vesktop_dir/vencord.theme.css"
  printf '/* Noir System24 source */\n@import url("https://refact0r.github.io/system24/build/system24.css");\n' > "$source_css"
  printf '@import url("https://imbypass.github.io/base16-discord/omarchy-discord.theme.css");\n' > "$current_css"
  printf '@import url("https://imbypass.github.io/base16-discord/omarchy-discord.theme.css");\n' > "$installed"

  THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" THPM_STATE_DIR="$state_dir" HOME="$home_dir" bash "$ROOT_DIR/theme-set.d/10-discord.sh" >/dev/null 2>&1

  assert_file_missing "$generated" "discord plugin does not generate Base16 fallback when named theme source exists"
  assert_eq "$(cat "$source_css")" "$(cat "$current_css")" "discord plugin repairs stale current Vencord CSS from named theme source"
  assert_eq "$(cat "$source_css")" "$(cat "$installed")" "discord plugin installs repaired named theme Vencord CSS"
}

test_discord_plugin_generates_base16_fallback_without_theme_css() {
  local home_dir="$TMP_ROOT/discord-base16-fallback-home"
  local theme_dir="$home_dir/.local/state/omarchy/current/theme"
  local state_dir="$home_dir/.local/share/thpm"
  local vesktop_dir="$home_dir/.config/vesktop/themes"
  local generated
  local installed

  write_colors_fixture "$home_dir"
  mkdir -p "$vesktop_dir"
  generated="$state_dir/discord/vencord-base16.theme.css"
  installed="$vesktop_dir/vencord.theme.css"

  THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" THPM_STATE_DIR="$state_dir" HOME="$home_dir" bash "$ROOT_DIR/theme-set.d/10-discord.sh" >/dev/null 2>&1

  assert_file_missing "$theme_dir/vencord.theme.css" "discord plugin does not create fallback CSS inside current theme"
  assert_contains "$(cat "$generated")" "base16-discord" "discord plugin generates Base16 fallback source"
  assert_eq "$(cat "$generated")" "$(cat "$installed")" "discord plugin installs generated Base16 fallback"
}

test_browser_plugins_skip_missing_profiles() {
  local home_dir="$TMP_ROOT/browser-missing-profile-home"
  local bin_dir="$TMP_ROOT/browser-missing-profile-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/40-firefox.sh" "$hook_dir/40-firefox.sh"
  cp "$ROOT_DIR/theme-set.d/40-zen.sh" "$hook_dir/40-zen.sh"
  chmod +x "$hook_dir/40-firefox.sh" "$hook_dir/40-zen.sh"
  make_stub_bin "$bin_dir" firefox 'exit 0'
  make_stub_bin "$bin_dir" zen-browser 'exit 0'

  output="$(PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" 2>&1)"

  assert_contains "$output" "Firefox profile not found. Skipping.." "firefox plugin skips missing profile"
  assert_contains "$output" "Zen Browser profile not found. Skipping.." "zen plugin skips missing profile"
  assert_file_missing "$home_dir/.mozilla/firefox/chrome/colors.css" "firefox plugin does not write fallback root profile"
  assert_file_missing "$home_dir/.zen/chrome/colors.css" "zen plugin does not write fallback root profile"
}

test_firefox_plugin_writes_managed_imports_and_popup_rules() {
  local home_dir="$TMP_ROOT/firefox-managed-home"
  local bin_dir="$TMP_ROOT/firefox-managed-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local profile_dir="$home_dir/.mozilla/firefox/default"
  local chrome_dir="$profile_dir/chrome"
  local user_chrome="$chrome_dir/userChrome.css"
  local user_content="$chrome_dir/userContent.css"
  local managed_chrome="$chrome_dir/thpm-firefox-userChrome.css"
  local managed_content="$chrome_dir/thpm-firefox-userContent.css"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$chrome_dir"
  cat > "$home_dir/.mozilla/firefox/profiles.ini" <<'EOF'
[Install123]
Default=default
EOF
  printf 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", false);\n' > "$profile_dir/prefs.js"
  cp "$ROOT_DIR/theme-set.d/40-firefox.sh" "$hook_dir/40-firefox.sh"
  chmod +x "$hook_dir/40-firefox.sh"
  make_stub_bin "$bin_dir" firefox 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  output="$(PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" 2>&1)"

  assert_contains "$output" "Firefox theme updated!" "firefox plugin reports success"
  assert_file_exists "$chrome_dir/thpm-firefox-colors.css" "firefox plugin writes managed colors file"
  assert_file_exists "$chrome_dir/colors.css" "firefox plugin keeps legacy colors.css for existing imports"
  assert_file_exists "$managed_chrome" "firefox plugin writes managed chrome stylesheet"
  assert_file_exists "$managed_content" "firefox plugin writes managed content stylesheet"
  assert_contains "$(cat "$user_chrome")" "/* THPM Firefox hook start */" "firefox plugin inserts userChrome managed import marker"
  assert_contains "$(cat "$user_chrome")" '@import url("./thpm-firefox-colors.css");' "firefox plugin imports managed colors into userChrome"
  assert_contains "$(cat "$user_chrome")" '@import url("./thpm-firefox-userChrome.css");' "firefox plugin imports managed chrome stylesheet"
  assert_contains "$(cat "$user_content")" '@import url("./thpm-firefox-userContent.css");' "firefox plugin imports managed content stylesheet"
  assert_contains "$(cat "$managed_chrome")" "--panel-background: var(--base01) !important;" "firefox plugin sets current panel background variable"
  assert_contains "$(cat "$managed_chrome")" "#PopupSearchAutoComplete::part(content)" "firefox plugin targets search autocomplete popup content"
  assert_contains "$(cat "$managed_chrome")" "--panel-list-background-color: var(--base01) !important;" "firefox plugin sets search mode panel list background"
  assert_contains "$(cat "$managed_chrome")" "--urlbarview-separator-color: var(--base01) !important;" "firefox plugin sets current lowercase urlbar separator variable"
  assert_contains "$(cat "$managed_chrome")" "--urlbar-box-background-color: var(--base01) !important;" "firefox plugin sets current urlbar box background variable"
  assert_contains "$(cat "$profile_dir/prefs.js")" 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' "firefox plugin enables userChrome pref"
}

test_firefox_plugin_preserves_custom_user_css() {
  local home_dir="$TMP_ROOT/firefox-custom-home"
  local bin_dir="$TMP_ROOT/firefox-custom-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local profile_dir="$home_dir/.mozilla/firefox/default"
  local chrome_dir="$profile_dir/chrome"
  local user_chrome="$chrome_dir/userChrome.css"
  local user_content="$chrome_dir/userContent.css"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$chrome_dir"
  cat > "$home_dir/.mozilla/firefox/profiles.ini" <<'EOF'
[Install123]
Default=default
EOF
  cat > "$user_chrome" <<'EOF'
.custom-chrome-rule { color: red; }
EOF
  cat > "$user_content" <<'EOF'
.custom-content-rule { color: blue; }
EOF
  cp "$ROOT_DIR/theme-set.d/40-firefox.sh" "$hook_dir/40-firefox.sh"
  chmod +x "$hook_dir/40-firefox.sh"
  make_stub_bin "$bin_dir" firefox 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_contains "$(cat "$user_chrome")" "/* THPM Firefox hook start */" "firefox plugin inserts managed import block into custom userChrome"
  assert_contains "$(cat "$user_chrome")" ".custom-chrome-rule" "firefox plugin preserves custom userChrome content"
  assert_contains "$(cat "$user_content")" "/* THPM Firefox hook start */" "firefox plugin inserts managed import block into custom userContent"
  assert_contains "$(cat "$user_content")" ".custom-content-rule" "firefox plugin preserves custom userContent content"
}

test_firefox_plugin_migrates_legacy_generated_css() {
  local home_dir="$TMP_ROOT/firefox-legacy-home"
  local bin_dir="$TMP_ROOT/firefox-legacy-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local profile_dir="$home_dir/.mozilla/firefox/default"
  local chrome_dir="$profile_dir/chrome"
  local user_chrome="$chrome_dir/userChrome.css"
  local user_content="$chrome_dir/userContent.css"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$chrome_dir"
  cat > "$home_dir/.mozilla/firefox/profiles.ini" <<'EOF'
[Install123]
Default=default
EOF
  cat > "$user_chrome" <<'EOF'
@import url("./colors.css");
:root {
    --panel-separator-zap-gradient: linear-gradient(red, blue) !important;
    --arrowpanel-background: var(--base01) !important;
    --urlbar-box-bgcolor: var(--base01) !important;
}
EOF
  cat > "$user_content" <<'EOF'
@import url("./colors.css");
:root {
    --newtab-background-color: var(--base01) !important;
    --toolbar-field-focus-background-color: var(--base02) !important;
}
.search-inner-wrapper {
    margin-top: 10% !important;
}
EOF
  cp "$ROOT_DIR/theme-set.d/40-firefox.sh" "$hook_dir/40-firefox.sh"
  chmod +x "$hook_dir/40-firefox.sh"
  make_stub_bin "$bin_dir" firefox 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_exists "$user_chrome.thpm-migrated.bak" "firefox plugin backs up legacy generated userChrome"
  assert_file_exists "$user_content.thpm-migrated.bak" "firefox plugin backs up legacy generated userContent"
  assert_contains "$(cat "$user_chrome")" '@import url("./thpm-firefox-userChrome.css");' "firefox plugin replaces legacy userChrome with managed import"
  assert_not_contains "$(cat "$user_chrome")" "--urlbar-box-bgcolor" "firefox plugin removes stale legacy userChrome body"
  assert_contains "$(cat "$user_content")" '@import url("./thpm-firefox-userContent.css");' "firefox plugin replaces legacy userContent with managed import"
  assert_not_contains "$(cat "$user_content")" "--newtab-background-color" "firefox plugin removes stale legacy userContent body"
}

test_zen_plugin_uses_managed_imports_and_migrates_legacy_css() {
  local home_dir="$TMP_ROOT/zen-managed-home"
  local bin_dir="$TMP_ROOT/zen-managed-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local profile_dir="$home_dir/.zen/default"
  local user_chrome="$profile_dir/chrome/userChrome.css"
  local user_content="$profile_dir/chrome/userContent.css"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$profile_dir/chrome"
  cat > "$home_dir/.zen/profiles.ini" <<'EOF'
[Install123]
Default=default
EOF
  printf 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", false);\n' > "$profile_dir/prefs.js"
  cat > "$user_chrome" <<'EOF'
@import url("./colors.css");
:root {
    --panel-separator-zap-gradient: linear-gradient(red, blue) !important;
    --zen-main-browser-background: var(--base00) !important;
}
EOF
  cat > "$user_content" <<'EOF'
@import url("./colors.css");
:root {
    --newtab-background-color: var(--base01) !important;
    --zen-main-browser-background: var(--base00) !important;
}
EOF
  cat > "$profile_dir/chrome/colors.css" <<'EOF'
:root {
--color00: #000000;
--color0F: #ffffff;
}
EOF
  cp "$ROOT_DIR/theme-set.d/40-zen.sh" "$hook_dir/40-zen.sh"
  chmod +x "$hook_dir/40-zen.sh"
  make_stub_bin "$bin_dir" zen-browser 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  output="$(PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" 2>&1)"

  assert_contains "$output" "Zen Browser theme updated!" "zen plugin reports success"
  assert_file_exists "$profile_dir/chrome/thpm-zen-colors.css" "zen plugin writes managed colors file"
  assert_file_exists "$profile_dir/chrome/thpm-zen-userChrome.css" "zen plugin writes managed chrome stylesheet"
  assert_file_exists "$profile_dir/chrome/thpm-zen-userContent.css" "zen plugin writes managed content stylesheet"
  assert_contains "$(cat "$profile_dir/chrome/thpm-zen-userChrome.css")" "#zen-sidebar-top-buttons" "zen plugin themes Zen sidebar top button container"
  assert_contains "$(cat "$profile_dir/chrome/thpm-zen-userChrome.css")" "#zen-appcontent-wrapper" "zen plugin themes Zen browser frame container"
  assert_contains "$(cat "$user_chrome")" '/* THPM Zen hook start */' "zen plugin inserts managed userChrome import marker"
  assert_contains "$(cat "$user_chrome")" '@import url("./thpm-zen-colors.css");' "zen plugin imports managed colors directly from userChrome"
  assert_contains "$(cat "$user_chrome")" '@import url("./thpm-zen-userChrome.css");' "zen plugin imports managed userChrome stylesheet"
  assert_not_contains "$(cat "$user_chrome")" "--panel-separator-zap-gradient" "zen plugin migrates legacy full userChrome body out"
  assert_contains "$(cat "$user_content")" '@import url("./thpm-zen-colors.css");' "zen plugin imports managed colors directly from userContent"
  assert_contains "$(cat "$user_content")" '@import url("./thpm-zen-userContent.css");' "zen plugin imports managed userContent stylesheet"
  assert_not_contains "$(cat "$user_content")" "--newtab-background-color" "zen plugin migrates legacy full userContent body out"
  assert_not_contains "$(cat "$profile_dir/chrome/thpm-zen-userChrome.css")" '@import url("./thpm-zen-colors.css");' "zen plugin avoids nested userChrome imports"
  assert_not_contains "$(cat "$profile_dir/chrome/thpm-zen-userContent.css")" '@import url("./thpm-zen-colors.css");' "zen plugin avoids nested userContent imports"
  assert_file_exists "$user_chrome.thpm-migrated.bak" "zen plugin backs up migrated legacy userChrome"
  assert_file_exists "$user_content.thpm-migrated.bak" "zen plugin backs up migrated legacy userContent"
  assert_file_missing "$profile_dir/chrome/colors.css" "zen plugin removes unused legacy colors file"
  assert_contains "$(cat "$profile_dir/prefs.js")" 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' "zen plugin enables userChrome pref"

  HOME="$home_dir" bash "$hook_dir/40-zen.sh" --cleanup

  assert_file_missing "$profile_dir/chrome/thpm-zen-colors.css" "zen cleanup removes managed colors file"
  assert_file_missing "$profile_dir/chrome/thpm-zen-userChrome.css" "zen cleanup removes managed chrome stylesheet"
  assert_file_missing "$profile_dir/chrome/thpm-zen-userContent.css" "zen cleanup removes managed content stylesheet"
  assert_not_contains "$(cat "$user_chrome")" "THPM Zen hook" "zen cleanup removes userChrome import marker"
  assert_not_contains "$(cat "$user_content")" "THPM Zen hook" "zen cleanup removes userContent import marker"
}

test_zen_plugin_repairs_incomplete_managed_import_block() {
  local home_dir="$TMP_ROOT/zen-repair-import-home"
  local bin_dir="$TMP_ROOT/zen-repair-import-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local profile_dir="$home_dir/.zen/default"
  local user_chrome="$profile_dir/chrome/userChrome.css"
  local user_content="$profile_dir/chrome/userContent.css"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$profile_dir/chrome"
  cat > "$home_dir/.zen/profiles.ini" <<'EOF'
[Install123]
Default=default
EOF
  cat > "$user_chrome" <<'EOF'
/* THPM Zen hook start */
/* THPM Zen hook end */
.custom-rule { color: red; }
EOF
  cat > "$user_content" <<'EOF'
/* THPM Zen hook start */
@import url("./wrong.css");
/* THPM Zen hook end */
body { color: red; }
EOF
  cp "$ROOT_DIR/theme-set.d/40-zen.sh" "$hook_dir/40-zen.sh"
  chmod +x "$hook_dir/40-zen.sh"
  make_stub_bin "$bin_dir" zen-browser 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_contains "$(cat "$user_chrome")" '@import url("./thpm-zen-colors.css");' "zen plugin repairs missing userChrome colors import"
  assert_contains "$(cat "$user_chrome")" '@import url("./thpm-zen-userChrome.css");' "zen plugin repairs missing userChrome stylesheet import"
  assert_contains "$(cat "$user_chrome")" ".custom-rule" "zen plugin preserves userChrome content when repairing imports"
  assert_contains "$(cat "$user_content")" '@import url("./thpm-zen-colors.css");' "zen plugin repairs missing userContent colors import"
  assert_contains "$(cat "$user_content")" '@import url("./thpm-zen-userContent.css");' "zen plugin repairs missing userContent stylesheet import"
  assert_not_contains "$(cat "$user_content")" "wrong.css" "zen plugin removes stale managed import block contents"
  assert_contains "$(cat "$user_content")" "body { color: red; }" "zen plugin preserves userContent content when repairing imports"
}

test_qutebrowser_plugin_writes_theme_and_config() {
  local home_dir="$TMP_ROOT/qutebrowser-home"
  local bin_dir="$TMP_ROOT/qutebrowser-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local draw_file="$home_dir/.config/qutebrowser/omarchy/draw.py"
  local config_file="$home_dir/.config/qutebrowser/config.py"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/40-qutebrowser.sh" "$hook_dir/40-qutebrowser.sh"
  chmod +x "$hook_dir/40-qutebrowser.sh"
  make_stub_bin "$bin_dir" qutebrowser 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir"

  assert_file_exists "$draw_file" "qutebrowser plugin writes draw.py"
  assert_contains "$(cat "$draw_file")" "bg        = '#101112'" "qutebrowser draw.py uses background"
  assert_contains "$(cat "$draw_file")" "preferred_color_scheme = 'dark'" "qutebrowser draw.py defaults to dark mode"
  assert_file_exists "$config_file" "qutebrowser plugin writes config.py"
  assert_contains "$(cat "$config_file")" "import omarchy.draw" "qutebrowser config imports theme"
  assert_contains "$(cat "$config_file")" "omarchy.draw.apply(c)" "qutebrowser config applies theme"
}

test_qutebrowser_light_mode_change_requires_restart() {
  local home_dir="$TMP_ROOT/qutebrowser-light-home"
  local bin_dir="$TMP_ROOT/qutebrowser-light-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local draw_file="$home_dir/.config/qutebrowser/omarchy/draw.py"
  local notify_log="$TMP_ROOT/qutebrowser-light-notify.log"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$(dirname "$draw_file")"
  touch "$home_dir/.local/state/omarchy/current/theme/light.mode"
  cat > "$draw_file" <<'EOF'
def apply(c):
    c.colors.webpage.preferred_color_scheme = 'dark'
EOF
  cp "$ROOT_DIR/theme-set.d/40-qutebrowser.sh" "$hook_dir/40-qutebrowser.sh"
  chmod +x "$hook_dir/40-qutebrowser.sh"
  make_stub_bin "$bin_dir" qutebrowser 'exit 0'
  make_stub_bin "$bin_dir" pgrep '[[ "$2" == "qutebrowser" ]]'
  cat > "$bin_dir/notify-send" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$notify_log"
EOF
  chmod +x "$bin_dir/notify-send"

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir"

  assert_contains "$(cat "$draw_file")" "preferred_color_scheme = 'light'" "qutebrowser switches draw.py to light mode"
  assert_file_exists "$notify_log" "qutebrowser mode change requests restart notification"
  assert_contains "$(cat "$notify_log")" "Qutebrowser" "qutebrowser restart notification lists app"
}

test_fzf_plugin_writes_fish_theme() {
  local home_dir="$TMP_ROOT/fzf-home"
  local bin_dir="$TMP_ROOT/fzf-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output_file="$home_dir/.local/state/omarchy/current/theme/fzf.fish"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/00-fzf.sh" "$hook_dir/00-fzf.sh"
  chmod +x "$hook_dir/00-fzf.sh"
  make_stub_bin "$bin_dir" fish 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_exists "$output_file" "fzf plugin writes fzf.fish"
  assert_contains "$(cat "$output_file")" "set -l color00 '#000000'" "fzf plugin writes normal black"
  assert_contains "$(cat "$output_file")" "set -l color0F '#ffffff'" "fzf plugin writes bright white"
  assert_contains "$(cat "$output_file")" "--color=bg+:\$color00" "fzf plugin writes FZF color options"
}

test_fish_plugin_writes_shell_colors() {
  local home_dir="$TMP_ROOT/fish-home"
  local bin_dir="$TMP_ROOT/fish-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output_file="$home_dir/.local/state/omarchy/current/theme/colors.fish"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/00-fish.sh" "$hook_dir/00-fish.sh"
  chmod +x "$hook_dir/00-fish.sh"
  make_stub_bin "$bin_dir" fish 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_exists "$output_file" "fish plugin writes colors.fish"
  assert_contains "$(cat "$output_file")" "set -U background '#101112'" "fish plugin writes background"
  assert_contains "$(cat "$output_file")" "set -U foreground '#f1f2f3'" "fish plugin writes foreground"
  assert_contains "$(cat "$output_file")" "set -U color15 '#ffffff'" "fish plugin writes bright white"
}

test_obsidian_terminal_plugin_discovers_registered_vault() {
  local home_dir="$TMP_ROOT/obsidian-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local vault_dir="$home_dir/Notes/Team Vault"
  local data_file="$vault_dir/.obsidian/plugins/terminal/data.json"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$(dirname "$data_file")" "$home_dir/.config/obsidian"
  cp "$ROOT_DIR/theme-set.d/35-obsidian-terminal.sh" "$hook_dir/35-obsidian-terminal.sh"
  cat > "$home_dir/.config/obsidian/obsidian.json" <<EOF
{
  "vaults": {
    "team": {
      "path": "$vault_dir"
    }
  }
}
EOF
  cat > "$data_file" <<'EOF'
{
  "terminalOptions": {
    "fontSize": 14
  }
}
EOF

  XDG_CONFIG_HOME="$home_dir/.config" run_theme_hooks "$home_dir" >/dev/null

  assert_eq "#101112" "$(jq -r '.terminalOptions.theme.background' "$data_file")" "obsidian terminal plugin uses registered vault path"
  assert_eq "#f1f2f3" "$(jq -r '.terminalOptions.theme.foreground' "$data_file")" "obsidian terminal plugin writes foreground"
  assert_eq "14" "$(jq -r '.terminalOptions.fontSize' "$data_file")" "obsidian terminal plugin preserves existing settings"
}

test_obsidian_terminal_plugin_direct_run_loads_theme_env() {
  local home_dir="$TMP_ROOT/obsidian-direct-home"
  local data_file="$home_dir/Documents/Vault/.obsidian/plugins/terminal/data.json"

  write_colors_fixture "$home_dir"
  mkdir -p "$(dirname "$data_file")"
  cat > "$data_file" <<'EOF'
{
  "terminalOptions": {
    "theme": {
      "background": "#010203"
    }
  }
}
EOF

  XDG_CONFIG_HOME="$home_dir/.config" THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" "$ROOT_DIR/theme-set.d/35-obsidian-terminal.sh" >/dev/null

  assert_eq "#101112" "$(jq -r '.terminalOptions.theme.background' "$data_file")" "obsidian terminal plugin direct run loads theme env"
}

test_emacs_plugin_skips_when_missing() {
  local home_dir="$TMP_ROOT/emacs-missing-home"
  local stub_bin="$TMP_ROOT/stub-bin"
  local output

  mkdir -p "$stub_bin"
  cp "$(command -v bash)" "$stub_bin/"
  cp "$(command -v env)" "$stub_bin/"
  write_colors_fixture "$home_dir"

  output="$(PATH="$stub_bin" XDG_CONFIG_HOME="$home_dir/.config" THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" "$ROOT_DIR/theme-set.d/30-emacs.sh")"

  assert_contains "$output" "Emacs not found" "emacs plugin skips cleanly when emacs is missing"
}

test_emacs_plugin_generates_standard_emacs_theme() {
  local home_dir="$TMP_ROOT/emacs-standard-home"
  local emacs_dir="$home_dir/.config/emacs"

  write_colors_fixture "$home_dir"
  mkdir -p "$emacs_dir"

  XDG_CONFIG_HOME="$home_dir/.config" THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" "$ROOT_DIR/theme-set.d/30-emacs.sh" >/dev/null

  assert_file_exists "$emacs_dir/omarchy-colors.el" "emacs plugin generates omarchy-colors.el"
  assert_file_exists "$emacs_dir/themes/omarchy-theme.el" "emacs plugin generates omarchy-theme.el"
  assert_file_exists "$emacs_dir/omarchy.el" "emacs plugin generates omarchy.el"
  assert_contains "$(cat "$emacs_dir/omarchy-colors.el")" 'omarchy-color-bg "#101112"' "emacs plugin omarchy-colors.el uses primary background"
  assert_contains "$(cat "$emacs_dir/themes/omarchy-theme.el")" "deftheme omarchy" "omarchy-theme.el defines omarchy theme"
  assert_contains "$(cat "$emacs_dir/omarchy.el")" "omarchy-apply-theme" "omarchy.el defines omarchy-apply-theme"
}

test_emacs_plugin_generates_doom_emacs_theme() {
  local home_dir="$TMP_ROOT/emacs-doom-home"
  local doom_dir="$home_dir/.config/doom"

  write_colors_fixture "$home_dir"
  mkdir -p "$doom_dir"

  XDG_CONFIG_HOME="$home_dir/.config" THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" HOME="$home_dir" "$ROOT_DIR/theme-set.d/30-emacs.sh" >/dev/null

  assert_file_exists "$doom_dir/omarchy-colors.el" "emacs plugin generates omarchy-colors.el for Doom Emacs"
  assert_file_exists "$doom_dir/themes/omarchy-theme.el" "emacs plugin generates omarchy-theme.el for Doom Emacs"
  assert_file_exists "$doom_dir/omarchy.el" "emacs plugin generates omarchy.el for Doom Emacs"
  assert_contains "$(cat "$doom_dir/themes/omarchy-theme.el")" "doom-modeline" "omarchy-theme.el includes Doom modeline faces"
  assert_contains "$(cat "$doom_dir/omarchy.el")" "doom-theme" "omarchy.el includes Doom Emacs support"
}

test_foot_plugin_respects_disable_flag() {
  local home_dir="$TMP_ROOT/foot-disabled-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local log_file="/tmp/foot-theme-hook.log"

  rm -f "$log_file"
  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir"
  cp "$ROOT_DIR/theme-set.d/26-foot-live-colors.sh" "$hook_dir/26-foot-live-colors.sh"
  chmod +x "$hook_dir/26-foot-live-colors.sh"

  FOOT_LIVE_THEME=0 run_theme_hooks "$home_dir" >/dev/null

  assert_file_exists "$log_file" "foot plugin writes log when disabled"
  assert_contains "$(cat "$log_file")" "disabled via FOOT_LIVE_THEME=0" "foot plugin respects disable flag"
}

test_foot_plugin_logs_missing_theme_file() {
  local home_dir="$TMP_ROOT/foot-missing-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local log_file="/tmp/foot-theme-hook.log"

  rm -f "$log_file"
  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir"
  cp "$ROOT_DIR/theme-set.d/26-foot-live-colors.sh" "$hook_dir/26-foot-live-colors.sh"
  chmod +x "$hook_dir/26-foot-live-colors.sh"

  run_theme_hooks "$home_dir" >/dev/null

  assert_file_exists "$log_file" "foot plugin writes log when foot.ini is missing"
  assert_contains "$(cat "$log_file")" "missing theme file:" "foot plugin logs missing foot.ini"
}

test_foot_plugin_reads_theme_and_logs_no_ttys() {
  local home_dir="$TMP_ROOT/foot-theme-home"
  local bin_dir="$TMP_ROOT/foot-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local foot_file="$home_dir/.local/state/omarchy/current/theme/foot.ini"
  local base_file="$home_dir/.config/foot/foot.ini"
  local log_file="/tmp/foot-theme-hook.log"

  rm -f "$log_file"
  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$(dirname "$base_file")"
  cp "$ROOT_DIR/theme-set.d/26-foot-live-colors.sh" "$hook_dir/26-foot-live-colors.sh"
  chmod +x "$hook_dir/26-foot-live-colors.sh"
  cat > "$foot_file" <<'EOF'
[colors]
background = 202122
foreground = e1e2e3
cursor = c0ffee
selection-background = 303132
selection-foreground = fafafa
regular0 = 000001
bright7 = fffffe
EOF
  cat > "$base_file" <<'EOF'
[colors]
alpha = 0.75
EOF
  make_stub_bin "$bin_dir" ps 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_exists "$log_file" "foot plugin logs when no foot tty is available"
  assert_contains "$(cat "$log_file")" "no foot tty updates applied (attempted=0)" "foot plugin handles no writable foot tty"
}

test_foot_plugin_writes_osc_sequences_to_tty() {
  local home_dir="$TMP_ROOT/foot-tty-home"
  local bin_dir="$TMP_ROOT/foot-tty-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local foot_file="$home_dir/.local/state/omarchy/current/theme/foot.ini"
  local wrapper="$TMP_ROOT/foot-tty-wrapper.sh"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/26-foot-live-colors.sh" "$hook_dir/26-foot-live-colors.sh"
  chmod +x "$hook_dir/26-foot-live-colors.sh"
  cat > "$foot_file" <<'EOF'
[colors]
background = 202122
foreground = e1e2e3
cursor = c0ffee
selection-background = 303132
selection-foreground = fafafa
regular0 = 000001
regular1 = 111112
regular2 = 222223
regular3 = 333334
regular4 = 444445
regular5 = 555556
regular6 = 666667
regular7 = 777778
bright0 = 888889
bright1 = 99999a
bright2 = aaaabb
bright3 = bbbbcc
bright4 = ccccdd
bright5 = ddddee
bright6 = eeeeff
bright7 = fffffe
EOF

  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
set -u
tty_name="\$(tty)"
tty_name="\${tty_name#/dev/}"
cat > "$bin_dir/ps" <<PS
#!/usr/bin/env bash
printf '100 0 %s foot\n' "\$tty_name"
PS
chmod +x "$bin_dir/ps"
THPM_THEME_ENV="$ROOT_DIR/lib/theme-env.sh" PATH="$bin_dir:\$PATH" HOME="$home_dir" "$hook_dir/26-foot-live-colors.sh"
EOF
  chmod +x "$wrapper"

  if ! command -v script >/dev/null 2>&1; then
    fail "foot plugin writes OSC sequences to a writable tty"
    printf '  missing command: script\n'
    return
  fi

  output="$(script -qfec "$wrapper" /dev/null 2>&1)"

  assert_contains "$output" $'\e]10;rgb:f1/f2/f3\e\\' "foot plugin writes foreground OSC sequence"
  assert_contains "$output" $'\e]11;rgb:10/11/12\e\\' "foot plugin writes background OSC sequence"
  assert_contains "$output" $'\e]4;15;rgb:ff/ff/ff\e\\' "foot plugin writes palette OSC sequence"
}

test_cava_plugin_writes_theme_and_updates_config() {
  local home_dir="$TMP_ROOT/cava-home"
  local bin_dir="$TMP_ROOT/cava-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local theme_file="$home_dir/.config/cava/themes/omarchy"
  local config_file="$home_dir/.config/cava/config"
  local pkill_log="$TMP_ROOT/pkill.log"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$(dirname "$config_file")"
  cp "$ROOT_DIR/theme-set.d/40-cava.sh" "$hook_dir/40-cava.sh"
  chmod +x "$hook_dir/40-cava.sh"
  cat > "$config_file" <<'EOF'
[general]
framerate = 60

[color]
gradient = 0
EOF
  make_stub_bin "$bin_dir" cava 'exit 0'
  make_stub_bin "$bin_dir" pgrep '[[ "$2" == "cava" ]]'
  cat > "$bin_dir/pkill" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$pkill_log"
EOF
  chmod +x "$bin_dir/pkill"
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_exists "$theme_file" "cava plugin writes omarchy theme"
  assert_contains "$(cat "$theme_file")" "gradient_color_1 = '#666666'" "cava theme uses normal cyan"
  assert_contains "$(cat "$theme_file")" "gradient_color_8 = '#666666'" "cava theme writes final gradient color"
  assert_contains "$(cat "$config_file")" "theme = 'omarchy'" "cava plugin inserts theme setting"
  assert_file_exists "$pkill_log" "cava plugin signals running cava"
  assert_contains "$(cat "$pkill_log")" "-USR2 cava" "cava plugin sends USR2"
}

test_cava_plugin_does_not_duplicate_theme_setting() {
  local home_dir="$TMP_ROOT/cava-existing-home"
  local bin_dir="$TMP_ROOT/cava-existing-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local config_file="$home_dir/.config/cava/config"
  local theme_count

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$(dirname "$config_file")"
  cp "$ROOT_DIR/theme-set.d/40-cava.sh" "$hook_dir/40-cava.sh"
  chmod +x "$hook_dir/40-cava.sh"
  cat > "$config_file" <<'EOF'
[color]
theme = 'omarchy'
gradient = 0
EOF
  make_stub_bin "$bin_dir" cava 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null
  theme_count="$(grep -c "theme = 'omarchy'" "$config_file")"

  assert_eq "1" "$theme_count" "cava plugin does not duplicate existing theme setting"
}

test_superfile_plugin_writes_theme_and_requests_restart() {
  local home_dir="$TMP_ROOT/superfile-home"
  local bin_dir="$TMP_ROOT/superfile-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local theme_file="$home_dir/.config/superfile/theme/omarchy.toml"
  local notify_log="$TMP_ROOT/superfile-notify.log"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/10-superfile.sh" "$hook_dir/10-superfile.sh"
  chmod +x "$hook_dir/10-superfile.sh"
  make_stub_bin "$bin_dir" spf 'exit 0'
  make_stub_bin "$bin_dir" pgrep '[[ "$2" == "spf" ]]'
  cat > "$bin_dir/notify-send" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$notify_log"
EOF
  chmod +x "$bin_dir/notify-send"

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_exists "$theme_file" "superfile plugin writes omarchy theme"
  assert_contains "$(cat "$theme_file")" "full_screen_bg = '#101112'" "superfile theme uses background"
  assert_contains "$(cat "$theme_file")" "file_panel_border_active = '#444444'" "superfile theme uses normal blue"
  assert_file_exists "$notify_log" "superfile plugin requests restart notification"
  assert_contains "$(cat "$notify_log")" "Spf" "superfile restart notification lists spf"
}

test_zellij_plugin_generates_current_theme() {
  local home_dir="$TMP_ROOT/zellij-home"
  local bin_dir="$TMP_ROOT/zellij-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local config_file="$home_dir/.config/zellij/config.kdl"
  local legacy_theme_file="$home_dir/.config/zellij/themes/current.kdl"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$(dirname "$config_file")" "$(dirname "$legacy_theme_file")"
  cp "$ROOT_DIR/theme-set.d/10-zellij.sh" "$hook_dir/10-zellij.sh"
  chmod +x "$hook_dir/10-zellij.sh"
  cat > "$config_file" <<'EOF'
keybinds {
    normal {
        bind "Ctrl g" { SwitchToMode "locked"; }
    }
}
theme "old"
EOF
  cat > "$legacy_theme_file" <<'EOF'
// Generated by thpm zellij plugin. Do not edit directly.
themes {
    current {}
}
EOF
  make_stub_bin "$bin_dir" zellij 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_exists "$config_file" "zellij plugin writes config"
  assert_file_missing "$legacy_theme_file" "zellij plugin removes legacy generated theme file"
  assert_contains "$(cat "$config_file")" "bind \"Ctrl g\"" "zellij plugin preserves existing config"
  assert_contains "$(cat "$config_file")" "theme \"current\"" "zellij plugin selects current theme"
  assert_not_contains "$(cat "$config_file")" "theme \"old\"" "zellij plugin replaces old theme selection"
  assert_contains "$(cat "$config_file")" "// thpm-zellij-theme-start" "zellij config has managed theme block start"
  assert_contains "$(cat "$config_file")" "// thpm-zellij-theme-end" "zellij config has managed theme block end"
  assert_contains "$(cat "$config_file")" "Generated by thpm zellij plugin" "zellij theme identifies generated owner"
  assert_contains "$(cat "$config_file")" "background 16 17 18" "zellij theme uses primary background"
  assert_contains "$(cat "$config_file")" "base 241 242 243" "zellij theme uses primary foreground"
  assert_contains "$(cat "$config_file")" "table_title {
            base 85 85 85" "zellij table title uses normal magenta"
  assert_contains "$(cat "$config_file")" "background 34 34 34" "zellij theme uses selection background"
}

test_zellij_plugin_prefers_theme_provided_kdl() {
  local home_dir="$TMP_ROOT/zellij-provided-home"
  local bin_dir="$TMP_ROOT/zellij-provided-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local source_file="$home_dir/.local/state/omarchy/current/theme/zellij.kdl"
  local config_file="$home_dir/.config/zellij/config.kdl"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$(dirname "$config_file")"
  cp "$ROOT_DIR/theme-set.d/10-zellij.sh" "$hook_dir/10-zellij.sh"
  chmod +x "$hook_dir/10-zellij.sh"
  printf 'theme "current"\n' > "$config_file"
  cat > "$source_file" <<'EOF'
themes {
    current {
        text_unselected {
            base 1 2 3
            background 4 5 6
        }
    }
}
EOF
  make_stub_bin "$bin_dir" zellij 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_exists "$config_file" "zellij plugin writes provided theme to config"
  assert_contains "$(cat "$config_file")" "Generated by thpm zellij plugin" "zellij provided theme keeps ownership header"
  assert_contains "$(cat "$config_file")" "base 1 2 3" "zellij plugin copies theme-provided kdl"
  assert_contains "$(cat "$config_file")" "background 4 5 6" "zellij plugin preserves theme-provided colors"
}

test_zellij_plugin_skips_when_zellij_missing() {
  local home_dir="$TMP_ROOT/zellij-missing-home"
  local bin_dir="$TMP_ROOT/zellij-missing-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local config_file="$home_dir/.config/zellij/config.kdl"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/10-zellij.sh" "$hook_dir/10-zellij.sh"
  chmod +x "$hook_dir/10-zellij.sh"
  ln -s /usr/bin/bash "$bin_dir/bash"
  ln -s /usr/bin/awk "$bin_dir/awk"
  ln -s /usr/bin/cat "$bin_dir/cat"
  ln -s /usr/bin/mkdir "$bin_dir/mkdir"

  PATH="$bin_dir" run_theme_hooks "$home_dir" >/dev/null

  assert_file_missing "$config_file" "zellij plugin skips without zellij command"
}

test_swaync_plugin_installs_theme_files_and_reloads() {
  local home_dir="$TMP_ROOT/swaync-home"
  local bin_dir="$TMP_ROOT/swaync-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local source_dir="$home_dir/.local/state/omarchy/current/theme"
  local target_dir="$home_dir/.config/swaync"
  local reload_log="$TMP_ROOT/swaync-reload.log"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/25-swaync.sh" "$hook_dir/25-swaync.sh"
  chmod +x "$hook_dir/25-swaync.sh"
  printf 'style-current\n' > "$source_dir/swaync.style.css"
  printf '{"config":"current"}\n' > "$source_dir/swaync.config.json"
  printf 'colors-current\n' > "$source_dir/colors.css"
  make_stub_bin "$bin_dir" swaync 'exit 0'
  cat > "$bin_dir/swaync-client" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$reload_log"
EOF
  chmod +x "$bin_dir/swaync-client"

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_exists "$target_dir/style.css" "swaync plugin installs style.css"
  assert_file_exists "$target_dir/config.json" "swaync plugin installs config.json"
  assert_file_exists "$target_dir/colors.css" "swaync plugin installs colors.css"
  assert_eq "style-current" "$(cat "$target_dir/style.css")" "swaync plugin copies current style"
  assert_contains "$(cat "$reload_log")" "--reload-config -sw" "swaync plugin reloads config"
  assert_contains "$(cat "$reload_log")" "--reload-css -sw" "swaync plugin reloads css"
}

test_swaync_plugin_prefers_named_theme_over_current_theme() {
  local home_dir="$TMP_ROOT/swaync-named-home"
  local bin_dir="$TMP_ROOT/swaync-named-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local current_dir="$home_dir/.local/state/omarchy/current/theme"
  local named_dir="$home_dir/.config/omarchy/themes/named-theme"
  local target_dir="$home_dir/.config/swaync"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$named_dir"
  cp "$ROOT_DIR/theme-set.d/25-swaync.sh" "$hook_dir/25-swaync.sh"
  chmod +x "$hook_dir/25-swaync.sh"
  printf 'named-theme\n' > "$home_dir/.local/state/omarchy/current/theme.name"
  printf 'style-current\n' > "$current_dir/swaync.style.css"
  printf '{"config":"current"}\n' > "$current_dir/swaync.config.json"
  printf 'colors-current\n' > "$current_dir/colors.css"
  printf 'style-named\n' > "$named_dir/swaync.style.css"
  printf '{"config":"named"}\n' > "$named_dir/swaync.config.json"
  make_stub_bin "$bin_dir" swaync 'exit 0'
  make_stub_bin "$bin_dir" swaync-client 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_eq "style-named" "$(cat "$target_dir/style.css")" "swaync plugin prefers named theme style"
  assert_eq '{"config":"named"}' "$(cat "$target_dir/config.json")" "swaync plugin prefers named theme config"
  assert_eq "colors-current" "$(cat "$target_dir/colors.css")" "swaync plugin still uses current colors.css"
}

test_tmux_plugin_skips_without_theme_conf() {
  local home_dir="$TMP_ROOT/tmux-skip-home"
  local bin_dir="$TMP_ROOT/tmux-skip-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local target_file="$home_dir/.config/tmux/omarchy-theme.conf"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/10-tmux.sh" "$hook_dir/10-tmux.sh"
  chmod +x "$hook_dir/10-tmux.sh"
  make_stub_bin "$bin_dir" tmux 'printf "tmux should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_missing "$target_file" "tmux plugin skips when theme has no tmux.conf"
}

test_tmux_plugin_removes_managed_theme_when_theme_conf_missing() {
  local home_dir="$TMP_ROOT/tmux-cleanup-home"
  local bin_dir="$TMP_ROOT/tmux-cleanup-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local target_file="$home_dir/.config/tmux/omarchy-theme.conf"
  local config_file="$home_dir/.config/tmux/tmux.conf"
  local tmux_log="$TMP_ROOT/tmux-cleanup.log"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$(dirname "$config_file")"
  cp "$ROOT_DIR/theme-set.d/10-tmux.sh" "$hook_dir/10-tmux.sh"
  chmod +x "$hook_dir/10-tmux.sh"
  printf 'set -g status-style "bg=#000000"\n' > "$target_file"
  printf 'set -g mouse on\n\nsource-file ~/.config/tmux/omarchy-theme.conf\n' > "$config_file"
  cat > "$bin_dir/tmux" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmux_log"
EOF
  chmod +x "$bin_dir/tmux"
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_missing "$target_file" "tmux plugin removes stale managed theme file"
  assert_not_contains "$(cat "$config_file")" "source-file ~/.config/tmux/omarchy-theme.conf" "tmux plugin removes managed source line"
  assert_contains "$(cat "$tmux_log")" "source-file $config_file" "tmux plugin reloads base config after cleanup"
}

test_tmux_plugin_installs_theme_and_reloads() {
  local home_dir="$TMP_ROOT/tmux-home"
  local bin_dir="$TMP_ROOT/tmux-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local theme_file="$home_dir/.local/state/omarchy/current/theme/tmux.conf"
  local target_file="$home_dir/.config/tmux/omarchy-theme.conf"
  local config_file="$home_dir/.config/tmux/tmux.conf"
  local tmux_log="$TMP_ROOT/tmux.log"
  local source_count

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/10-tmux.sh" "$hook_dir/10-tmux.sh"
  chmod +x "$hook_dir/10-tmux.sh"
  printf 'set -g status-style "bg=#101112,fg=#f1f2f3"\n' > "$theme_file"
  cat > "$bin_dir/tmux" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmux_log"
EOF
  chmod +x "$bin_dir/tmux"
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null
  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_exists "$target_file" "tmux plugin installs theme file"
  assert_eq "$(cat "$theme_file")" "$(cat "$target_file")" "tmux plugin copies current theme tmux.conf"
  assert_file_exists "$config_file" "tmux plugin creates xdg tmux config"
  assert_contains "$(cat "$config_file")" "source-file ~/.config/tmux/omarchy-theme.conf" "tmux plugin sources stable theme file"
  source_count="$(grep -Fc "source-file ~/.config/tmux/omarchy-theme.conf" "$config_file")"
  assert_eq "1" "$source_count" "tmux plugin does not duplicate source line"
  assert_contains "$(cat "$tmux_log")" "source-file $target_file" "tmux plugin reloads installed theme"
}

test_tmux_plugin_prefers_existing_legacy_config() {
  local home_dir="$TMP_ROOT/tmux-legacy-home"
  local bin_dir="$TMP_ROOT/tmux-legacy-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local theme_file="$home_dir/.local/state/omarchy/current/theme/tmux.conf"
  local legacy_config="$home_dir/.tmux.conf"
  local xdg_config="$home_dir/.config/tmux/tmux.conf"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/10-tmux.sh" "$hook_dir/10-tmux.sh"
  chmod +x "$hook_dir/10-tmux.sh"
  printf 'set -g pane-active-border-style "fg=#444444"\n' > "$theme_file"
  printf 'set -g mouse on\n' > "$legacy_config"
  make_stub_bin "$bin_dir" tmux 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_contains "$(cat "$legacy_config")" "source-file ~/.config/tmux/omarchy-theme.conf" "tmux plugin uses existing legacy tmux config"
  assert_file_missing "$xdg_config" "tmux plugin does not create xdg config when legacy config exists"
}

test_vscode_plugin_builds_local_extension_from_source() {
  local home_dir="$TMP_ROOT/vscode-build-home"
  local bin_dir="$TMP_ROOT/vscode-build-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local theme_dir="$home_dir/.local/state/omarchy/current/theme"
  local install_log="$home_dir/code-install.log"

  if ! command -v zip >/dev/null 2>&1; then
    pass "vscode local-extension build test skipped (zip not installed)"
    return 0
  fi

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$theme_dir/vscode-extension/themes"
  cp "$ROOT_DIR/theme-set.d/30-vscode.sh" "$hook_dir/30-vscode.sh"
  chmod +x "$hook_dir/30-vscode.sh"
  printf '{"name":"Foo","extension":"local.theme-foo"}\n' > "$theme_dir/vscode.json"
  printf '{"name":"theme-foo","publisher":"local","contributes":{"themes":[{"label":"Foo","uiTheme":"vs-dark","path":"./themes/foo.json"}]}}\n' > "$theme_dir/vscode-extension/package.json"
  printf '{"name":"Foo","colors":{"editor.background":"#101112"}}\n' > "$theme_dir/vscode-extension/themes/foo.json"
  make_stub_bin "$bin_dir" code 'case "$1" in --list-extensions) cat "$HOME/code-installed.txt" 2>/dev/null ;; --install-extension) printf "%s\n" "$2" >> "$HOME/code-install.log"; printf "local.theme-foo\n" >> "$HOME/code-installed.txt" ;; esac'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null
  assert_file_exists "$install_log" "vscode plugin builds and installs a local extension from vscode-extension/"
  assert_eq "1" "$(wc -l < "$install_log" 2>/dev/null | tr -d ' ')" "local extension installed exactly once"

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null
  assert_eq "1" "$(wc -l < "$install_log" 2>/dev/null | tr -d ' ')" "unchanged local theme is not reinstalled on the next theme switch"
}

test_vscode_plugin_requires_extension_id_for_local_theme() {
  local home_dir="$TMP_ROOT/vscode-noext-home"
  local bin_dir="$TMP_ROOT/vscode-noext-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local theme_dir="$home_dir/.local/state/omarchy/current/theme"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$theme_dir/vscode-extension/themes"
  cp "$ROOT_DIR/theme-set.d/30-vscode.sh" "$hook_dir/30-vscode.sh"
  chmod +x "$hook_dir/30-vscode.sh"
  printf '{"name":"Foo"}\n' > "$theme_dir/vscode.json"
  printf '{"name":"theme-foo","publisher":"local","contributes":{"themes":[]}}\n' > "$theme_dir/vscode-extension/package.json"
  printf '{"name":"Foo","colors":{}}\n' > "$theme_dir/vscode-extension/themes/foo.json"
  make_stub_bin "$bin_dir" code 'case "$1" in --install-extension) printf "%s\n" "$2" >> "$HOME/code-install.log" ;; esac; exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null
  assert_file_missing "$home_dir/code-install.log" "local theme without an extension id is not installed (no reinstall loop)"
}

test_vscode_plugin_skips_when_theme_provides_vscode_json() {
  local home_dir="$TMP_ROOT/vscode-skip-home"
  local bin_dir="$TMP_ROOT/vscode-skip-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local generated_file="$home_dir/.local/state/omarchy/current/theme/vscode_colors.json"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/30-vscode.sh" "$hook_dir/30-vscode.sh"
  chmod +x "$hook_dir/30-vscode.sh"
  printf '{"theme":"provided"}\n' > "$home_dir/.local/state/omarchy/current/theme/vscode.json"
  make_stub_bin "$bin_dir" code 'printf "code should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_missing "$generated_file" "vscode plugin skips generated colors when vscode.json exists"
}

test_vscode_plugin_patches_extension_manifest_and_installs_theme() {
  local home_dir="$TMP_ROOT/vscode-full-home"
  local bin_dir="$TMP_ROOT/vscode-full-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local extension_dir="$home_dir/.vscode/extensions/tintedtheming.base16-tinted-themes-1.0.0"
  local theme_file="$extension_dir/themes/base16/omarchy.json"
  local package_file="$extension_dir/package.json"
  local code_log="$TMP_ROOT/vscode-code.log"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$extension_dir/themes/base16"
  cp "$ROOT_DIR/theme-set.d/30-vscode.sh" "$hook_dir/30-vscode.sh"
  chmod +x "$hook_dir/30-vscode.sh"
  cat > "$package_file" <<'EOF'
{
  "contributes": {
    "themes": []
  }
}
EOF
  cat > "$bin_dir/code" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$code_log"
case "\${1:-}" in
  --list-extensions) exit 0 ;;
  --install-extension) exit 0 ;;
esac
EOF
  chmod +x "$bin_dir/code"
  make_stub_bin "$bin_dir" sleep 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_exists "$theme_file" "vscode plugin installs omarchy theme file"
  assert_contains "$(cat "$theme_file")" '"name": "Omarchy"' "vscode theme file contains Omarchy theme"
  assert_contains "$(cat "$theme_file")" '"foreground":"#777777"' "vscode theme uses palette colors"
  assert_eq "Omarchy" "$(jq -r '.contributes.themes[] | select(.label == "Omarchy") | .label' "$package_file")" "vscode plugin adds Omarchy manifest entry"
  assert_eq "./themes/base16/omarchy.json" "$(jq -r '.contributes.themes[] | select(.label == "Omarchy") | .path' "$package_file")" "vscode manifest points to installed theme"
  assert_contains "$(cat "$code_log")" "--install-extension tintedtheming.base16-tinted-themes" "vscode plugin installs extension when missing"
}

test_cursor_plugin_suppresses_electron_deprecation_warning() {
  local home_dir="$TMP_ROOT/cursor-warning-home"
  local bin_dir="$TMP_ROOT/cursor-warning-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local extension_dir="$home_dir/.cursor/extensions/tintedtheming.base16-tinted-themes-1.0.0"
  local package_file="$extension_dir/package.json"
  local cursor_log="$TMP_ROOT/cursor.log"
  local output

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir" "$extension_dir/themes/base16"
  cp "$ROOT_DIR/theme-set.d/30-cursor.sh" "$hook_dir/30-cursor.sh"
  chmod +x "$hook_dir/30-cursor.sh"
  cat > "$package_file" <<'EOF'
{
  "contributes": {
    "themes": []
  }
}
EOF
  cat > "$bin_dir/cursor" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$cursor_log"
printf '%s\n' '(node:182356) [DEP0040] DeprecationWarning: The \`punycode\` module is deprecated. Please use a userland alternative instead.' >&2
case "\${1:-}" in
  --list-extensions) exit 0 ;;
  --install-extension) exit 0 ;;
esac
EOF
  chmod +x "$bin_dir/cursor"
  make_stub_bin "$bin_dir" sleep 'exit 0'
  make_stub_bin "$bin_dir" pgrep 'exit 1'
  make_stub_bin "$bin_dir" notify-send 'exit 0'

  output="$(PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" 2>&1)"

  assert_contains "$output" "Cursor theme updated!" "cursor plugin still reports success"
  assert_not_contains "$output" "punycode" "cursor plugin suppresses Electron punycode warning"
  assert_contains "$(cat "$cursor_log")" "--install-extension tintedtheming.base16-tinted-themes" "cursor plugin still installs extension when missing"
}

test_theme_set_extracts_colors_with_leading_whitespace_and_comments() {
  local home_dir="$TMP_ROOT/spaced-colors-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output_file="$TMP_ROOT/spaced-colors-output"
  local theme_dir="$home_dir/.local/state/omarchy/current/theme"

  write_colors_fixture "$home_dir"
  theme_dir="$home_dir/.local/state/omarchy/current/theme"
  cat > "$theme_dir/colors.toml" <<'EOF'
# comments should be ignored
  background = "#010203" # inline comment
	foreground = "#a0b0c0"
cursor = "#abcdef"
selection_background = "#112233"
selection_foreground = "#ddeeff"
color0 = "#000000"
color1 = "#111111"
color2 = "#222222"
color3 = "#333333"
color4 = "#444444"
color5 = "#555555"
color6 = "#666666"
color7 = "#777777"
color8 = "#888888"
color9 = "#999999"
color10 = "#aaaaaa"
color11 = "#bbbbbb"
color12 = "#cccccc"
color13 = "#dddddd"
color14 = "#eeeeee"
color15 = "#ffffff"
EOF
  mkdir -p "$hook_dir"
  cat > "$hook_dir/10-capture.sh" <<EOF
#!/usr/bin/env bash
source "$ROOT_DIR/lib/theme-env.sh"
printf '%s\n' "\$primary_background|\$primary_foreground|\$rgb_primary_background" > "$output_file"
EOF

  run_theme_hooks "$home_dir"

  assert_eq "010203|a0b0c0|1, 2, 3" "$(cat "$output_file")" "theme-set extracts colors with whitespace and comments"
}

test_install_preserves_disabled_plugins_and_installs_files() {
  local home_dir="$TMP_ROOT/install-home"
  local bin_dir="$TMP_ROOT/install-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local installed_thpm="$home_dir/.local/bin/thpm"
  local legacy_thpm="$home_dir/.local/share/omarchy/bin/thpm"
  local installed_theme_set="$home_dir/.config/omarchy/hooks/theme-set"
  local installed_theme_env="$home_dir/.local/share/thpm/lib/theme-env.sh"
  local installed_skill="$home_dir/.local/share/thpm/skills/theme-hook-plugin-authoring/SKILL.md"
  local installed_version="$home_dir/.local/share/thpm/version"
  local update_cache="$home_dir/.local/share/thpm/update-check"
  local installed_config="$home_dir/.config/thpm/config.toml"
  local output
  local status

  mkdir -p "$hook_dir" "$bin_dir" "$home_dir/.local/share/omarchy/bin" "$(dirname "$update_cache")"
  printf '#!/usr/bin/env bash\n' > "$legacy_thpm"
  printf '# Omarchy 3.3+ uses colors.toml as the source of truth for theme colors.\n' > "$installed_theme_set"
  printf '#!/usr/bin/env bash\n' > "$hook_dir/00-fish.sh.sample"
  printf 'checked_at=1\nstatus=update_available\nremote_commit=old\n' > "$update_cache"

  make_stub_bin "$bin_dir" pacman 'exit 0'
  make_stub_bin "$bin_dir" sudo 'printf "sudo should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" omarchy-hook 'printf "omarchy-hook %s\n" "$*"'
  make_stub_bin "$bin_dir" omarchy-show-done 'printf "done\n"'
  make_install_git_stub "$bin_dir"

  output="$(PATH="$bin_dir:$PATH" HOME="$home_dir" "$ROOT_DIR/install.sh" 2>&1)"
  status=$?

  assert_success "$status" "install exits successfully"
  assert_contains "$output" "Downloading thpm.." "install announces download"
  assert_contains "$output" "omarchy-hook theme-set" "install applies theme-set hook"
  assert_eq "thpm" "$(install_git_branch)" "install defaults to release branch"
  assert_eq "clone --branch thpm --depth 1 https://github.com/OldJobobo/theme-hook-plugin-manager.git /tmp/theme-hook" "$(install_git_args)" "install clones expected repository and destination"
  assert_file_executable "$installed_thpm" "install writes executable thpm"
  assert_file_missing "$legacy_thpm" "install removes legacy omarchy bin thpm"
  assert_file_missing "$installed_theme_set" "install removes old thpm theme-set dispatcher"
  assert_file_exists "$installed_theme_env" "install writes shared theme env"
  assert_file_exists "$installed_skill" "install writes bundled agent skills"
  assert_contains "$(cat "$installed_version")" "commit=local-install-commit" "install records installed commit"
  assert_file_missing "$update_cache" "install clears stale update availability cache"
  assert_file_exists "$installed_config" "install writes default config.toml"
  assert_contains "$(cat "$installed_config")" "skills_dir = \"~/.local/share/thpm/skills\"" "default config documents bundled skills path"
  assert_contains "$(cat "$installed_config")" "[notifications.restart.apps]" "default config documents restart app controls"
  assert_file_exists "$hook_dir/00-fish.sh.sample" "install preserves disabled plugin as sample"
  assert_file_missing "$hook_dir/00-fish.sh" "install removes active file for disabled plugin"
  assert_file_exists "$hook_dir/10-branding.sh.sample" "install disables branding plugin by default"
  assert_file_missing "$hook_dir/10-branding.sh" "install does not enable branding plugin by default"
  assert_file_exists "$hook_dir/11-discord-system24.sh.sample" "install disables discord system24 plugin by default"
  assert_file_missing "$hook_dir/11-discord-system24.sh" "install does not enable discord system24 plugin by default"
  assert_file_exists "$hook_dir/10-zellij.sh.sample" "install disables zellij plugin by default"
  assert_file_missing "$hook_dir/10-zellij.sh" "install does not enable zellij plugin by default"
  assert_file_exists "$hook_dir/10-tmux.sh.sample" "install hides tmux as disabled sample"
  assert_file_missing "$hook_dir/10-tmux.sh" "install does not enable hidden tmux plugin"
  assert_file_exists "$hook_dir/50-cliamp.sh" "install enables cliamp by default"
  assert_file_missing "$hook_dir/50-cliamp.sh.sample" "install does not hide cliamp as disabled sample"
  assert_file_exists "$hook_dir/30-vscode.sh" "install enables bundled plugins by default"
}

test_install_preserves_existing_config() {
  local home_dir="$TMP_ROOT/install-config-home"
  local bin_dir="$TMP_ROOT/install-config-bin"
  local config_file="$home_dir/.config/thpm/config.toml"
  local status

  rm -f "$TMP_ROOT/install-git-branch.log"
  rm -f "$TMP_ROOT/install-git-args.log"
  mkdir -p "$bin_dir" "$(dirname "$config_file")"
  printf '[notifications.restart]\nenabled = false\n' > "$config_file"
  make_stub_bin "$bin_dir" pacman 'exit 0'
  make_stub_bin "$bin_dir" sudo 'printf "sudo should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_install_git_stub "$bin_dir"

  PATH="$bin_dir:$PATH" HOME="$home_dir" "$ROOT_DIR/install.sh" >/dev/null 2>&1
  status=$?

  assert_success "$status" "install with existing config exits successfully"
  assert_eq "[notifications.restart]
enabled = false" "$(cat "$config_file")" "install preserves existing config.toml"
}

test_install_keeps_non_executable_hooks_enabled() {
  local home_dir="$TMP_ROOT/install-non-executable-home"
  local bin_dir="$TMP_ROOT/install-non-executable-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local status

  rm -f "$TMP_ROOT/install-git-branch.log"
  rm -f "$TMP_ROOT/install-git-args.log"
  mkdir -p "$hook_dir" "$bin_dir"
  printf '#!/usr/bin/env bash\n' > "$hook_dir/30-vscode.sh"
  chmod 644 "$hook_dir/30-vscode.sh"
  make_stub_bin "$bin_dir" pacman 'exit 0'
  make_stub_bin "$bin_dir" sudo 'printf "sudo should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_install_git_stub "$bin_dir"

  PATH="$bin_dir:$PATH" HOME="$home_dir" "$ROOT_DIR/install.sh" >/dev/null 2>&1
  status=$?

  assert_success "$status" "install with non-executable active hook exits successfully"
  assert_file_exists "$hook_dir/30-vscode.sh" "install keeps non-executable active hook enabled"
  assert_file_missing "$hook_dir/30-vscode.sh.sample" "install does not convert non-executable hook to sample"
}

test_install_recovers_all_bundled_plugins_disabled_by_bad_update() {
  local home_dir="$TMP_ROOT/install-all-disabled-home"
  local bin_dir="$TMP_ROOT/install-all-disabled-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local hook
  local status

  rm -f "$TMP_ROOT/install-git-branch.log"
  rm -f "$TMP_ROOT/install-git-args.log"
  mkdir -p "$hook_dir" "$bin_dir"
  for hook in "$ROOT_DIR"/theme-set.d/*.sh; do
    printf '#!/usr/bin/env bash\n' > "$hook_dir/$(basename "$hook").sample"
  done
  make_stub_bin "$bin_dir" pacman 'exit 0'
  make_stub_bin "$bin_dir" sudo 'printf "sudo should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_install_git_stub "$bin_dir"

  PATH="$bin_dir:$PATH" HOME="$home_dir" "$ROOT_DIR/install.sh" >/dev/null 2>&1
  status=$?

  assert_success "$status" "install recovers all-bundled-disabled state successfully"
  assert_file_exists "$hook_dir/00-fish.sh" "install re-enables fish after all-disabled update fallout"
  assert_file_exists "$hook_dir/30-vscode.sh" "install re-enables vscode after all-disabled update fallout"
  assert_file_exists "$hook_dir/40-zen.sh" "install re-enables zen after all-disabled update fallout"
  assert_file_missing "$hook_dir/00-fish.sh.sample" "install clears fish sample after all-disabled update fallout"
  assert_file_exists "$hook_dir/10-branding.sh.sample" "install keeps branding disabled after all-disabled update recovery"
  assert_file_exists "$hook_dir/10-zellij.sh.sample" "install keeps zellij disabled after all-disabled update recovery"
  assert_file_exists "$hook_dir/10-tmux.sh.sample" "install keeps hidden tmux disabled after all-disabled update recovery"
  assert_file_exists "$hook_dir/50-cliamp.sh" "install restores cliamp enabled after all-disabled update recovery"
  assert_file_missing "$hook_dir/50-cliamp.sh.sample" "install clears cliamp sample after all-disabled update recovery"
  assert_file_missing "$hook_dir/40-zen.sh.sample" "install clears zen sample after all-disabled update fallout"
}

test_install_recovery_preserves_custom_sample_hooks() {
  local home_dir="$TMP_ROOT/install-all-disabled-custom-home"
  local bin_dir="$TMP_ROOT/install-all-disabled-custom-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local hook
  local status

  rm -f "$TMP_ROOT/install-git-branch.log"
  rm -f "$TMP_ROOT/install-git-args.log"
  mkdir -p "$hook_dir" "$bin_dir"
  for hook in "$ROOT_DIR"/theme-set.d/*.sh; do
    printf '#!/usr/bin/env bash\n' > "$hook_dir/$(basename "$hook").sample"
  done
  printf '#!/usr/bin/env bash\nprintf custom\n' > "$hook_dir/99-custom.sh.sample"
  make_stub_bin "$bin_dir" pacman 'exit 0'
  make_stub_bin "$bin_dir" sudo 'printf "sudo should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_install_git_stub "$bin_dir"

  PATH="$bin_dir:$PATH" HOME="$home_dir" "$ROOT_DIR/install.sh" >/dev/null 2>&1
  status=$?

  assert_success "$status" "install recovers all-disabled state with custom sample successfully"
  assert_file_exists "$hook_dir/40-zen.sh" "install re-enables bundled hooks with custom sample present"
  assert_file_missing "$hook_dir/40-zen.sh.sample" "install removes bundled sample with custom sample present"
  assert_file_exists "$hook_dir/99-custom.sh.sample" "install preserves custom sample during all-disabled recovery"
  assert_file_missing "$hook_dir/99-custom.sh" "install does not activate custom sample during all-disabled recovery"
}

test_install_preserves_mixed_enabled_and_disabled_state() {
  local home_dir="$TMP_ROOT/install-mixed-state-home"
  local bin_dir="$TMP_ROOT/install-mixed-state-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local output
  local status

  rm -f "$TMP_ROOT/install-git-branch.log"
  rm -f "$TMP_ROOT/install-git-args.log"
  mkdir -p "$hook_dir" "$bin_dir"
  printf '#!/usr/bin/env bash\n' > "$hook_dir/00-fish.sh"
  chmod 644 "$hook_dir/00-fish.sh"
  printf '#!/usr/bin/env bash\n' > "$hook_dir/30-vscode.sh.sample"
  make_stub_bin "$bin_dir" pacman 'exit 0'
  make_stub_bin "$bin_dir" sudo 'printf "sudo should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_install_git_stub "$bin_dir"

  output="$(PATH="$bin_dir:$PATH" HOME="$home_dir" "$ROOT_DIR/install.sh" 2>&1)"
  status=$?

  assert_success "$status" "install preserves mixed enabled and disabled state successfully"
  assert_not_contains "$output" "All bundled plugins are disabled" "install does not recover when any bundled hook is enabled"
  assert_file_exists "$hook_dir/00-fish.sh" "install preserves active bundled hook in mixed state"
  assert_file_exists "$hook_dir/10-branding.sh.sample" "install keeps newly added branding disabled in mixed state"
  assert_file_exists "$hook_dir/30-vscode.sh.sample" "install preserves disabled bundled hook in mixed state"
  assert_file_missing "$hook_dir/30-vscode.sh" "install does not enable disabled bundled hook in mixed state"
}

test_install_preserves_enabled_branding_plugin() {
  local home_dir="$TMP_ROOT/install-branding-enabled-home"
  local bin_dir="$TMP_ROOT/install-branding-enabled-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local status

  rm -f "$TMP_ROOT/install-git-branch.log"
  rm -f "$TMP_ROOT/install-git-args.log"
  mkdir -p "$hook_dir" "$bin_dir"
  printf '#!/usr/bin/env bash\n' > "$hook_dir/10-branding.sh"
  make_stub_bin "$bin_dir" pacman 'exit 0'
  make_stub_bin "$bin_dir" sudo 'printf "sudo should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_install_git_stub "$bin_dir"

  PATH="$bin_dir:$PATH" HOME="$home_dir" "$ROOT_DIR/install.sh" >/dev/null 2>&1
  status=$?

  assert_success "$status" "install with enabled branding exits successfully"
  assert_file_exists "$hook_dir/10-branding.sh" "install preserves explicitly enabled branding plugin"
  assert_file_missing "$hook_dir/10-branding.sh.sample" "install does not disable explicitly enabled branding plugin"
}

test_install_respects_branch_override() {
  local home_dir="$TMP_ROOT/install-branch-home"
  local bin_dir="$TMP_ROOT/install-branch-bin"
  local status

  rm -f "$TMP_ROOT/install-git-branch.log"
  rm -f "$TMP_ROOT/install-git-args.log"
  mkdir -p "$bin_dir" "$home_dir/.config/omarchy/hooks"
  make_stub_bin "$bin_dir" pacman 'exit 0'
  make_stub_bin "$bin_dir" sudo 'printf "sudo should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_install_git_stub "$bin_dir"

  THPM_BRANCH=test-branch PATH="$bin_dir:$PATH" HOME="$home_dir" "$ROOT_DIR/install.sh" >/dev/null 2>&1
  status=$?

  assert_success "$status" "install with branch override exits successfully"
  assert_eq "test-branch" "$(install_git_branch)" "install honors THPM_BRANCH override"
  assert_eq "clone --branch test-branch --depth 1 https://github.com/OldJobobo/theme-hook-plugin-manager.git /tmp/theme-hook" "$(install_git_args)" "install passes branch override to git clone"
}

test_install_preserves_existing_sample_disabled_plugin() {
  local home_dir="$TMP_ROOT/install-sample-home"
  local bin_dir="$TMP_ROOT/install-sample-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local status

  rm -f "$TMP_ROOT/install-git-branch.log"
  rm -f "$TMP_ROOT/install-git-args.log"
  mkdir -p "$hook_dir" "$bin_dir"
  printf '#!/usr/bin/env bash\n' > "$hook_dir/30-vscode.sh.sample"
  make_stub_bin "$bin_dir" pacman 'exit 0'
  make_stub_bin "$bin_dir" sudo 'printf "sudo should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_install_git_stub "$bin_dir"

  PATH="$bin_dir:$PATH" HOME="$home_dir" "$ROOT_DIR/install.sh" >/dev/null 2>&1
  status=$?

  assert_success "$status" "install with existing sample exits successfully"
  assert_file_exists "$hook_dir/30-vscode.sh.sample" "install preserves existing .sample disabled plugin"
  assert_file_missing "$hook_dir/30-vscode.sh" "install keeps .sample plugin inactive"
}

test_install_restores_cliamp_hidden_sample() {
  local home_dir="$TMP_ROOT/install-cliamp-restore-home"
  local bin_dir="$TMP_ROOT/install-cliamp-restore-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local status

  rm -f "$TMP_ROOT/install-git-branch.log"
  rm -f "$TMP_ROOT/install-git-args.log"
  mkdir -p "$hook_dir" "$bin_dir"
  printf '#!/usr/bin/env bash\n' > "$hook_dir/50-cliamp.sh.sample"
  make_stub_bin "$bin_dir" pacman 'exit 0'
  make_stub_bin "$bin_dir" sudo 'printf "sudo should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_install_git_stub "$bin_dir"

  PATH="$bin_dir:$PATH" HOME="$home_dir" "$ROOT_DIR/install.sh" >/dev/null 2>&1
  status=$?

  assert_success "$status" "install restores cliamp from hidden sample successfully"
  assert_file_exists "$hook_dir/50-cliamp.sh" "install restores cliamp hook active"
  assert_file_missing "$hook_dir/50-cliamp.sh.sample" "install removes stale hidden cliamp sample"
}

test_install_disabled_sample_wins_over_stale_active_plugin() {
  local home_dir="$TMP_ROOT/install-stale-active-home"
  local bin_dir="$TMP_ROOT/install-stale-active-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local status

  rm -f "$TMP_ROOT/install-git-branch.log"
  rm -f "$TMP_ROOT/install-git-args.log"
  mkdir -p "$hook_dir" "$bin_dir"
  printf '#!/usr/bin/env bash\nprintf disabled\n' > "$hook_dir/30-vscode.sh.sample"
  printf '#!/usr/bin/env bash\nprintf stale-active\n' > "$hook_dir/30-vscode.sh"
  make_stub_bin "$bin_dir" pacman 'exit 0'
  make_stub_bin "$bin_dir" sudo 'printf "sudo should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_install_git_stub "$bin_dir"

  PATH="$bin_dir:$PATH" HOME="$home_dir" "$ROOT_DIR/install.sh" >/dev/null 2>&1
  status=$?

  assert_success "$status" "install with disabled sample and stale active hook exits successfully"
  assert_file_exists "$hook_dir/30-vscode.sh.sample" "install keeps bundled plugin disabled when sample exists"
  assert_file_missing "$hook_dir/30-vscode.sh" "install removes stale active copy for disabled plugin"
  assert_not_contains "$(cat "$hook_dir/30-vscode.sh.sample")" "stale-active" "install replaces stale active hook with bundled hook"
}

test_install_preserves_custom_omarchy_hook() {
  local home_dir="$TMP_ROOT/install-custom-home"
  local bin_dir="$TMP_ROOT/install-custom-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local custom_hook="$hook_dir/99-custom.sh"
  local status

  rm -f "$TMP_ROOT/install-git-branch.log"
  rm -f "$TMP_ROOT/install-git-args.log"
  mkdir -p "$hook_dir" "$bin_dir"
  printf '#!/usr/bin/env bash\nprintf custom\n' > "$custom_hook"
  make_stub_bin "$bin_dir" pacman 'exit 0'
  make_stub_bin "$bin_dir" sudo 'printf "sudo should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_install_git_stub "$bin_dir"

  PATH="$bin_dir:$PATH" HOME="$home_dir" "$ROOT_DIR/install.sh" >/dev/null 2>&1
  status=$?

  assert_success "$status" "install with custom hook exits successfully"
  assert_file_exists "$custom_hook" "install preserves custom Omarchy hook"
  assert_eq '#!/usr/bin/env bash
printf custom' "$(cat "$custom_hook")" "install preserves custom hook contents"
}

test_install_preserves_custom_sample_hook() {
  local home_dir="$TMP_ROOT/install-custom-sample-home"
  local bin_dir="$TMP_ROOT/install-custom-sample-bin"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local custom_hook="$hook_dir/99-custom.sh.sample"
  local status

  rm -f "$TMP_ROOT/install-git-branch.log"
  rm -f "$TMP_ROOT/install-git-args.log"
  mkdir -p "$hook_dir" "$bin_dir"
  printf '#!/usr/bin/env bash\nprintf custom-sample\n' > "$custom_hook"
  make_stub_bin "$bin_dir" pacman 'exit 0'
  make_stub_bin "$bin_dir" sudo 'printf "sudo should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_install_git_stub "$bin_dir"

  PATH="$bin_dir:$PATH" HOME="$home_dir" "$ROOT_DIR/install.sh" >/dev/null 2>&1
  status=$?

  assert_success "$status" "install with custom sample hook exits successfully"
  assert_file_exists "$custom_hook" "install preserves custom .sample hook"
  assert_eq '#!/usr/bin/env bash
printf custom-sample' "$(cat "$custom_hook")" "install preserves custom .sample hook contents"
  assert_file_missing "$hook_dir/99-custom.sh" "install does not activate custom .sample hook"
}

test_install_preserves_user_theme_set_hook() {
  local home_dir="$TMP_ROOT/install-user-theme-set-home"
  local bin_dir="$TMP_ROOT/install-user-theme-set-bin"
  local theme_set="$home_dir/.config/omarchy/hooks/theme-set"
  local status

  rm -f "$TMP_ROOT/install-git-branch.log"
  rm -f "$TMP_ROOT/install-git-args.log"
  mkdir -p "$bin_dir" "$(dirname "$theme_set")"
  printf '#!/usr/bin/env bash\nprintf user-hook\n' > "$theme_set"
  make_stub_bin "$bin_dir" pacman 'exit 0'
  make_stub_bin "$bin_dir" sudo 'printf "sudo should not be called\n" >&2; exit 1'
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_install_git_stub "$bin_dir"

  PATH="$bin_dir:$PATH" HOME="$home_dir" "$ROOT_DIR/install.sh" >/dev/null 2>&1
  status=$?

  assert_success "$status" "install with user theme-set hook exits successfully"
  assert_file_exists "$theme_set" "install preserves user theme-set hook"
  assert_contains "$(cat "$theme_set")" "user-hook" "install preserves user theme-set hook contents"
}

test_install_interactive_prompt_installs_missing_adw_theme() {
  local home_dir="$TMP_ROOT/install-interactive-home"
  local bin_dir="$TMP_ROOT/install-interactive-bin"
  local sudo_log="$TMP_ROOT/install-interactive-sudo.log"
  local output
  local status

  rm -f "$TMP_ROOT/install-git-branch.log"
  rm -f "$TMP_ROOT/install-git-args.log"
  mkdir -p "$bin_dir" "$home_dir/.config/omarchy/hooks"
  make_stub_bin "$bin_dir" pacman 'exit 1'
  cat > "$bin_dir/sudo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$sudo_log"
EOF
  chmod +x "$bin_dir/sudo"
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_install_git_stub "$bin_dir"

  output="$(printf 'y\n' | PATH="$bin_dir:/bin" HOME="$home_dir" "$ROOT_DIR/install.sh" 2>&1)"
  status=$?

  assert_success "$status" "interactive install exits successfully"
  assert_contains "$output" "\"adw-gtk-theme\" is required to theme GTK applications." "install interactive path explains missing GTK theme"
  assert_file_exists "$sudo_log" "install interactive path invokes sudo when confirmed"
  assert_eq "pacman -S adw-gtk-theme" "$(cat "$sudo_log")" "install interactive path installs adw-gtk-theme"
  assert_file_executable "$home_dir/.local/bin/thpm" "install interactive path still installs thpm"
}

test_install_gum_prompt_installs_missing_adw_theme() {
  local home_dir="$TMP_ROOT/install-gum-home"
  local bin_dir="$TMP_ROOT/install-gum-bin"
  local sudo_log="$TMP_ROOT/install-gum-sudo.log"
  local gum_log="$TMP_ROOT/install-gum.log"
  local status

  rm -f "$TMP_ROOT/install-git-branch.log"
  rm -f "$TMP_ROOT/install-git-args.log"
  mkdir -p "$bin_dir" "$home_dir/.config/omarchy/hooks"
  make_stub_bin "$bin_dir" pacman 'exit 1'
  cat > "$bin_dir/gum" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$gum_log"
[[ "\${1:-}" == "confirm" ]] && exit 0
exit 0
EOF
  chmod +x "$bin_dir/gum"
  cat > "$bin_dir/sudo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$sudo_log"
EOF
  chmod +x "$bin_dir/sudo"
  make_stub_bin "$bin_dir" omarchy-hook 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_install_git_stub "$bin_dir"

  PATH="$bin_dir:/bin" HOME="$home_dir" "$ROOT_DIR/install.sh" >/dev/null 2>&1
  status=$?

  assert_success "$status" "gum install exits successfully"
  assert_contains "$(cat "$gum_log")" "style --border normal" "install gum path renders warning"
  assert_contains "$(cat "$gum_log")" "confirm Would you like to install \"adw-gtk-theme\"?" "install gum path asks for confirmation"
  assert_eq "pacman -S adw-gtk-theme" "$(cat "$sudo_log")" "install gum path installs adw-gtk-theme"
}

test_uninstall_removes_files_and_qutebrowser_theme() {
  local home_dir="$TMP_ROOT/uninstall-home"
  local bin_dir="$TMP_ROOT/uninstall-bin"
  local output

  mkdir -p "$bin_dir" "$home_dir/.local/bin" "$home_dir/.local/share/omarchy/bin" "$home_dir/.config/omarchy/hooks/theme-set.d" "$home_dir/.config/omarchy/branding" "$home_dir/.config/qutebrowser/omarchy" "$home_dir/.config/zellij/themes" "$home_dir/.zen/default/chrome" "$home_dir/.mozilla/firefox/default/chrome"
  printf '#!/usr/bin/env bash\n' > "$home_dir/.local/bin/thpm"
  printf '#!/usr/bin/env bash\n' > "$home_dir/.local/share/omarchy/bin/thpm"
  printf 'default about\n' > "$home_dir/.local/share/omarchy/icon.txt"
  printf 'default screensaver\n' > "$home_dir/.local/share/omarchy/logo.txt"
  printf 'themed about\n' > "$home_dir/.config/omarchy/branding/about.txt"
  printf 'themed screensaver\n' > "$home_dir/.config/omarchy/branding/screensaver.txt"
  printf '# Omarchy 3.3+ uses colors.toml as the source of truth for theme colors.\n' > "$home_dir/.config/omarchy/hooks/theme-set"
  printf '#!/usr/bin/env bash\n' > "$home_dir/.config/omarchy/hooks/theme-set.d/00-fzf.sh"
  printf '#!/usr/bin/env bash\n' > "$home_dir/.config/omarchy/hooks/theme-set.d/10-branding.sh"
  cp "$ROOT_DIR/theme-set.d/40-firefox.sh" "$home_dir/.config/omarchy/hooks/theme-set.d/40-firefox.sh"
  cp "$ROOT_DIR/theme-set.d/40-zen.sh" "$home_dir/.config/omarchy/hooks/theme-set.d/40-zen.sh"
  printf '#!/usr/bin/env bash\n' > "$home_dir/.config/omarchy/hooks/theme-set.d/99-custom.sh"
  mkdir -p "$home_dir/.local/share/thpm/lib"
  printf '#!/usr/bin/env bash\n' > "$home_dir/.local/share/thpm/lib/theme-env.sh"
  cat > "$home_dir/.config/qutebrowser/config.py" <<'EOF'
config.load_autoconfig()
import omarchy.draw
omarchy.draw.apply(c)
EOF
  cat > "$home_dir/.config/zellij/config.kdl" <<'EOF'
theme "current"
keybinds {
    normal {
        bind "Ctrl g" { SwitchToMode "locked"; }
    }
}
// thpm-zellij-theme-start
// Generated by thpm zellij plugin. Do not edit directly.
themes {
    current {}
}
// thpm-zellij-theme-end
EOF
  cat > "$home_dir/.config/zellij/themes/current.kdl" <<'EOF'
// Generated by thpm zellij plugin. Do not edit directly.
themes {
    current {}
}
EOF
  cat > "$home_dir/.zen/profiles.ini" <<'EOF'
[Install123]
Default=default
EOF
  cat > "$home_dir/.zen/default/chrome/userChrome.css" <<'EOF'
/* THPM Zen hook start */
@import url("./thpm-zen-userChrome.css");
/* THPM Zen hook end */
EOF
  printf 'managed\n' > "$home_dir/.zen/default/chrome/thpm-zen-userChrome.css"
  cat > "$home_dir/.mozilla/firefox/profiles.ini" <<'EOF'
[Install123]
Default=default
EOF
  cat > "$home_dir/.mozilla/firefox/default/chrome/userChrome.css" <<'EOF'
/* THPM Firefox hook start */
@import url("./thpm-firefox-userChrome.css");
/* THPM Firefox hook end */
EOF
  printf 'managed\n' > "$home_dir/.mozilla/firefox/default/chrome/thpm-firefox-userChrome.css"

  make_stub_bin "$bin_dir" omarchy-show-logo 'printf "logo\n"'
  make_stub_bin "$bin_dir" omarchy-show-done 'printf "done\n"'
  make_stub_bin "$bin_dir" python 'exit 1'
  make_stub_bin "$bin_dir" spicetify 'exit 1'
  make_stub_bin "$bin_dir" gsettings 'exit 1'
  make_stub_bin "$bin_dir" qutebrowser 'exit 0'
  make_stub_bin "$bin_dir" vicinae 'exit 1'

  output="$(OMARCHY_PATH="$home_dir/.local/share/omarchy" PATH="$bin_dir:$PATH" HOME="$home_dir" bash "$ROOT_DIR/uninstall.sh" 2>&1)"

  assert_contains "$output" "Uninstalled thpm!" "uninstall reports completion"
  assert_file_missing "$home_dir/.local/bin/thpm" "uninstall removes thpm binary"
  assert_file_missing "$home_dir/.local/share/omarchy/bin/thpm" "uninstall removes legacy omarchy bin thpm"
  assert_file_missing "$home_dir/.config/omarchy/hooks/theme-set" "uninstall removes theme-set hook"
  assert_file_missing "$home_dir/.config/omarchy/hooks/theme-set.d/00-fzf.sh" "uninstall removes bundled plugin"
  assert_file_missing "$home_dir/.config/omarchy/hooks/theme-set.d/10-branding.sh" "uninstall removes branding plugin"
  assert_file_missing "$home_dir/.config/omarchy/hooks/theme-set.d/40-zen.sh" "uninstall removes zen plugin"
  assert_file_exists "$home_dir/.config/omarchy/hooks/theme-set.d/99-custom.sh" "uninstall preserves custom Omarchy hook"
  assert_eq "default about" "$(cat "$home_dir/.config/omarchy/branding/about.txt")" "uninstall restores Omarchy about branding default"
  assert_eq "default screensaver" "$(cat "$home_dir/.config/omarchy/branding/screensaver.txt")" "uninstall restores Omarchy screensaver branding default"
  assert_file_missing "$home_dir/.local/share/thpm/lib/theme-env.sh" "uninstall removes shared theme env"
  assert_file_missing "$home_dir/.config/qutebrowser/omarchy" "uninstall removes qutebrowser theme directory"
  assert_eq "config.load_autoconfig()" "$(cat "$home_dir/.config/qutebrowser/config.py")" "uninstall removes qutebrowser config lines"
  assert_not_contains "$(cat "$home_dir/.config/zellij/config.kdl")" "thpm-zellij-theme-start" "uninstall removes zellij managed theme block"
  assert_contains "$(cat "$home_dir/.config/zellij/config.kdl")" "bind \"Ctrl g\"" "uninstall preserves zellij user config"
  assert_file_missing "$home_dir/.config/zellij/themes/current.kdl" "uninstall removes legacy zellij generated theme file"
  assert_file_missing "$home_dir/.zen/default/chrome/thpm-zen-userChrome.css" "uninstall removes managed zen stylesheet"
  assert_not_contains "$(cat "$home_dir/.zen/default/chrome/userChrome.css")" "THPM Zen hook" "uninstall removes zen import block"
  assert_file_missing "$home_dir/.mozilla/firefox/default/chrome/thpm-firefox-userChrome.css" "uninstall removes managed firefox stylesheet"
  assert_file_missing "$home_dir/.mozilla/firefox/default/chrome/userChrome.css" "uninstall removes empty firefox userChrome after managed block cleanup"
}

test_uninstall_warns_and_preserves_branding_when_default_missing() {
  local home_dir="$TMP_ROOT/uninstall-branding-missing-home"
  local bin_dir="$TMP_ROOT/uninstall-branding-missing-bin"
  local output

  mkdir -p "$bin_dir" "$home_dir/.local/share/omarchy" "$home_dir/.config/omarchy/branding"
  printf 'default about\n' > "$home_dir/.local/share/omarchy/icon.txt"
  printf 'themed about\n' > "$home_dir/.config/omarchy/branding/about.txt"
  printf 'themed screensaver\n' > "$home_dir/.config/omarchy/branding/screensaver.txt"

  make_stub_bin "$bin_dir" omarchy-show-logo 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_stub_bin "$bin_dir" python 'exit 1'
  make_stub_bin "$bin_dir" spicetify 'exit 1'
  make_stub_bin "$bin_dir" gsettings 'exit 1'
  make_stub_bin "$bin_dir" qutebrowser 'exit 1'
  make_stub_bin "$bin_dir" vicinae 'exit 1'

  output="$(OMARCHY_PATH="$home_dir/.local/share/omarchy" PATH="$bin_dir:$PATH" HOME="$home_dir" bash "$ROOT_DIR/uninstall.sh" 2>&1)"

  assert_contains "$output" "Warning: Omarchy screensaver branding default not found" "uninstall warns when screensaver default is missing"
  assert_contains "$output" "Uninstalled thpm!" "uninstall continues after missing branding default"
  assert_eq "default about" "$(cat "$home_dir/.config/omarchy/branding/about.txt")" "uninstall restores available about default"
  assert_eq "themed screensaver" "$(cat "$home_dir/.config/omarchy/branding/screensaver.txt")" "uninstall preserves screensaver branding when default is missing"
}

test_uninstall_invokes_external_revert_commands() {
  local home_dir="$TMP_ROOT/uninstall-external-home"
  local bin_dir="$TMP_ROOT/uninstall-external-bin"
  local steam_log="$TMP_ROOT/uninstall-steam.log"
  local spicetify_log="$TMP_ROOT/uninstall-spicetify.log"
  local gsettings_log="$TMP_ROOT/uninstall-gsettings.log"
  local vicinae_log="$TMP_ROOT/uninstall-vicinae.log"

  mkdir -p "$bin_dir" "$home_dir/.local/share/steam-adwaita"
  cat > "$home_dir/.local/share/steam-adwaita/install.py" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$steam_log"
EOF
  chmod +x "$home_dir/.local/share/steam-adwaita/install.py"
  make_stub_bin "$bin_dir" omarchy-show-logo 'exit 0'
  make_stub_bin "$bin_dir" omarchy-show-done 'exit 0'
  make_stub_bin "$bin_dir" python 'exit 0'
  cat > "$bin_dir/spicetify" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$spicetify_log"
EOF
  chmod +x "$bin_dir/spicetify"
  cat > "$bin_dir/gsettings" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$gsettings_log"
EOF
  chmod +x "$bin_dir/gsettings"
  make_stub_bin "$bin_dir" qutebrowser 'exit 1'
  cat > "$bin_dir/vicinae" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$vicinae_log"
EOF
  chmod +x "$bin_dir/vicinae"

  PATH="$bin_dir:$PATH" HOME="$home_dir" bash "$ROOT_DIR/uninstall.sh" >/dev/null 2>&1

  assert_eq "--uninstall" "$(cat "$steam_log")" "uninstall invokes Steam adwaita uninstall"
  assert_eq "restore" "$(cat "$spicetify_log")" "uninstall invokes spicetify restore"
  assert_eq "set org.gnome.desktop.interface gtk-theme Adwaita" "$(cat "$gsettings_log")" "uninstall restores GTK theme"
  assert_eq "theme set vicinae-dark" "$(cat "$vicinae_log")" "uninstall restores Vicinae theme"
}

print_coverage_summary() {
  local all_scripts=("$ROOT_DIR/thpm" "$ROOT_DIR/theme-set" "$ROOT_DIR/install.sh" "$ROOT_DIR/uninstall.sh" "$ROOT_DIR/lib/theme-env.sh")
  local direct_scripts=(
    "$ROOT_DIR/thpm"
    "$ROOT_DIR/theme-set"
    "$ROOT_DIR/lib/theme-env.sh"
    "$ROOT_DIR/install.sh"
    "$ROOT_DIR/uninstall.sh"
    "$ROOT_DIR/theme-set.d/10-branding.sh"
    "$ROOT_DIR/theme-set.d/00-fish.sh"
    "$ROOT_DIR/theme-set.d/00-fzf.sh"
    "$ROOT_DIR/theme-set.d/10-superfile.sh"
    "$ROOT_DIR/theme-set.d/10-tmux.sh"
    "$ROOT_DIR/theme-set.d/10-zellij.sh"
    "$ROOT_DIR/theme-set.d/25-swaync.sh"
    "$ROOT_DIR/theme-set.d/26-foot-live-colors.sh"
    "$ROOT_DIR/theme-set.d/35-obsidian-terminal.sh"
    "$ROOT_DIR/theme-set.d/30-emacs.sh"
    "$ROOT_DIR/theme-set.d/30-vscode.sh"
    "$ROOT_DIR/theme-set.d/40-cava.sh"
    "$ROOT_DIR/theme-set.d/40-qutebrowser.sh"
  )
  local script
  local total
  local direct
  local percent

  for script in "$ROOT_DIR"/theme-set.d/*.sh; do
    all_scripts+=("$script")
  done

  total="${#all_scripts[@]}"
  direct="${#direct_scripts[@]}"
  percent=$((direct * 100 / total))

  printf '\nAssertions: %d\n' "$TEST_ASSERTIONS"
  printf 'Direct script coverage: %d/%d scripts (%d%%)\n' "$direct" "$total" "$percent"
  printf 'Note: this is script-level behavioral coverage, not line coverage.\n'
}

test_cliamp_uses_ansi_default_without_native() {
  local home_dir="$TMP_ROOT/cliamp-ansi-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local bin_dir="$TMP_ROOT/cliamp-ansi-bin"
  local cfg="$home_dir/.config/cliamp/config.toml"

  write_colors_fixture "$home_dir"   # theme ships no cliamp.toml -> ANSI default
  mkdir -p "$hook_dir" "$bin_dir" "$(dirname "$cfg")"
  cp "$ROOT_DIR/theme-set.d/50-cliamp.sh" "$hook_dir/50-cliamp.sh"
  chmod +x "$hook_dir/50-cliamp.sh"
  printf 'theme = "omarchy"\nvolume = -6\n[navidrome]\npassword = "p#1"\n' > "$cfg"
  make_stub_bin "$bin_dir" cliamp 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_missing "$home_dir/.config/cliamp/themes/omarchy.toml" "cliamp ANSI mode writes no generated theme"
  assert_contains "$(cat "$cfg")" 'theme = ""' "cliamp ANSI mode empties theme so cliamp uses its ANSI default"
  assert_contains "$(cat "$cfg")" 'password = "p#1"' "cliamp ANSI mode preserves other config keys"
}

test_cliamp_installs_canonical_native_dropping_inline_comments() {
  local home_dir="$TMP_ROOT/cliamp-native-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local bin_dir="$TMP_ROOT/cliamp-native-bin"
  local theme_dir="$home_dir/.local/state/omarchy/current/theme"
  local out="$home_dir/.config/cliamp/themes/omarchy.toml"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/50-cliamp.sh" "$hook_dir/50-cliamp.sh"
  chmod +x "$hook_dir/50-cliamp.sh"
  # The theme ships its own cliamp.toml WITH inline comments. Older cliamp builds may reject these
  # (folding the comment into the value), so the hook canonicalises. Real-binary oracle (run
  # locally; CI has no cliamp): `cliamp theme list | grep -qx '  omarchy'`. Here we assert the
  # canonical output that makes cliamp accept it (clean uppercased hex, no comments).
  cat > "$theme_dir/cliamp.toml" <<'EOF'
# thpm:cliamp-use-native
accent = "#2488cb"   # muted purple — primary interactive
bright_fg = "#d2833b"  # warm parchment
fg = "#9287b0"       # dim charcoal
green = "#238e9e"
yellow = "#d8979a"
red = "#D93C76"
EOF
  make_stub_bin "$bin_dir" cliamp 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_exists "$out" "cliamp installs the theme's own cliamp.toml"
  assert_contains "$(cat "$out")" 'accent    = "#2488CB"' "cliamp native install canonicalises hex (uppercased)"
  assert_not_contains "$(cat "$out")" "muted purple" "cliamp native install strips inline comments older cliamp builds would reject"
  assert_contains "$(cat "$home_dir/.config/cliamp/config.toml")" 'theme = "omarchy"' "cliamp native install selects the omarchy theme"
}

test_cliamp_falls_back_to_ansi_for_incomplete_native() {
  local home_dir="$TMP_ROOT/cliamp-incomplete-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local bin_dir="$TMP_ROOT/cliamp-incomplete-bin"
  local theme_dir="$home_dir/.local/state/omarchy/current/theme"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/50-cliamp.sh" "$hook_dir/50-cliamp.sh"
  chmod +x "$hook_dir/50-cliamp.sh"
  printf '# thpm:cliamp-use-native\naccent = "#2488cb"\nbright_fg = "#d2833b"\n' > "$theme_dir/cliamp.toml"   # opted-in but only 2 of 6 keys
  make_stub_bin "$bin_dir" cliamp 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_missing "$home_dir/.config/cliamp/themes/omarchy.toml" "cliamp drops an incomplete native cliamp.toml"
  assert_contains "$(cat "$home_dir/.config/cliamp/config.toml")" 'theme = ""' "cliamp falls back to ANSI for an incomplete native theme"
}

test_cliamp_ignores_native_without_opt_in_marker() {
  local home_dir="$TMP_ROOT/cliamp-no-marker-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local bin_dir="$TMP_ROOT/cliamp-no-marker-bin"
  local theme_dir="$home_dir/.local/state/omarchy/current/theme"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/50-cliamp.sh" "$hook_dir/50-cliamp.sh"
  chmod +x "$hook_dir/50-cliamp.sh"
  # A complete, valid cliamp.toml WITHOUT the opt-in marker (e.g. an auto-generated artifact).
  # Mere existence must NOT activate native -> ANSI.
  cat > "$theme_dir/cliamp.toml" <<'EOF'
accent = "#2488cb"
bright_fg = "#d2833b"
fg = "#9287b0"
green = "#238e9e"
yellow = "#d8979a"
red = "#d93c76"
EOF
  make_stub_bin "$bin_dir" cliamp 'exit 0'

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_missing "$home_dir/.config/cliamp/themes/omarchy.toml" "cliamp ignores a native cliamp.toml without the opt-in marker"
  assert_contains "$(cat "$home_dir/.config/cliamp/config.toml")" 'theme = ""' "cliamp uses ANSI when a native theme lacks the opt-in marker"
}

test_cliamp_requires_exact_opt_in_marker() {
  local bin_dir="$TMP_ROOT/cliamp-nearmiss-bin"
  local colors='accent = "#2488cb"\nbright_fg = "#d2833b"\nfg = "#9287b0"\ngreen = "#238e9e"\nyellow = "#d8979a"\nred = "#d93c76"\n'
  local i=0 mark home_dir hook_dir theme_dir

  mkdir -p "$bin_dir"
  make_stub_bin "$bin_dir" cliamp 'exit 0'

  # Only the EXACT line activates native. Near-misses (trailing text, leading whitespace, different
  # case) must stay ANSI. The trailing-text case fails under a substring match (grep -qF), so it
  # guards against loosening grep -qxF. (A marker inside a value is covered by the same whole-line
  # match and needs no separate case.)
  for mark in '# thpm:cliamp-use-native please' '  # thpm:cliamp-use-native' '# THPM:CLIAMP-USE-NATIVE'; do
    i=$((i + 1))
    home_dir="$TMP_ROOT/cliamp-nearmiss-$i"
    hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
    theme_dir="$home_dir/.local/state/omarchy/current/theme"
    write_colors_fixture "$home_dir"
    mkdir -p "$hook_dir"
    cp "$ROOT_DIR/theme-set.d/50-cliamp.sh" "$hook_dir/50-cliamp.sh"
    chmod +x "$hook_dir/50-cliamp.sh"
    printf '%s\n%b' "$mark" "$colors" > "$theme_dir/cliamp.toml"

    PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

    assert_file_missing "$home_dir/.config/cliamp/themes/omarchy.toml" "cliamp near-miss marker [$mark] does NOT activate native"
    assert_contains "$(cat "$home_dir/.config/cliamp/config.toml")" 'theme = ""' "cliamp near-miss marker [$mark] falls back to ANSI"
  done
}

test_cliamp_fails_loud_when_config_cannot_be_created() {
  local home_dir="$TMP_ROOT/cliamp-cfgfail-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local bin_dir="$TMP_ROOT/cliamp-cfgfail-bin"
  local cliamp_dir="$home_dir/.config/cliamp"
  local output status

  write_colors_fixture "$home_dir"   # no cliamp.toml -> ANSI path -> _set_theme creates config
  mkdir -p "$hook_dir" "$bin_dir" "$cliamp_dir"
  cp "$ROOT_DIR/theme-set.d/50-cliamp.sh" "$hook_dir/50-cliamp.sh"
  chmod +x "$hook_dir/50-cliamp.sh"
  make_stub_bin "$bin_dir" cliamp 'exit 0'
  chmod 500 "$cliamp_dir"   # config.toml cannot be created here

  output="$(PATH="$bin_dir:$PATH" HOME="$home_dir" XDG_CONFIG_HOME="$home_dir/.config" bash "$hook_dir/50-cliamp.sh" 2>&1)"
  status=$?
  chmod 700 "$cliamp_dir"

  if [[ "$status" -ne 0 ]]; then
    pass "cliamp exits non-zero when config.toml cannot be created"
  else
    fail "cliamp exits non-zero when config.toml cannot be created"
  fi
  assert_not_contains "$output" "SUCCESS" "cliamp does not report SUCCESS when config write fails"
}

test_cliamp_only_removes_its_exact_owned_file() {
  local bin_dir="$TMP_ROOT/cliamp-owner-bin"
  local h1="$TMP_ROOT/cliamp-owner-keep"
  local h2="$TMP_ROOT/cliamp-owner-remove"

  mkdir -p "$bin_dir"
  make_stub_bin "$bin_dir" cliamp 'exit 0'

  # (a) first line only CONTAINS the marker as a substring (e.g. a user backup) -> must be KEPT
  write_colors_fixture "$h1"
  mkdir -p "$h1/.config/omarchy/hooks/theme-set.d" "$h1/.config/cliamp/themes"
  cp "$ROOT_DIR/theme-set.d/50-cliamp.sh" "$h1/.config/omarchy/hooks/theme-set.d/50-cliamp.sh"
  chmod +x "$h1/.config/omarchy/hooks/theme-set.d/50-cliamp.sh"
  printf '# thpm:cliamp-omarchy-backup\nmy backup\n' > "$h1/.config/cliamp/themes/omarchy.toml"
  PATH="$bin_dir:$PATH" run_theme_hooks "$h1" >/dev/null
  assert_file_exists "$h1/.config/cliamp/themes/omarchy.toml" "cliamp keeps a file whose first line only contains the owner marker as a substring"

  # (b) first line IS exactly the owner marker -> removed during ANSI tidy-up
  write_colors_fixture "$h2"
  mkdir -p "$h2/.config/omarchy/hooks/theme-set.d" "$h2/.config/cliamp/themes"
  cp "$ROOT_DIR/theme-set.d/50-cliamp.sh" "$h2/.config/omarchy/hooks/theme-set.d/50-cliamp.sh"
  chmod +x "$h2/.config/omarchy/hooks/theme-set.d/50-cliamp.sh"
  printf '# thpm:cliamp-omarchy\nold\n' > "$h2/.config/cliamp/themes/omarchy.toml"
  PATH="$bin_dir:$PATH" run_theme_hooks "$h2" >/dev/null
  assert_file_missing "$h2/.config/cliamp/themes/omarchy.toml" "cliamp removes a file whose first line is exactly the owner marker"
}

test_cliamp_native_handles_crlf_opt_in_marker() {
  local home_dir="$TMP_ROOT/cliamp-crlf-home"
  local hook_dir="$home_dir/.config/omarchy/hooks/theme-set.d"
  local bin_dir="$TMP_ROOT/cliamp-crlf-bin"
  local theme_dir="$home_dir/.local/state/omarchy/current/theme"
  local out="$home_dir/.config/cliamp/themes/omarchy.toml"

  write_colors_fixture "$home_dir"
  mkdir -p "$hook_dir" "$bin_dir"
  cp "$ROOT_DIR/theme-set.d/50-cliamp.sh" "$hook_dir/50-cliamp.sh"
  chmod +x "$hook_dir/50-cliamp.sh"
  make_stub_bin "$bin_dir" cliamp 'exit 0'
  # exact opt-in marker but CRLF line endings -> must still be recognised (not silently ANSI)
  printf '# thpm:cliamp-use-native\r\naccent = "#2488cb"\r\nbright_fg = "#d2833b"\r\nfg = "#9287b0"\r\ngreen = "#238e9e"\r\nyellow = "#d8979a"\r\nred = "#d93c76"\r\n' > "$theme_dir/cliamp.toml"

  PATH="$bin_dir:$PATH" run_theme_hooks "$home_dir" >/dev/null

  assert_file_exists "$out" "cliamp recognises an exact opt-in marker with CRLF line endings"
  assert_contains "$(cat "$out")" 'accent    = "#2488CB"' "cliamp canonicalises a CRLF native theme"
  assert_contains "$(cat "$home_dir/.config/cliamp/config.toml")" 'theme = "omarchy"' "cliamp selects the native theme for a CRLF opt-in file"
}

main() {
  test_shell_syntax
  test_installer_bundled_plugin_inventory_matches_hooks
  test_project_omarchy_default_contract
  test_thpm_help
  test_thpm_cli_uses_terminal_palette_roles
  test_thpm_install_skills_prompts_and_installs_codex_skill
  test_thpm_install_skills_accepts_explicit_skill_and_agent
  test_thpm_enable_disable_and_list
  test_thpm_hides_tmux_but_keeps_cliamp_visible
  test_thpm_discord_plugins_are_mutually_exclusive
  test_thpm_manages_custom_hooks
  test_thpm_reads_hook_dir_from_config
  test_thpm_env_hook_dir_overrides_config
  test_thpm_list_reports_available_update
  test_thpm_help_reports_cached_update_without_network
  test_thpm_aliases
  test_thpm_doctor_reports_missing_colors
  test_thpm_doctor_warns_for_missing_plugin_command
  test_thpm_doctor_reports_broken_hook_syntax
  test_thpm_doctor_reports_firefox_profile_issue
  test_thpm_doctor_zen_reports_missing_generated_files
  test_thpm_doctor_zen_reports_late_import_overrides
  test_thpm_doctor_zen_accepts_existing_import_variants
  test_thpm_doctor_zen_reports_stale_frame_rules
  test_thpm_doctor_limits_plugin_specific_checks
  test_thpm_open_uses_xdg_open_for_hook_dir
  test_thpm_gtk_post_enable_disable_updates_gsettings
  test_theme_set_exports_colors_and_runs_enabled_hooks
  test_theme_set_handles_commented_palette_color
  test_theme_env_errors_without_colors_file
  test_theme_set_reports_hook_failure
  test_theme_set_sends_restart_notification
  test_theme_env_reads_colors_file_from_config
  test_theme_env_prefers_quattro_theme_with_legacy_default_config
  test_theme_env_falls_back_to_legacy_theme_dir
  test_thpm_doctor_uses_quattro_theme_with_legacy_default_config
  test_restart_notification_can_be_disabled_globally
  test_restart_notification_can_be_disabled_for_app
  test_restart_notification_supports_stdout_and_not_running
  test_branding_plugin_copies_theme_branding
  test_branding_plugin_preserves_missing_sources
  test_branding_plugin_skips_without_theme_branding
  test_branding_plugin_disable_stops_sync_until_enabled
  test_hook_plugins_use_portable_assumption_guards
  test_discord_system24_plugin_writes_theme_and_installs_existing_clients
  test_discord_plugin_installs_theme_css_when_switching_back
  test_discord_plugin_repairs_stale_current_css_from_theme_source
  test_discord_plugin_generates_base16_fallback_without_theme_css
  test_browser_plugins_skip_missing_profiles
  test_firefox_plugin_writes_managed_imports_and_popup_rules
  test_firefox_plugin_preserves_custom_user_css
  test_firefox_plugin_migrates_legacy_generated_css
  test_zen_plugin_uses_managed_imports_and_migrates_legacy_css
  test_zen_plugin_repairs_incomplete_managed_import_block
  test_qutebrowser_plugin_writes_theme_and_config
  test_qutebrowser_light_mode_change_requires_restart
  test_fzf_plugin_writes_fish_theme
  test_fish_plugin_writes_shell_colors
  test_obsidian_terminal_plugin_discovers_registered_vault
  test_obsidian_terminal_plugin_direct_run_loads_theme_env
  test_emacs_plugin_skips_when_missing
  test_emacs_plugin_generates_standard_emacs_theme
  test_emacs_plugin_generates_doom_emacs_theme
  test_foot_plugin_respects_disable_flag
  test_foot_plugin_logs_missing_theme_file
  test_foot_plugin_reads_theme_and_logs_no_ttys
  test_foot_plugin_writes_osc_sequences_to_tty
  test_cava_plugin_writes_theme_and_updates_config
  test_cava_plugin_does_not_duplicate_theme_setting
  test_cliamp_uses_ansi_default_without_native
  test_cliamp_installs_canonical_native_dropping_inline_comments
  test_cliamp_falls_back_to_ansi_for_incomplete_native
  test_cliamp_ignores_native_without_opt_in_marker
  test_cliamp_requires_exact_opt_in_marker
  test_cliamp_fails_loud_when_config_cannot_be_created
  test_cliamp_only_removes_its_exact_owned_file
  test_cliamp_native_handles_crlf_opt_in_marker
  test_superfile_plugin_writes_theme_and_requests_restart
  test_zellij_plugin_generates_current_theme
  test_zellij_plugin_prefers_theme_provided_kdl
  test_zellij_plugin_skips_when_zellij_missing
  test_swaync_plugin_installs_theme_files_and_reloads
  test_swaync_plugin_prefers_named_theme_over_current_theme
  test_tmux_plugin_skips_without_theme_conf
  test_tmux_plugin_removes_managed_theme_when_theme_conf_missing
  test_tmux_plugin_installs_theme_and_reloads
  test_tmux_plugin_prefers_existing_legacy_config
  test_vscode_plugin_skips_when_theme_provides_vscode_json
  test_vscode_plugin_patches_extension_manifest_and_installs_theme
  test_vscode_plugin_builds_local_extension_from_source
  test_vscode_plugin_requires_extension_id_for_local_theme
  test_cursor_plugin_suppresses_electron_deprecation_warning
  test_theme_set_extracts_colors_with_leading_whitespace_and_comments
  test_install_preserves_disabled_plugins_and_installs_files
  test_install_preserves_existing_config
  test_install_keeps_non_executable_hooks_enabled
  test_install_recovers_all_bundled_plugins_disabled_by_bad_update
  test_install_recovery_preserves_custom_sample_hooks
  test_install_preserves_mixed_enabled_and_disabled_state
  test_install_preserves_enabled_branding_plugin
  test_install_respects_branch_override
  test_install_preserves_existing_sample_disabled_plugin
  test_install_restores_cliamp_hidden_sample
  test_install_disabled_sample_wins_over_stale_active_plugin
  test_install_preserves_custom_omarchy_hook
  test_install_preserves_custom_sample_hook
  test_install_preserves_user_theme_set_hook
  test_install_interactive_prompt_installs_missing_adw_theme
  test_install_gum_prompt_installs_missing_adw_theme
  test_uninstall_removes_files_and_qutebrowser_theme
  test_uninstall_warns_and_preserves_branding_when_default_missing
  test_uninstall_invokes_external_revert_commands

  if [[ "$TEST_FAILURES" -gt 0 ]]; then
    print_coverage_summary
    printf '\n%d test(s) failed.\n' "$TEST_FAILURES"
    exit 1
  fi

  print_coverage_summary
  printf '\nAll tests passed.\n'
}

main "$@"
