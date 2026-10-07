#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

term_alpha=100 #Set this to < 100 make all your terminals transparent
# sleep 0 # idk i wanted some delay or colors dont get applied properly
if [ ! -d "$STATE_DIR"/user/generated ]; then
  mkdir -p "$STATE_DIR"/user/generated
fi
cd "$CONFIG_DIR" || exit

colornames=''
colorstrings=''
colorlist=()
colorvalues=()

colornames=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f1)
colorstrings=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f2 | cut -d ' ' -f2 | cut -d ";" -f1)
IFS=$'\n'
colorlist=($colornames)     # Array of color names
colorvalues=($colorstrings) # Array of color values

render_terminal_template() (
  local template="$1" destination="$2" temporary i
  temporary=$(mktemp "${destination}.XXXXXX") || exit
  trap 'rm -f -- "$temporary"' EXIT
  cp "$template" "$temporary" || exit
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$temporary" || exit
  done
  sed -i "s/\$alpha/$term_alpha/g" "$temporary" || exit
  if [[ $(<"$temporary") =~ \$[[:alpha:]_][[:alnum:]_]* ]]; then
    printf 'Incomplete terminal palette; keeping %s unchanged.\n' "$destination" >&2
    exit 1
  fi
  chmod --reference="$template" "$temporary" || exit
  # Kitty automatically reloads changed files. Publish only a complete theme.
  mv -f -- "$temporary" "$destination" || exit
)

apply_kitty() {  
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/kitty-theme.conf" ]; then
    echo "Template file not found for Kitty theme. Skipping that."
    return
  fi
  mkdir -p "$STATE_DIR"/user/generated/terminal
  render_terminal_template "$SCRIPT_DIR/terminal/kitty-theme.conf" \
    "$STATE_DIR/user/generated/terminal/kitty-theme.conf" || return

  # Reload
  if ! pgrep -x -u "$UID" kitty >/dev/null; then
    return
  fi
  pkill -SIGUSR1 -x -u "$UID" kitty
}

apply_anyterm() {
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/sequences.txt" ]; then
    echo "Template file not found for Terminal. Skipping that."
    return
  fi
  mkdir -p "$STATE_DIR"/user/generated/terminal
  render_terminal_template "$SCRIPT_DIR/terminal/sequences.txt" \
    "$STATE_DIR/user/generated/terminal/sequences.txt" || return

  for file in /dev/pts/*; do
    if [[ $file =~ ^/dev/pts/[0-9]+$ ]]; then
      # A stopped (Ctrl+S) or unresponsive terminal blocks writes indefinitely.
      {
      timeout --kill-after=1 2 cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file"
      } 2>/dev/null &
    fi
  done
  wait
}

apply_term() {
  apply_kitty || return
  apply_anyterm
}

# Check if terminal theming is enabled in config
CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
if [ -f "$CONFIG_FILE" ]; then
  enable_terminal=$(jq -r '.appearance.wallpaperTheming.enableTerminal' "$CONFIG_FILE")
  if [ "$enable_terminal" = "true" ]; then
    apply_term
  fi
else
  echo "Config file not found at $CONFIG_FILE. Applying terminal theming by default."
  apply_term
fi

# Qt theming is handled by apply-qt-theme.py in switchwall.sh.
