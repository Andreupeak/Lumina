# Lumina

A small macOS menu-bar app for controlling your MacBook's keyboard backlight.
Set a brightness, follow the sun, or choose the hours when your keyboard should light up.

Lumina uses Apple's **private CoreBrightness framework**. Hardware support can change
with macOS updates. It runs without App Sandbox and is not suitable for Mac App Store
distribution. No administrator account, helper service, or Accessibility permission is required.

## Download and install

The free public beta is available from [GitHub Releases](https://github.com/Andreupeak/Lumina/releases).
Download the DMG, drag Lumina into Applications, eject the image, then open the installed app.
See [installation and first-open instructions](docs/INSTALL.md).

The free download has an identity-free local signature and is **not Apple-notarized**. Expect a
macOS first-open warning. Apple's per-app approval process is documented in the installation guide;
never disable system security controls. A warning-free Developer ID/notarized release normally
requires a paid Apple Developer membership. This project does not require that purchase.

This is a **public beta**, with a universal Intel/Apple silicon binary and real keyboard checks on
one Apple silicon Mac. Other hardware and macOS versions need compatibility reports.

## Features

- **System:** fixed brightness in 2% steps or ambient auto-brightness.
- **Periodic → Sun Cycle:** night brightness from sunset to sunrise; off during daylight.
- **Periodic → Time Slots:** up to three non-overlapping daily slots, including overnight slots.
  The backlight is off outside those slots.
- **Inactivity timeout:** a global duration, with optional overrides for individual slots.
- **Local solar calculations:** choose Mac Location, manual coordinates, or an explicitly requested IP estimate.
- Native menus, sliders, and switches, with keyboard and accessibility support.
- Restores the brightness and ambient setting captured at launch when you quit normally.

## Requirements

- macOS 14 or later (deployment target).
- A Mac with a keyboard backlight supported by CoreBrightness. External keyboards are not guaranteed to work.
- Xcode 16 or later to open the synchronized Xcode project and build from source.

Builds and automated tests have been verified locally with Xcode 27 on macOS 27, on Apple silicon.
The deployment target is not a claim that every Mac or older macOS version has been hardware-tested.
See [testing](docs/TESTING.md) for the validation scope and remaining hardware checks.

## Build and run

Clone this repository, open `Lumina.xcodeproj`, choose the **Lumina** scheme and **My Mac**,
then build and run. If Xcode asks for signing, choose your own team under Signing & Capabilities;
no developer team is committed to the project.

To build locally with an identity-free signature and no developer account:

```sh
./scripts/build.sh Debug
open build/DerivedData/Build/Products/Debug/Lumina.app
```

The app lives in the menu bar. Click its sun or moon icon to open settings.
The book button reopens setup; **Quit** stops Lumina and restores the captured hardware settings.
The build script completes the app-bundle signature without a personal certificate. See
[releasing](docs/RELEASING.md) for the privacy-checked public package process.

## Timers and schedules

Click a minutes or seconds menu to change a timeout. Scroll the panel to reach additional settings;
moving the pointer or scrolling past a closed menu does not edit the timer.

| Setting | Behavior |
| --- | --- |
| Global timeout disabled, or `00 min 00 sec` | No global idle dimming |
| Slot timeout above zero | Takes priority over the global timeout while that slot is active |
| Slot timeout `00 min 00 sec` | Uses the global inactivity setting |
| Slot start equals end | Rejected; use different times |
| Adjacent slots | Allowed; start is inclusive and end is exclusive |
| Slot crosses midnight | Applies on both sides of midnight |
| Idle timeout removed while you are away | Backlight stays off until actual user input |

Times use your Mac's local clock and time zone. Solar events are approximate civil sunrise and
sunset, calculated offline from [NOAA's solar equations](https://gml.noaa.gov/grad/solcalc/solareqns.PDF).
Polar day and polar night are handled explicitly. Sun Cycle waits for a saved location rather than
assuming a default city. Brightness previews last three seconds before the current mode resumes.

## Location and privacy

**Manual** works without a location service. **Mac Location** asks macOS for a location after
you select it; only an already authorized, selected Mac Location source can refresh on launch.
Apple's Location Services may use network services.

**IP Estimate** contacts `https://ipapi.co/json/` only after a separate confirmation. That provider
receives your public IP address. Lumina never silently falls back to it, and does not repeat an
IP lookup at startup. The request uses an ephemeral session without cookies, cache, or saved credentials.

Coordinates are rounded to 0.1° before being saved locally, including coordinates from older versions.
This reduces precision but does not make location anonymous. Preferences are stored unencrypted in
macOS UserDefaults. **Sun Cycle → location details → Forget Saved Location** removes Lumina's saved
coordinates and cancels pending requests. Permission revocation is managed separately in macOS settings.

There are no analytics, accounts, ads, telemetry, or automatic update checks. Idle detection reads
elapsed time since input; it does not record keys, pointer positions, or event contents.
See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Test and contribute

```sh
swift test --scratch-path build/SwiftPackage
./scripts/check.sh
```

The Swift package tests the same core sources compiled into the app, without touching keyboard
hardware or making live network requests. The full check also scans repository hygiene and builds
Debug and universal Release binaries. CI runs these checks on standard macOS runners only while
the repository is public. It does not store paid Actions artifacts/caches or use signing secrets.

See [CONTRIBUTING.md](CONTRIBUTING.md), [architecture](docs/ARCHITECTURE.md),
[testing](docs/TESTING.md), and the [changelog](CHANGELOG.md).
Report ordinary bugs in [GitHub Issues](https://github.com/Andreupeak/Lumina/issues).
Please omit coordinates, IP addresses, serial numbers, and other personal information.

## License

[MIT](LICENSE). Apple frameworks remain subject to Apple's terms; they are not bundled with Lumina.

Lumina is an independent community project and is not endorsed by Apple. The MIT license covers
this repository's code and assets, not Apple's system frameworks. See
[distribution and costs](docs/DISTRIBUTION.md) for the tradeoffs of this free release.
