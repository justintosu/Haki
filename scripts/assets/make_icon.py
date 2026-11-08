import sys
from PIL import Image, ImageDraw

S = 4096          # supersampled canvas
OUT = 1024

def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))

def gradient(top, bottom):
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            pass
    # diagonal gradient, computed per row and column via two linear gradients blended
    base = Image.linear_gradient("L").resize((S, S))          # vertical 0..255
    side = base.rotate(90)                                     # horizontal
    mask = Image.blend(base, side, 0.35)
    a = Image.new("RGB", (S, S), top)
    b = Image.new("RGB", (S, S), bottom)
    return Image.composite(b, a, mask)

def glyph(draw, color, accent=None):
    # Geometry in a 1024 grid, scaled up.
    k = S / 1024
    w = 118          # stroke width
    left_x, right_x = 330, 694
    top, bottom = 248, 776
    r = w / 2
    def bar(x, y0, y1, fill):
        draw.rounded_rectangle([ (x - r) * k, y0 * k, (x + r) * k, y1 * k ], radius=r * k, fill=fill)
    bar(left_x, top + 150, bottom, color)     # left stem, a little shorter: growth
    bar(right_x, top, bottom, color)          # right stem
    # rising crossbar from the left stem to the right stem
    x0, y0 = left_x, 612
    x1, y1 = right_x, 428
    draw.line([x0 * k, y0 * k, x1 * k, y1 * k], fill=color, width=int(w * 0.86 * k))
    for (cx, cy) in [(x0, y0), (x1, y1)]:
        rr = w * 0.43
        draw.ellipse([(cx - rr) * k, (cy - rr) * k, (cx + rr) * k, (cy + rr) * k], fill=color)
    # a small dot above the left stem: the "next" point on the line

def render(bg, glyph_color, path, dot=None):
    img = bg.copy() if isinstance(bg, Image.Image) else Image.new("RGB", (S, S), bg)
    d = ImageDraw.Draw(img)
    glyph(d, glyph_color, dot)
    img.resize((OUT, OUT), Image.LANCZOS).save(path, optimize=True)

out = sys.argv[1]
render(gradient((24, 178, 140), (9, 92, 84)), (255, 255, 255), f"{out}/AppIcon.png", dot=(214, 255, 238))
render((11, 20, 18), (56, 214, 168), f"{out}/AppIcon-Dark.png", dot=(150, 240, 210))
render((0, 0, 0), (235, 235, 235), f"{out}/AppIcon-Tinted.png", dot=(160, 160, 160))
print("done")
