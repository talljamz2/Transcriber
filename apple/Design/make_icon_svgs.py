# Generates the icon SVGs. Concept: a serif opening quotation mark (speech) above two caption
# lines, the end of the second one grey, the way words still being recognized look in the app.
import sys

def quote_mark(cx, cy, r):
    # A teardrop "6": a round head with a tail sweeping up to the right, like a serif opening quote.
    t = r * 0.16
    return (f'<circle cx="{cx}" cy="{cy}" r="{r}"/>'
            f'<path d="M {cx - r} {cy} '
            f'C {cx - r*1.02} {cy - r*1.5}, {cx - r*0.15} {cy - r*2.4}, {cx + r*1.02} {cy - r*2.68} '
            f'A {t} {t} 0 0 1 {cx + r*1.12} {cy - r*2.36} '
            f'C {cx + r*0.38} {cy - r*2.08}, {cx - r*0.22} {cy - r*1.45}, {cx - r*0.02} {cy - r*0.6} Z"/>')

def artwork(ink, grey):
    r = 66
    marks = quote_mark(412, 474, r) + quote_mark(612, 474, r)
    bar = 46
    return f'''
  <g fill="{ink}">{marks}</g>
  <rect x="262" y="610" width="500" height="{bar}" rx="{bar/2}" fill="{ink}"/>
  <rect x="262" y="700" width="300" height="{bar}" rx="{bar/2}" fill="{ink}"/>
  <rect x="586" y="700" width="176" height="{bar}" rx="{bar/2}" fill="{grey}"/>'''

def ios(dark):
    bg = '<rect width="1024" height="1024" fill="url(#g)"/>'
    stops = ('<stop offset="0" stop-color="#1C1C1E"/><stop offset="1" stop-color="#000000"/>' if dark
             else '<stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#ECECEE"/>')
    ink, grey = ('#F5F5F7', '#6E6E73') if dark else ('#1D1D1F', '#B8B8BD')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">{stops}</linearGradient></defs>
  {bg}<g transform="translate(512 512) scale(1.1) translate(-512 -512)">{artwork(ink, grey)}</g>
</svg>'''

def mac():
    # macOS icons carry their own rounded-square shape, inset from the canvas, with a soft shadow.
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E9E9EC"/></linearGradient>
    <filter id="s" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity="0.28"/></filter>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#g)" filter="url(#s)"/>
  <rect x="100.5" y="100.5" width="823" height="823" rx="184.5" fill="none" stroke="#000" stroke-opacity="0.08"/>
  <g transform="translate(512 512) scale(0.885) translate(-512 -512)">{artwork('#1D1D1F', '#B8B8BD')}</g>
</svg>'''

open('ios-light.svg','w').write(ios(False))
open('ios-dark.svg','w').write(ios(True))
open('mac.svg','w').write(mac())
