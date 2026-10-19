# Dialed app icon — "The Dial"

A dial made of glass over the app's colours: a full 270° ring in green →
sky → lavender → orange (blended in OKLCH so it stays vivid) lit like a
glass tube, a graduated scale lit up to the value, a raised knob sitting
in a socket (knurled side wall, chamfered edge, frosted dished glass top with
a pointer groove), and a glass
lens riding the ring at "dialed in". The same geometry is drawn live in the app by
`Views/Brand/DialedMark.swift` (splash, onboarding, Settings).

## Files

| Path | What |
| --- | --- |
| `make_icon.py` | Generates everything from one set of numbers (angles, radii, colours). |
| `render.js` | Renders the SVGs to 1024 px PNGs with Playwright. |
| `svg/dialed-icon-{light,dark,tinted}.svg` | The iPhone icon in each appearance. |
| `svg/dialed-icon-watch.svg` | Apple Watch icon (dark, sized for the round mask). |
| `Dialed.icon/` | Icon Composer bundle: flat layers + `icon.json` for live Liquid Glass. |
| `png/` | Rendered PNGs (copied into the asset catalog). |

## Regenerating

```sh
python3 make_icon.py
NODE_PATH=$(npm root -g) node render.js png
cp png/AppIcon-{light,dark,tinted}.png ../../Dialed/Dialed/Resources/Assets.xcassets/AppIcon.appiconset/
cp png/AppIcon-watch.png ../../Dialed/Dialed/Resources/Assets.xcassets/WatchAppIcon.appiconset/WatchAppIcon.png
```

## Live Liquid Glass on iOS 26 (Dialed.icon)

The PNG icons work everywhere. `Dialed.icon` is the iOS 26 version: the
system draws the glass itself, so highlights move as the phone tilts and
you get real Clear and Tinted looks. Its layers are flat shapes, grouped
front to back as **Knob** (pointer + knob), **Bead**, and **Scale** (ticks +
ring), each with glass, specular and shadow turned on.

1. Open `Dialed.icon` in Icon Composer (Xcode 26 → Open Developer Tool →
   Icon Composer) and check Default, Dark, Clear and Tinted in the preview.
   Tweak glass/translucency per group if you like and save.
2. Drag `Dialed.icon` into the Xcode project (Dialed target), then in the
   target's General tab set **App Icon** to `Dialed`. iOS 26 uses it; older
   iOS keeps using `AppIcon`.

`icon.json` was written by the script rather than by Icon Composer, so if
Icon Composer reports anything odd on open, re-create the three groups by
dragging in the SVGs from `Dialed.icon/Assets` — it takes about five minutes.
