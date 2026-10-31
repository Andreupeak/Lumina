# Architecture

Lumina is a SwiftUI menu-bar app. Xcode's synchronized `Lumina/` group compiles all app sources.
`Package.swift` compiles the same `Lumina/Core/` files as a small library for hardware-independent
XCTest coverage; the app does not link or download a separate copy of the library.

| Area | Responsibility |
| --- | --- |
| `LuminaApp.swift` | Menu-bar scene, startup, and normal termination |
| `ContentView.swift` | Mode selection, onboarding, schedule editing, and bounded scrolling |
| `Views/` | Native duration/time menus, sliders, switches, and reusable styling |
| `Core/BrightnessPeriod.swift` | Validated daily ranges, overnight intervals, and overlap checks |
| `Core/Preferences.swift` | Main-actor UserDefaults storage, migration, validation, and location deletion |
| `Core/AutomationPolicy.swift` | Pure brightness decisions, idle-timeout precedence, and inactivity state |
| `Core/SolarCalculator.swift` | Offline NOAA-based solar events, time zones, and polar conditions |
| `Core/LocationCoordinate.swift` | Coordinate validation, reduced storage precision, response parsing, and startup policy |
| `Core/LocationLookupClient.swift` | Bounded, cancellable, optional HTTPS IP lookup |
| `Location/SunScheduleManager.swift` | Mac location authorization, request lifecycle, saved coordinates, and solar refresh |
| `Automation/AutoBacklightController.swift` | Applies policy, manages previews and sleep/wake, and publishes status |
| `Hardware/KeyboardBacklightManager.swift` | Fixed-path CoreBrightness loading and checked Objective-C dispatch |

## Runtime

Observable controllers and preferences are isolated to the main actor. A timer evaluates policy
twice a second while hardware is available, with tolerance for coalescing. The idle counter is
read only when a timeout applies or the keyboard is already off for inactivity. Hardware commands
and published values change only when needed. Solar times are cached for the day and time zone;
clock/time-zone changes and wake force a refresh.

The controller captures brightness and ambient mode once before taking control and restores them
on normal termination. Sleep stops polling and cancels a brightness preview; wake reapplies the
current mode without replacing the original captured state. Slider previews coalesce into one
pending reset and expire after three seconds.

The core inactivity latch prevents changing a schedule or removing a timeout from lighting an
unattended keyboard. Actual input clears it. Slot-specific nonzero timeouts take priority; zero
inherits the global setting. Invalid stored periods are excluded before time arithmetic.

## Location lifecycle

The selected source is preserved across launches. Startup can refresh only an already authorized
Mac Location source. IP lookup requires a user confirmation and never runs as a fallback.
Network requests use a cancellable task plus an identity check; switching to manual/Mac location
or forgetting location invalidates pending results. Core Location callbacks are accepted only
while a Mac location request is active. Responses are rounded before being persisted.

## Test window

Only a Debug build compiled with `LUMINA_UI_TESTING` replaces the menu-bar scene with a regular
window. It uses an isolated preference domain and simulates keyboard hardware, idle input, and
location requests. Release builds ignore the test flag. This allows UI verification without
changing the user's keyboard state or location settings. It does not test CoreBrightness itself. `--light` selects light appearance.
The explicit `--test-mac-location` argument enables a real, consent-based Mac Location request
in that Debug-only window; IP lookup and keyboard hardware remain simulated. Test coordinates
stay in the isolated domain and are deleted on normal quit.
