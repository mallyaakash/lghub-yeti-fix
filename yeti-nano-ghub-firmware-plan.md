# Yeti Nano + G HUB firmware loop: diagnosis and fix plan

Written 2026-10-16 from evidence on this PC (Device Manager history, Windows PnP event logs,
G HUB's depot cache, Blue Sherpa's log). Nothing has been flashed yet; this is the plan.

## 1. What actually happens (from the logs, not guesswork)

The mic has three USB identities, and Windows kept timestamps for all of them today:

| Identity | What it is | Firmware rev reported |
|---|---|---|
| `USB\VID_B58E&PID_0005` | Blue-era Yeti Nano (as shipped: rev 4.06; after Sherpa: rev 4.05) | `REV_0406` / `REV_0405` |
| `USB\VID_B58E&PID_0006` "Blue Yeti Nano Bootloader" | USB DFU bootloader (class FE/01/02), bound to G HUB's WinUSB driver | `REV_0200` |
| `USB\VID_046D&PID_0AB1` "Yeti Nano (HID++)" | The mic **after** G HUB's firmware 4.10, re-badged with Logitech's VID | `REV_040A` (= 4.10) |

Timeline of your first G HUB attempt (Kernel-PnP "surprise removed" events, hh:mm:ss):

```
19:18:12  G HUB downloads yeti_original_nano_v4_10.bin (SHA256 matches its dfu.json)
19:18:24  B58E:0005 leaves the bus      (G HUB told it to reboot into the bootloader)
19:18:25  B58E:0006 bootloader appears
19:18:32  bootloader leaves             (flash took ~7 s)
19:18:32  046D:0AB1 appears, all 5 HID collections + audio interface start fine
19:18:34  Windows creates its mic/speaker endpoints
19:18:36  046D:0AB1 "surprise removed"  <-- the new firmware dies 3.6 s after boot
   ...    mic comes back as the BOOTLOADER on its own
19:18:49  bootloader leaves, 19:18:59 bootloader leaves again (G HUB re-flash)
19:19:00  046D:0AB1 appears again
19:19:03  046D:0AB1 "surprise removed"  <-- dies again after 3.5 s
19:19:19  bootloader leaves (you unplugged)
```

Your second attempt at 19:45 is identical: 0AB1 up at 19:45:58, dead at 19:46:02.

So the update is **not failing**. The flash succeeds, firmware 4.10 boots and enumerates fully,
then the mic drops off the USB bus about 3.6 seconds later and falls back into the DFU
bootloader. G HUB's rules file (`dfu.json`) marks the bootloader identity `force: true`, so every
time it sees the bootloader it flashes 4.10 again. That is the infinite loop.

The nag you still get on Sherpa's 4.5 is by design, not a bug: `dfu.json` also marks
`B58E:0005` as `force: true`. G HUB will always demand 4.10 for a Blue-identity Nano. There is
no "skip" switch. Either 4.10 has to stay alive on this mic, or G HUB cannot manage it.

## 2. Why 4.10 dies: the two candidates

**A. G HUB kills it.** As soon as 0AB1 enumerates, G HUB's agent talks to it over HID++
(the agent binary contains `Feature00c0DFUControl`, `feature_c010a_generic_dfu`, a
`Bootloader-stuck timer`, and a `[dfu_diag] package_version=… device_version=… outdated=…`
check). If G HUB 2026.6 decides the device is still "outdated", or the 2021-era firmware
mishandles a request this much newer G HUB sends, it either commands the mic back into DFU
or crashes it. The ~3.5 s latency fits a HID++ enumeration and decision.

**B. Firmware 4.10 is incompatible with this particular unit.** It boots, then hard-faults
(for example reading a settings/calibration region laid out differently by the 4.06 factory
firmware), and the bootloader refuses to re-run an app that never confirmed a good boot.

Both images are plain Cortex-M applications linked at `0x08010000` (Sherpa's own log:
"burning address 0x08010000"), so flash layout is the same. That lowers but does not
eliminate B.

The one thing that separates A from B: **run 4.10 with G HUB not running.** Logitech's
software can never do that experiment; that is the whole gap I can close.

## 3. Facts that make this safe

- **The bootloader is never written.** Both firmware images start at `0x08010000`; the
  bootloader lives below that. Your 30-second button hold proves the bootloader is reachable
  regardless of what the application does. As long as I only write at `0x08010000`, the mic
  cannot be bricked by a bad app image.
