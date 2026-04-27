#!/bin/bash
# add-helper.sh — register a new helper on the workstation side
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ASM-TECH-MIAMI/unlok-fleet/main/add-helper.sh | bash -s -- N "<helper-pubkey>"
#
# Run THIS on unlok-workstation (NOT on the helper).

set -euo pipefail

N=${1:-}
PUBKEY=${2:-}

if [ -z "$N" ] || ! [[ "$N" =~ ^[0-9]+$ ]] || [ -z "$PUBKEY" ]; then
  echo "Usage: add-helper.sh <N> '<helper-pubkey>'"
  echo "  N is the helper number (2, 3, 4, ...)"
  echo "  helper-pubkey is the ssh-ed25519 ... line printed by bootstrap.sh"
  exit 1
fi

HOSTNAME="unlok-server-$N"
USER_NAME="server-$N"

banner() { printf "\n>>> %s\n" "$*"; }

banner "Authorizing $HOSTNAME to SSH back to this workstation"
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
if ! grep -qF "$PUBKEY" ~/.ssh/authorized_keys; then
  echo "$PUBKEY" >> ~/.ssh/authorized_keys
  echo "  added"
else
  echo "  already present"
fi

banner "Adding ~/.ssh/config entry for $HOSTNAME"
touch ~/.ssh/config
chmod 600 ~/.ssh/config
if ! grep -qE "^Host $HOSTNAME$" ~/.ssh/config; then
  cat >> ~/.ssh/config <<EOF

Host $HOSTNAME
  HostName $HOSTNAME
  User $USER_NAME
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m
  ServerAliveInterval 30
  ServerAliveCountMax 3
EOF
  echo "  added"
else
  echo "  already present"
fi

banner "Testing SSH connection to $HOSTNAME"
if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
     "$HOSTNAME" "hostname && whoami" 2>&1; then
  echo ""
  echo "✓ $HOSTNAME is in the fleet."
else
  echo ""
  echo "⚠ Could not reach $HOSTNAME. Common causes:"
  echo "  - Tailscale not connected on one of the ends"
  echo "  - The helper hasn't finished booting"
  echo "  - The pubkey arg was wrong"
fi
