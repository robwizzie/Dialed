#!/usr/bin/env python3
"""
Dialed app icon — "The Dial", Liquid Glass edition.

A dial built from glass over the app's colours:

  * the scale is a full 270° ring in all four app colours
    (green → sky → lavender → orange), lit like a glass tube;
  * the knob is a frosted glass disc that picks up the colours around it,
    with a specular rim and one pointer dot;
  * a glass lens sits on the ring at the dialed-in value and magnifies the
    colour under it, like an iOS 26 slider thumb.

One geometry, three appearances (light / dark / tinted) plus separate
layers for Icon Composer. Everything is drawn on a 1024 canvas; run this,
then render.js turns the SVGs into the PNGs in the asset catalog.

    python3 make_icon.py     # writes ./svg/*.svg
"""
import math, os

S = 1024
C = (512, 530)   # a touch low: the open bottom of the dial reads lighter
OUT = os.path.join(os.path.dirname(__file__), "svg")
os.makedirs(OUT, exist_ok=True)

# App palette (Utilities/NekaTheme.swift)
GREEN, SKY, LAV, ORANGE = "#4CB868", "#5DB4F0", "#A88BEB", "#F59A4C"
STOPS = [(0.0, GREEN), (0.38, SKY), (0.70, LAV), (1.0, ORANGE)]

START = 135.0        # scale starts at ~7:30 (SVG degrees, clockwise from +x)
SWEEP = 270.0        # and runs 270° to ~4:30, like a real knob
VALUE = 0.74         # how far it's dialed in
POINTER = START + SWEEP * VALUE

RING_R, RING_W = 316, 92     # the colour ring
KNOB_R = 200                 # the glass knob
LENS_R = 70                  # glass lens on the ring
PTR = (64, 168, 26)          # pointer line: from, to, width
KNURL = (KNOB_R - 24, KNOB_R - 6, 72)   # grip ridges: from, to, count
SCALE_R = (220, 250)         # graduations between knob and ring
SCALE_N = 27                 # 28 marks; every 3rd is major


def pt(r, deg, c=C):
    a = math.radians(deg)
    return c[0] + r * math.cos(a), c[1] + r * math.sin(a)