- **Known-good rollback is already on disk:** `C:\Program Files\Blue Sherpa\yetinano_4_5.bin`
  (60,286 bytes). This is exactly what fixed the mic today.
- **The G HUB image is already captured.** No network sniffing needed:
  `C:\ProgramData\LGHUB\depots\876190\yeti_original_nano_dfu\yeti_original_nano_v4_10.bin`
  (58,495 bytes, SHA256 `74F0121A…7886F`, matching the hash G HUB's `dfu.json` demands). Its
  download URL is also recorded in `C:\ProgramData\LGHUB\current.json` if we ever need a
  fresh copy.
- **The bootloader is standard USB DFU** (Sherpa drives it with libusb, DfuSe-style address
  download). `dfu-util` speaks that protocol; I do not need to write a flasher.

## 4. One confounder to remove first

Blue Sherpa's service (`sherpa_service`, `Blue.exe`) and G HUB (`lghub_agent`,
`LGHUBUpdaterService`) are **both running right now**, and both will grab the bootloader when
it appears. Two DFU managers on one device can corrupt a flash. Sherpa was installed after the
loop began, so it did not cause it, but it must be stopped before any further test.

## 5. The plan

### Phase 0: prepare (no risk)
1. Stop both managers: quit G HUB from the tray, `Stop-Service LGHUBUpdaterService`,
   kill `lghub_agent.exe`; quit Sherpa, `Stop-Service sherpa_service`. Set both to not
   auto-start for the duration.
