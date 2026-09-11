# Norypt Ghost — On-Device Acceptance Checklist

This checklist validates the Norypt Ghost hardening package on a real GL-iNet GL-E5800 (Mudi 7) device running firmware 4.8.5, before the package is considered shipped to customers.

**Setup:**
1. Deploy the package with `./deploy.sh` from the build host.
2. On the device, run `norypt-ghost install`.
3. The device will reboot. Wait 60–90 seconds for boot completion.
4. Then work through the sections below.

This is the final acceptance gate. All items must pass — the AT commands, framebuffer writes, and IMEI persistence cannot be tested off-hardware, so each procedure must be verified on the actual device.

---

## Facts to Confirm First

These checks verify that the device hardware, dependencies, and GL-iNet environment are ready for hardening operations. Do them before any identity rotation.

- [ ] **Modem model and RAT-lock syntax**
  - Run `AT+GSM_CMD="ATI"` (via the modem CLI or SSH to `/dev/ttyUSB0`).
  - Record the modem model name (e.g., RG650V, EC25, EG95).
  - Run `AT+GSM_CMD="AT+QNWPREFCFG=?"` and record the response to confirm which RAT modes are supported.
  - Run `AT+GSM_CMD="AT+QNWPREFCFG=\"mode_pref\""` to read the current mode.
  - Confirm the device accepts `AT+QNWPREFCFG="mode_pref",NR5G:LTE` (the factory-state RAT lock). If the exact token differs (e.g., your modem uses `AT+QCFG="nwscanmode"` instead), update `RAT_LOCK_APPLY` in `files/lib/norypt-ghost/functions.sh` to match.
  - Fallback: If the above fails, try `AT+GSM_CMD="AT+QCFG=?"` and record the response; document the equivalent mode in a comment at the top of `functions.sh`.

- [ ] **No-retention model (no factory capture)**
  - Run `uci -q show norypt-ghost | grep -c '\.factory'` and confirm the count is **0** — the package never writes a `factory` section.
  - Confirm `norypt-ghost install` only enables services and writes default options; it does not read, snapshot, or store any pre-existing identifier.

- [ ] **GL-iNet telemetry directories (for cleanup validation)**
  - Run `ls -la /etc/oui-tertf /var/lib/nlbwmon /etc/vnstat /var/lib/vnstat 2>&1 | grep -v "cannot access"` to see which paths exist.
  - Compare the existing paths with the `_CLEAN_DIRS` array in `files/lib/norypt-ghost/clean.sh`.
  - If any telemetry paths exist on the device but are missing from `_CLEAN_DIRS`, append them to the array and redeploy.
  - Fallback: If none of these paths exist (GL-iNet version difference), the device is already clean; no update needed.

- [ ] **On-screen QR code rendering dependencies**
  - Run `command -v qrencode && echo "qrencode: present" || echo "qrencode: absent"`.
  - Run `command -v fbv && echo "fbv: present" || command -v fbi && echo "fbi: present" || echo "neither present"`.
  - If **both** `qrencode` and (`fbv` or `fbi`) are present: The join-Wi-Fi QR code will render directly on the device touchscreen (`/dev/fb0`) at rotation time, and credentials will be displayed on-screen.
  - If **either is absent**: The on-screen QR is skipped. The SSID and PSK will be printed to the console/SSH terminal instead. Fallback: Manually enter the SSID and PSK shown in the terminal to rejoin Wi-Fi after rotation.

- [ ] **Firewall backend for TTL normalization**
  - Run `nft list ruleset 2>&1 | head -1 | grep -q "^table" && echo "nftables" || echo "iptables"` to detect the active firewall.
  - Run `iptables -V` to confirm the iptables version.
  - The `norypt-ghost-ttl` init service normalizes egress TTL to 64 (NR5G/LTE standard). Confirm:
    - If **nftables** is active: Check that the `ttl set 64` rule is compiled in the ruleset (`nft list ruleset | grep ttl`).
    - If **iptables** is active: Check that the TTL target module is loaded (`lsmod | grep -i ttl || modprobe xt_TTL`).
  - Fallback: If neither backend loads the required module, TTL normalization will be skipped and a warning will be logged. Plan a device firmware/package update to enable it.

- [ ] **Bluetooth MAC rotation support** (only if Bluetooth is configured to be used)
  - By default, Bluetooth is disabled. If you plan to enable BT, verify:
  - Run `command -v btmgmt && echo "btmgmt: present" || echo "btmgmt: absent"`.
  - Run `command -v hciconfig && echo "hciconfig: present" || echo "hciconfig: absent"`.
  - If **both** are present: Bluetooth MAC rotation will work and will be logged.
  - If **either is absent**: Bluetooth MAC rotation is a no-op (device keeps the factory BT address). The rotation will still succeed and log the action. Plan to reinstall Bluetooth tools if MAC rotation is critical for your use case.