def _lin(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _srgb(c):
    c = c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
    return max(0, min(255, round(c * 255)))


def _oklch(hexc):
    r, g, b = (_lin(int(hexc[i:i + 2], 16)) for i in (1, 3, 5))
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(A, B), math.degrees(math.atan2(B, A))


def _from_oklch(L, Cc, H):
    A, B = Cc * math.cos(math.radians(H)), Cc * math.sin(math.radians(H))
    l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3
    m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3
    s = (L - 0.0894841775 * A - 1.2914855480 * B) ** 3
    r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return "#%02X%02X%02X" % (_srgb(r), _srgb(g), _srgb(b))


def mix(c1, c2, t):
    # blend in OKLCH so lavender → orange goes through pink, not grey
    L1, C1, H1 = _oklch(c1)
    L2, C2, H2 = _oklch(c2)
    dh = (H2 - H1 + 180) % 360 - 180
    return _from_oklch(L1 + (L2 - L1) * t, C1 + (C2 - C1) * t, H1 + dh * t)


def grad(t):
    for (t0, c0), (t1, c1) in zip(STOPS, STOPS[1:]):
        if t <= t1:
            return mix(c0, c1, (t - t0) / (t1 - t0))
    return STOPS[-1][1]


def gray(hexc):
    r, g, b = (int(hexc[i:i + 2], 16) for i in (1, 3, 5))
    y = round(0.30 * r + 0.59 * g + 0.11 * b)
    y = min(255, y + 70)  # lift so the tinted ring reads bright on black
    return "#%02X%02X%02X" % (y, y, y)


def arc_path(r, a0, a1):
    x0, y0 = pt(r, a0)
    x1, y1 = pt(r, a1)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return f"M{x0:.2f} {y0:.2f} A{r} {r} 0 {large} 1 {x1:.2f} {y1:.2f}"


def theme(name):
    if name == "light":
        return dict(name=name, bg0="#FFFFFF", bg1="#EDEDF2", bloomA=0.35, glass="#FFFFFF", glassA=0.62,
                    spec=1.0, edgeA=0.10, dot="#151619", shadowA=0.18, col=lambda c: c,
                    dim="#000000", dimA=0.16, ridge="#000000", ridgeA=0.07)
    if name == "dark":
        return dict(name=name, bg0="#202024", bg1="#050506", bloomA=0.45, glass="#FFFFFF", glassA=0.14,
                    spec=0.55, edgeA=0.25, dot="#FFFFFF", shadowA=0.55, col=lambda c: c,
                    dim="#FFFFFF", dimA=0.22, ridge="#FFFFFF", ridgeA=0.10)
    # tinted: iOS turns this into the user's tint colour, so it's drawn in luminance only
    return dict(name=name, bg0="#141414", bg1="#000000", bloomA=0.30, glass="#FFFFFF", glassA=0.14,
                spec=0.55, edgeA=0.25, dot="#FFFFFF", shadowA=0.55, col=gray,
                dim="#FFFFFF", dimA=0.25, ridge="#FFFFFF", ridgeA=0.12)


def defs(t):
    cx, cy = C
    return f"""
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{t['bg0']}"/><stop offset="1" stop-color="{t['bg1']}"/>
    </linearGradient>
    <!-- light comes from the top left -->
    <linearGradient id="spec" gradientUnits="userSpaceOnUse" x1="{cx - 300}" y1="{cy - 320}" x2="{cx + 260}" y2="{cy + 300}">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="{0.95 * t['spec']:.2f}"/>
      <stop offset="0.45" stop-color="#FFFFFF" stop-opacity="0"/>
      <stop offset="0.8" stop-color="#FFFFFF" stop-opacity="0"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="{0.55 * t['spec']:.2f}"/>
    </linearGradient>
    <linearGradient id="knobFace" x1="0.2" y1="0" x2="0.8" y2="1">
      <stop offset="0" stop-color="{t['glass']}" stop-opacity="{min(1, t['glassA'] + 0.25):.2f}"/>
      <stop offset="1" stop-color="{t['glass']}" stop-opacity="{t['glassA']:.2f}"/>
    </linearGradient>
    <radialGradient id="lensFace" cx="0.35" cy="0.3" r="0.8">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.55"/>
      <stop offset="0.6" stop-color="#FFFFFF" stop-opacity="0.12"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0.05"/>
    </radialGradient>
    <filter id="bloom" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="60"/></filter>
    <filter id="frost" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="34"/></filter>
    <filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="24"/></filter>
    <filter id="tiny" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="8"/></filter>
    <clipPath id="knobClip"><circle cx="{cx}" cy="{cy}" r="{KNOB_R}"/></clipPath>
    <clipPath id="lensClip"><circle cx="{pt(RING_R, POINTER)[0]:.1f}" cy="{pt(RING_R, POINTER)[1]:.1f}" r="{LENS_R}"/></clipPath>
  </defs>"""


def ring_strokes(t, r=RING_R, w=RING_W, seg=150, a_from=START, a_to=START + SWEEP, f_from=0.0, f_to=1.0, caps=True):
    out = []
    if caps:
        # round ends as separate dots, so no segment's cap pokes over its neighbour
        for a, f in ((a_from, f_from), (a_to, f_to)):
            x, y = pt(r, a)
            out.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{w / 2:.1f}" fill="{t["col"](grad(f))}"/>')
    for i in range(seg):
        a0 = a_from + (a_to - a_from) * i / seg
        a1 = a_from + (a_to - a_from) * (i + 1) / seg + (0.8 if i < seg - 1 else 0)
        col = t["col"](grad(f_from + (f_to - f_from) * (i + 0.5) / seg))
        out.append(f'<path d="{arc_path(r, a0, a1)}" fill="none" stroke="{col}" stroke-width="{w}"/>')
    return "".join(out)


def background(t):
    # a soft bloom of the ring's colours, for the glass to refract
    return (f'<rect width="{S}" height="{S}" fill="url(#bg)"/>'
            f'<g filter="url(#bloom)" opacity="{t["bloomA"]}">{ring_strokes(t, r=RING_R - 40, w=200, seg=40)}</g>')


def ring(t):
    out = [ring_strokes(t)]
    # glass tube lighting: a bright edge along the top-left, a soft one bottom-right
    out.append(f'<path d="{arc_path(RING_R + RING_W / 2 - 9, START + 3, START + SWEEP - 3)}" fill="none" '
               f'stroke="url(#spec)" stroke-width="6" stroke-linecap="round"/>')
    out.append(f'<path d="{arc_path(RING_R - 6, START + 16, START + SWEEP - 16)}" fill="none" '
               f'stroke="#FFFFFF" stroke-opacity="{0.22 * t["spec"]:.2f}" stroke-width="26" stroke-linecap="round" filter="url(#tiny)"/>')
    out.append(f'<path d="{arc_path(RING_R - RING_W / 2 + 6, START + 3, START + SWEEP - 3)}" fill="none" '
               f'stroke="#000000" stroke-opacity="0.08" stroke-width="6" stroke-linecap="round"/>')
    return "".join(out)


def scale(t):
    # the graduated scale printed between knob and ring — lit up to the value
    out = []
    for i in range(SCALE_N + 1):
        f = i / SCALE_N
        a = START + SWEEP * f
        major = i % 3 == 0
        r0 = SCALE_R[0] if major else SCALE_R[0] + 9
        x0, y0 = pt(r0, a)
        x1, y1 = pt(SCALE_R[1], a)
        lit = f <= VALUE + 1e-6
        col = t["col"](grad(f)) if lit else t["dim"]
        out.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" stroke="{col}" '
                   f'stroke-opacity="{1 if lit else t["dimA"]}" stroke-width="{11 if major else 7}" stroke-linecap="round"/>')
    return "".join(out)


