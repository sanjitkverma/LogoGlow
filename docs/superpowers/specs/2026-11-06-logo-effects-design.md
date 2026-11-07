# LogoGlow effects: design

Date: 2026-11-06
Status: draft, awaiting approval

## Goal

Turn LogoGlow from an on/off switch into a paid-quality logo light app: custom brightness,
animated effects, music sync, and status alerts on the physical Apple logo of the
MacBook Pro (PROLED XDR, tested on Mac17,12).

Scope chosen by the user: **Core effects**, **Music sync**, **Alerts & status**.
Out of scope for now: schedules, battery rules, hotkeys, launch at login, removing the
room-light limit.

## What the hardware allows (from the 2026-11-06 spike)

- macOS calls the logo a "Light Emitter" (LE). It is driven by a PWM dimmer
  (`bklb-backlight`, `AppleARMPWMDevice`) managed by `corebrightnessd`.
- Any user process can set the logo's brightness, without admin rights, through the private
  `BrightnessSystemClient` in CoreBrightness:
  `setProperty:@[@[@0, @(nits)], @[@2000, @(nits)]] forKey:@"LEPWMBrightnessNitsMapping"`.
  This is a display-nits → logo-nits table; a flat table pins the logo to one value.
- The logo follows within about 0.1–0.3 s. A 30 Hz sine between 20 and 200 nits breathed smoothly.
- Live status is readable from `copyPropertyForKey:@"LEPWMState"` (AppliedNits,
  Min/MaxNitsRestriction, Lux, Factor, ...).
- macOS still clamps the result by room light (e.g. 20–223 nits at 12 lux). Effects work
  inside that range; the UI shows "Limited by room light" when the max cap is below the target.
- **The override is saved permanently** to root's `com.apple.CoreBrightness` prefs and survives
  restarts. Setting an empty or nil table does not clear it. Restoring Apple's behaviour needs
  `defaults delete com.apple.CoreBrightness LEPWMBrightnessNitsMapping` as root, then
  `killall corebrightnessd`. That was verified to restore normal behaviour.
- `LEBacklightMode` reads `2` normally; `0` turns the logo off (existing feature).

## Features

### Core effects
- **Menu bar first.** The menu bar popover becomes the main UI: on/off, a brightness slider,
  an effect picker with per-effect controls, and a live preview using the existing
  `GlowingApple` view. The existing window stays as the "showcase" view.
- Effects (each is a pure function `level(t) -> 0...1`):
  - **Apple default:** no override; macOS controls the logo (the restore path).
  - **Steady:** a fixed level from the brightness slider.
  - **Breathe:** a smooth ease in/out. Controls: speed (2–10 s per breath) and depth.
  - **Heartbeat:** a double pulse ("lub-dub"), then rest. Control: BPM (40–120).
  - **Candle:** a smoothed random flicker. Control: intensity.
- Level → nits: `minNits + level * (userMaxNits - minNits)`, where `userMaxNits` comes from the
  brightness slider (20–600 nits) and `minNits` = 2. macOS clamps the result further.

### Music sync
- Captures system audio output (not the mic) with a Core Audio **process tap**
  (`CATapDescription` / `AudioHardwareCreateProcessTap`, macOS 14.2+). It needs the one-time
  "System Audio Recording" permission and `NSAudioCaptureUsageDescription` in Info.plist.
- **Beat detector:** bass-band energy (a simple low-pass with RMS over ~20 ms frames)
  compared with a running average. A beat fires when energy > k × average and the
  minimum gap has passed. The output envelope has a fast attack and an exponential decay.
- Controls: intensity (how bright the beats are), floor glow between beats, and a strobe
  toggle (hard on/off flashes instead of a smooth decay).
- Audio is processed in memory only; nothing is recorded or stored.

### Alerts & status
Alerts temporarily take over the logo, then hand back to the current effect.
- **Claude Code status:**
  - A "Connect Claude Code" button adds hooks to `~/.claude/settings.json` (merged, with a
    backup made first). Each hook is one command tagged `# logoglow` that writes a state word to
    `~/Library/Application Support/LogoGlow/agent-state`.
  - Hooks: `UserPromptSubmit` → `working`, `Stop` → `done`, `Notification` → `needs-you`.
  - The app watches that file. `working` → steady slow pulse. `needs-you` → double-blink
    repeated every 4 s until the next prompt. `done` → one bright flash, then back to the effect.
  - "Disconnect" removes only the hooks tagged `# logoglow`.
