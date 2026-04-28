# unlok-fleet

Bootstrap and dispatch tooling for the Unlok Mac mini fleet.

## The fleet

| Machine | Role | macOS user | Status |
|---|---|---|---|
| `unlok-workstation` | Driver (where you work) | `asm002` | ✅ live |
| `unlok-server-1` | Helper #1 | `mini3` | ✅ live |
| `unlok-server-2` | Helper #2 | `server-2` | ✅ live |
| `unlok-server-3` | Helper #3 | `server-3` | _pending setup_ |
| `unlok-server-4` | Helper #4 | `server-4` | _pending setup_ |

All on Tailscale tailnet `corp@unlok.me`. **Always reach machines by Tailscale name, never by LAN IP.**

---

## Before you start: what to download

You need these *before* opening a terminal on the new mini:

| What | Where | Required |
|---|---|---|
| **Tailscale** | Mac App Store | yes — paso 2 |
| **Claude Desktop** (GUI) | https://claude.ai/download | optional |
| Claude.ai subscription **or** Anthropic API key | https://claude.ai/upgrade or https://console.anthropic.com | yes — para activar Claude Code en paso 5 |

Everything else (Homebrew, tmux, mosh, Node, gh, Claude Code CLI) is installed by the bootstrap script. **Do not** try to install Homebrew or git manually first — the script handles it.

---

## Adding a new helper (server-N)

> Total time: ~20 minutes. The bootstrap is unattended after the first password prompt.

### Step 1 — macOS first-boot (~5 min, manual)

Power on the new mini and walk through the setup wizard:

- **Account name:** `server-N` (where N = `2`, `3`, `4`, ...)
- Skip Apple ID unless you specifically need iCloud on the helper.
- Connect to your network (Wi-Fi or ethernet).

### Step 2 — Tailscale (~2 min, manual)

