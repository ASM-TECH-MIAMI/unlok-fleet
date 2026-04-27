# unlok-fleet

Bootstrap and dispatch tooling for the Unlok Mac mini fleet.

## The fleet

| Machine | Role | macOS user | Tailscale |
|---|---|---|---|
| `unlok-workstation` | Driver (where you work) | `asm002` | `100.127.43.98` |
| `unlok-server-1` | Helper #1 | `mini3` | `100.76.41.68` |
| `unlok-server-2` | Helper #2 | `server-2` | _(pending)_ |
| `unlok-server-3` | Helper #3 | `server-3` | _(pending)_ |
| `unlok-server-4` | Helper #4 | `server-4` | _(pending)_ |

All on Tailscale tailnet `corp@`. Always reach machines by Tailscale name, never by LAN IP.

---

## Adding a new helper (server-2, 3, or 4)

> Total time: ~15 minutes. Most of it is brew installing in the background.

### Step 1 — macOS first-boot (manual, ~5 min)

Power on the new mini and walk through the macOS setup wizard:

- **Account name:** `server-N` (where N is the helper number — `server-2`, `server-3`, etc.)
- Skip Apple ID if you don't need iCloud sync on the helper.
- Connect to your network.

### Step 2 — Tailscale (manual, ~1 min)

1. Install **Tailscale** from the Mac App Store.
2. Open it, sign in with the same account that owns the `corp@` tailnet.
3. Approve the new device in the Tailscale admin console.

### Step 3 — Run bootstrap (~10 min, mostly unattended)

Open Terminal on the new helper and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/ASM-TECH-MIAMI/unlok-fleet/main/bootstrap.sh | bash -s -- N
```

Replace `N` with the helper number (`2`, `3`, or `4`).

The script will:
- Set the hostname (ComputerName / LocalHostName / HostName) to `unlok-server-N`
- Configure power: never sleep, wake on LAN, restart on power loss
- Turn off the firewall (so mosh works)
- Install Homebrew + `tmux` + `mosh` + Node.js
- Install Claude Code CLI (`npm i -g @anthropic-ai/claude-code`)
- Write `~/.zshenv` (PATH for non-interactive SSH) and `~/.tmux.conf`
- Generate the helper's SSH keypair
- Add `unlok-workstation`'s pubkey to `~/.ssh/authorized_keys`
- Create the `~/Documents/Claude/Unlok/` workspace + `CLAUDE.md`

You'll be asked for your password 1-2 times (sudo for hostname / power settings).

At the end, the script prints the helper's **public SSH key**. Copy it.

### Step 4 — Register helper with workstation (~30 sec)

On `unlok-workstation`, paste:

```bash
curl -fsSL https://raw.githubusercontent.com/ASM-TECH-MIAMI/unlok-fleet/main/add-helper.sh | bash -s -- N "ssh-ed25519 AAAA... server-N@unlok-server-N"
```

(Replace the second arg with the actual pubkey from Step 3.)

This adds the helper's pubkey to the workstation's `authorized_keys`, adds a `Host unlok-server-N` block to `~/.ssh/config`, and tests the connection.

### Step 5 (optional) — Claude Desktop

If you want to run **Claude Desktop** (the GUI) on the helper:
1. Download from https://claude.ai/download
2. Sign in
3. Configure MCPs as needed

Most agent work can run via the Claude Code CLI without the GUI.

---

## Daily use

From `unlok-workstation`:

```bash
fleet.sh status                    # uptime + disk + tmux on all helpers
fleet.sh all "claude -p 'task'"    # run a Claude task on all 4 in parallel
fleet.sh 2 "tmux ls"               # only on server-2
fleet.sh logs 3                    # recent agent logs from server-3
```

Install `fleet.sh` on the workstation:
```bash
curl -fsSL https://raw.githubusercontent.com/ASM-TECH-MIAMI/unlok-fleet/main/fleet.sh -o ~/bin/fleet.sh
chmod +x ~/bin/fleet.sh
```

---

## Conventions

- **Naming:** every machine uses the same canonical name in 5 places: ComputerName, LocalHostName, HostName, Tailscale, and SSH config Host alias. Don't improvise variants.
- **Users:** helpers created from this repo use `server-N` as the macOS username (matches the machine name). The two pre-existing machines keep their legacy usernames (`asm002`, `mini3`).
- **No LAN IPs:** always use Tailscale MagicDNS hostnames. LAN IPs are DHCP and change.
- **No private keys committed.** Tailscale auth keys go through the admin console, not this repo.

---

## Files

- [bootstrap.sh](bootstrap.sh) — runs on a fresh helper to set everything up
- [add-helper.sh](add-helper.sh) — runs on the workstation to register a helper
- [fleet.sh](fleet.sh) — dispatch commands across the fleet
- [CLAUDE.md.template](CLAUDE.md.template) — workspace doc, copied into each helper's `~/Documents/Claude/Unlok/`
