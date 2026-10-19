#!/usr/bin/env python3
"""
Dialed app icon — "The Dial", liquid-glass edition.

One geometry, three appearances (light / dark / tinted) plus separate layers
for Icon Composer. Everything is drawn on a 1024 canvas; run this, then
render.js turns the SVGs into the PNGs in the asset catalog.

    python3 make_icon.py     # writes ./svg/*.svg
"""
import math, os

S = 1024
C = (512, 528)   # a touch low: the open bottom of the dial reads lighter
OUT = os.path.join(os.path.dirname(__file__), "svg")
os.makedirs(OUT, exist_ok=True)

# App palette (Utilities/NekaTheme.swift)
GREEN, SKY, LAV, ORANGE = "#4CB868", "#5DB4F0", "#A88BEB", "#F59A4C"
STOPS = [(0.0, GREEN), (0.38, SKY), (0.70, LAV), (1.0, ORANGE)]

START = 135.0        # scale starts at ~7:30 (SVG degrees, clockwise from +x)
SWEEP = 270.0        # and runs 270° to ~4:30, like a real knob
VALUE = 0.74         # how far it's dialed in
POINTER = START + SWEEP * VALUE


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
        return dict(bg0="#FFFFFF", bg1="#ECEAE4", tick="#151619", tickA=0.30, track="#151619", trackA=0.07,
                    knob0="#FFFFFF", knob1="#E9E7E1", knobA=0.72, rim="#FFFFFF", rimA=0.95, ridge="#151619",
                    ridgeA=0.10, ptr="#151619", shadowA=0.22, glowA=0.55, color=True)
    if name == "dark":
        return dict(bg0="#25262B", bg1="#0B0C0E", tick="#FFFFFF", tickA=0.34, track="#FFFFFF", trackA=0.08,
                    knob0="#3A3B42", knob1="#17181C", knobA=0.78, rim="#FFFFFF", rimA=0.30, ridge="#FFFFFF",
                    ridgeA=0.10, ptr="#F2F2F3", shadowA=0.55, glowA=0.45, color=True)
    # tinted: grayscale on black; iOS applies the user's tint
    return dict(bg0="#1A1A1A", bg1="#000000", tick="#FFFFFF", tickA=0.40, track="#FFFFFF", trackA=0.10,
                knob0="#5A5A5A", knob1="#262626", knobA=0.9, rim="#FFFFFF", rimA=0.35, ridge="#FFFFFF",
                ridgeA=0.12, ptr="#FFFFFF", shadowA=0.5, glowA=0.0, color=False)


def defs(t):
    return f"""
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{t['bg0']}"/><stop offset="1" stop-color="{t['bg1']}"/>
    </linearGradient>
    <radialGradient id="knob" cx="0.38" cy="0.30" r="0.85">
      <stop offset="0" stop-color="{t['knob0']}"/><stop offset="1" stop-color="{t['knob1']}"/>
    </radialGradient>
    <radialGradient id="spec" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.95"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="0.4" y2="1">
      <stop offset="0" stop-color="{t['rim']}" stop-opacity="{t['rimA']}"/>
      <stop offset="0.55" stop-color="{t['rim']}" stop-opacity="0.05"/>
      <stop offset="1" stop-color="{t['rim']}" stop-opacity="{t['rimA'] * 0.5:.2f}"/>
    </linearGradient>
    <filter id="soft" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="26"/></filter>
    <filter id="blur90" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="70"/></filter>
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="14"/></filter>
    <clipPath id="knobClip"><circle cx="{C[0]}" cy="{C[1]}" r="214"/></clipPath>
  </defs>"""


def background(t):
    out = f'<rect width="{S}" height="{S}" fill="url(#bg)"/>'
    if t["color"]:
        # soft colour behind the glass so the knob has something to refract
        out += f'<g filter="url(#blur90)" opacity="{0.30 if t["bg0"] == "#FFFFFF" else 0.38}">'
        for f in (0.1, 0.45, 0.8):
            x, y = pt(300, START + SWEEP * f)
            out += f'<circle cx="{x:.1f}" cy="{y:.1f}" r="170" fill="{grad(f)}"/>'
        out += "</g>"
    return out


