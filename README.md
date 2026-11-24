<div align="center">

# Norypt Ghost

**Full-device identity rotation for the GL-iNet GL-E5800 (Mudi 7) 5G hotspot.**

*Every identifier your router broadcasts — IMEI, MAC, BSSID, SSID, hostname, host keys — rotated together, coherently, in one command.*

[![Build (script)](https://github.com/norypt-website/Norypt-Mudi7/actions/workflows/build.yml/badge.svg)](https://github.com/norypt-website/Norypt-Mudi7/actions/workflows/build.yml)
[![Build (SDK)](https://github.com/norypt-website/Norypt-Mudi7/actions/workflows/sdk-build.yml/badge.svg)](https://github.com/norypt-website/Norypt-Mudi7/actions/workflows/sdk-build.yml)
[![License: GPL-2.0](https://img.shields.io/badge/License-GPL--2.0-blue.svg)](#license)
[![Platform](https://img.shields.io/badge/platform-GL--E5800%20(Mudi%207)-8900ff.svg)](#compatibility)
[![Verified TACs](https://img.shields.io/badge/TAC%20pool-verified-00c2ff.svg)](#imei-realism-the-profile-catalog)

</div>

---

A travel router is a beacon. It shouts an IMEI at every cell tower, a set of BSSIDs at every Wi-Fi scanner in range, an SSID and hostname to every client, and it quietly writes down every device that ever connected to it. Rotate one of those and the others still link you to yesterday.

**Norypt Ghost rotates all of them at once — and makes the result look like an ordinary phone.**

```console
$ norypt-ghost new-identity
norypt-ghost: staging new device identity...
  Profile: apple-iphone-15-pro-eu
  SSID:    iPhone
norypt-ghost: rebooting in 5s to apply the new identity cleanly.
  Scan the QR on the device screen to rejoin Wi-Fi.
```

One command. One reboot. New IMEIs on both SIM slots, new MACs on every radio *and* the wired port, new SSID, new passwords, new hostname, new SSH host keys, new TLS certificates — and no record of the old identity kept in RAM or written to flash to bridge the two.

---

## Why this exists

<table>
<tr>
<td width="50%" valign="top">

### Coherent, not just random

Most tools randomize each field independently. That produces impossible devices — an Apple OUI broadcasting a NETGEAR SSID — which is *more* identifying, not less.

Norypt Ghost picks **one real device profile** per rotation. The IMEI's TAC vendor, the Wi-Fi OUI vendor, and the SSID all name the same phone, by construction.

</td>
<td width="50%" valign="top">

### Verified, not invented

Every TAC in the catalog is the real first-8 digits of a genuine device IMEI, sourced from a public IMEI registry with the URL recorded per entry.

A fabricated TAC — or a real one whose radio bands don't match the cell you attach to — is internally inconsistent, and an inconsistent identity is a weaker privacy measure than a coherent one.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### Blends into the largest anonymity set

The catalog presents the device as a popular smartphone tethering its SIM — millions of identical units — rather than a niche hotspot model with a few thousand.

Modern phones also randomize their own hotspot BSSID, so the locally-administered MAC bit reads as *normal phone behavior* rather than an anomaly.

</td>
<td width="50%" valign="top">

### Forgets everything, by default

Stock firmware keeps a permanent on-flash database of every client that ever connected, plus DNS query logs, lease files, and bandwidth stats per device.

Norypt Ghost RAM-backs all of it, so the device keeps no standing record of who connected — data minimization by default, the way a privacy-first device should behave. `norypt-ghost check` fails loudly if that ever stops being true.

</td>
</tr>
</table>

### Intended use and legal notice

Norypt Ghost is a privacy-research and personal-privacy tool for people working on hardware they own. It is intended for security and privacy research, education, testing on equipment you own or are authorized to test, and lawful personal-privacy use where permitted.

**Modifying a device's IMEI, and altering network identifiers, is restricted or a criminal offense in many jurisdictions.** You are solely responsible for ensuring your use complies with all applicable laws and with your mobile carrier's terms of service. Do not use this project to commit fraud, to evade lawful process, to interfere with networks or devices you do not own, or for any other unlawful purpose. It is provided "as is," without warranty, and the authors accept no liability for misuse. If you are unsure whether a particular use is lawful where you are, do not proceed.

---

## Table of Contents

- [Feature Matrix](#feature-matrix)
- [Compatibility](#compatibility)
- [Quick Start](#quick-start)
- [Usage](#usage) — [LuCI](#luci-admin-page) · [CLI](#command-line) · [Touchscreen](#touchscreen-menu) · [Health check](#health-check)
- [How It Works](#how-it-works)
  - [What it protects (and what it can't)](#what-it-protects-and-what-it-cant)
  - [`new-identity`: the full clean rotation](#new-identity-the-full-clean-rotation)
  - [IMEI realism: the profile catalog](#imei-realism-the-profile-catalog)
  - [Boot sequence](#boot-sequence)
  - [IMEI rotation](#imei-rotation) · [IMEI modes](#imei-modes)
  - [SIM-swap flow](#sim-swap-flow)
  - [MAC, BSSID, and SSID randomization](#mac-bssid-and-ssid-randomization)
  - [RAT lock (2G/3G downgrade block)](#rat-lock-2g3g-downgrade-block)
  - [No persistent connected-device logs](#no-persistent-connected-device-logs)
  - [No-retention model](#no-retention-model)
  - [TTL normalization](#ttl-normalization)
  - [Splash screens](#splash-screens)
- [Configuration Reference](#configuration-reference)
- [Building from Source](#building-from-source)
- [Uninstalling](#uninstalling)
- [AT Commands We Deliberately Avoid](#at-commands-we-deliberately-avoid)
- [Project Status](#project-status) · [Roadmap](#roadmap)
- [Repository Layout](#repository-layout)
- [Attribution](#attribution) · [License](#license)

---

## Feature Matrix

| | Feature | What it does |
|---|---|---|
| ⚡ | **`new-identity`** | One command, one reboot: coherent device profile, both IMEIs, every MAC (Wi-Fi **and** wired), SSID, passwords, hostname, SSH host keys, and the web-admin TLS certs — all rotated together, with a join QR to reconnect |
| 🎭 | **Profile catalog** | Six real-phone archetypes (Apple / Samsung, EU + US) with **verified TACs** and vendor-matched OUIs — the presented identity is internally consistent at every layer |
| 📡 | **Dual IMEI rotation** | Both modem slots (SIM 1 + SIM 2/eSIM) rotated independently via `AT+EGMR`, persisted to modem NV |
| 🔀 | **Three IMEI modes** | Per-slot **Random** (Luhn-valid, band-matched TAC), **Deterministic** (stable per-SIM), or **Static** (user-supplied) |
| 🛡️ | **RAT lock** | Modem locked to 5G NR / LTE, blocking the 2G downgrade IMSI-catchers rely on to strip authentication |
| 🔁 | **Two-stage SIM swap** | Throwaway IMEIs written before poweroff, final IMEIs on next boot *before* first attach — neither real identity bridges the swap |
| 🧹 | **No connected-device logs** | Syslog, DNS query log, DHCP leases, client-MAC DB, and bandwidth stats all RAM-backed — nothing about a client reaches flash |
| 🕳️ | **No-retention model** | No factory/original identity is ever captured, stored, or recoverable — there is nothing on flash that bridges an old identity to a new one |
| 🥷 | **TTL normalization** | Egress TTL/hop-limit pinned to 64, so forwarded client traffic stays consistent with the single-device profile the tool presents |
| 🔑 | **Host-key rotation** | SSH host keys and the GL admin (nginx) + LuCI TLS certs regenerated — permanent identifiers that survive every lesser rotation |
| 🩺 | **Health check** | `norypt-ghost check` — read-only self-test of modem, generator, services, and the no-logs guarantee; non-zero exit on failure |
| 🖥️ | **Three control surfaces** | CLI over SSH, a LuCI admin page, and an on-device touchscreen menu (2-second clock long-press) |
| 📶 | **Network visibility** | Per-slot registration state, operator, and signal in both CLI and LuCI |
| 🖼️ | **Splash screens** | Six full-screen status frames written straight to the framebuffer during operations |

---

## Compatibility

| | |
|---|---|
| **Device** | GL-iNet GL-E5800 (Mudi 7) |
| **Firmware** | GL.iNet 4.8.3, 4.8.5 and 4.10.3 (OpenWrt 23.05.4) |
| **Modem firmware** | `RG650VNA01ACR02A04G8G` (same revision string in 4.8.3, 4.8.5 and 4.10.3; the 4.10.3 baseband binary differs) |
| **Architecture** | `aarch64_cortex-a53` |
| **Required deps** | `luci-base`, `lua`, `luabitop`, `jsonfilter` — all present in stock firmware |
| **Optional deps** | `qrencode` + `fbv`/`fbi` (on-screen join QR) |

The installer verifies the device model and firmware version before touching anything. Unknown firmware prompts for confirmation on interactive SSH installs; non-interactive installs on unknown firmware abort safely.

> **Firmware upgrades remove the package without running its uninstall hooks.** The modem keeps its current rotated IMEIs, and with *Keep Settings* the rotated MACs/SSID/passwords/hostname are kept too — but the no-log protections are off until you reinstall. Reinstall right after every firmware upgrade.
>
> **Before upgrading, run `norypt-ghost prepare-upgrade`.** GL-iNet's *Keep Settings* backup copies `/etc/oui-tertf/client.db`, `/etc/gl_modem_traffic/` and the DPI databases from the *running* system, so without this the RAM-only connected-device history would be written into the new firmware's flash.
>
> **4.10.3 support** was verified by diffing the 4.10.3 and 4.8.5 system images (init order, AT tooling, UCI layout, keep-lists, new services). Confirm on your unit with `norypt-ghost check` after installing.

---

## Quick Start

**1 — Enable LuCI** (bundled with the firmware, off by default, no internet required):

Open `http://192.168.8.1` → **System → Advanced Settings** → **Install Now**. LuCI is then at `http://192.168.8.1:8080`.

**2 — Install the package:**

```sh
scp -O norypt-ghost_1.0.0-Script-Local.ipk root@192.168.8.1:/tmp/
ssh root@192.168.8.1 opkg install /tmp/norypt-ghost_1.0.0-Script-Local.ipk
```

```console
Installing norypt-ghost (1.0.0) to root...
Firmware 4.8.5 confirmed supported.
Configuring norypt-ghost.
norypt-ghost: setup complete (no-retention model).
  Change identity on demand: norypt-ghost new-identity  (or the on-screen menu).
```

**No factory or original identity is ever captured.** Install only enables the services and writes safe defaults — there is no stored copy of your device's real IMEIs, MACs, SSIDs, or keys anywhere on flash. Identity is stable across reboots and changes only when you ask it to (via `norypt-ghost new-identity`/`rotate`, or the on-device menu).

**3 — Verify, then rotate:**

```sh
ssh root@192.168.8.1
norypt-ghost check          # everything should PASS
norypt-ghost new-identity   # full clean rotation (reboots)
```

The admin page lives under **Services → Norypt Ghost** in LuCI.

---

## Usage

### LuCI admin page

**Services → Norypt Ghost** (`http://192.168.8.1:8080`):

| Section | Contents |
|---|---|
| **Actions** | **New Identity** (primary, double-confirmed — full rotation + reboot), then the advanced partial actions: Rotate IMEIs, Rotate Wireless/System, SIM Swap |
| **IMEI** | Current IMEI per slot, IMSI, and live network state (registration / operator / signal, loaded asynchronously) |
| **Wireless/System Identity** | Current SSID, all nine MACs/BSSIDs, hostname, and the main/guest passwords (masked, with Show/Hide) |
| **Rotation Options** | Per-feature checkboxes; per-slot IMEI mode radios with inline-validated static fields; re-attach timeout; touchscreen trigger. A separate **Security / Region** section holds the RAT lock and default region. Every control saves instantly |
| **Last Command Log** | Output of the most recent operation (`/tmp/norypt-ghost.log`) |

> Screenshots are intentionally not committed — the admin page displays live IMEIs, IMSIs, and BSSIDs, and publishing a real unit's would expose them permanently.

### Command line

```sh
norypt-ghost new-identity      # ⭐ full clean rotation: new profile, every identifier, reboot
norypt-ghost status            # identity + network registration overview
norypt-ghost check             # health check (see below)
norypt-ghost rotate            # partial, live: rotate both IMEIs only
norypt-ghost rotate-wireless   # partial, live: rotate MACs/SSID/hostname/password only
norypt-ghost sim-swap          # stage 1 of the SIM-swap flow (powers off!)
norypt-ghost prepare-upgrade   # run right before a firmware upgrade (wipes RAM-only history)
norypt-ghost forget-sims       # forget every SIM that is not inserted
norypt-ghost wipe-logs         # delete on-flash logs now and move log dirs to RAM
norypt-ghost wipe-sms          # delete every stored SMS now
norypt-ghost install           # one-time setup: enable services, write defaults
norypt-ghost help              # full usage, including per-slot mode flags
```

`rotate` and `rotate-wireless` are **partial, live** operations — handy for a quick refresh, but each leaves the other layer as a linking handle. Use `new-identity` for a real break.

Per-slot IMEI modes can be set for a single run (`--slot1=deterministic --slot2=random`, or `--random` / `--deterministic` / `--static` for both). Invalid modes fail loudly rather than silently falling back. Persistent defaults live in UCI.

`status` includes a Network section — the first place to look when a SIM won't connect:

```console
=== Network ===
  Slot 1 registration: registered (home)
  Slot 2 registration: not registered (idle)
  Operator: <carrier>
  Signal:   -77 dBm
```

### Touchscreen menu

Hold the **clock in the top-left corner** for **2 seconds** to open the on-device menu — every action, right on the screen, no laptop needed. The menu is drawn full-screen straight to the framebuffer:

| Item | What it does |
|---|---|
| **New Identity** | Full clean rotation, then reboots (same as `norypt-ghost new-identity`) |
| **SIM Swap** | Stage 1 of the SIM-swap flow — writes throwaway IMEIs and powers off |
| **Rotate IMEIs** | Rotates both slot IMEIs, live (same as `norypt-ghost rotate`) |
| **Rotate Wireless** | Rotates MACs/SSID/hostname/password, live (same as `norypt-ghost rotate-wireless`) |
| **Cancel** | Closes the menu and hands the screen back to the stock UI |

Pick an item, confirm on the follow-up screen, and the daemon runs it. For the IMEI-rotating actions (**New Identity**, **Rotate IMEIs**) the screen then shows the **last three digits** of the old and new IMEI (`............572`) so you can confirm the change at a glance before the frame is handed back (or the reboot proceeds).

The `norypt-ghost-touch` daemon (a small statically linked C binary, source in `src/`) reads `/dev/input/event0` *without* grabbing it, so the stock `gl_screen` UI keeps working while the menu is closed. It owns the framebuffer only while the menu is on screen, and hands it back seamlessly: on open it **freezes** `gl_screen` (`SIGSTOP`) and snapshots the current screen, draws the menu into the framebuffer, and on close **restores that snapshot and resumes** `gl_screen` (`SIGCONT`) — so the stock UI returns instantly and exactly as it was. It never kills or restarts the display service (an earlier approach that visibly disrupted the panel and the USB link on real hardware); freeze-and-restore keeps the device rock-steady. Menu text and the masked-IMEI readout are drawn by the daemon itself, from an embedded bitmap font — the device has no runtime text renderer. Guards against accidents:

- 2-second hold required — quick taps are logged and ignored
- 10-second cooldown between menu opens
- Blocked while a sim-swap is already in progress
- The menu auto-cancels after 15 seconds of inactivity

Toggle from LuCI → Rotation Options → **Touchscreen Trigger**, or `/etc/init.d/norypt-ghost-touch disable && /etc/init.d/norypt-ghost-touch stop`.

### Health check

`norypt-ghost check` is a read-only self-test — run it any time something seems off, or after a firmware update:

```console
=== norypt-ghost health check ===

Modem:
  PASS  gl_modem present
  PASS  AT socket present (/tmp/modem.CPU.AT.sock)
  PASS  modem answers AT commands
  PASS  IMEI readable (slot 1: <current IMEI>)

IMEI generator:
  PASS  lua generator produces valid IMEIs (sample: <generated>)
  PASS  TAC pool present
  PASS  OUI pool present

Splash frames:
  PASS  all 6 frames present
  PASS  framebuffer present (/dev/fb0)

Services:
  PASS  norypt-ghost-clean enabled
  PASS  norypt-ghost-wireless enabled
  PASS  norypt-ghost-sim-swap enabled
  PASS  norypt-ghost-touch enabled and running
  PASS  syslog not persisted to flash
  PASS  /etc/oui-tertf is RAM-backed

Result: all checks passed.
```

**Exit code is non-zero if anything FAILs** — including a broken no-logs guarantee — so it works as a scripted gate.

---

## How It Works

### What it protects (and what it can't)

Norypt Ghost reduces the **device-identity** trail a mobile hotspot leaves: the IMEI broadcast to towers, the MACs/BSSIDs/SSID visible to anyone scanning, the hostname, the host keys, and the on-flash record of who connected. It cannot anonymize what it doesn't control:

| Out of scope | Why |
|---|---|
| **The SIM itself** | IMSI/ICCID identify the subscriber regardless of IMEI. Rotating the IMEI alone unlinks only the *hardware* — use the [SIM-swap flow](#sim-swap-flow) for a clean break |
| **The eSIM EID** | A fixed hardware identifier of the eUICC, presented during remote provisioning. Not rotatable |
| **The eSIM app's cloud check-in** | GL-iNet's bundled eSIM client sends the slot's IMEI to its provider's server. Norypt Ghost keeps it off by default (`block_esim`); if you turn it back on to manage eSIM profiles, it sends the *rotated* IMEI |
| **Static IMEI mode** | If you choose the `static` IMEI mode, the IMEI you enter is stored in `/etc/config/norypt-ghost` by design. The default `random` mode stores none |
| **6 GHz AFC location** | When 6 GHz standard-power AFC is configured, GL-iNet stores the device location (encrypted) in `/etc/afc/` |
| **Location & behavior** | Reappearing in the same place, at the same times, with the same traffic patterns re-links identities no rotation can hide |
| **Upstream traffic** | Norypt Ghost handles the radio-identity layer only. Use a VPN/Tor on top |

The deterministic IMEI mode deliberately trades unlinkability for consistency — see [IMEI modes](#imei-modes).

### `new-identity`: the full clean rotation

The single command that changes **everything at once**, across a clean reboot:

1. **Picks a whole coherent device profile** from `profiles.json` — vendor, Wi-Fi OUI, client OUI, SSID/hostname/password format, region, and a matching verified TAC. Not independent random fields, so the result can never show one vendor's SSID over another's OUI.
2. **Validates every derived value first** (SSID, both passwords ≥ 16 chars, hostname, both IMEIs Luhn-valid) — on any failure it aborts with nothing changed.
3. **Writes the new IMEIs now, with RF off**, and reads them back. If the write or read-back fails it stops here: RF stays off and no other identifier has changed.
4. **Stages the wireless + system identity** into UCI: all six AP BSSIDs (profile's Wi-Fi OUI), the repeater STA MAC (client OUI), the **wired** WAN/LAN MAC, SSID + guest SSID, both passwords, hostname, and the DHCP hostname sent upstream.
5. **Regenerates SSH host keys and the TLS certs** (GL admin UI on nginx, and LuCI) — permanent device identifiers that survive `rotate`/`rotate-wireless` untouched. The admin cert keeps GL-iNet's stock subject, shared by every GL unit, so only its key and dates differ.
6. **Shows the join credentials**: the SSID and password on the console (never logged), plus a `WIFI:` QR on the device screen when `qrencode` and a framebuffer viewer are installed. GL's own Wi-Fi screen page also shows them.
7. **Fresh start, settings kept**: every SMS, every on-flash log, crash dump, shell history and connected-device record is deleted (with eMMC discard), and GL's per-SIM settings keep only the SIM(s) inserted now. Settings (VPN, Wi-Fi, firewall, the current SIM's APN, passwords) are kept.
8. **Reboots.** RF stays off from step 3 until the reboot, and the modem comes back up already holding the new IMEIs, so the old IMEI never re-attaches. At S25 the IMEIs are verified (and rewritten with RF off if the modem disagrees); the check repeats on every boot until it passes. Because it's a reboot, all RAM-resident correlation state (client-MAC DB, DHCP leases, ARP/conntrack, in-memory log) is gone too.

> **Why the IMEIs are written before the reboot:** the AT interface only answers at S25, after `gl_cellular_manager` (S23) has already attached. An IMEI staged only for the next boot would let the old IMEI re-attach for a few seconds, from the same cell, right before the new one.

### IMEI realism: the profile catalog

`files/usr/share/norypt-ghost/profiles.json` is the heart of the coherent-identity model. Each entry is one complete, consistent real-device archetype:

```jsonc
{
  "id": "apple-iphone-15-pro-eu",
  "class": "phone", "region": "EU", "vendor": "Apple",
  "imei_tacs": [
    { "tac": "35937079", "device": "Apple iPhone 15 Pro (A3102, intl)",
      "verified": true, "source": "https://swappa.com/imei/info/359370797011487" }
  ],
  "wifi_oui":   ["3C:22:FB", "40:98:AD", "88:66:5A"],
  "client_oui": ["F4:D4:88", "AC:DE:48"],
  "ssid_format": "iPhone",
  "hostname_format": "iPhone",
  "bands": ["n1", "n3", "n7", "n28", "n78"]
}
```

Design rules, enforced automatically:

- **Phone-only.** The device presents as a popular smartphone tethering its SIM — a far larger anonymity set than any single hotspot model, and it reads as a phone on the carrier's network.
- **Every TAC verified.** Each is the real first-8 digits of a genuine device IMEI from a public registry, with the source URL stored per entry. **CI fails the build** if any TAC is ever left unverified (`tests/run.sh --release`).
- **Vendor coherence by construction.** A validator asserts that the IMEI TAC vendor, the Wi-Fi OUI vendor, and the SSID all name the same device — and that `wifi_oui` and `client_oui` never overlap, because a real phone doesn't use its own AP OUI for its upstream client interface.
- **Universally-administered OUIs only**, checked bit-by-bit (a locally-administered value in the pool would mean it was never a real vendor allocation).
- **Region-aware.** The SIM's IMSI MCC selects the EU or NA pool at rotation time, so the IMEI is plausible for the network the SIM actually belongs to; `default_region` covers an unreadable SIM.

### Boot sequence

| Priority | Service | What it does |
|---|---|---|
| **S9** | `norypt-ghost-clean` | Before any GL-iNet tracker starts: RAM-backs the syslog, `tmpfs`-mounts every present telemetry directory, disables dnsmasq query logging/caching |
| **S10** | `norypt-ghost-wireless` | Boot rotation of MACs/SSID/hostname/passwords — *skipped* when a `new-identity` is staged, so it never clobbers the coherent identity |
| **S23** | `gl_cellular_manager` | GL-iNet's modem init — the first point where the AT socket accepts commands |
| **S25** | `norypt-ghost-sim-swap` | `new-identity` pending: verifies the pre-written IMEIs (rewrites with RF off only on mismatch). Sim-swap pending: RF off as soon as AT answers, writes + verifies the final IMEIs, RAT lock, RF on. Exits instantly on normal boots |
| **S45** | `norypt-ghost-ttl` | Normalizes egress TTL/hop-limit to 64 (`nft`, falling back to `iptables`/`ip6tables`) |
| **S80** | `gl_screen` | GL-iNet's touchscreen UI daemon |
| **S81** | `norypt-ghost-touch` | The long-press trigger daemon (procd-managed, auto-respawns) |

### IMEI rotation

1. **RF off** (`AT+CFUN=4`) — the old IMEI stops transmitting before anything is written
2. Both slots written via `AT+EGMR` (field 7 = Slot 1, field 11 = Slot 2/eSIM), NV-persisted with `AT+QPRTPARA=1`
3. **RF on** (`AT+CFUN=1`) + automatic operator re-attach (`AT+COPS=0`)
4. Registration polled via `AT+CEREG?` until attached or the configured timeout (default 120 s)
5. `gl_cellular_manager` restarted so GL-iNet's cached IMEI (Settings → About Device) matches the modem

A re-attach timeout is **non-fatal**: the warning screen shows, RF stays on, and the modem keeps retrying — relevant for factory-fresh SIMs whose first activation can take the carrier minutes.

If a *write* fails, Norypt Ghost deliberately leaves RF **off** rather than transmit a half-rotated identity, shows the error screen, and prints recovery steps.

### IMEI modes

| Mode | Behavior | Trade-off |
|---|---|---|
| **Random** *(default)* | A TAC from the pool + 6 rejection-sampled serial digits + Luhn check digit | Best unlinkability |
| **Deterministic** | `luhn(tac[djb2(IMSI) % n] + serial(djb2(IMSI)))` — the same SIM always maps to the same IMEI | Useful when a stable per-SIM identity is preferable to one that changes, but djb2 is a *public, unkeyed* hash: anyone who once observes the IMEI↔IMSI pairing can re-derive it forever |
| **Static** | A user-supplied 15-digit IMEI, Luhn-validated client- *and* server-side | Written verbatim on every rotation |

All three fall back to Random (with a warning) if their inputs are unavailable, so a rotation never fails on a missing IMSI or unset static value.

**Random** mode (`rotate`, `sim-swap`) draws from the same **verified** phone TACs as `new-identity`: it picks a catalog profile for the SIM's region (IMSI MCC, else `default_region`) and appends a `/dev/urandom` serial, so it produces a genuine phone IMEI just like `new-identity` does. The legacy `tac_pool.json` is only a last-resort fallback if the catalog can't be read. (Note that `rotate` changes *only* the IMEIs: for a single coherent phone across IMEI **and** Wi-Fi/SSID/hostname together, use `new-identity`.)

**Band matching matters.** A coherent identity has to be internally consistent: a 4G-only TAC presented on a 5G NR cell is a contradiction, and an inconsistent profile is a weaker privacy measure than a consistent one. Every catalog profile records its band set so the presented device stays plausible.

### SIM-swap flow

The problem with a naive swap: if the modem ever holds *old SIM + new IMEI* (or vice versa), the two identities become linkable. Norypt Ghost splits the swap across a power cycle so they never coexist on air:

1. **Stage 1** (`sim-swap`, touchscreen, or LuCI) — RF off → random **throwaway** IMEIs written to both slots → state saved → device powers off
2. **You swap SIM(s)** — and ideally location — while it's off
3. **Stage 2** (S25, automatic) — the AT interface only answers at S25, after `gl_cellular_manager` (S23) may already have attached the **throwaway** IMEI for a few seconds. Stage 2 polls every second, cuts RF the moment AT answers, writes and verifies the final IMEIs, applies the RAT lock, then re-enables RF. The throwaway is random and never linked to the old identity, so neither real identity bridges the swap

If Stage 2 can't reach the modem, or a write fails its read-back, it keeps the pending state and retries next boot with RF off — the modem keeps the harmless throwaway identity meanwhile. Only the IMEI *modes* are stored for Stage 2: no IMEI, IMSI or ICCID of the outgoing SIM is ever written to flash.

### MAC, BSSID, and SSID randomization

There are two paths, and they differ deliberately:

**`new-identity` (recommended)** draws everything from one phone profile — all six AP interfaces share the profile's vendor OUI, the repeater STA gets a client-class OUI, and the SSID is that phone's hotspot name (`iPhone`, `Galaxy-S24-A3F1`).

**`rotate-wireless` / boot rotation (partial, live)** uses the legacy curated router pool in `oui_pool.json`: one router vendor per rotation, all BSSIDs sharing its OUI, SSID `<brand>-XXXX` to match (vendors whose factory SSIDs aren't brand-prefixed use a generic `HOME-XXXX`).

Common to both:

- **The locally-administered bit is forced** on every generated MAC. The Qualcomm `ath11k` driver requires LA MACs for runtime channel changes on AP interfaces. With the phone profiles this is *authentic* — modern phones randomize their own SoftAP BSSID the same way.
- **GL-iNet's `random_bssid` is disabled at install** (it generates its own MACs on its own schedule) and re-enabled at uninstall.
- Main and guest networks get **independent** random passwords.

### RAT lock (2G/3G downgrade block)

The classic IMSI-catcher technique is a **downgrade**: force the device onto 2G, where mutual authentication is absent and encryption is weak or off. Every IMEI write (`new-identity`, `rotate`, sim-swap Stage 2) issues:

```
AT+QNWPREFCFG="mode_pref",NR5G:LTE
```

— locking the modem to 5G NR / LTE, so it can no longer silently fall back to GSM. Controlled by `rat_lock` (default **on**); disable it from LuCI or UCI for regions without LTE coverage.

### No persistent connected-device logs

Applied by `norypt-ghost-clean` at **S9**, before any tracking daemon starts:

- **System log stays in RAM.** Any flash `log_file` under `system.@system[0]` is unset — `logread` still works, nothing hits flash.
- **System log file removed.** If a flash log file was configured, the old file is deleted and `logd` restarted; `check` also warns if remote syslog (`log_ip`) is set.
- **`tmpfs` over every telemetry directory** (created if missing, so a daemon that creates it later still writes to RAM) — `/etc/oui-tertf` (client-MAC tracker) and `/etc/gl_modem_traffic` (per-SIM cellular data counters, which 4.10.x also copies to flash on every shutdown), plus `/etc/vnstat` when present. Each daemon keeps writing, believing it's on flash; the data evaporates every reboot. *(Side effect: GL-iNet's cellular data-usage counters reset at each reboot.)*
- **DPI Flow Statistics off** (4.10.x) — it keeps a per-client MAC + app + bytes + timestamp database (`/etc/netifyd/traffic_data.db`) on flash. The cleaner disables it and deletes the database at every boot; `check` fails while it is enabled.
- **Kernel crash recorder off** — `mtdoops` copies the kernel log tail to a flash partition on every oops and keeps it across reboots and upgrades; the cleaner unloads it.
- **Vendor logs on `/data` off.** That partition is not rewritten by firmware upgrades, and on a unit in use for months it held ~230 MB of logs:
  - Wi-Fi daemon (`hostapd`/`wpa_supplicant`) debug logs, with every client MAC and every rotated BSSID: file logging turned off in UCI, old files deleted.
  - Wi-Fi driver script command log (`qcacld32_commands.txt`): redirected to `/dev/null`.
  - IPA offload daemon log (`/data/data_ipa`, client addresses, ~1 KB/s in debug mode): debug off, directory RAM-backed.
  - Modem diagnostics log (`/data/data_tlpd`): RAM-backed.
- **eSIM client folder RAM-backed** (`/root/esim`): GL's eSIM client keeps a copy of the slot's IMEI and its own log there.
- **Web server error log discarded.** GL copies nginx's RAM error log (client IPs) to `/etc/nginx/error.log` every 10 minutes and at shutdown; the RAM log now points to `/dev/null` and the flash copy stays empty.
- **Old SIMs forgotten.** GL keeps per-SIM settings and APN history keyed by ICCID for every SIM ever inserted. `new-identity` keeps only the inserted SIM(s), sim-swap Stage 1 forgets the outgoing SIM entirely, and `norypt-ghost forget-sims` does it on demand.
- **GoodCloud off.** GL's cloud management and its remote-terminal client are disabled at every boot (option `block_cloud`, default on; LuCI toggle under Security).
- **SMS wiped weekly and on every identity change.** GL stores every SMS (inbox, sent, drafts, send queue) as a file under `/etc/spool/sms`, and each file's header records the device IMEI and the SIM IMSI at that moment, so old messages bridge identities. Every Sunday at 04:00, on `new-identity` and on sim-swap Stage 1, each message is overwritten and deleted (with eMMC discard), and the SIM and modem message stores are emptied. Option `sms_wipe`, default on; LuCI toggle plus a **Wipe all SMS now** button; `norypt-ghost wipe-sms` on demand.
- **eSIM client off.** GL's eSIM client (LPA) sends the eSIM slot's IMEI to the eSIM provider's server, so it is disabled at every boot (option `block_esim`, default on; LuCI toggle under Security). Untick it to download or switch eSIM profiles.
- **No IMEI on flash, ever.** The `new-identity` boot check stores only the profile id and a 4-hex check tag (16 bits, not reversible to an IMEI); the on-screen handoff file holds only the last three digits.
- **Deleted with TRIM.** Install, `wipe-logs` and `prepare-upgrade` remount the ext4 partitions with `discard` while deleting, so the eMMC is told the freed blocks are unused. Physical erasure is up to the eMMC controller.
- **dnsmasq** runs with `logqueries=0` and `cachelocal=0` — no per-client DNS query log, no persisted cache.
- **DHCP leases forced to `/tmp`** if the firmware ever points `leasefile` at flash.
- **Rotation timestamps stay in RAM.** The "last IMEI / wireless rotation" markers live in `/tmp`, never `/etc` — a persisted timestamp would be retained metadata about *when* the identity last changed, which the no-retention model avoids keeping on flash. The cleaner also sweeps any such file left on flash by an older build.

The pre-existing on-flash client database is unlinked at first run. *(It is unlinked, not overwritten: the Mudi 7's overlay is ext4 on eMMC, whose flash translation layer remaps writes, so overwrite-in-place tools like `shred` are ineffective. The tmpfs mount is the real protection.)*

`norypt-ghost check` reports each of these independently **and fails its exit code** if any is violated. Its output never contains an IMEI, IMSI, MAC or password, so it is safe to paste into a bug report. `norypt-ghost-clean stop` (run automatically on removal) clears the RAM copies before exiting.

### No-retention model

Norypt Ghost **never captures or stores your device's original identity.** There is no `factory` section, no sealed vault, no `restore` path — because a stored copy of the real IMEIs, MACs, SSIDs and keys is itself a complete recovery key that would link every rotated identity straight back to the original device. Keeping nothing is the point: rotation is forward-only, and there is no retained record that could undo it.

- **Install captures nothing.** `norypt-ghost install` only enables the services and writes safe UCI defaults. It does not read, snapshot, or persist any pre-existing identifier.
- **No restore, by design.** There is nothing to restore *to*. Rotation is forward-only: each `new-identity`/`rotate` derives a fresh coherent identity and leaves no on-flash trail linking it to what came before.
- **Stable across reboots.** Identity does not drift on its own — it stays put until you change it via the CLI or the on-device menu. (Boot-time wireless rotation exists as an explicit opt-in toggle, off by default.)
- **Nothing on flash bridges old to new.** Combined with the RAM-backed logs above, a powered-down device holds only its *current* identity and no record of any prior one.

### TTL normalization

A router forwards client packets with the IP TTL / IPv6 hop-limit decremented by one, so forwarded traffic is distinguishable from traffic the phone originates itself. That inconsistency contradicts a profile that presents as a single phone.

`norypt-ghost-ttl` (S45) pins egress IPv4 TTL and IPv6 hop-limit to **64** via `nft`, falling back to `iptables`/`ip6tables` — so forwarded client traffic stays consistent with the presented single-device profile.

### Splash screens

During operations Norypt Ghost stops `gl_screen` and writes pre-rendered 240×320 RGB565 frames straight to `/dev/fb0`:

| | | |
|:---:|:---:|:---:|
| ![Rotating](screens/previews/rotating.png) | ![Done](screens/previews/done.png) | ![SIM Swap](screens/previews/simswap.png) |
| ![Warning](screens/previews/warning.png) | ![Error](screens/previews/error.png) | |

| Frame | Shown when |
|---|---|
| `rotating` | IMEI rotation, `new-identity` apply, or sim-swap Stage 2 in progress |
| `done` | Operation complete and modem re-registered |
| `simswap` | Stage 1: powering off for the SIM swap |
| `warning` | Soft failure: IMEIs written but no re-registration within the timeout |
| `error` | Hard failure: a write failed; **RF is left off** until recovered |

Frames are generated by `screens/generate.py` (Python 3 + Pillow, dev-side only — the device never needs Python) and committed as binaries.

*Implementation note:* `gl_screen` respawns via procd, so a plain `stop` would repaint over the frame within seconds — the splash helper first removes it from procd's watch list, then stops it, then writes. A separate GL-iNet boot process draws a progress bar at a fixed row; the `rotating`/`done` layouts leave that row empty so Stage 2 splashes aren't overdrawn.

---

## Configuration Reference

Everything lives in `/etc/config/norypt-ghost` (standard UCI). There is a single `options` section — no `factory`/original-identity section is ever written:

```sh
config norypt-ghost 'options'
    option randomize_on_boot    '0'        # opt-in: rotate wireless identity at every boot (default off — identity is stable across reboots)
    option randomize_mac        '1'        # per-feature toggles for boot rotation + rotate-wireless
    option randomize_ssid       '1'
    option randomize_hostname   '1'
    option randomize_password   '1'
    option imei_mode_slot1      'random'   # random | deterministic | static
    option imei_mode_slot2      'random'
    option static_imei_slot1    ''         # used when the slot's mode is 'static'
    option static_imei_slot2    ''
    option register_timeout     '120'      # seconds to wait for re-attach (10-600)
    option touch_enabled        '1'        # touchscreen menu trigger preference
    option rat_lock             '1'        # lock modem to 5G NR/LTE; blocks 2G/3G downgrade
    option default_region       'NA'       # NA | EU — profile region when no SIM/MCC is readable
```

All values are editable from LuCI (applied instantly) or via `uci set norypt-ghost.options.<name>=<value> && uci commit norypt-ghost`. Every value is validated server-side — malformed input is rejected, never written to the modem.

---

## Building from Source

The touchscreen daemon is compiled from `src/` — **no binaries are committed to this repository.**

### 1 — `build-ipk.sh` (no OpenWrt SDK required)

```sh
git clone https://github.com/norypt-website/Norypt-Mudi7.git
cd Norypt-Mudi7
sudo apt install -y gcc-aarch64-linux-gnu   # or have Docker available
./build-ipk.sh
```

Needs `bash`, `tar`, `gzip`, and an aarch64 cross-compiler (Docker is used automatically as a fallback). Builds `norypt-ghost-touch` first if missing or stale. **Use for:** day-to-day development and offline builds.

### 2 — OpenWrt SDK (`Makefile`)

Compiles the daemon against the exact target toolchain:

```sh
# 23.05.4 ipq807x/generic SDK — the same OpenWrt release the GL-E5800 firmware
# is based on, and the same aarch64_cortex-a53 musl ABI. (The GL-E5800's IPQ9574
# has no upstream stable SDK; any 23.05.4 aarch64_cortex-a53 target is identical.)
curl -fLO https://downloads.openwrt.org/releases/23.05.4/targets/ipq807x/generic/openwrt-sdk-23.05.4-ipq807x-generic_gcc-12.3.0_musl.Linux-x86_64.tar.xz
tar -xJf openwrt-sdk-23.05.4-*.tar.xz && cd openwrt-sdk-23.05.4-*/

ln -s /path/to/Norypt-Mudi7 package/norypt-ghost
make defconfig
make package/norypt-ghost/compile V=s
```

**Use for:** reproducible/auditable builds or opkg feed submission.

### 3 — GitHub Actions

| Workflow | What it does | Output |
|---|---|---|
| [`build.yml`](.github/workflows/build.yml) | **Host tests first** (`./tests/run.sh --release`), then the fast script build | `norypt-ghost_<version>-Script-{CI\|Release}.ipk` |
| [`sdk-build.yml`](.github/workflows/sdk-build.yml) | Downloads the pinned, checksum-verified 23.05.4 SDK and builds via the `Makefile` | `norypt-ghost_<version>-SDK-{CI\|Release}.ipk` |

The build job **depends on the test job** — shellcheck, the profile/coherence validator (in release mode, so an unverified TAC fails the build), and the Lua + Python unit suites all gate every artifact. On a `v*.*.*` tag both IPKs are attached to a GitHub Release:

```sh
git tag v1.1.0 && git push origin v1.1.0
```

Full release procedure: [docs/RELEASING.md](docs/RELEASING.md).

### Testing locally

```sh
./tests/run.sh              # shellcheck + validator + unit suites
./tests/run.sh --release    # additionally fails on any unverified TAC
```

### Other tooling

```sh
./tools/build-touch.sh      # build just the touch daemon (native cross-gcc or Docker/Alpine)
./deploy.sh [host]          # push the working tree to a device over SCP (default root@192.168.8.1)
```

`deploy.sh` does **not** run setup — run `norypt-ghost install` manually to enable services and write defaults if needed.

---

## Uninstalling

```sh
opkg remove norypt-ghost
```

`prerm` stops and disables all services; `postrm` re-enables GL-iNet's BSSID randomization and clears runtime state.

**There is no factory identity to restore** — the no-retention model never stored one, so removal simply leaves the device on its **current** identity. If you want to return to a stock-like state, run a normal GL-iNet factory reset from the device UI (that regenerates the vendor's own identifiers); Norypt Ghost has no copy of your original values to write back.

To also drop the package's own settings:

```sh
uci delete norypt-ghost.options && uci commit norypt-ghost
```

---

## AT Commands We Deliberately Avoid

Hard-won knowledge from bricking-adjacent experiments on the RG650V-NA — none of these are used, and none should be added:

| Command | Why not |
|---|---|
| `AT+QPOWD` | Leaves the modem unresponsive until a full device reboot |
| `AT+CFUN=1,1` | Reboots the entire device, not just the modem RF |
| `AT+QPRTPARA=3` | Quectel factory reset — undefined behavior on carrier units |
| `AT+QUIMSUB` | Breaks the AT socket until reboot |
| `ubus call cellular.cm cm_stop_dial` | Persists `allow_dial=0` to flash; cellular manager then skips SIM detection on every subsequent boot |
| Writes to the RAWDATA MMC partition | Where the hardware MAC lives; corruption is unrecoverable |
| Default eSIM profile deletion | Cannot be restored without a factory reset |

---

## Project Status

**Implemented and host-tested.** The full hardening suite — profile catalog, `new-identity`, RAT lock, no-persistent-logs, no-retention model, TTL normalization, host-key rotation, on-device touchscreen menu, LuCI controls — is complete, reviewed, and green in CI (shellcheck, profile/coherence validator in release mode, Lua + Python unit suites).

**On-device acceptance is the remaining gate.** AT writes, IMEI persistence, and the framebuffer cannot be validated off-hardware. Run **[docs/ACCEPTANCE.md](docs/ACCEPTANCE.md)** on a real Mudi 7 before considering this shipped — it also confirms the handful of device facts the code adapts to (exact `AT+QNWPREFCFG` syntax, `openssl`/`qrencode` availability, the real telemetry paths, and the firewall backend).

---

## Roadmap

Ranked improvements with rationale and effort estimates live in **[docs/ROADMAP.md](docs/ROADMAP.md)**, including a [Delivered](docs/ROADMAP.md#delivered) section. Currently open:

- Expand the profile catalog beyond six archetypes, and refresh TACs as new flagships ship
- Reconsider the forced locally-administered MAC bit for the legacy router path
- Key the deterministic IMEI hash with a per-install secret
- Serving-cell monitoring / IMSI-catcher **detection** (the RAT lock is prevention)

Design and implementation records: [docs/HARDENING-DESIGN.md](docs/HARDENING-DESIGN.md) · [docs/HARDENING-PLAN.md](docs/HARDENING-PLAN.md)

---

## Repository Layout

```
Norypt-Mudi7/
├── build-ipk.sh                  IPK builder (no SDK; control scripts inlined)
├── Makefile                      OpenWrt SDK package recipe
├── deploy.sh                     dev deploy over SCP
├── tools/build-touch.sh          cross-compiles the touch daemon from src/
├── src/norypt-ghost-touch.c      touchscreen daemon (C, statically linked)
├── tests/                        host test suite (run.sh + validator + unit tests)
├── screens/
│   ├── generate.py               RGB565 frame generator (dev-side, Python+Pillow)
│   └── previews/                 PNG previews of all frames
├── docs/
│   ├── ACCEPTANCE.md             on-device acceptance checklist (pre-ship gate)
│   ├── ROADMAP.md                ranked improvement backlog + delivered log
│   ├── RELEASING.md              release process
│   ├── HARDENING-DESIGN.md       design record for the hardening suite
│   └── HARDENING-PLAN.md         implementation plan
└── files/                        package payload (mirrors the device filesystem)
    ├── usr/bin/norypt-ghost      CLI entry point (ash)
    ├── usr/libexec/norypt-ghost  rpcd exec backend for LuCI (JSON over fs.exec)
    ├── lib/norypt-ghost/
    │   ├── functions.sh          AT helpers, MAC/SSID generation, RF control, RAT lock
    │   ├── profile.sh            profiles.json loader, selection, format-token derivation
    │   ├── identity.sh           new-identity stage/apply engine, SSH/TLS key regen
    │   ├── clean.sh              telemetry tmpfs + no-persistent-logs guarantee
    │   ├── imei_generate.lua     IMEI generator (profile TAC / random / deterministic)
    │   └── luhn.lua              Luhn checksum module
    ├── etc/init.d/               five services: clean (S9), wireless (S10),
    │                             sim-swap stage 2 (S25), ttl (S45), touch (S81)
    ├── usr/share/norypt-ghost/
    │   ├── profiles.json         coherent device-profile catalog (verified TACs)
    │   ├── tac_pool.json         legacy TAC pool (fallback only; random mode uses profiles.json)
    │   ├── oui_pool.json         router + client OUIs for the partial wireless path
    │   └── screens/*.rgb565      six pre-rendered splash frames
    └── www/…/norypt_ghost.js     LuCI2 admin page (vanilla JS view)
```

---

## Attribution

- **[blue-merle-v2](https://github.com/WSchlesner/blue-merle-v2)** — the direct upstream: the Mudi 7 port, the dual-IMEI `AT+EGMR` mapping, the two-stage SIM-swap design, and the LuCI/touchscreen/splash implementation. GPL-2.0-only.
- **[SRLabs](https://www.srlabs.de) / [srlabs/blue-merle](https://github.com/srlabs/blue-merle)** — the original design, threat model, and first implementation, for the GL-E750 Mudi. BSD 3-Clause.
- **[gl-inet/glinet-tac-fix](https://github.com/gl-inet/glinet-tac-fix)** — the only public GL.iNet code calling `AT+EGMR`, which confirmed the quoting format and the `AT+QPRTPARA=1` NV-persistence pattern for the RG650V-NA.

Norypt Ghost is a rebranded and modified derivative, not an official continuation of either project. Neither SRLabs nor the blue-merle-v2 authors endorse it.

## License

**GPL-2.0-only** — see [LICENSE](LICENSE).

Norypt Ghost inherits GPL-2.0-only from blue-merle-v2. Code derived from SRLabs' BSD-3-Clause blue-merle (`files/lib/norypt-ghost/luhn.lua`) retains SRLabs' copyright, and their full BSD notice is reproduced in [NOTICE](NOTICE) as its terms require. BSD 3-Clause code may be incorporated into a GPL-2.0 work; the combined project is distributed under GPL-2.0-only.

<div align="center">

---

**Norypt Ghost** · Radio-identity rotation for the Mudi 7 · [Report an issue](https://github.com/norypt-website/Norypt-Mudi7/issues)

</div>