- [ ] **busybox grep alternation support (SSID token expansion)**
  - `_expand_format` in `files/lib/norypt-ghost/profile.sh` uses `grep '{[0-9]\+\(hex\|lower\|digits\)}'` (BRE alternation via `\|`), which host GNU grep supports but this device's busybox grep may not — it's not testable off-hardware.
  - After running `norypt-ghost new-identity`, inspect the resulting SSID (`uci get wireless.wifi2g.ssid`).
  - If it is an expanded value (e.g. `NETGEAR-a3f1`): busybox grep supports the alternation; no action needed.
  - If it is still the literal template (e.g. `NETGEAR-{4hex}`): busybox grep lacks `\|` support and `_expand_format` needs a `case`/`sed` rewrite instead of the `grep \|` alternation.

---

## Full-Identity Rotation

This section validates that a complete identity rotation works end-to-end: modem, Wi-Fi, network identity, and connectivity.

- [ ] **Record pre-rotation identifiers**
  - Run `norypt-ghost status` and record **every** identifier it prints:
    - Both IMEI values (slot 1 and slot 2, if dual-SIM).
    - All six Wi-Fi Access Point (AP) BSSIDs (2.4 GHz main, guest; 5 GHz main, guest; 6 GHz main, guest — or subset if your device model has fewer bands).
    - Station (STA) MAC (device's own Wi-Fi client MAC, if it connects as a client elsewhere).
    - Wired WAN MAC (the modem's Ethernet address facing the uplink).
    - Wired LAN MAC (the device's LAN Ethernet address toward local clients).
    - SSID (both main and guest).
    - Hostname.
    - Both PSK/passphrases (main and guest Wi-Fi).
    - Upstream DHCP hostname (what the device announces to the DHCP server).
  - **Save this record to a text file** (e.g., `pre-rotation-status.txt`) for side-by-side comparison.

- [ ] **Trigger full-identity rotation**
  - Run `norypt-ghost new-identity`.
  - The command will:
    - Generate all new identifiers.
    - Write them to the modem and device configs.
    - Render the new join-Wi-Fi QR code (on-screen if tools present, or to the terminal).
    - Initiate a reboot.
  - **Wait 60–90 seconds** for the device to fully boot.

- [ ] **Verify all identifiers changed**
  - Once the device is back online (ping succeeds, or SSH is responsive), run `norypt-ghost status` again and record the new values.
  - Compare the new status to the pre-rotation record:
    - **IMEI (slot 1 and slot 2):** Both must differ from the pre-rotation values.
    - **All AP BSSIDs (2.4 GHz / 5 GHz / 6 GHz, main & guest):** Each BSSID must differ from its pre-rotation counterpart.
    - **STA MAC:** Must differ (if applicable).
    - **WAN MAC:** Must differ.
    - **LAN MAC:** Must differ.
    - **SSID (main and guest):** Both must differ.
    - **Hostname:** Must differ.
    - **PSK (main and guest):** Both must differ.
    - **DHCP hostname:** Must differ.
  - If **any** identifier did not change, note it as a failure; do not proceed until the rotation engine is debugged.

- [ ] **Verify identity coherence (vendor match)**
  - The IMEI TAC (first 8 digits), the BSSID OUI (first 6 hex nibbles), and the SSID brand must all map to the **same vendor**. This confirms that the rotation picked a consistent profile.
  - Example: If the new IMEI is `86688401...` (Apple TAC), all BSSIDs should start with `a0a8d4` (Apple OUI), and the SSID should contain "iPhone" or similar.
  - Run `norypt-ghost status | grep -E "IMEI|BSSID|SSID"` and manually verify the vendor alignment, or use a reference table (docs or script) to confirm TAC/OUI mappings.

- [ ] **Verify Wi-Fi join with the on-screen QR (or manual entry)**
  - If the QR was rendered on-screen at rotation time:
    - Scan the QR with a smartphone or laptop.
    - It should decode to the new Wi-Fi SSID and PSK.
    - Use the phone to connect to the SSID using the PSK.
    - The phone should authenticate and receive an IP via DHCP.
    - Fallback: If the QR is not visible, manually read the SSID and PSK from the terminal output of `norypt-ghost new-identity` and enter them into the phone's Wi-Fi settings.
  - **Success:** The phone is now connected to the Mudi 7 as a client.

- [ ] **Verify RAT lock applied (2G/3G blocked, NR5G/LTE only)**
  - While the phone is still connected, SSH into the device.
  - Run `AT+GSM_CMD="AT+QNWPREFCFG=\"mode_pref\""` (or the fallback command if different for your modem).
  - The response should read `NR5G:LTE` (or the equivalent for your modem), confirming that 2G and 3G are disabled.
  - If the response differs, the RAT lock was not applied; check the modem logs: `logread | grep -i "qnwprefcfg"`.

- [ ] **Verify egress TTL is normalized to 64**
  - On the connected phone, open a terminal or packet capture tool (e.g., Wireshark, tcpdump via SSH).
  - Generate a ping or HTTP request from the phone to an external server (e.g., `ping 8.8.8.8`).
  - Capture the outbound packet (leaving the phone's network interface).
  - Verify the IP header's **TTL field is exactly 64** (the NR5G/LTE standard). This confirms the device normalized the TTL.
  - Fallback: If TTL normalization is not compiled in (see "Facts to Confirm First"), this check will show the original/client TTL and can be deferred.

- [ ] **Verify SSH host key regeneration**
  - On the device, run `ssh-keygen -l -f /etc/ssh/ssh_host_rsa_key`.
  - Record the fingerprint and the key's date.
  - Compare to a pre-rotation backup (if you took one). The fingerprint must differ.
  - Also check the key's modification date: `stat /etc/ssh/ssh_host_rsa_key | grep "Modify"` should show the current time (or time of rotation).
  - If the fingerprint and date are unchanged, SSH keys were not regenerated; this is a failure.

- [ ] **Verify HTTPS certificate regeneration**
  - Open a browser and visit the device's LuCI web interface (e.g., `https://<new-hostname>:443` or the new IP address).
  - The browser will show a self-signed certificate warning. Right-click / inspect the certificate.
  - Record the certificate's **fingerprint** and **valid from** date.
  - If you have a pre-rotation backup, compare. The fingerprint must differ and the **valid from** date must be recent (close to rotation time).
  - If the certificate and date are unchanged, HTTPS certs were not regenerated; this is a failure.

---

## No Connected-Device Logs

This section confirms that the device does not retain logs of connected clients (phones, laptops) across reboots.

- [ ] **Log connectivity of a test client**
  - Connect a test phone or laptop to the Mudi 7's Wi-Fi (using the new SSID and PSK from the previous rotation).
  - On the phone, open a browser and visit a website (e.g., https://example.com) to generate traffic.
  - Let the connection idle for ~10 seconds, then browse a few more sites to generate packets.
  - Record the current time.

- [ ] **Reboot the device**
  - SSH into the device and run `reboot`.
  - Wait 60–90 seconds for the device to fully boot.
  - The phone will briefly lose connection, then may reconnect (DHCP re-assign).

- [ ] **Verify no persistent client logs**
  - After boot, SSH into the device.
  - Run `logread | tail -100` to check the syslog. The output should **NOT** contain the test phone's MAC address or hostname from before the reboot.
  - Run `cat /tmp/dhcp.leases` to check DHCP leases. The output should be **empty** (or contain only leases granted after the reboot, with no historical entries from before the reboot).
  - Check the GL-iNet client list (if present): Run `curl -s http://127.0.0.1:8080/api/clients` or equivalent (GL-iNet API varies by firmware version). The response should **not** list the pre-reboot client.
  - **Pass:** All three checks return no pre-reboot client data.
  - **Fail:** If any of the three shows pre-reboot client data, the no-logs feature is broken; do not ship.

- [ ] **Verify syslog is not persisted to flash**
  - Run `uci get system.@system[0].log_file`.
  - The output should be **empty** (not `/var/log/messages` or any other path).
  - This confirms that syslog is not written to persistent storage.

- [ ] **Verify the norypt-ghost check tool detects no-logs status**
  - Run `norypt-ghost check`.
  - The output should include a line like `PASS: No persistent client logging (syslog)` or similar.
  - The exit code should be **0** (success).
  - To simulate a failure: Temporarily add a syslog path with `uci set system.@system[0].log_file=/var/log/messages` and rerun `norypt-ghost check`. The exit code should now be **non-zero** (failure), and the output should flag the issue.
  - Revert the change with `uci delete system.@system[0].log_file` and confirm `norypt-ghost check` returns 0 again.

---

## No-Retention Model

This section validates that no factory/original identity is ever captured, stored, or restorable — the core no-retention guarantee.

- [ ] **No factory section on flash**
  - Run `uci -q show norypt-ghost`.
  - Confirm there is **no** `norypt-ghost.factory` section and no stored IMEIs, MACs, SSIDs, or keys anywhere in the config.

- [ ] **No `restore` path**
  - Run `norypt-ghost restore`.
  - It should print an unknown-command/usage error and exit **non-zero**. There is nothing to restore to: rotation is forward-only.

- [ ] **`opkg remove` keeps the current identity**
  - Rotate the identity with `norypt-ghost new-identity`, then run `opkg remove norypt-ghost`.
  - `prerm` stops and disables the services; `postrm` re-enables GL-iNet's own BSSID randomization and clears runtime state.
  - The modem and Wi-Fi remain at their **current** rotated identity — removal does not (and cannot) restore an original identity, because none was ever stored.
  - Run `norypt-ghost status`; it should report the package is not installed.

---

## Regression: Legacy Command Compatibility

This section confirms that older command syntax still works (for backward compatibility with scripts and documentation).

- [ ] **Legacy rotate command**
  - Run `norypt-ghost rotate`.
  - This rotates **both IMEIs only** (slots 1 and 2) and cycles RF for re-attachment. It is a **partial, live rotation** — it does NOT change BSSIDs, SSID, PSK, hostname, or wired MAC, shows NO QR code, and does NOT reboot. Use `new-identity` for a clean break.
  - After the command completes, run `norypt-ghost status` and verify:
    - IMEI (both slots) **changed** from the previous value.
    - All BSSIDs, SSID, PSKs, hostname, and wired MACs remained **unchanged**.
    - The modem cycled RF (radio silence, then re-attach to the current network).

- [ ] **Legacy rotate-wireless command**
  - Run `norypt-ghost rotate-wireless`.
  - This rotates the wireless and network identity **without touching the modem IMEI**. By default, it changes MACs, BSSIDs, SSID, guest SSID, both PSKs, **and the hostname** (the last is controlled by the `randomize_hostname` option, which defaults to enabled). It applies changes live via `wifi reload` and does NOT reboot.
  - After the command completes, run `norypt-ghost status` and verify:
    - IMEI (both slots) remained **unchanged** from the previous value.
    - All Wi-Fi BSSIDs and SSID **changed**.
    - Hostname **changed** (if `randomize_hostname=1`, which is the default; set `randomize_hostname=0` in the config to preserve hostname).
    - All MACs changed (2.4 GHz, 5 GHz, 6 GHz, guest, and STA MACs).
  - Connect a device to the new SSID to verify Wi-Fi works.

- [ ] **Legacy sim-swap command (two-stage)**
  - Run `norypt-ghost sim-swap` (or `norypt-ghost sim-swap start` if the command is two-stage).
  - This should:
    - Notify the user: `SIM swap initiated. The device will rotate IMEI and RAT lock at the next boot.`
    - Or: `SIM swap prepared. Run 'norypt-ghost sim-swap commit' to finalize.` (if two-stage).
  - Wait for the next automatic reboot, or run the commit command if two-stage.
  - After reboot, verify with `norypt-ghost status` that the IMEI changed and the RAT lock is applied.

- [ ] **No `restore` command exists**
  - Run `norypt-ghost restore`.
  - It should print an unknown-command/usage error and exit non-zero — the no-retention model has no restore path.

---

## Reinstall Captures Nothing

- [ ] **Reinstall does not capture or change identity**
  - Start with a device that has been rotated (identity changed); record it with `norypt-ghost status`.
  - Run `opkg remove norypt-ghost` (the identity stays as-is — see the No-Retention Model section).
  - Run `opkg install norypt-ghost` (or `./deploy.sh && norypt-ghost install`).
  - Reinstall only re-enables services and writes default options; it captures no identifier.
  - Run `norypt-ghost status` and confirm the identity is unchanged from before the remove.

---

## Summary

All sections above must pass before the package is considered ready for customer deployment. Critical items that cannot be deferred:

- [ ] **All identifiers change on rotation** (modem IMEI, all Wi-Fi BSSIDs, hostname, MACs, SSID, PSK).
- [ ] **Vendor coherence** (IMEI TAC, BSSID OUI, SSID brand all match).
- [ ] **No persistent client logs** (syslog, DHCP leases, client list all empty after reboot).
- [ ] **No-retention model** (no `factory` section is written; `norypt-ghost restore` does not exist).
- [ ] **TTL normalization** (egress TTL is 64 if the firewall backend supports it).
- [ ] **RAT lock applied** (2G/3G blocked, NR5G/LTE only).

Items that can be deferred with a warning (if hardware does not support them):

- [ ] **On-screen QR rendering** (fallback: terminal SSID/PSK display).
- [ ] **Bluetooth MAC rotation** (fallback: BT address unchanged; feature still installs cleanly).
- [ ] **TTL normalization** (if firewall backend does not support TTL targets; exit 0 but no TTL rewrite).

If any critical item fails, **do not ship**. Update the code and retest on the device.
