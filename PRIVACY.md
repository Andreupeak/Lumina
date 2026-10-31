# Privacy

This policy describes the source code in this repository. It was reviewed on 2026-10-23.

## Data on your Mac

Lumina saves brightness settings, daily schedules, timeout durations, setup completion, selected
location source, and optional region coordinates in macOS UserDefaults under the app's bundle identifier
(`Andreupeak.Lumina` for the upstream app). There is no account or Lumina-operated server.

Coordinates from every source are validated and rounded to one decimal place before storage.
One tenth of a degree of latitude is about 11 km; longitude resolution varies with latitude.
Older stored coordinates are rounded when loaded. Region coordinates can still reveal where you live
or work. UserDefaults is unencrypted and may be readable by software running as your user or included
in system backups. Lumina does not claim to securely erase existing backups.

Open **Periodic → Sun Cycle**, expand location details, and select **Forget Saved Location** to
cancel pending lookups and remove the saved coordinates. This also switches the source to Manual.
It does not revoke Apple's location permission; use **System Settings → Privacy & Security → Location Services**.
Time Slots and System Control work without a saved location.

To remove all preferences, quit Lumina first, then run `defaults delete Andreupeak.Lumina`.
This resets schedules, brightness settings, and setup as well as location. Forks using a different
bundle identifier must use their own identifier. Deleting the app alone does not remove UserDefaults.

## Location sources

| Source | Trigger | Network and retention |
| --- | --- | --- |
| Manual | You save valid latitude and longitude | Lumina makes no location network request; rounded coordinates stay on your Mac |
| Mac Location | You select it; on later launches only if selected and already authorized | Uses Apple's Core Location services, which may use Wi-Fi and Apple's network services; only rounded coordinates are saved by Lumina |
| IP Estimate | You select it and confirm the disclosure | Sends an HTTPS request to `ipapi.co`; that provider sees your public IP and standard connection/request metadata, including a generic `Lumina` user agent; Lumina saves rounded coordinates |

IP Estimate is optional, may be inaccurate with VPNs or mobile networks, and is never an automatic
fallback or startup lookup. The provider's own [privacy policy](https://ipapi.co/privacy/) governs its
handling of the request. The provider states that it retains IP queries in logs for a limited time.
Lumina does not control that provider's logs or retention. It does not send
your saved coordinates, schedules, keyboard state, or a persistent identifier to the provider.

Requests use an ephemeral URLSession without a persistent cache, cookies, or credential storage.
Redirects are rejected. Responses must be successful HTTP responses, are limited to 16 KiB, and must
contain valid coordinates. Switching source or forgetting location cancels pending work; stale
callbacks cannot overwrite the new choice. Unneeded response fields such as city and IP are not saved.

## Keyboard activity and hardware

Lumina reads a system idle-time counter to determine whether to dim the backlight.
It does not install event taps, read typed text, log input, or transmit activity data.
It loads CoreBrightness from a fixed system framework path, checks required selectors, and controls
the first supported keyboard reported by that framework. It does not require administrator access.

## Tracking and dependencies

Lumina has no analytics, ads, crash-upload SDK, third-party runtime package, or automatic update check.
The privacy manifest declares local UserDefaults access, no tracking, and coarse location for the
optional IP lookup's app functionality. That declaration is conservatively marked linked because
the provider receives a raw IP address, even though Lumina has no account or device identifier.
This follows Apple's [data disclosure guidance](https://developer.apple.com/app-store/app-privacy-details/)
for IP addresses used for location. Manual coordinates and Mac Location remain local to Lumina;
data collected separately by Apple is governed by Apple's policies. GitHub and Apple apply their own policies
when you visit this repository, download releases, or use operating-system services.

Do not put coordinates, IP addresses, system serial numbers, or screenshots containing personal data
in public bug reports. See [SECURITY.md](SECURITY.md) for security-reporting instructions.
