# DualSense / vDS HarmonyOS Port Plan

## Goal

Make DualSense a first-class controller path for the Proton HarmonyOS launcher:

- normal gamepad input into Wine DInput/XInput
- Adaptive Trigger output for L2/R2
- classic rumble and lightbar/player LED output
- HD haptics as a later audio-path feature

The first target is MatePad Edge over wired USB-C. Bluetooth is useful later, but it
adds stack ownership problems that are not needed for the first proof.

Updated read after checking the local HarmonyOS SDK docs: HID DDK is the best
first transport to probe, not the high-level USB Manager API alone.

## What vDS Gives Us

Upstream: https://github.com/hurryman2212/vds

Inspected snapshot: tag `0.2.1`, commit `97c96d8`.

Reusable pieces:

- `include/vds/ds5.h`
  - Sony vendor/product IDs: DualSense `054c:0ce6`, DualSense Edge `054c:0df2`
  - USB input/output report sizes
  - `right_trigger_ffb[11]` and `left_trigger_ffb[11]`
  - output state fields for rumble, haptics, LEDs, player lights, audio control
- `src/vds_protocol.cc`
  - output CRC helpers
  - USB output report decoding
  - output state merge logic
  - Bluetooth state/haptics packet builders
  - 4-channel PCM to haptics/speaker packet conversion

Linux-only pieces we should not try to ship inside the HAP:

- `module/`
  - Linux kernel virtual USB HCD
  - `/dev/vdsX` misc device ABI
  - USB isochronous URB handling
- `src/vds_bt.cc`
  - BlueZ L2CAP socket ownership
  - `AF_BLUETOOTH`, HID Control PSM `0x0011`, HID Interrupt PSM `0x0013`
- `src/vds_udev.cc`
  - `libudev` virtual device discovery
- `src/vds_bluez.cc`
  - DBus / BlueZ metadata lookup
- PipeWire/WirePlumber/ALSA setup
  - useful as architecture reference only, not directly portable to a HarmonyOS
    app sandbox

Verdict: vDS is very valuable as a protocol reference, but not as a drop-in
library. The HarmonyOS port should be a new userspace transport with selected
vDS protocol code adapted behind a small C ABI.

## HarmonyOS Transport Shape

Official HarmonyOS docs confirm the USB Manager host-side path covers device
enumeration, permission control, interface claiming, bulk transfer, and control
transfer. The same docs state bulk transfer and control transfer are the
supported data-transfer methods in that guide.

Sources:

- https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-usbmanager
- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V13/usb-guidelines-V13

The gamepad input docs cover ArkTS-side gamepad interaction/event handling from
API 15, which is enough for normal buttons/sticks when HarmonyOS exposes the
controller as a gamepad.

Source:

- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-interaction-development-guide-gamepad

I did not find an official HarmonyOS high-level Adaptive Trigger or DualSense HD
haptics API. Those features should be treated as raw HID / USB output work.

Local SDK HID DDK docs add the important missing piece:

- `OH_Hid_Open(deviceId, interfaceIndex, ...)`
- `OH_Hid_Write(...)`: write an Output report to a HID device
- `OH_Hid_SendReport(...)`
- `OH_Hid_GetReport(...)`
- `OH_Hid_GetReportDescriptor(...)`
- permission references to `ohos.permission.ACCESS_DDK_HID`

This makes an Adaptive Trigger probe realistic, especially over USB. The caveat:
the docs tie these APIs to DDK/driver-extension style access and the local API
text references USB-protocol HID interfaces. It is not yet confirmed that an
ordinary HAP can open a Bluetooth HoG DualSense raw channel, nor that it can
exclusively own Bluetooth L2CAP control/interrupt channels.

Practical position:

- USB Adaptive Trigger: promising, do first.
- Bluetooth Adaptive Trigger: investigate after USB, because system HoG
  ownership may block raw vendor reports.
- HD haptics: keep as a later system-service/audio-transport lane, not a normal
  launcher-HAP promise.

## Proposed Components

### `libdualsense_hid.so`

Native C/C++ library shipped with the app.

Responsibilities:

- open a DualSense through HID DDK when permissions/device class allow it
- parse USB input reports when raw HID input is available
- build USB output report `0x02`
- later build Bluetooth output report `0x31` if raw Bluetooth transport is
  available
- expose presets for Adaptive Trigger:
  - off
  - rigid resistance
  - weapon-style resistance
  - vibration / pulse
- expose rumble, lightbar, player LED, and trigger reset commands
- optionally import vDS protocol helpers for CRC/state packing

ArkTS-facing C ABI:

- `ds_open(deviceId)`
- `ds_close(handle)`
- `ds_set_trigger(handle, side, mode, params)`
- `ds_set_rumble(handle, left, right)`
- `ds_set_lightbar(handle, r, g, b)`
- `ds_reset(handle)`
- `ds_probe(handle)` for VID/PID/report descriptor facts

### ArkTS HID Probe Page

Temporary debug UI inside the launcher.

