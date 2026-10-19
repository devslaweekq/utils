#!/bin/bash
# Install zsh + Oh My Zsh on a clean Ubuntu and hook up ~/.bash_aliases.
# Usage: bash zsh-install.sh             (idempotent, safe to re-run)
#        bash zsh-install.sh --delete    (undo everything this script installed or created)
set -euo pipefail

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

ZSH_DIR="$HOME/.oh-my-zsh"
PLUGINS_DIR="$ZSH_DIR/custom/plugins"
MARK="# managed by zsh-install.sh"

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

clone() { # url dest
  if [ -d "$2/.git" ]; then
    git -C "$2" pull --ff-only --quiet || true
  else
    git clone --depth 1 --quiet "$1" "$2"
  fi
}

STATE_FILE="$HOME/.zsh-install.state"   # "pkg <name>" / "shell <path>" lines, used by --delete

# VS Code / Cursor (desktop and remote server) settings that get zsh as the default terminal profile
EDITOR_SETTINGS=(
  "$HOME/.config/Code/User/settings.json"
  "$HOME/.config/Cursor/User/settings.json"
  "$HOME/.vscode-server/data/Machine/settings.json"
  "$HOME/.cursor-server/data/Machine/settings.json"
)
SETTING_KEY="terminal.integrated.defaultProfile.linux"
SETTING_LINE="\"$SETTING_KEY\": \"zsh\""
SETTING_TAG="// zsh-install.sh"           # trails the line we add
OFF_TAG="// zsh-install.sh-off: "         # prefixes a pre-existing setting we commented out

# install only what is missing and remember it, so --delete does not remove git/curl you already had
install_pkg() {
  local pkg
  for pkg in "$@"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
      $SUDO apt install -y "$pkg"
      echo "pkg $pkg" >> "$STATE_FILE"
    fi
  done
}

set_editors_zsh() {
  local f
  for f in "${EDITOR_SETTINGS[@]}"; do
    if [ ! -s "$f" ]; then
      mkdir -p "$(dirname "$f")"
      printf '{\n    %s %s\n}\n' "$SETTING_LINE" "$SETTING_TAG" > "$f"
    elif grep -q "$SETTING_TAG\$" "$f"; then
      continue   # already done by a previous run
    elif ! grep -qE '^[[:space:]]*\{[[:space:]]*$' "$f"; then
      log "Skipping $f: cannot find the opening brace, add $SETTING_LINE manually"
    else
      # comment out an existing setting (--delete turns it back on), then add ours right after the opening brace
      sed -i "s|^\([[:space:]]*\)\(\"$SETTING_KEY\"\)|\1$OFF_TAG\2|" "$f"
      sed -i "0,/^[[:space:]]*{[[:space:]]*\$/ s|\$|\n    $SETTING_LINE, $SETTING_TAG|" "$f"
    fi
  done
}

unset_editors_zsh() {
  local f
  for f in "${EDITOR_SETTINGS[@]}"; do
    [ -f "$f" ] && grep -qF "// zsh-install.sh" "$f" || continue
    sed -i "\|$SETTING_TAG\$|d" "$f"
    sed -i "s|^\([[:space:]]*\)$OFF_TAG|\1|" "$f"
    # the file only existed for our line: drop it, and its directory if that is now empty
    if [ "$(tr -d '[:space:]' < "$f")" = "{}" ]; then
      rm -f "$f"
      rmdir "$(dirname "$f")" 2>/dev/null || true
    fi
  done
}

uninstall() {
  local prev pkgs latest

  log "Restoring the login shell"
  prev=$(awk '$1 == "shell" {print $2}' "$STATE_FILE" 2>/dev/null || true)
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" == */zsh ]]; then
    $SUDO chsh -s "${prev:-/bin/bash}" "$USER"
  fi

  log "Removing the zsh default from VS Code / Cursor settings"
  unset_editors_zsh

  log "Removing Oh My Zsh, plugins, the completion cache and zsh history"
  rm -rf "$ZSH_DIR" "$HOME"/.zcompdump* "$HOME/.zsh_history"

  if [ -f "$HOME/.zshrc" ] && grep -qF "$MARK" "$HOME/.zshrc"; then
    log "Removing ~/.zshrc"
    rm -f "$HOME/.zshrc"
    latest=$(ls -1t "$HOME"/.zshrc.bak.* 2>/dev/null | head -n 1 || true)
    if [ -n "$latest" ]; then
      log "Restoring your previous ~/.zshrc from $latest"
      mv "$latest" "$HOME/.zshrc"
    fi
  fi

  # git and curl are never removed, even if this script was the one that installed them
  pkgs=$(awk '$1 == "pkg" && $2 != "git" && $2 != "curl" {print $2}' "$STATE_FILE" 2>/dev/null | tr '\n' ' ' || true)
  if [ -n "$pkgs" ]; then
    log "Removing packages installed by this script: $pkgs"
    # shellcheck disable=SC2086
    $SUDO apt remove --purge $pkgs
  fi
  rm -f "$STATE_FILE"

  log "Done. Older ~/.zshrc.bak.* files were kept. Log out and back in."
}

