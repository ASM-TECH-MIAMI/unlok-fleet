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
sudo pmset -a sleep 0 displaysleep 0 disksleep 0 womp 1 autorestart 1 powernap 1

banner "Disabling firewall (so mosh UDP 60000-61000 works)"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off >/dev/null

banner "Disabling auto-install of macOS updates (prevents surprise reboots that kill agents)"
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true

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

# Align Tailscale hostname with the OS hostname (no-op if Tailscale not yet up).
TS=/usr/local/bin/tailscale
[ -x "$TS" ] || TS=/opt/homebrew/bin/tailscale
if [ -x "$TS" ] && "$TS" status >/dev/null 2>&1; then
  banner "Aligning Tailscale hostname with $HOSTNAME"
  sudo "$TS" set --hostname="$HOSTNAME" 2>/dev/null || \
    "$TS" set --hostname="$HOSTNAME" 2>/dev/null || \
    echo "  (skip — could not set; rename manually in Tailscale admin console if needed)"
fi

cat <<DONE

============================================================
DONE. $HOSTNAME is configured.

REMAINING STEPS (cannot be automated — macOS blocks them from CLI):

1. Enable Remote Login (so the workstation can SSH in):
   System Settings -> General -> Sharing -> Remote Login -> ON
   "Allow access for" -> Only these users -> add $USER_NAME
   (CLI 'systemsetup -setremotelogin on' requires Full Disk Access.)

2. Enable auto-login (so the mini comes back unattended after a reboot):
   System Settings -> Users & Groups -> "Automatically log in as" -> $USER_NAME

3. Activate Claude Code on this helper (one-time, interactive):
   Run 'claude' in this terminal and complete the login flow.
   Either:
     a) Sign in with your claude.ai subscription (Pro/Max), OR
     b) Paste an Anthropic API key from console.anthropic.com.

4. (Optional) Install Claude Desktop GUI from https://claude.ai/download

5. On unlok-workstation, register this helper. Run there:

   curl -fsSL $REPO_RAW/add-helper.sh | bash -s -- $N "$(cat ~/.ssh/id_ed25519.pub)"

   The pubkey to paste is:

$(cat ~/.ssh/id_ed25519.pub)

6. From the workstation, test it:

   ssh $HOSTNAME 'hostname && claude --version'

============================================================
DONE
