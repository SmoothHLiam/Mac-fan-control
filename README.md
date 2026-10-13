# Mac Fan Control

A modern fan controller and thermal monitor for **Apple Silicon** Macs, in the spirit of
[Macs Fan Control](https://crystalidea.com/macs-fan-control): a dark, liquid-glass, minimalist interface, and a
menu bar presence in the style of [Stats](https://github.com/exelban/stats).

> **Status: first pass, never run on a Mac.** This was written without access to macOS or Apple Silicon hardware,
> and nothing here has been compiled or run yet. Expect to fix compile errors and verify SMC behaviour on your
> machine before trusting it. The portable logic has unit tests (`swift test`); the SMC write path is the part
> most in need of real-hardware verification. See [Known risks](#known-risks).

## What it does

- **Fan control modes per fan:** Auto (macOS), Manual (RPM slider), Curve (sensor → speed, draggable points),
  Max.
- **Profiles:** Auto, Quiet, Balanced, Performance, Max, plus your own saved setups. One click from the menu bar.
- **Sensors:** every readable SMC temperature, grouped (CPU, GPU, memory, storage, battery, ambient).
- **Menu bar (Stats-style):** separate fan and temperature items, each with a widget style — icon + value,
  sparkline, bar, or value only — optionally colour-coded by temperature. Left-click opens a glass popover;
  right-click is a profile switcher.
- **Safety:** thermal safeguard forces max fans at a configurable silicon temperature (default 95 °C, releases
  at −7 °C); curve mode with no temperature data fails to *max*, not off; fans return to automatic when the app
  quits, and the helper's watchdog releases them if the app stops talking for 6 s.
- **Efficiency:** one timer, ≈1 ms of IOKit reads per sample, key metadata cached, sensors enumerated once.
  Samples every 1 s while a window is open and every 3 s when only the menu bar shows (timer tolerance lets
  macOS coalesce wakeups). No animations run while idle.
- **Fanless Macs** (MacBook Air) work as a pure thermal monitor.
- `--demo` launches with simulated hardware, which is handy for UI work.

## Architecture

```
Sources/
  FanCore/          Portable logic + SMC/XPC plumbing
    SMCCodec        fourCC + flt/ui*/sp78/fpe2 encode/decode           (pure, tested)
    FanCurve        piecewise-linear curve, monotonic normalisation    (pure, tested)
    FanController   ramping, deadband, smoothing, safety latch         (pure, tested)
    Models/Sensors  settings, profiles, sensor classification          (pure, tested)
    SMCClient       AppleSMC user client (IOKit)                       (macOS)
    HelperProtocol  XPC contract                                       (macOS)
  FanHelper/        Root launch daemon: the only code that writes to the SMC
  MacFanControl/    AppKit shell + SwiftUI UI
    State/          AppState (sampling + control loop), config persistence
    Hardware/       SMC / simulated sources, XPC client, SMAppService install
    MenuBar/        NSStatusItem controller + widget renderer
    UI/             Theme (Liquid Glass), popover, control center, curve editor
```

Reads go straight to the SMC from the app (no root needed). Writes go through the helper over XPC, which clamps
every request to the fan's own min/max and only accepts connections that satisfy a code-signing requirement.

## Build

Requires macOS 14+, Xcode 15+ (Xcode 26 enables real Liquid Glass; earlier SDKs use a frosted-material fallback).

```sh
swift test                    # core logic tests
./scripts/build_app.sh        # → build/Mac Fan Control.app (ad-hoc signed, arm64)
open "build/Mac Fan Control.app"
```

Then **Settings → Fan helper → Install** and approve it under *System Settings → General → Login Items*.
If SMAppService refuses an ad-hoc build, use the plain launchd route instead:

```sh
sudo ./scripts/install_helper.sh "build/Mac Fan Control.app"
sudo ./scripts/install_helper.sh --uninstall
```

For distribution, sign with a Developer ID (`SIGN_ID=… ./scripts/build_app.sh`) and tighten
`HelperConstants.appRequirement` in `Sources/FanCore/HelperProtocol.swift` to include your Team ID.

## Known risks

- **Unverified SMC writes.** Manual fan control on Apple Silicon uses `F<n>Md` / `F<n>Tg`; on recent macOS
  releases `thermalmonitord` reasserts automatic mode, so the helper falls back to the `Ftst` unlock and retries.
  Key names and behaviour vary by chip and OS version, so confirm on your machine (watch the RPM follow the
  target). Reading is far less risky than writing.
- **Sensor naming.** SMC temperature keys differ across M-series generations. Sensors are classified by key
  prefix and shown with their raw key; unknown ones land under "Other".
- **Ad-hoc signing** can only pin the XPC peer by identifier, which a local attacker can imitate. Use a Team ID
  requirement for anything you distribute.
- **No app icon** is included yet.
- **Don't push fans below macOS's judgement for long.** Manual/curve modes can run hotter than Auto. The safeguard
  exists, but this is a tool that overrides thermal management; use it deliberately.
