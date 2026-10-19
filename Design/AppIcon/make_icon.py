#!/usr/bin/env python3
"""
Dialed app icon — "The Dial".

Kept to three things, the way Apple draws its own icons: one thick
gradient arc (the app's green → sky → lavender → orange, with an
Activity-ring style shadow under its end cap), one smooth glass knob,
and one pointer dot. No outlines, no texture, no tiny detail that turns
to mush at 29 pt.

One geometry, three appearances (light / dark / tinted) plus separate
layers for Icon Composer. Everything is drawn on a 1024 canvas; run
this, then render.js turns the SVGs into the PNGs in the asset catalog.

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

ARC_R, ARC_W = 318, 104      # the ring
ARC_TO = 0.70                # arc runs green → sky → lavender; stopping short of
                             # orange keeps the end cap one clean colour
KNOB_R = 206                 # the glass knob
DOT_R, DOT_AT = 26, 146      # pointer dot size, distance from centre
TICK_R = (KNOB_R - 30, KNOB_R - 14)


def pt(r, deg, c=C):
    a = math.radians(deg)
    return c[0] + r * math.cos(a), c[1] + r * math.sin(a)


def mix(c1, c2, t):
    a = [int(c1[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(c2[i:i + 2], 16) for i in (1, 3, 5)]
    return "#%02X%02X%02X" % tuple(round(a[k] + (b[k] - a[k]) * t) for k in range(3))


def grad(t):
    for (t0, c0), (t1, c1) in zip(STOPS, STOPS[1:]):
        if t <= t1:
            return mix(c0, c1, (t - t0) / (t1 - t0))
    return STOPS[-1][1]


def arc_path(r, a0, a1):
    x0, y0 = pt(r, a0)
    x1, y1 = pt(r, a1)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return f"M{x0:.2f} {y0:.2f} A{r} {r} 0 {large} 1 {x1:.2f} {y1:.2f}"


def theme(name):
    if name == "light":
        return dict(bg0="#FFFFFF", bg1="#EEEEF0", track="#000000", trackA=0.06,
                    knob0="#FFFFFF", knob1="#F1F1F3", edge="#000000", edgeA=0.05,
                    dot="#151619", tick="#000000", tickA=0.14, shadowA=0.20, capA=0.30, color=True)
    if name == "dark":
        return dict(bg0="#1C1C1E", bg1="#000000", track="#FFFFFF", trackA=0.10,
                    knob0="#4A4A4F", knob1="#2A2A2E", edge="#FFFFFF", edgeA=0.10,
                    dot="#FFFFFF", tick="#FFFFFF", tickA=0.18, shadowA=0.60, capA=0.55, color=True)
    # tinted: grayscale on black; iOS applies the user's tint
    return dict(bg0="#141414", bg1="#000000", track="#FFFFFF", trackA=0.14,
                knob0="#5C5C5C", knob1="#3A3A3A", edge="#FFFFFF", edgeA=0.12,
                dot="#FFFFFF", tick="#FFFFFF", tickA=0.22, shadowA=0.6, capA=0.6, color=False)


def defs(t):
    return f"""
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{t['bg0']}"/><stop offset="1" stop-color="{t['bg1']}"/>
    </linearGradient>
    <linearGradient id="knob" x1="0.3" y1="0" x2="0.7" y2="1">
      <stop offset="0" stop-color="{t['knob0']}"/><stop offset="1" stop-color="{t['knob1']}"/>
    </linearGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.55"/>
      <stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
    <filter id="soft" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="28"/></filter>
    <filter id="cap" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="9"/></filter>
    <clipPath id="ring"><path d="{arc_path(ARC_R, START, START + SWEEP)}" stroke="#000" stroke-width="{ARC_W}"/></clipPath>
  </defs>"""


def background(t):
    return f'<rect width="{S}" height="{S}" fill="url(#bg)"/>'


def ring(t):
    out = []
    fill_to = SWEEP * VALUE
    # track for the rest of the scale
    out.append(f'<path d="{arc_path(ARC_R, START, START + SWEEP)}" fill="none" stroke="{t["track"]}" '
               f'stroke-opacity="{t["trackA"]}" stroke-width="{ARC_W}" stroke-linecap="round"/>')
    # soft shadow under the end cap, falling onto the track like the Activity rings
    sx, sy = pt(ARC_R, POINTER + 2.5)
    out.append(f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="{ARC_W / 2 - 4:.0f}" fill="#000000" opacity="{t["capA"]}" '
               f'filter="url(#cap)"/>')
    # coloured arc, drawn as short overlapping segments so the colour follows the arc
    seg = 120
    for i in range(seg):
        a0 = START + fill_to * i / seg
        a1 = START + fill_to * (i + 1) / seg + (0.8 if i < seg - 1 else 0)
        col = grad(i / (seg - 1) * ARC_TO) if t["color"] else "#FFFFFF"
        cap = ' stroke-linecap="round"' if i in (0, seg - 1) else ""
        out.append(f'<path d="{arc_path(ARC_R, a0, a1)}" fill="none" stroke="{col}" stroke-width="{ARC_W}"{cap}/>')
    return "".join(out)


def knob(t):
    cx, cy = C
    out = []
    out.append(f'<circle cx="{cx}" cy="{cy + 30}" r="{KNOB_R - 6}" fill="#000000" opacity="{t["shadowA"]}" filter="url(#soft)"/>')
    out.append(f'<circle cx="{cx}" cy="{cy}" r="{KNOB_R}" fill="url(#knob)"/>')
    out.append(f'<circle cx="{cx}" cy="{cy}" r="{KNOB_R - 1.5}" fill="none" stroke="{t["edge"]}" stroke-opacity="{t["edgeA"]}" stroke-width="3"/>')
    out.append(f'<circle cx="{cx}" cy="{cy}" r="{KNOB_R - 4}" fill="url(#sheen)" opacity="{0.9 if t["bg0"] == "#FFFFFF" else 0.35}"/>')
    # a quiet scale printed round the knob face — what makes it a dial
    n = 9
    for i in range(n + 1):
        a = START + SWEEP * i / n
        x0, y0 = pt(TICK_R[0], a)
        x1, y1 = pt(TICK_R[1], a)
        out.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" stroke="{t["tick"]}" '
                   f'stroke-opacity="{t["tickA"]}" stroke-width="9" stroke-linecap="round"/>')
    # pointer: one dot, aimed at the value
    x, y = pt(DOT_AT, POINTER)
    out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{DOT_R}" fill="{t["dot"]}"/>')
    return "".join(out)


def svg(body, t):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" width="{S}" height="{S}">'
            f'{defs(t)}{body}</svg>\n')


for name in ("light", "dark", "tinted"):
    t = theme(name)
    open(os.path.join(OUT, f"dialed-icon-{name}.svg"), "w").write(svg(background(t) + ring(t) + knob(t), t))

# Icon Composer layers (light geometry; Icon Composer adds the glass itself)
t = theme("light")
for f in ("layer-2-scale.svg",):
    p = os.path.join(OUT, f)
    if os.path.exists(p): os.remove(p)
open(os.path.join(OUT, "layer-1-background.svg"), "w").write(svg(background(t), t))
open(os.path.join(OUT, "layer-2-ring.svg"), "w").write(svg(ring(t), t))
open(os.path.join(OUT, "layer-3-knob.svg"), "w").write(svg(knob(t), t))
print("wrote", sorted(os.listdir(OUT)))
