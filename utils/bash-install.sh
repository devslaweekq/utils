#!/bin/bash
# Nicer path completion in plain bash: cd ../<Tab> and cd ./ba<Tab> list the directories you can go to.
# Usage: bash bash-install.sh             (idempotent, safe to re-run)
#        bash bash-install.sh --delete    (undo everything this script installed or created)
set -euo pipefail

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

BASHRC="$HOME/.bashrc"
BASHRC_BAK="$HOME/.bashrc.bak.bash-install"
BEGIN="# >>> bash-install.sh >>>"
END="# <<< bash-install.sh <<<"
STATE_FILE="$HOME/.bash-install.state"   # "pkg <name>" lines, used by --delete

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

# install only what is missing and remember it, so --delete does not remove packages you already had
install_pkg() {
  local pkg
  for pkg in "$@"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
      $SUDO apt install -y "$pkg"
      echo "pkg $pkg" >> "$STATE_FILE"
    fi
  done
}

# the block that goes to the end of ~/.bashrc
print_block() {
  echo "$BEGIN"
  cat <<'EOF'
if [[ $- == *i* ]]; then
  # programmable completion: cd completes directories only
  if ! declare -F _init_completion >/dev/null && [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  fi

  bind 'set show-all-if-unmodified on'
  bind 'set completion-ignore-case on'        # `cd ./ba` also finds Backups
  bind 'set completion-map-case on'
  bind 'set mark-directories on'              # directories get a trailing /
  bind 'set mark-symlinked-directories on'
  bind 'set colored-stats on'                 # colors in the list, like ls
  bind 'set colored-completion-prefix on'
  bind '"\e[Z":menu-complete'                 # Shift+Tab cycles through the matches

  bind 'set show-all-if-ambiguous on'         # list the matches on the first Tab
  bind '"\e[A":history-search-backward'       # Up/Down search history by what is already typed
  bind '"\e[B":history-search-forward'
fi
EOF
  echo "$END"
}

remove_block() {
  [ -f "$BASHRC" ] && sed -i "\|$BEGIN|,\|$END|d" "$BASHRC"
  return 0
}

uninstall() {
  local pkgs

  log "Removing the block from ~/.bashrc"
  remove_block
  rm -f "$BASHRC_BAK"

  # git and curl are never removed, even if this script was the one that installed them
  pkgs=$(awk '$1 == "pkg" && $2 != "git" && $2 != "curl" {print $2}' "$STATE_FILE" 2>/dev/null | tr '\n' ' ' || true)
  if [ -n "$pkgs" ]; then
    log "Removing packages installed by this script: $pkgs"
    # shellcheck disable=SC2086
    $SUDO apt remove --purge $pkgs
  fi
  rm -f "$STATE_FILE"

  log "Done. Open a new terminal or run: exec bash"
}

case "${1:-}" in
  "") ;;
  --delete) uninstall; exit 0 ;;
  *) echo "Usage: bash bash-install.sh [--delete]" >&2; exit 1 ;;
esac

log "Packages: bash-completion"
$SUDO apt update -y
install_pkg bash-completion

log "~/.bashrc"
touch "$BASHRC"
[ -f "$BASHRC_BAK" ] || cp "$BASHRC" "$BASHRC_BAK"
remove_block
[ -z "$(tail -c1 "$BASHRC")" ] || echo >> "$BASHRC"
print_block >> "$BASHRC"

log "Done. Open a new terminal or run: exec bash"