case "${1:-}" in
  "") ;;
  --delete) uninstall; exit 0 ;;
  *) echo "Usage: bash zsh-install.sh [--delete]" >&2; exit 1 ;;
esac

log "Packages: zsh git curl fzf"
$SUDO apt update -y
install_pkg zsh git curl fzf

if apt-cache show zoxide >/dev/null 2>&1; then
  log "Package zoxide (smart cd: z <part-of-path>)"
  install_pkg zoxide
else
  log "zoxide is not available in this Ubuntu release, skipping"
fi

log "Oh My Zsh"
clone https://github.com/ohmyzsh/ohmyzsh.git "$ZSH_DIR"

log "Plugins"
mkdir -p "$PLUGINS_DIR"
clone https://github.com/zsh-users/zsh-autosuggestions.git     "$PLUGINS_DIR/zsh-autosuggestions"
clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$PLUGINS_DIR/zsh-syntax-highlighting"
clone https://github.com/zsh-users/zsh-completions.git         "$PLUGINS_DIR/zsh-completions"

log "~/.zshrc"
if [ -f "$HOME/.zshrc" ] && ! grep -qF "$MARK" "$HOME/.zshrc"; then
  cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%s)"
fi

cat > "$HOME/.zshrc" <<'EOF'
# managed by zsh-install.sh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
zstyle ':omz:update' mode reminder

export PATH="$HOME/.local/bin:$PATH"

# --- macOS-like directory navigation ---
setopt AUTO_CD            # `Downloads` instead of `cd Downloads`, `..` instead of `cd ..`
setopt CDABLE_VARS        # `cd CRYPTO` -> cd "$CRYPTO"
setopt AUTO_PUSHD         # every cd pushes the directory onto the stack
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
setopt PUSHD_MINUS        # `cd -2` = second directory in the stack; `d` prints the stack

# fpath for zsh-completions must be set before compinit (oh-my-zsh calls it)
fpath+="$ZSH/custom/plugins/zsh-completions/src"

# dirhistory: Alt+Left/Right = back/forward through visited dirs, Alt+Up = parent, Alt+Down = first subdir
# zsh-syntax-highlighting must be the last plugin in the list
plugins=(
  git sudo dirhistory extract colored-man-pages
  docker docker-compose npm fzf
  zsh-autosuggestions zsh-completions zsh-syntax-highlighting
)

source "$ZSH/oh-my-zsh.sh"
ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}(%{$fg[red]%}"

# --- completion: case-insensitive, with a selectable menu ---
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' menu select

# --- history ---
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE

# --- zoxide: `z foo` jumps to the most frequent directory matching "foo" ---
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# --- nvm (the `nv` alias from .bash_aliases calls nvm install/use) ---
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export PATH=/home/msi/.opencode/bin:$PATH
export PATH=$PATH:/usr/local/go/bin

# Added by Antigravity CLI installer
export PATH="/home/msi/.local/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# --- shared aliases and variables; sourced after oh-my-zsh so they override its aliases ---
[ -f "$HOME/.bash_aliases" ] && source "$HOME/.bash_aliases"
EOF

current_shell=$(getent passwd "$USER" | cut -d: -f7)
if [[ "$current_shell" != */zsh ]]; then
  log "Setting zsh as the login shell for terminals (remembering $current_shell for --delete)"
  grep -q '^shell ' "$STATE_FILE" 2>/dev/null || echo "shell $current_shell" >> "$STATE_FILE"
  $SUDO chsh -s "$(command -v zsh)" "$USER"
fi

log "Setting zsh as the default terminal profile in VS Code / Cursor"
set_editors_zsh

log "Done. Log out and back in so the login shell applies everywhere, or run: exec zsh"
