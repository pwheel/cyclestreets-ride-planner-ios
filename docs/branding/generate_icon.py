"""Generates the Wheel Routes app icon SVGs (icon-color.svg, icon-tinted.svg)
from the geometry locked in docs/superpowers/specs/2026-08-23-wheel-routes-logo-design.md.

Run from this directory: `python3 generate_icon.py`. Rasterize the outputs with
`rsvg-convert -w 1024 -h 1024 icon-color.svg -o icon-color.png` (and likewise
for icon-tinted.svg) before copying into AppIcon.appiconset.
"""

import math

CANVAS = 1024.0
CX = CY = CANVAS / 2

S = CANVAS / 180.0  # scale factor from the approved 180-unit concept sketch

R_RIM = 47 * S
R_HUB = 10 * S
R_SPOKE_INNER = 13 * S
R_SPOKE_OUTER = 44 * S
R_NEEDLE_TIP = 53 * S
R_NEEDLE_SHOULDER = 11 * S
NEEDLE_PERP = 6 * S

RIM_STROKE = 4 * S
SPOKE_STROKE = 1.5 * S
HUB_STROKE = 2 * S
DOT_R = 3 * S

NEEDLE_BEARING = 60  # degrees clockwise from vertical, confirmed in design review
SPOKE_BEARINGS = [b for b in range(0, 360, 30)]


def unit(bearing_deg):
    r = math.radians(bearing_deg)
    return math.sin(r), -math.cos(r)


def pt(bearing_deg, radius):
    dx, dy = unit(bearing_deg)
    return CX + dx * radius, CY + dy * radius


def fmt(p):
    return f"{p[0]:.2f},{p[1]:.2f}"


def spoke_lines():
    lines = []
    for b in SPOKE_BEARINGS:
        inner = pt(b, R_SPOKE_INNER)
        outer = pt(b, R_SPOKE_OUTER)
        lines.append(
            f'<line x1="{inner[0]:.2f}" y1="{inner[1]:.2f}" '
            f'x2="{outer[0]:.2f}" y2="{outer[1]:.2f}" '
            f'stroke="{{spoke}}" stroke-width="{SPOKE_STROKE:.2f}" stroke-linecap="round"/>'
        )
    return "\n".join(lines)


def needle_polygons():
    dx, dy = unit(NEEDLE_BEARING)
    perp = (-dy, dx)

    tip_n = pt(NEEDLE_BEARING, R_NEEDLE_TIP)
    shoulder_n = pt(NEEDLE_BEARING, R_NEEDLE_SHOULDER)
    s1_n = (shoulder_n[0] + perp[0] * NEEDLE_PERP, shoulder_n[1] + perp[1] * NEEDLE_PERP)
    s2_n = (shoulder_n[0] - perp[0] * NEEDLE_PERP, shoulder_n[1] - perp[1] * NEEDLE_PERP)

    south_bearing = (NEEDLE_BEARING + 180) % 360
    tip_s = pt(south_bearing, R_NEEDLE_TIP)
    shoulder_s = pt(south_bearing, R_NEEDLE_SHOULDER)
    s1_s = (shoulder_s[0] + perp[0] * NEEDLE_PERP, shoulder_s[1] + perp[1] * NEEDLE_PERP)
    s2_s = (shoulder_s[0] - perp[0] * NEEDLE_PERP, shoulder_s[1] - perp[1] * NEEDLE_PERP)

    north = f'<polygon points="{fmt(tip_n)} {fmt(s1_n)} {fmt(s2_n)}" fill="{{needle_tip}}"/>'
    south = f'<polygon points="{fmt(tip_s)} {fmt(s1_s)} {fmt(s2_s)}" fill="{{needle_tail}}"/>'
    return north, south


def build_svg(background, spoke_color, needle_tip_color, needle_tail_color, hub_fill, transparent_bg=False):
    spokes = spoke_lines().format(spoke=spoke_color)
    north, south = needle_polygons()
    north = north.format(needle_tip=needle_tip_color)
    south = south.format(needle_tail=needle_tail_color)

    bg_rect = "" if transparent_bg else f'<rect x="0" y="0" width="{CANVAS:.0f}" height="{CANVAS:.0f}" fill="{background}"/>'

    return f'''<svg width="{CANVAS:.0f}" height="{CANVAS:.0f}" viewBox="0 0 {CANVAS:.0f} {CANVAS:.0f}" xmlns="http://www.w3.org/2000/svg">
{bg_rect}
<circle cx="{CX:.2f}" cy="{CY:.2f}" r="{R_RIM:.2f}" fill="none" stroke="{spoke_color}" stroke-width="{RIM_STROKE:.2f}"/>
{spokes}
{north}
{south}
<circle cx="{CX:.2f}" cy="{CY:.2f}" r="{R_HUB:.2f}" fill="{hub_fill}" stroke="{spoke_color}" stroke-width="{HUB_STROKE:.2f}"/>
<circle cx="{CX:.2f}" cy="{CY:.2f}" r="{DOT_R:.2f}" fill="{needle_tip_color}"/>
</svg>
'''


TERRACOTTA = "#B5472E"
TEAL = "#123C36"
WHITE = "#FFFFFF"

color_svg = build_svg(
    background=TERRACOTTA,
    spoke_color=WHITE,
    needle_tip_color=TEAL,
    needle_tail_color=WHITE,
    hub_fill=TERRACOTTA,
    transparent_bg=False,
)

tinted_svg = build_svg(
    background="none",
    spoke_color=WHITE,
    needle_tip_color=WHITE,
    needle_tail_color=WHITE,
    hub_fill=WHITE,
    transparent_bg=True,
)

with open("icon-color.svg", "w") as f:
    f.write(color_svg)

with open("icon-tinted.svg", "w") as f:
    f.write(tinted_svg)

print("Wrote icon-color.svg and icon-tinted.svg")
