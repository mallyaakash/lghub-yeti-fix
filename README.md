# Blue Yeti Nano + Logitech G HUB: firmware update loop, fixed

**Symptom.** G HUB says the Yeti Nano needs a firmware update. You accept. It flashes, the mic
restarts, the mic is dead, G HUB asks for the update again. Forever. Recovering with the old
Blue Sherpa app gets you a working mic that G HUB immediately wants to re-flash.

**Cause (measured, not guessed).** The flash succeeds. Firmware 4.10 boots and enumerates
fully as a Logitech device (`USB\VID_046D&PID_0AB1`). About 3.6 seconds later G HUB's own
post-flash step kills it, the mic falls back into its DFU bootloader (`USB\VID_B58E&PID_0006`),
and G HUB's rules mark the bootloader "always flash". The firmware is fine. The mic is fine.
G HUB 2026.6 is the problem.

**Fix.** Kill G HUB the instant the new firmware boots, before it can do the post-flash step.

## Steps

1. Quit G HUB and Blue Sherpa completely. No `lghub*`, `Blue.exe` or `sherpa_service` process
   may be running. Two firmware managers on one device is how flashes get corrupted.
2. In an elevated or normal PowerShell, run:
   ```powershell
   .\kill-ghub-on-0ab1.ps1
   ```
   It polls the USB bus every 50 ms and kills every G HUB process the moment the mic shows up
   as `046D:0AB1`. It logs what it sees to `kill-ghub.log`.
3. Start G HUB and accept the firmware update. The flash takes about 6 seconds. The script kills
   G HUB roughly 0.2 seconds after the new firmware boots.
4. Stop the script (Ctrl+C) and start G HUB again normally. The mic now shows as a current
   Yeti Nano and no update is demanded. Uninstall Sherpa; it cannot see the new identity anyway.

If the mic is already stuck in the loop, step 3 is just "plug it in": G HUB flashes the
bootloader-mode mic on its own.

## What is in here

| File | What |
|---|---|
| `kill-ghub-on-0ab1.ps1` | The fix. `-Trigger` takes a regex on the identity list if you need a different kill condition. |
| `watch-mic.ps1` | Slow 1 s identity logger used during diagnosis. |
| `yeti-nano-ghub-firmware-plan.md` | Full write-up: evidence, timeline, hypotheses, results. |
| `kill-ghub.phase1.log` | The run that proved it: G HUB killed 182 ms after boot, mic survived. |
| `firmware/dfu.json` | G HUB's rules file for this mic (why the bootloader is always re-flashed). |
| `firmware/SHA256SUMS.txt` | Hashes of G HUB's 4.10 and Sherpa's 4.5 images. The images themselves are Logitech's and are not included. G HUB caches its copy under `C:\ProgramData\LGHUB\depots\<build>\yeti_original_nano_dfu\`. |

## Caveats

- Tested on one original Yeti Nano (bootloader `B58E:0006`, not the "Evantra" revision) with
  G HUB 2026.6 on Windows 11. Other Blue mics with the same loop may behave the same, untested.
- The exact message G HUB sends that kills the firmware was not identified; the agent log
  (`lghub_agent.exe --enable_logging`, written to `%TEMP%\com.logi.ghub.agent.logs\`) is where
  to look if Logitech wants a bug report.
- Nothing here writes to the mic. All flashing is done by G HUB itself. Still, you are running
  this at your own risk.