1. Open the **App Store**, search "Tailscale", install.
2. Open the Tailscale app, **sign in** with the account that owns the `corp@unlok.me` tailnet.
3. Approve the device in the [admin console](https://login.tailscale.com/admin/machines).
4. **Verify the name has no typo.** It should appear as exactly `unlok-server-N` (not `unblok-...`, not `Alvaros-Mac-mini`, etc.). If wrong, click *Edit machine name* in the admin console and fix it before continuing.

Verify from the mini's terminal:
```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale status
```
You should see your mini and the rest of the fleet.

### Step 3 — Bootstrap (~10 min, mostly unattended)

In the new mini's **Terminal.app**, paste:

```bash
curl -fsSL https://raw.githubusercontent.com/ASM-TECH-MIAMI/unlok-fleet/main/bootstrap.sh | bash -s -- N
```

Replace `N` with the helper number.

> ⚠️ Run from a real Terminal window (Terminal.app or iTerm2) so `sudo` can prompt for your password. It will ask 1–2 times.

The script:
- Sets the hostname (ComputerName / LocalHostName / HostName) to `unlok-server-N`
- Configures power: never sleep (system + display + disk), wake on LAN, restart on power loss
- Disables firewall (so mosh UDP 60000-61000 works)
- Disables auto-install of macOS updates (prevents surprise reboots)
- Installs Homebrew + tmux + mosh + Node.js + gh
- Installs Claude Code CLI globally
- Writes `~/.zshenv` (PATH for non-interactive SSH) and `~/.tmux.conf`
- Generates the helper's SSH keypair
- Adds `unlok-workstation`'s pubkey to `authorized_keys`
- Creates `~/Documents/Claude/Unlok/` workspace + `CLAUDE.md`
- Aligns Tailscale hostname

At the end it prints the helper's **public SSH key** and a list of remaining manual steps. **Copy the pubkey.**

### Step 4 — Manual macOS settings (~2 min, GUI required)

These can't be done from the CLI on modern macOS (Apple blocks them without Full Disk Access).

**4a. Enable Remote Login** *(critical — without this, SSH from the workstation fails)*
> System Settings → General → **Sharing** → **Remote Login** → ON
> "Allow access for" → **Only these users** → add `server-N`

**4b. Enable auto-login** *(so the mini comes back unattended after power loss)*
> System Settings → **Users & Groups** → "Automatically log in as" → `server-N`

You'll need to type the user's password. FileVault must be off for this to work (it is by default on a fresh setup).

### Step 5 — Activate Claude Code (~2 min, interactive)

The bootstrap installs the `claude` binary, but each helper needs to be authenticated separately.

In the helper's terminal:
```bash
claude
```

Choose one:
- **Subscription**: Sign in with the same claude.ai account (Pro/Max). The CLI opens a browser; copy the code back to the terminal.
- **API key**: Paste a key from https://console.anthropic.com/settings/keys (set `ANTHROPIC_API_KEY=...` in `~/.zshenv` if you want it persistent without an interactive login).

Verify:
```bash
claude --version
echo "test" | claude -p "respond OK"
```

### Step 6 — Register helper with workstation (~30 sec)

On `unlok-workstation`, paste:

```bash
curl -fsSL https://raw.githubusercontent.com/ASM-TECH-MIAMI/unlok-fleet/main/add-helper.sh | bash -s -- N "ssh-ed25519 AAAA... server-N@unlok-server-N"
```

Replace the second arg with the actual pubkey from Step 3. This adds the helper's pubkey to the workstation, adds a `Host unlok-server-N` block to `~/.ssh/config`, and tests the connection.

### Step 7 — Verify

From the workstation:
```bash
ssh unlok-server-N 'hostname && claude --version'
fleet.sh status
```

If both work, the helper is part of the fleet.

### Step 8 (optional) — Claude Desktop GUI

If you want the Claude Desktop GUI on the helper (for MCPs, file browsing, etc.):
1. Download from https://claude.ai/download
2. Sign in
3. Configure MCPs as needed

Most agent work runs through the Claude Code CLI without the GUI.

---

## Daily use

From `unlok-workstation`:

```bash
fleet.sh status                    # uptime + disk + tmux on all helpers
fleet.sh all "claude -p 'task'"    # parallel Claude task on every helper
fleet.sh 2 "tmux ls"               # only on server-2
fleet.sh logs 3                    # recent agent logs from server-3
```

Install `fleet.sh` on the workstation once:
```bash
mkdir -p ~/bin
curl -fsSL https://raw.githubusercontent.com/ASM-TECH-MIAMI/unlok-fleet/main/fleet.sh -o ~/bin/fleet.sh
chmod +x ~/bin/fleet.sh
```

---

## Conventions

- **Naming:** every machine uses the same canonical name in 5 places — ComputerName, LocalHostName, HostName, Tailscale, and SSH config Host alias. Don't improvise variants.
- **Users:** helpers from this repo use `server-N` as the macOS username. Pre-existing machines keep their legacy usernames (`asm002`, `mini3`).
- **No LAN IPs:** always Tailscale MagicDNS hostnames.
- **No private keys committed.** Tailscale auth keys go through the admin console, not this repo.

---

## Troubleshooting

**`ssh unlok-server-N` falla con "Connection refused"**
→ Step 4a no se hizo. Encender Remote Login en System Settings.

**`ssh unlok-server-N` cuelga / timeout**
→ La mini no está alcanzable por Tailscale. Verifica con `tailscale status` desde la workstation.

**Bootstrap muere en `sudo: a terminal is required`**
→ Estás corriendo el `curl | bash` desde un contexto sin TTY (un wrapper, un IDE raro). Abre Terminal.app y vuelve a pegar.

**Bootstrap se queja de `/etc/paths.d/homebrew` durante el install de Homebrew**
→ Falla transitoria del prompt de sudo durante el install de brew. No es crítico; `~/.zshenv` arregla el PATH. Si quieres, después del bootstrap: `which brew` para confirmar que `/opt/homebrew/bin/brew` está en PATH.

**`claude` da error de autenticación tras el primer login**
→ Re-ejecuta `claude` y elige re-authenticate. Si usas API key, mete `export ANTHROPIC_API_KEY=...` en `~/.zshenv` y abre una nueva sesión.

**Después de un reboot la mini queda en pantalla de login**
→ Step 4b no se hizo (auto-login). Hazlo en System Settings y reinicia para probar.

**Tailscale aparece con nombre mal escrito en el admin (`unblok-...`, `Alvaros-Mac-mini`, etc.)**
→ Renómbralo en https://login.tailscale.com/admin/machines *antes* del bootstrap, o el script intentará alinearlo pero puede fallar.

---

## Files

- [bootstrap.sh](bootstrap.sh) — runs on a fresh helper to set everything up
- [add-helper.sh](add-helper.sh) — runs on the workstation to register a helper
- [fleet.sh](fleet.sh) — dispatch commands across the fleet
- [CLAUDE.md.template](CLAUDE.md.template) — workspace doc, copied into each helper's `~/Documents/Claude/Unlok/`
