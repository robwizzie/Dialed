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
| `make_icon.py` | Generates every SVG from one set of numbers (angles, radii, colours). |
| `render.js` | Renders the SVGs to 1024 px PNGs with Playwright. |
| `svg/dialed-icon-{light,dark,tinted}.svg` | Flat icons for each appearance. |
| `svg/layer-{1-background,2-ring,3-knob}.svg` | Layers for Icon Composer. |
| `png/` | Rendered PNGs (copied into `AppIcon.appiconset`). |

## Regenerating

```sh
python3 make_icon.py
NODE_PATH=$(npm root -g) node render.js png
cp png/AppIcon-*.png ../../Dialed/Dialed/Resources/Assets.xcassets/AppIcon.appiconset/
```

## Full Liquid Glass on iOS 26 (optional)

The asset catalog icon works everywhere now (light, dark and tinted). For the
system's live glass treatment, build a `.icon` in Icon Composer (Xcode 26 →
Open Developer Tool → Icon Composer):

1. Drag in `layer-1-background.svg`, `layer-2-ring.svg`, `layer-3-knob.svg`
   as three groups, bottom to top.
2. Turn **Liquid Glass** on for the knob group (knob + lens) and lightly for the ring;
   leave the background plain.
3. Save as `AppIcon.icon` into the app target and set it as the app icon in
   the target's General tab. Xcode uses it on iOS 26 and the PNG set below that.