def scale(t):
    out = []
    # tick marks
    n = 18
    for i in range(n + 1):
        a = START + SWEEP * i / n
        major = i % 3 == 0
        r0, r1 = (400, 446) if major else (412, 438)
        x0, y0 = pt(r0, a)
        x1, y1 = pt(r1, a)
        lit = a <= POINTER + 0.01
        col = grad(i / n) if (lit and t["color"]) else t["tick"]
        op = 0.95 if lit else t["tickA"]
        w = 13 if major else 9
        out.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" stroke="{col}" '
                   f'stroke-opacity="{op}" stroke-width="{w}" stroke-linecap="round"/>')
    # track
    out.append(f'<path d="{arc_path(312, START, START + SWEEP)}" fill="none" stroke="{t["track"]}" '
               f'stroke-opacity="{t["trackA"]}" stroke-width="60" stroke-linecap="round"/>')
    # progress arc, drawn as short segments so the colour follows the arc
    seg = 90
    fill_to = SWEEP * VALUE
    if t["color"]:
        glow = []
        for i in range(seg):
            a0 = START + fill_to * i / seg
            a1 = START + fill_to * (i + 1) / seg + 0.6
            col = grad(i / seg * VALUE / VALUE * (fill_to / SWEEP))
            glow.append(f'<path d="{arc_path(312, a0, a1)}" fill="none" stroke="{col}" stroke-width="60"/>')
        out.append(f'<g filter="url(#glow)" opacity="{t["glowA"]}">' + "".join(glow) + "</g>")
        for i in range(seg):
            a0 = START + fill_to * i / seg
            a1 = START + fill_to * (i + 1) / seg + 0.6
            col = grad(i / seg * (fill_to / SWEEP))
            cap = ' stroke-linecap="round"' if i in (0, seg - 1) else ""
            out.append(f'<path d="{arc_path(312, a0, a1)}" fill="none" stroke="{col}" stroke-width="60"{cap}/>')
    else:
        out.append(f'<path d="{arc_path(312, START, START + fill_to)}" fill="none" stroke="#FFFFFF" '
                   f'stroke-width="60" stroke-linecap="round"/>')
    # glossy highlight along the arc
    out.append(f'<path d="{arc_path(322, START + 4, START + fill_to - 4)}" fill="none" stroke="#FFFFFF" '
               f'stroke-opacity="0.35" stroke-width="10" stroke-linecap="round"/>')
    return "".join(out)


def knob(t):
    cx, cy = C
    out = []
    # contact shadow
    out.append(f'<ellipse cx="{cx}" cy="{cy + 34}" rx="214" ry="200" fill="#000000" '
               f'opacity="{t["shadowA"]}" filter="url(#soft)"/>')
    # glass body
    out.append(f'<circle cx="{cx}" cy="{cy}" r="216" fill="url(#knob)" fill-opacity="{t["knobA"]}"/>')
    # knurled grip: fine ridges round the edge
    ridges = []
    for i in range(96):
        a = 360 * i / 96
        x0, y0 = pt(186, a)
        x1, y1 = pt(212, a)
        ridges.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}"/>')
    out.append(f'<g stroke="{t["ridge"]}" stroke-opacity="{t["ridgeA"]}" stroke-width="5" '
               f'stroke-linecap="round" clip-path="url(#knobClip)">' + "".join(ridges) + "</g>")
    # inner face + bevel
    out.append(f'<circle cx="{cx}" cy="{cy}" r="176" fill="url(#knob)" fill-opacity="{min(1, t["knobA"] + 0.12):.2f}"/>')
    out.append(f'<circle cx="{cx}" cy="{cy}" r="176" fill="none" stroke="url(#rim)" stroke-width="5"/>')
    # glass rim (liquid-glass edge light)
    out.append(f'<circle cx="{cx}" cy="{cy}" r="214" fill="none" stroke="url(#rim)" stroke-width="7"/>')
    # specular highlight
    out.append(f'<ellipse cx="{cx - 62}" cy="{cy - 92}" rx="112" ry="62" fill="url(#spec)" '
               f'opacity="{0.55 if t["bg0"] == "#FFFFFF" else 0.22}" transform="rotate(-28 {cx - 62} {cy - 92})"/>')
    # pointer: a recessed bar on the knob face aiming at the value
    x0, y0 = pt(62, POINTER)
    x1, y1 = pt(150, POINTER)
    out.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" stroke="{t["ptr"]}" '
               f'stroke-width="30" stroke-linecap="round"/>')
    return "".join(out)


def bead(t):
    # the glass bead riding the end of the arc
    x, y = pt(312, POINTER)
    col = grad(VALUE) if t["color"] else "#FFFFFF"
    ring = t["ptr"]
    return (f'<circle cx="{x:.1f}" cy="{y:.1f}" r="44" fill="{col}" opacity="0.35" filter="url(#glow)"/>'
            f'<circle cx="{x:.1f}" cy="{y:.1f}" r="35" fill="{t["bg0"] if t["color"] else "#000000"}" stroke="{ring}" stroke-width="12"/>'
            f'<circle cx="{x - 9:.1f}" cy="{y - 11:.1f}" r="10" fill="#FFFFFF" opacity="0.7"/>')


def svg(body, t):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" width="{S}" height="{S}">'
            f'{defs(t)}{body}</svg>\n')


for name in ("light", "dark", "tinted"):
    t = theme(name)
    full = background(t) + scale(t) + knob(t) + bead(t)
    open(os.path.join(OUT, f"dialed-icon-{name}.svg"), "w").write(svg(full, t))

# Icon Composer layers (light geometry; Icon Composer adds the glass itself)
t = theme("light")
open(os.path.join(OUT, "layer-1-background.svg"), "w").write(svg(background(t), t))
open(os.path.join(OUT, "layer-2-scale.svg"), "w").write(svg(scale(t) + bead(t), t))
open(os.path.join(OUT, "layer-3-knob.svg"), "w").write(svg(knob(t), t))
print("wrote", sorted(os.listdir(OUT)))
