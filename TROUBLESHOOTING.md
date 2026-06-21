# Troubleshooting — pitfalls and fixes

Real problems hit while standing this server up on an Apple-silicon (M-series) Mac, and how to
solve them. Command shortcuts assume you're in the project directory.

> Docker context used by the scripts: `export DOCKER_CONTEXT=colima-valheim` (they do it for you).
> Live server logs: `./scripts/logs.sh` · full status: `./scripts/status.sh`

---

### 1. VM won't start: `guest agent binary could not be found for Linux-x86_64`
Lima (under Colima) only ships a guest agent for the native architecture (arm64); an **x86_64** VM
needs a separate package.
```bash
brew install lima-additional-guestagents
colima delete valheim --force      # clean up the failed attempt (the image stays cached)
./scripts/setup.sh
```

### 2. `colima start --vm-type qemu` fails: no qemu
Colima needs the QEMU binary to emulate x86_64 (not always pulled in by `colima`).
```bash
brew install qemu
```

### 3. Docker Desktop + Rosetta instead? — NO
The server image (mono/Unity) **crashes** under "Use Rosetta for x86/amd64 emulation" in Docker
Desktop (mono codegen error / SIGABRT). That's why this project uses **Colima + full QEMU**
(`--arch x86_64 --vm-type qemu`) — slower, but stable. Don't switch to Rosetta.

### 4. SteamCMD: `Info request for AppId 896660 returned error Timeout` / `Failed to download`
Usually **transient** (flaky Steam metadata) — don't panic, force a retry:
```bash
docker exec valheim supervisorctl restart valheim-updater
```
The updater retries by itself every 15 min anyway. If it keeps failing — check connectivity (you
should see `Connecting anonymously to Steam Public... OK`); if you see that, it's not the network,
just Steam being flaky.

### 5. A restart takes ~7 minutes
By default the image re-verifies (`validate`) all ~1.7 GB of files on every start — under QEMU that's
several minutes. This project disables it via `STEAMCMD_ARGS: ""` in `docker-compose.yml`
→ restart drops to ~2-3 min. If you edited the compose, make sure that line is there.

