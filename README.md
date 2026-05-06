# LGMonitorControl

A small macOS menu bar app to control any DDC/CI-capable external monitor — brightness, contrast, volume, mute, and input source — from the system menu bar. Built because macOS doesn't expose these settings for third-party displays.

Supports multiple monitors at once: each detected display gets its own tab in the popover. Vendor-specific quirks (LG monitors use alternate VCP addressing for input switching) are handled automatically.

The project name is historical — it began as a single-monitor LG controller and the package name stuck. It now works with any DDC/CI display.

Under the hood it shells out to [m1ddc](https://github.com/waydabber/m1ddc), which speaks DDC/CI over USB-C / DisplayPort.

## Requirements

- Apple Silicon Mac (m1ddc does not support the built-in HDMI port on M1 / entry M2 Macs)
- macOS 14 or later
- One or more external monitors connected via USB-C / Thunderbolt / DisplayPort that support DDC/CI
- [Homebrew](https://brew.sh)
- Xcode 15+ (only for building from source)

## Install

There's no pre-built release yet — build from source.

```bash
# 1. Install runtime + build dependencies
brew install m1ddc xcodegen

# 2. Clone
git clone https://github.com/jigarthummar/LGMonitorControl.git
cd LGMonitorControl

# 3. Generate the Xcode project and build a Release .app
xcodegen generate
xcodebuild -project LGMonitorControl.xcodeproj \
           -scheme LGMonitorControl \
           -configuration Release \
           -derivedDataPath build \
           build

# 4. Move the app into /Applications and launch it
cp -R build/Build/Products/Release/LGMonitorControl.app /Applications/
open /Applications/LGMonitorControl.app
```

A `display` icon will appear in the menu bar. The app has no Dock icon (`LSUIElement`).

## Usage

Click the menu bar icon to open the popover.

- **Tabs** at the top — one per detected external monitor. Click a tab to switch which monitor's controls are shown. Built-in panels are filtered out (m1ddc can't control them).
- **Brightness / Contrast / Volume** — drag a slider, release to apply. Writes happen on release, not while dragging, to avoid spamming the DDC bus. If a monitor doesn't support a control, the slider renders disabled and labeled "not supported".
- **Mute** — speaker icon next to the volume slider.
- **Input** — switch between HDMI 1, HDMI 2, DisplayPort 1/2, USB-C. The app dispatches via standard or alternate VCP addressing depending on the monitor's vendor.
- **Launch at login** — registers the app via `SMAppService`.
- **Quit** — exits the app.

The status dot in the per-display header is green when the monitor is reachable over DDC, gray when not. The selected tab is remembered across launches.

## How it detects monitors

At launch (and whenever displays are added or removed), the app runs `m1ddc display list detailed` and parses the output. Each entry's manufacturer code is read from the `- Manufacturer:` line:

- Entries with name `(null)` or manufacturer `00-10-fa` (Apple's PNP ID) are skipped — they are built-in panels that m1ddc can't drive.
- Entries with manufacturer `GSM` (LG) are flagged for alternate input-switch addressing.
- All other vendors use standard VCP input codes (HDMI 1=17, HDMI 2=18, DP 1=15, DP 2=16, USB-C=27).

If a vendor-detection heuristic misses your monitor and input switching doesn't work, please open an issue with the output of `m1ddc display list detailed`.

## Troubleshooting

**Popover shows "m1ddc is not installed"**
Run `brew install m1ddc`. The app expects the binary at `/opt/homebrew/bin/m1ddc`.

**"No external displays detected"**
Run `m1ddc display list` in Terminal — your monitor should appear there. If it doesn't, m1ddc can't see it (built-in HDMI port limitation on entry-level Apple Silicon, or the monitor doesn't support DDC/CI).

**A control is greyed out and says "not supported"**
The monitor reported `0` for that property's max value over DDC, meaning it doesn't expose that control. Common cases: monitors without speakers (volume disabled), some KVM-equipped monitors that lock contrast, etc.

**Input switching doesn't change the input**
The app guesses LG's alt addressing by manufacturer code `GSM`. If you have an LG monitor that reports a different code, or a non-LG monitor that nonetheless uses alt addressing, the dispatch will be wrong. Open an issue and include `m1ddc display list detailed`.

## Uninstall

```bash
# Stop the app
pkill -f "LGMonitorControl/Contents/MacOS"

# Unregister launch-at-login if you enabled it (no-op if you didn't)
launchctl bootout gui/$(id -u)/com.jigarthummar.LGMonitorControl 2>/dev/null

# Remove the app and its preferences
rm -rf /Applications/LGMonitorControl.app
rm -rf ~/Library/Preferences/com.jigarthummar.LGMonitorControl.plist
rm -rf ~/Library/Caches/com.jigarthummar.LGMonitorControl
```

## Project layout

- `LGMonitorControl/LGMonitorControlApp.swift` — `MenuBarExtra` entry point
- `LGMonitorControl/MenuBarView.swift` — the popover UI: tab strip + per-display controls + footer
- `LGMonitorControl/MonitorManager.swift` — discovers displays, owns the list of `DisplayController`s, persists the selected tab, listens for hot-plug events
- `LGMonitorControl/DisplayController.swift` — per-display observable state, capability flags, debounced writes, vendor-aware input dispatch
- `LGMonitorControl/DDC.swift` — m1ddc subprocess wrapper. All calls run on a single serial dispatch queue (DDC/CI is a serial bus and concurrent calls corrupt each other's responses). Includes the display-list parser and `Display` model.
- `LGMonitorControl/Theme.swift` — Claude-inspired warm palette and a `ThemedSlider` row that respects `@Environment(\.isEnabled)` for the disabled state.
- `project.yml` — xcodegen project spec; regenerate the `.xcodeproj` after editing with `xcodegen generate`.