Responsibilities:

- enumerate USB devices
- surface HID DDK device/interface candidates
- show VID/PID/product/manufacturer when available
- request USB/DDK right where the platform exposes it
- open HID interface through `OH_Hid_Open`
- dump report descriptor through `OH_Hid_GetReportDescriptor`
- send safe output reports:
  - reset triggers
  - lightbar color
  - tiny rumble pulse
  - left/right trigger test preset

### Wine Bridge

First pass:

- ArkTS/gamepad events -> native bridge -> Wine DInput/XInput-compatible events
- Adaptive Trigger output only from our launcher/debug profiles

Second pass:

- expose raw HID-like DualSense device to Wine games that know DualSense
- translate selected Wine HID OUT reports into `libdualsense_hid.so`
- keep XInput fallback for games that only understand Xbox controllers

## Execution Plan

### Phase DS-0: Device Visibility

- Use hdc to install a debug build on MatePad Edge.
- Add a DualSense Probe page.
- Connect DualSense over USB-C.
- Verify HarmonyOS can see `054c:0ce6` or `054c:0df2`.
- Verify whether `ohos.permission.ACCESS_DDK_HID` is grantable to this app
  shape, or whether a `DriverExtensionAbility`/system-signed sidecar is needed.
- Open the HID interface and dump the report descriptor.

### Phase DS-1: Safe Output

- Port only the small protocol structs and report builder.
- Send trigger reset on open/close.
- Send lightbar/player LED command.
- Send basic rumble command.
- Add guardrails so failed writes always reset triggers.
- Log the exact transport used: USB HID DDK, USB Manager fallback, or blocked.

### Phase DS-2: Adaptive Trigger Presets

- Implement preset builders for the 11-byte trigger FFB fields.
- Test L2/R2 independently.
- Add launcher-side profile selection per game.
- Persist per-game trigger profile in app sandbox.

### Phase DS-3: Wine Input

- Map HarmonyOS gamepad button/stick events into Wine DInput/XInput.
- Verify with the Win32 Tiny Game first.
- Then test with a small controller-aware Win32 sample.

### Phase DS-4: Wine Output

- Inspect Wine/DInput/XInput/HID output path.
- Translate supported output reports into DualSense commands.
- Start with rumble and trigger reset.
- Add Adaptive Trigger routing after basic rumble is stable.

### Phase DS-5: HD Haptics

- Treat this as audio transport, not ordinary rumble.
- vDS uses 48 kHz 4-channel PCM where channels 3/4 carry haptics data and Opus
  is used for the speaker path.
- On HarmonyOS, first determine whether the app can access a compatible USB
  audio or raw HID route for DualSense haptics.
- If not, keep HD haptics as launcher-synthesized effects, while still shipping
  Adaptive Trigger and ordinary rumble.
- Full vDS-like Bluetooth haptics likely needs system-service/HDI ownership of
  Bluetooth HID/L2CAP plus a virtual audio route. Treat that as a separate
  platform-integration track.

## Current Device Status

MatePad Edge is reachable over wireless hdc:

- target: `192.168.3.73:42895`
- product: `HUAWEI MatePad Edge`
- device type: `tablet`

Installed successfully with the paired HAP/HSP command:

```powershell
hdc -t 192.168.3.73:42895 install -r `
  entry/build/default/outputs/default/entry-default-signed.hap `
  proton/build/default/outputs/default/Proton.hsp
```

Do not use `hdc install -s` for this project. `proton` is an intra-app HSP
dependency here, while `-s` is for inter-application shared-bundle directories
and fails with `install param error`.

## Wine / Proton Parallel Track

Current build checkpoint:

- `assembleHap` succeeds.
- `assembleHsp` succeeds.
- HAP path:
  `entry/build/default/outputs/default/entry-default-signed.hap`
- HSP path:
  `proton/build/default/outputs/default/Proton.hsp`
- HAP contains:
  - `resources/rawfile/win32-smoke/ProtonSmokeWin32.exe`
  - `resources/rawfile/win32-smoke/ProtonTinyGame.exe`
  - `resources/rawfile/win32-smoke/proton_rawfile_index.json`

Tiny Game status:

- The first run staged runtime/payload and then crashed inside
  `libbox64_hmos_core.so` with `SIGSEGV`.
- `proton/src/main/cpp/napi_init.cpp` now launches the Wine/Box64 runtime in a
  forked child process and waits briefly for crashes. This should let the UI
  survive and report `proton runtime child crashed with signal 11` instead of
  killing the ArkTS app process.
- The patched HSP has been built and installed.
- Post-install launch verification is currently blocked because the MatePad Edge
  is locked; `aa start` returns `10106102` until the tablet is manually unlocked.

Run after unlock:

1. Start:
   `hdc -t <target> shell aa start -a WineFullWindowsDesktopExperienceAbility -b com.caidingding233.genohinimbact`
2. Tap `启动 Tiny Game`.
3. Expected next result: UI remains alive and reports child exit/crash status.