def knob(t):
    cx, cy = C
    out = []
    out.append(f'<circle cx="{cx}" cy="{cy + 28}" r="{KNOB_R - 8}" fill="#000000" opacity="{t["shadowA"]}" filter="url(#soft)"/>')
    # frosted glass: the colours round the knob, blurred and pulled inward
    out.append(f'<g clip-path="url(#knobClip)"><g filter="url(#frost)" opacity="0.9">'
               f'{ring_strokes(t, r=KNOB_R - 10, w=90, seg=40)}</g>'
               f'<circle cx="{cx}" cy="{cy}" r="{KNOB_R}" fill="url(#knobFace)"/></g>')
    # specular rim + a faint dark edge so it sits off the background
    out.append(f'<circle cx="{cx}" cy="{cy}" r="{KNOB_R - 0.5}" fill="none" stroke="#000000" stroke-opacity="{t["edgeA"] * 0.5:.2f}" stroke-width="1.5"/>')
    out.append(f'<circle cx="{cx}" cy="{cy}" r="{KNOB_R - 4}" fill="none" stroke="url(#spec)" stroke-width="7"/>')
    # knurled grip round the edge
    ridges = []
    for i in range(KNURL[2]):
        a = 360 * i / KNURL[2]
        x0, y0 = pt(KNURL[0], a)
        x1, y1 = pt(KNURL[1], a)
        ridges.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}"/>')
    out.append(f'<g stroke="{t["ridge"]}" stroke-opacity="{t["ridgeA"]}" stroke-width="6" stroke-linecap="round" '
               f'clip-path="url(#knobClip)">' + "".join(ridges) + '</g>')
    # pointer: a recessed line from the centre out to the edge, aimed at the value
    x0, y0 = pt(PTR[0], POINTER)
    x1, y1 = pt(PTR[1], POINTER)
    out.append(f'<line x1="{x0:.1f}" y1="{y0 + 3:.1f}" x2="{x1:.1f}" y2="{y1 + 3:.1f}" stroke="#FFFFFF" '
               f'stroke-opacity="{0.8 * t["spec"]:.2f}" stroke-width="{PTR[2]}" stroke-linecap="round"/>')
    out.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" stroke="{t["dot"]}" '
               f'stroke-width="{PTR[2]}" stroke-linecap="round"/>')
    return "".join(out)


def lens(t):
    # a glass lens riding the ring at the value, magnifying the colour under it
    x, y = pt(RING_R, POINTER)
    out = []
    out.append(f'<circle cx="{x:.1f}" cy="{y + 14:.1f}" r="{LENS_R - 4}" fill="#000000" opacity="{t["shadowA"] * 1.2:.2f}" filter="url(#tiny)"/>')
    # tinted with the colour under it, lit from the top left
    out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{LENS_R}" fill="{t["col"](grad(VALUE))}"/>')
    out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{LENS_R}" fill="url(#lensFace)"/>')
    out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{LENS_R - 3}" fill="none" stroke="url(#spec)" stroke-width="6"/>')
    out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{LENS_R - 0.5}" fill="none" stroke="#000000" stroke-opacity="{t["edgeA"] * 0.6:.2f}" stroke-width="1.5"/>')
    out.append(f'<ellipse cx="{x - 22:.1f}" cy="{y - 30:.1f}" rx="26" ry="13" fill="#FFFFFF" opacity="{0.85 * t["spec"]:.2f}" '
               f'transform="rotate(-30 {x - 22:.1f} {y - 30:.1f})"/>')
    return "".join(out)


def svg(body, t):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" width="{S}" height="{S}">'
            f'{defs(t)}{body}</svg>\n')


for name in ("light", "dark", "tinted"):
    t = theme(name)
    open(os.path.join(OUT, f"dialed-icon-{name}.svg"), "w").write(
        svg(background(t) + ring(t) + scale(t) + knob(t) + lens(t), t))

# Icon Composer layers (light geometry; Icon Composer adds its own glass)
t = theme("light")
open(os.path.join(OUT, "layer-1-background.svg"), "w").write(svg(background(t), t))
open(os.path.join(OUT, "layer-2-ring.svg"), "w").write(svg(ring(t) + scale(t), t))
open(os.path.join(OUT, "layer-3-knob.svg"), "w").write(svg(knob(t) + lens(t), t))
print("wrote", sorted(os.listdir(OUT)))
