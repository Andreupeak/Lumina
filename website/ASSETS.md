# Showcase assets

The website uses real Lumina interface captures and one generated device illustration.
No user settings, real location requests, or hardware changes were used for these captures.

## App screenshots

`assets/app-system.png`, `app-sun-cycle.png`, `app-time-slots.png`, and
`app-idle.png` were captured from the app's isolated Debug UI test window.
It runs the real ContentView with a separate, disposable preferences domain and simulated
hardware. The app's source, feature controls, and displayed interface were not redesigned
for the images. The test window title bar was cropped away, and metadata was removed.

Sun Cycle uses manually entered **sample Berlin coordinates, 52.5, 13.4**, not the
maintainer's location. Sunrise/sunset times reflect the sample date and local time zone.
Time Slots uses illustrative “Evening focus” (18:00–22:00, 50%) and “Late reading”
(22:00–01:00, 30%) settings. Timer captures show a sample 30-second global timeout.

The icon comes from the existing repository's AppIcon asset set.

## Device illustration

Final asset: `assets/keyboard-studio.webp`.
Generated with the built-in image-generation tool, then exported as optimized WebP.
It is a product illustration, not a photograph, supported-hardware certification,
or proof of a specific Mac model. White keyboard LEDs are shown; the amber and indigo
are environmental scene lighting. Lumina does not change LED colors.

Final generation prompt:

```text
Use case: product-mockup
Asset type: premium open-source Mac keyboard-backlight app landing-page hero illustration, landscape 1536 by 1024 composition.
Primary request: a cinematic photorealistic product illustration of a slim dark aluminum laptop keyboard with soft WHITE keyboard backlighting. The white illumination is clearly visible around and through the black keycaps. The laptop has a plausible familiar compact laptop keyboard layout and large trackpad, no numeric keypad.
Scene/backdrop: almost-black studio, quiet warm amber atmospheric light from the upper left blending into muted indigo on the right, consistent with a sunset-to-night app identity. Very subtle haze, not sci-fi.
Composition/framing: close low three-quarter view from the front-left, the keyboard and trackpad occupy the lower two thirds, the open screen is mostly outside the upper frame and never shows UI. Leave some soft negative space above. Crisp product detail, beautifully restrained studio photography.
Materials/textures: graphite anodized aluminum, lightly textured matte keycaps, precise softly bevelled edges.
Constraints: no Apple logo, no brand, no watermark, no text overlays, no app interface, no hands, no objects, no RGB keys or colored keyboard LEDs. Colored ambient light is environmental; key LEDs are white. This is an illustrative device rendering, not a claim of specific hardware.
```

## Promotional layouts

`assets/lumina-social.png` is the 1200 × 630 social/repository cover.
`assets/lumina-feature-1.png` through `lumina-feature-3.png` are 900 × 1440
feature posters. `assets/lumina-features.png` is their 2400 × 1280 combined layout.

These are original deterministic graphic layouts exported by
`scripts/render_showcase.py` with Python and Pillow. They composite the actual
screenshots without generating or replacing the UI text or controls. Fonts are rendered
using local system fonts; no font files are distributed. The website has no font dependency.
Generated assets and layouts are included under the repository's MIT license.

To regenerate the layouts after replacing the sanitized screenshot inputs:

```sh
python3 scripts/render_showcase.py
python3 scripts/check_website.py
```