### 6. "Failed to connect" in game, with NO password prompt
The password prompt only appears AFTER a connection is established. "Failed to connect" without it =
the client never reached the server. Most common causes:
- **Server not ready yet** — on the FIRST world, map generation under QEMU takes **20+ min**
  (the log sits on `Generating locations` / `Failed to place all X` — those are NORMAL generation
  messages, not errors; CPU ~120% = it's working). Until generation finishes the server does NOT
  accept players. Wait for `Opened Steam server`.
- **Wrong address** — use the **Tailscale IPv4** (`100.x.y.z`) with port `:2456`, via "Join IP".
  NOT the short hostname (won't work across tailnets), NOT IPv6.
- **Crossplay** — keep it off (see #9).

> Tip: the first generation is one-time. Importing a ready world (`./scripts/import-world.sh`) skips it.

### 7. No `listening on UDP port 2456` line in the logs
This server version doesn't log that. The readiness signal is **`Opened Steam server`**, then a
periodic heartbeat `Connections X ZDOS:Y sent:Z recv:W` (every ~10 min). `./scripts/status.sh` checks it.

### 8. An empty server takes ~50% CPU (or ~1.2 cores on the Mac)
Normal. Valheim simulates the world non-stop even with no players (~25-30% of a core natively), and
QEMU bumps that up (~1.2 Mac cores). It's not a leak. `./scripts/stop.sh` kills the VM → 0% CPU and
the Mac can sleep. Keep the Mac on power during sessions (battery + emulation = heat/drain).

### 9. Crossplay breaks the Tailscale connection
Crossplay routes traffic through the PlayFab relay (no listening port), which tends to fail behind
VPN/NAT. Keep **crossplay off** (`SERVER_PUBLIC=false`, no `-crossplay`) — then it's a clean Steam
connection over Tailscale. All players must own Valheim on **Steam**.

### 10. Tailscale: share with friends or invite them?
**Share the NODE, don't invite them as users.** An invite lets them into your ENTIRE tailnet
(including e.g. Home Assistant); Share gives access only to the server node.
- Admin → Machines → server node → ⋯ → **Share** → a link for each person.
- While there: **Disable key expiry** for the node (so it doesn't log out between sessions).
- The default ACL lets shared users reach the game ports (2456-2457) — nothing to configure.
- Friends connect to `100.x.y.z:2456` (the Tailscale IPv4).

> Note: if a remote player's traffic must reach the game port and your ACLs are customized, make sure
> shared users (`autogroup:shared`) are allowed to the server node. With the default allow-all ACL it just works.

### 11. The Mac sleeps while playing
`play.sh` runs `caffeinate` — works with the **lid open / on power**. Lid closed:
```bash
sudo pmset -c disablesleep 1     # before the session (undo: sudo pmset -c disablesleep 0)
```
Keep it on power. Note: the server only runs while the Mac is **logged in** (Colima/docker live in
the user session) — waking to a login screen isn't enough.

### 12. The world is gone / I want to load a world from an old game
The world lives in the `valheim-config` volume (`/config/worlds_local` in the container) and survives
restarts. Import an existing world (both files, same name):
```bash
./scripts/import-world.sh ~/Downloads/World.db ~/Downloads/World.fwl
```
World backups: `./scripts/backup.sh` → `./backups/` (`stop.sh` does it too).

### 13. Reset from scratch
```bash
./scripts/stop.sh
colima delete valheim --force     # deletes the VM (the world is lost unless you have a backup!)
./scripts/setup.sh
```

### 14. Rubber-banding / lag for a REMOTE player (while the local host plays fine) — SOLVED
Symptoms: characters "slide", mobs teleport while dead, land loads slowly while sailing, a network
icon flickers in game — but **only** for the remote player; the host and players on the same network
are smooth. This is **NOT emulation** (CPU has headroom; if the server couldn't keep up it would
stutter for everyone) and **not anyone's link**. It's a **Tailscale DERP relay** for the remote peer.

**Cause:** when the Tailscale node runs **inside the VM**, it sits behind QEMU's **symmetric NAT**
(slirp/vmnet). Tailscale can't punch a direct path for a remote/cross-tailnet peer → it falls back to
the relay → jitter/drops.

**Diagnosis:**
```bash
# from inside the VM (old sidecar setup): MappingVariesByDestIP: true = symmetric NAT
docker exec valheim-ts tailscale netcheck
# from the remote player's machine: "direct" = good, "via DERP" = relay
tailscale ping <server-ip>
```

**The fix this project uses — run Tailscale on the Mac HOST, not in the VM.** The host sits behind
the router's *easy* NAT, so a remote player gets **direct P2P** instead of the relay. A small
`udp-proxy.py` bridge then carries the game's UDP from the host into the VM/container. This is wired
into `play.sh`/`stop.sh` and is the default. Full explanation and diagram: **[ARCHITECTURE.md](ARCHITECTURE.md)**.

Two bugs found while building the bridge (both fixed in `scripts/udp-proxy.py`, kept here as a warning):
- `socat -T<sec>` on a `UDP-LISTEN` listener gets killed after that many seconds of silence → the
  remote player hits a dead relay after the first idle window. (Fix: no idle timeout on the listener.)
- `socat UDP-LISTEN,fork` mangles demultiplexing with **more than one** concurrent client (each works
  alone, but a second player drops). (Fix: a proper per-client UDP proxy.)

Other ways to give remote players a direct path, if host-TS isn't an option:
- **Wired Ethernet + Colima bridged** (lowest ping; an L2 bridge won't work over Wi-Fi → needs a
  USB-C→Ethernet adapter).
- **Tailscale Peer Relay** (invite the player as a *user*, not a share) — still a relay, but private/low-ping.
- **A paid host** with a public IP — removes the NAT problem entirely (not free).
