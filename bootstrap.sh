#!/bin/bash
# bootstrap.sh — set up a fresh Mac mini as unlok-server-N
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ASM-TECH-MIAMI/unlok-fleet/main/bootstrap.sh | bash -s -- N
#
# Where N is the helper number (2, 3, 4, ...).
#
# Run AFTER:
#   - macOS first-boot setup is done (account name = server-N)
#   - Tailscale is installed and signed into the corp@ tailnet

set -euo pipefail

N=${1:-}
if [ -z "$N" ] || ! [[ "$N" =~ ^[0-9]+$ ]]; then
  echo "Usage: bootstrap.sh <N>"
  echo "  N is the helper number (2, 3, 4, ...)"
  exit 1
fi

HOSTNAME="unlok-server-$N"
USER_NAME=$(whoami)

# Workstation's public SSH key — public-key crypto, not a secret.
WORKSTATION_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFn1qaF+iskYBJn+V8jLBoIvYagtMOuFexeyaYymjiGA asm002@unlok-workstation"

# Where this repo lives — used to fetch the CLAUDE.md template.
REPO_RAW="https://raw.githubusercontent.com/ASM-TECH-MIAMI/unlok-fleet/main"

banner() { printf "\n>>> %s\n" "$*"; }

banner "Setting hostname to $HOSTNAME"
sudo scutil --set ComputerName "$HOSTNAME"
sudo scutil --set LocalHostName "$HOSTNAME"
sudo scutil --set HostName "$HOSTNAME"

banner "Power settings: never sleep, wake on LAN, restart on power loss"
sudo pmset -a sleep 0 displaysleep 0 womp 1 autorestart 1 powernap 1

banner "Disabling firewall (so mosh UDP 60000-61000 works)"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off >/dev/null

if ! command -v brew >/dev/null 2>&1; then
  banner "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

banner "Installing tools (tmux, mosh, node, gh)"
brew install tmux mosh node gh

banner "Installing Claude Code CLI"
npm install -g @anthropic-ai/claude-code

banner "Writing ~/.zshenv (PATH for non-interactive SSH)"
cat > ~/.zshenv <<'ZSHENV'
# Loaded for ALL shells (including non-interactive SSH commands).
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
export PATH="/usr/local/bin:$PATH"
[ -d "$HOME/.npm-global/bin" ] && export PATH="$HOME/.npm-global/bin:$PATH"
ZSHENV

banner "Writing ~/.tmux.conf"
cat > ~/.tmux.conf <<'TMUX'
set -g mouse on
set -g history-limit 50000
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",*256col*:Tc"
setw -g mode-keys vi
TMUX

banner "Generating SSH keypair"
mkdir -p ~/.ssh && chmod 700 ~/.ssh
if [ ! -f ~/.ssh/id_ed25519 ]; then
  ssh-keygen -t ed25519 -N '' -C "$USER_NAME@$HOSTNAME" -f ~/.ssh/id_ed25519
fi

banner "Authorizing workstation to SSH in"
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
if ! grep -qF "$WORKSTATION_PUBKEY" ~/.ssh/authorized_keys; then
  echo "$WORKSTATION_PUBKEY" >> ~/.ssh/authorized_keys
fi

banner "Creating workspace skeleton"
mkdir -p ~/Documents/Claude/Unlok/scripts
mkdir -p ~/agents/{workspace,logs,scratch}

if curl -fsSL "$REPO_RAW/CLAUDE.md.template" -o /tmp/CLAUDE.md.template 2>/dev/null; then
  sed "s/__HOSTNAME__/$HOSTNAME/g; s/__N__/$N/g; s/__USER__/$USER_NAME/g" \
    /tmp/CLAUDE.md.template > ~/Documents/Claude/Unlok/CLAUDE.md
  rm -f /tmp/CLAUDE.md.template
fi

cat <<DONE

============================================================
DONE. $HOSTNAME is configured.

NEXT STEPS:

1. (optional) Install Claude Desktop GUI from https://claude.ai/download

2. On unlok-workstation, register this helper. Run there:

   curl -fsSL $REPO_RAW/add-helper.sh | bash -s -- $N "$(cat ~/.ssh/id_ed25519.pub)"

   The pubkey to paste is:

$(cat ~/.ssh/id_ed25519.pub)

3. From the workstation, test it:

   ssh $HOSTNAME 'hostname && claude --version'

============================================================
DONE