- **Charging:** plugging in plays one "fill up" sweep (dim → bright); IOPowerSources notification.
- **Low battery:** at or below 10% and not charging, a slow triple blink every 60 s.
- **Focus timer:** 5/15/25/50 min presets in the menu. During the timer the logo glows steadily.
  At the end it blinks for 10 s, and a notification is posted.

## Architecture

The app splits into focused files under `Sources/`:

| File | Responsibility |
|---|---|
| `App.swift` | App entry, menu bar popover UI, showcase window (moved from today's file) |
| `GlowViews.swift` | `GlowingApple`, `Ripple`, `BrushedTexture` (moved, unchanged) |
| `LogoHardware.swift` | `BrightnessSystemClient` wrapper: `setNits(_:)`, `readState()`; loaded with `dlopen` + `objc_msgSend` |
| `Privileged.swift` | sudo rule install/upgrade, logo on/off, `restoreAppleDefaults()` |
| `Effects.swift` | Pure effect functions + `EffectSettings` (Codable, saved to UserDefaults) |
| `Engine.swift` | 30 Hz loop: picks the active source (alert > music > effect), maps level → nits, skips writes that change less than 0.5 nits, pauses while the display sleeps or the screen is locked |
| `MusicTap.swift` | Core Audio process tap → sample frames |
| `BeatDetector.swift` | Pure beat detection + envelope (testable) |
| `Alerts.swift` | Claude Code hook install/remove + file watcher, power monitor, focus timer |
| `HookConfig.swift` | Pure JSON merge/unmerge for `settings.json` (testable) |

### Privileged commands
The existing sudoers rule (`/etc/sudoers.d/logoglow`) is extended to exactly these commands:
- `/usr/bin/defaults write com.apple.CoreBrightness LEBacklightMode -int 0`
- `/usr/bin/defaults delete com.apple.CoreBrightness LEBacklightMode`
- `/usr/bin/defaults delete com.apple.CoreBrightness LEPWMBrightnessNitsMapping`
- `/usr/bin/killall corebrightnessd`

If the installed rule lacks a command (checked with `sudo -n -l <cmd>`), the app reinstalls it
with one password prompt, using the existing validate-with-visudo flow.

### Restoring Apple's settings (safety)
- A `overrideActive` flag is saved to UserDefaults before the first brightness write.
- Restore runs when the user picks "Apple default", when the app quits (`applicationWillTerminate`), and
  **on launch if the flag is still set** (crash recovery). Restore = delete key + restart
  `corebrightnessd`, then clear the flag.
- Turning the logo **off** stops the engine first, so no write fights the off mode.

## Error handling
- CoreBrightness class or keys missing (other Mac / future macOS): effects are disabled and the
  menu shows "Effects not supported on this Mac"; on/off still works.
- `setProperty` returns NO: stop the engine, show the message, restore.
- Audio permission denied: the Music option shows "Allow System Audio Recording in System Settings"
  with a button that opens that pane.
- `settings.json` unreadable or invalid JSON: don't touch it; show an error.

## Testing
- `test.sh` builds a small test runner with `swiftc` (no Xcode project) covering:
  - each effect function's range (always 0...1) and period;
  - beat detector on synthetic signals (a 120 BPM click track → about 2 beats/s; silence → none; constant tone → none);
  - hook merge/unmerge: adding to empty, adding to existing hooks, idempotent re-add, and removal leaving others intact.
- Manual hardware checks: each effect visibly runs on the logo; quit restores (`LEPWMState` follows
  display again); force-kill then relaunch restores; music reacts to a song; Claude Code hooks
  change the logo.

## Notes for selling (not built now)
- The `apple.logo` symbol in the icon and UI must be replaced before a paid release.
- Notarized Developer ID builds will need the audio capture usage string; the sudoers approach
  may need to move to a privileged helper (`SMAppService`) for a polished product.