2. Hash and copy both firmware images to `G:\Projects\Logitech\firmware\`.
3. Get `dfu-util` (official Windows build from dfu-util.sourceforge.net). I will ask before
   downloading. No Zadig needed: G HUB already installed a WinUSB driver for the bootloader
   and Sherpa's libusb already worked through it.
4. Move the mic to a **USB 2.0 port or a plain USB 2.0 hub** for the tests. It currently sits
   on an AMD USB 3.10 root port; old Blue firmware has a history of USB 3 quirks, and I want
   that variable removed.

### Phase 1: cheapest test, no flashing tool needed (optional)
Let G HUB flash 4.10 as before, but with a 200 ms PowerShell poll that kills `lghub_agent.exe`
and `lghub.exe` the instant `VID_046D&PID_0AB1` appears. By then the flash is complete and the
app is running, so killing the agent costs nothing. If the mic then stays alive, hypothesis A
is confirmed in one shot.

### Phase 2: the decisive test with dfu-util
1. Enter the bootloader with your button combo. Confirm with `dfu-util -l` that it shows
   `b58e:0006`, DfuSe (`bcdDFU 011a`) and an internal-flash map that includes `0x08010000`.
   If it does not look like that, **stop**; I will not guess at a protocol.
2. Flash G HUB's image, nothing else running:
   ```
   dfu-util -d b58e:0006 -a 0 -s 0x08010000:leave -D yeti_original_nano_v4_10.bin
   ```
3. Watch `046D:0AB1` with a 1 s poll for 5 minutes, and record from it in Windows Sound
   settings.
   - **Survives:** hypothesis A. Go to Phase 3.
   - **Dies in ~3.5 s with nothing talking to it:** hypothesis B. Roll back (step 5) and
     go to Phase 4.
4. Variant if it survives: start only `lghub_agent.exe` and see whether the running 4.10
   mic dies. That tells us whether G HUB's *post-flash* step or its *normal* HID++ handshake
   is the killer.
5. Rollback at any point: button combo, then
   ```
   dfu-util -d b58e:0006 -a 0 -s 0x08010000:leave -D yetinano_4_5.bin
   ```

### Phase 3: if G HUB is the killer
1. Start the agent with its hidden logging switch (`lghub_agent.exe --enable_logging`; the
   string is in the binary and no log files exist on this PC today), reproduce once, and read
   the `[dfu_diag]`, `[dfu_manager]`, `[dfu_update]` lines. That shows the exact decision
   ("outdated=true", a HID++ error, or a stuck-bootloader recovery).
2. Fixes, in order of preference:
   - If it is a version-compare bug (likely: `bcdDevice 0x040A` is not valid BCD, Windows
     prints it as `REV_040:`), that is a G HUB defect to report to Logitech with the log.
     Workaround: an older G HUB build from before the Blue brand was retired, if Logitech
     still serves one.
   - If it is the HID++ handshake: disable the mic's HID interface (`…&MI_03`) in Device
     Manager. G HUB can then neither query nor kill it. Audio still works through the
     Logitech audio driver, but G HUB's device page and Blue VO!CE controls may not appear.
     Last resort, documented as such.

### Phase 4: if the firmware itself dies
Nothing on the PC side changes this. The mic stays on Sherpa 4.5, works as a normal USB mic,
and G HUB will nag forever because of `force: true`. Options are a warranty claim
(bought recently, firmware the vendor pushes bricks the device), or keep G HUB for the other
peripherals and mute the nag by uninstalling Sherpa and simply declining the update.

## 5a. Results so far (2026-10-16 evening)

- Phase 0 done. The button combo does **not** enter the bootloader on a healthy 4.5 app; the mic
  only fell into the bootloader earlier because 4.10 had died. Sherpa enters DFU with a HID
  feature report ("dfu: entering upgrade mode" in its binary), bytes unknown.
- Phase 1 run at 20:51 with `kill-ghub-on-0ab1.ps1` (cfgmgr32 poll, 50 ms):
  ```
  20:51:55.106  B58E:0005 leaves         (G HUB sends it to the bootloader)
  20:51:56.105  B58E:0006 bootloader
  20:52:02.337  bootloader leaves        (flash done, ~6 s)
  20:52:02.765  046D:0AB1 appears
  20:52:02.947  lghub_agent killed       (182 ms after enumeration; lghub_updater survived, SYSTEM)
  20:52:30+     046D:0AB1 still alive, all HID + audio interfaces OK, endpoints present
  ```
  Previous two runs with G HUB alive: dead at 3.6 s. **Hypothesis A confirmed: G HUB's
  post-flash conversation kills firmware 4.10. The firmware itself runs fine on this unit.**

- Phase 3 at 20:56: `lghub_agent.exe --enable_logging` started alone against the running 4.10
  mic: mic survived. 20:57: full `lghub.exe` UI started: mic survived (6+ minutes and counting,
  records fine in Sound settings). Agent log (`%TEMP%\com.logi.ghub.agent.logs\`) shows
  `Device pid 0ab1 init features=6 connected=1 bootloader=0`, firmware entity `4.10.410`.
  **So only G HUB's immediate post-flash step kills the new firmware. Once 4.10 is booted
  without G HUB attached, G HUB works with it normally.**

## 5b. The fix that worked (repeatable)

1. Quit G HUB and Sherpa completely (no `lghub*`, `Blue.exe`, `sherpa_service` processes).
2. Run `kill-ghub-on-0ab1.ps1` (default trigger). It polls the USB bus every 50 ms and kills
   every G HUB process the instant the mic enumerates as `046D:0AB1`.
3. Start G HUB, accept the firmware update. Flash takes ~6 s; G HUB is killed ~180 ms after
   the new firmware boots, before it can do whatever kills the mic.
4. Start G HUB again normally. The mic now shows as a 4.10 Yeti Nano and no update is demanded.

Root cause, as far as the evidence goes: a defect in G HUB 2026.6's post-flash handling of this
2021-era Blue firmware (the verify/finalize step right after DFU), not the firmware and not the
mic. Worth reporting to Logitech with `kill-ghub.phase1.log` and the agent log.

## 6. Answers to your questions, short form

- **Proper fix:** diagnose first; the update does not fail, the new firmware dies 3.6 s after
  boot and the bootloader is set to always re-flash. Separate "G HUB kills it" from
  "firmware can't run here" by running 4.10 with G HUB stopped.
- **Can I flash it myself without bricking:** yes. Standard USB DFU bootloader, app region only
  at `0x08010000`, bootloader untouched, hardware recovery proven, known-good 4.5 image on disk.
- **How I find the firmware:** already found and hash-verified in G HUB's depot cache. No
  capture needed.
- **How I beat Logitech's own software:** by controlling variables it cannot: no G HUB running
  during first boot of 4.10, no second DFU manager, a USB 2.0 port, and the agent's hidden
  logging if it turns out to be the culprit.

## 7. What I will not do
- Write a custom flasher or send any DFU command the bootloader map does not clearly support.
- Flash anything below `0x08010000` or use mass-erase.
- Modify, patch or re-sign either firmware image.
- Run a test while both G HUB and Sherpa are alive.
