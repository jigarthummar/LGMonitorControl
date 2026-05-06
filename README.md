# LGMonitorControl

A small macOS menu bar app to control an LG 27UP850-W (and other DDC/CI monitors) from the system menu bar — brightness, contrast, volume, mute, and input source. Built because macOS doesn't expose these settings for third-party displays.

Under the hood it shells out to [m1ddc](https://github.com/waydabber/m1ddc), which speaks DDC/CI over USB-C / DisplayPort.

## Requirements

- Apple Silicon Mac (m1ddc does not support the built-in HDMI port on M1 / entry M2 Macs)
- macOS 14 or later
- A monitor connected via USB-C / Thunderbolt / DisplayPort that supports DDC/CI
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

- **Brightness / Contrast / Volume** — drag a slider, release to apply. The value is written to the monitor on release, not while dragging, to avoid spamming the DDC bus.
- **Mute** — speaker icon next to the volume slider.
- **Input** — switch between HDMI 1, HDMI 2, DisplayPort 1/2, USB-C. Uses m1ddc's `input-alt` codes (LG monitors use alternate addressing).
- **Launch at login** — registers the app via `SMAppService`.
- **Quit** — exits the app.

The status dot in the header is green when the monitor is reachable over DDC, gray when not. If the monitor goes away (sleep, unplug), click Retry on the popover.

## Customizing for a different monitor

The app finds your display by scanning `m1ddc display list` for an entry whose name contains "LG". To target a different monitor:

- Open `LGMonitorControl/DDC.swift`
- In `resolveDisplay()`, change the `upper.contains("LG")` check to match your display's name from `m1ddc display list`.
- Optionally update the header label in `LGMonitorControl/MenuBarView.swift` (`Text("LG 27UP850-W")`).

For non-LG monitors that don't use alternate input addressing, change `setInputAlt` to `set input` in `DDC.swift`, and adjust the `InputSource` enum raw values in `MonitorController.swift` to standard codes (HDMI 1 = 17, HDMI 2 = 18, DisplayPort 1 = 15, DisplayPort 2 = 16, USB-C = 27).

## Troubleshooting

**Popover shows "m1ddc is not installed"**
Run `brew install m1ddc`. The app expects the binary at `/opt/homebrew/bin/m1ddc`.

**"Monitor not reachable"**
Run `m1ddc display list` in Terminal — your monitor should appear. If it doesn't, m1ddc can't see it (HDMI port limitation on entry-level Apple Silicon, or the monitor doesn't support DDC/CI). If it does appear but the name doesn't contain "LG", see *Customizing for a different monitor* above.

**Values look wrong / change randomly**
Make sure you're on the latest commit. Earlier revisions had a bug where concurrent `m1ddc` calls collided on the DDC serial bus and returned each other's responses. Fixed in `291560e`.

**Sliders snap on click instead of where I dragged**
Same — update to the latest commit (`ad140bf`). The original used a custom slider with `DragGesture(minimumDistance: 0)` which interpreted clicks as drag-to-cursor.

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
- `LGMonitorControl/MenuBarView.swift` — the popover UI
- `LGMonitorControl/MonitorController.swift` — observable state, debounced writes, hot-plug handling
- `LGMonitorControl/DDC.swift` — m1ddc subprocess wrapper, serialized on a single dispatch queue
- `LGMonitorControl/Theme.swift` — Claude-inspired warm palette and themed slider row
- `project.yml` — xcodegen project spec; regenerate the `.xcodeproj` after editing
