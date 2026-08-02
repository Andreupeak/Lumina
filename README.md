# Lumina

Lumina is a macOS menu-bar utility for managing a MacBook keyboard backlight.

## Features

- Manual keyboard-backlight brightness and ambient auto-brightness controls
- Nightly automation from local sunset to sunrise
- Time-slot schedules for different brightness levels
- Optional inactivity timeout to turn the backlight off when idle
- Precise, approximate, or manually entered location sources for solar scheduling

## Requirements

- macOS 26.5 or later
- A Mac with a controllable keyboard backlight
- Xcode 26.5 or later to build from source

## Run locally

1. Open `Lumina.xcodeproj` in Xcode.
2. Select the **Lumina** scheme and your Mac as the destination.
3. Build and run.

## Privacy

Lumina stores its preferences, including selected location coordinates, locally in macOS user defaults. The optional **Approximate** location mode requests an IP-based estimate from `ipapi.co`; choose **Precise** or **Manual** if you do not want to use that service.

## Compatibility note

Lumina currently uses macOS's private CoreBrightness framework to control the keyboard backlight. This is not a public Apple API, so behavior may vary across hardware and macOS releases and the project is not suitable for Mac App Store distribution in its current form.
