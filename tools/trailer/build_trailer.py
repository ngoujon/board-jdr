"""Bande-annonce d'Arcanes & Lames (72 s, 1920 × 1080, 30 images/s), sans voix, textes en français
incrustés et sous-titres dans les 6 langues du jeu.

  python tools/trailer/build_trailer.py <dossier des images de gameplay> [--preview=<seconde>]

1. Images de gameplay : capturées par tests/trailer_capture.tscn (voir son en-tête). La partie est
   reproductible (graine fixe) : les numéros d'image ci-dessous (clip(...)) correspondent à cette capture.
2. Musique : tools/trailer/music.mp3 (ComfyUI, ACE-Step, tools/comfy_workflows/chiptune_music.json, graine 7301).
3. Illustrations : tools/trailer/art_*.png (ComfyUI, SDXL + pixel-art-xl, pixelisées comme les fonds du jeu).
4. Sortie : dist/trailer/arcanes_trailer.mp4 (sous-titres intégrés) + arcanes_trailer_<langue>.vtt
   et une image d'aperçu (poster.jpg) pour la page d'accueil.
"""
import json
import math
import os
import random
import subprocess
import sys

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "build", "trailer")
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
W, H, FPS, DUR = 1920, 1080, 30, 72.0
GOLD, NIGHT, CREAM, EMBER = (242, 193, 78), (26, 18, 32), (245, 233, 208), (224, 112, 58)
FONT_TITLE = os.path.join(ROOT, "assets", "fonts", "ArcanesPixel.ttf")
FONT_TEXT = os.path.join(ROOT, "assets", "fonts", "PixelifySans.ttf")
SUBS = json.load(open(os.path.join(HERE, "subtitles.json"), encoding="utf-8"))
FRAMES = ""


# ------------------------------------------------------------------ outils

def ease_out(x):
    x = min(max(x, 0.0), 1.0)
    return 1 - (1 - x) ** 3


def ease_out_back(x):
    x = min(max(x, 0.0), 1.0)
    c = 1.70158
    return 1 + (c + 1) * (x - 1) ** 3 + c * (x - 1) ** 2


def clamp01(x):
    return min(max(x, 0.0), 1.0)


def fade(t, start, end, fin=0.35, fout=0.35):
    """Opacité d'un élément visible de start à end, avec fondus."""
    if t < start or t > end:
        return 0.0
    return min(clamp01((t - start) / fin) if fin else 1.0, clamp01((end - t) / fout) if fout else 1.0)


_cache = {}


def art(name, scale=6):
    """Illustration pixel art agrandie sans lissage (pixels nets)."""
    key = ("art", name, scale)
    if key not in _cache:
        path = name if os.path.isabs(name) else os.path.join(ROOT, name)
        im = Image.open(path).convert("RGB")
        _cache[key] = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    return _cache[key]


def cover(im, zoom=1.0, cx=0.5, cy=0.5, resample=Image.BILINEAR):
    """Cadre 16:9 (zoom >= 1, centre relatif) de l'image, redimensionné en 1920 × 1080."""
    r = min(im.width / W, im.height / H) / zoom
    cw, ch = W * r, H * r
    x0 = min(max(cx * im.width - cw / 2, 0), im.width - cw)
    y0 = min(max(cy * im.height - ch / 2, 0), im.height - ch)
    return im.resize((W, H), resample, box=(x0, y0, x0 + cw, y0 + ch))


def gameplay(n):
    return Image.open(os.path.join(FRAMES, f"f{int(n):05d}.jpg")).convert("RGB")


def darken(im, k):
    return Image.blend(im, Image.new("RGB", im.size, (0, 0, 0)), clamp01(k))


def flash(im, a, color=(255, 244, 220)):
    return Image.blend(im, Image.new("RGB", im.size, color), clamp01(a)) if a > 0 else im


def font(path, size):
    key = ("font", path, size)
    if key not in _cache:
        _cache[key] = ImageFont.truetype(path, size)
    return _cache[key]


def text_layer(text, size, color=CREAM, path=FONT_TEXT, stroke=5, shadow=6, glow=None):
    """Texte en police pixel du jeu, contour sombre et ombre portée (mis en cache)."""
    key = ("text", text, size, color, path, stroke, shadow, glow)
    if key in _cache:
        return _cache[key]
    f = font(path, size)
    box = f.getbbox(text, stroke_width=stroke)
    pad = 40
    w, h = box[2] - box[0] + pad * 2 + shadow, box[3] - box[1] + pad * 2 + shadow
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ox, oy = pad - box[0], pad - box[1]
    if glow:
        g = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(g).text((ox, oy), text, font=f, fill=glow + (255,), stroke_width=stroke + 6, stroke_fill=glow + (255,))
        layer = Image.alpha_composite(layer, g.filter(ImageFilter.GaussianBlur(14)))
        d = ImageDraw.Draw(layer)
    if shadow:
        d.text((ox + shadow, oy + shadow), text, font=f, fill=(0, 0, 0, 200), stroke_width=stroke, stroke_fill=(0, 0, 0, 200))
    d.text((ox, oy), text, font=f, fill=color + (255,), stroke_width=stroke, stroke_fill=NIGHT + (255,))
    _cache[key] = layer
    return layer


def paste(frame, layer, cx, cy, alpha=1.0, scale=1.0):
    """Colle un calque RGBA centré en (cx, cy) avec opacité et échelle."""
    if alpha <= 0.01:
        return frame
    if abs(scale - 1.0) > 0.001:
        layer = layer.resize((max(1, int(layer.width * scale)), max(1, int(layer.height * scale))), Image.BILINEAR)
    if alpha < 0.999:
        a = layer.getchannel("A").point(lambda v: int(v * alpha))
        layer = layer.copy()
        layer.putalpha(a)
    frame.paste(layer, (int(cx - layer.width / 2), int(cy - layer.height / 2)), layer)
    return frame


def caption(frame, t, start, end, text, y=940, size=62, color=CREAM, band=True, glow=None):
    """Texte de sous-titrage incrusté (français) : glisse vers le haut en apparaissant."""
    a = fade(t, start, end)
    if a <= 0:
        return frame
    if band:
        bar = Image.new("RGBA", (W, 190), (0, 0, 0, 0))
        bd = ImageDraw.Draw(bar)
        for i in range(190):
            bd.line([(0, i), (W, i)], fill=(10, 6, 14, int(170 * min(i / 90, 1.0) * a)))
        frame.paste(bar, (0, H - 190), bar)
    return paste(frame, text_layer(text, size, color, glow=glow), W / 2, y + 18 * (1 - ease_out((t - start) / 0.45)), a)


class Particles:
    """Braises / étincelles carrées (style pixel) qui montent en scintillant."""

    def __init__(self, n, seed, colors, size=(4, 11), speed=(60, 190), area=(0, W)):
        rnd = random.Random(seed)
        self.p = [(rnd.uniform(*area), rnd.uniform(0, H + 200), rnd.uniform(*speed), rnd.randint(*size),
                   rnd.choice(colors), rnd.uniform(0, 6.28), rnd.uniform(0.6, 2.2)) for _ in range(n)]

    def draw(self, frame, t, intensity=1.0):
        if intensity <= 0:
            return frame
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        for x0, off, sp, sz, col, ph, fr in self.p:
            y = H + 60 - ((off + t * sp) % (H + 200))
            x = x0 + 26 * math.sin(t * 0.8 + ph)
            a = intensity * (0.55 + 0.45 * math.sin(t * fr * 3 + ph)) * clamp01((y + 40) / 300)
            if a > 0.03:
                d.rectangle((x, y, x + sz, y + sz), fill=col + (int(255 * min(a, 1)),))
        glow = layer.filter(ImageFilter.GaussianBlur(6))
        frame = frame.convert("RGBA")
        frame = Image.alpha_composite(frame, glow)
        frame = Image.alpha_composite(frame, layer)
        return frame.convert("RGB")


EMBERS = Particles(140, 1, [(255, 150, 60), (255, 200, 90), (230, 90, 40), (255, 230, 150)])
SPARKS = Particles(90, 2, [(255, 240, 180), (255, 215, 110), (255, 255, 255)], size=(3, 7), speed=(30, 90))


def vignette():
    if "vig" not in _cache:
        small = Image.new("L", (192, 108), 0)
        d = ImageDraw.Draw(small)
        for i in range(60):
            v = int(255 * (i / 60) ** 2.2)
            d.ellipse((-40 + i * 1.6, -30 + i * 0.9, 232 - i * 1.6, 138 - i * 0.9), fill=255 - v)
        mask = small.resize((W, H), Image.BILINEAR).filter(ImageFilter.GaussianBlur(30))
        v = Image.new("RGBA", (W, H), (5, 2, 8, 0))
        v.putalpha(mask.point(lambda x: int(x * 0.85)))
        _cache["vig"] = v
    return _cache["vig"]


def with_vignette(frame, k=1.0):
    v = vignette()
    if k < 1:
        v = v.copy()
        v.putalpha(v.getchannel("A").point(lambda x: int(x * k)))
    return Image.alpha_composite(frame.convert("RGBA"), v).convert("RGB")


def logo_layer():
    if "logo" not in _cache:
        _cache["logo"] = text_layer("ARCANES & LAMES", 150, GOLD, FONT_TITLE, stroke=8, shadow=12, glow=(255, 150, 40))
    return _cache["logo"]


def card_image(card_id, name, cost):
    """Carte façon jeu : cadre bois et or, illustration pixel art, nom sur parchemin, coût en énergie."""
    key = ("card", card_id)
    if key in _cache:
        return _cache[key]
    s = 3
    aw, ah = 144 * s, 112 * s
    w, h = aw + 36, ah + 118
    c = Image.new("RGBA", (w + 40, h + 40), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    ox, oy = 20, 20
    d.rectangle((ox - 6, oy - 6, ox + w + 5, oy + h + 5), fill=GOLD + (255,))
    d.rectangle((ox - 3, oy - 3, ox + w + 2, oy + h + 2), fill=NIGHT + (255,))
    d.rectangle((ox, oy, ox + w - 1, oy + h - 1), fill=(91, 59, 34, 255))
    d.rectangle((ox + 6, oy + 6, ox + w - 7, oy + h - 7), fill=(59, 38, 22, 255))
    c.paste(art(f"assets/art/{card_id}.png", s), (ox + 18, oy + 18))
    d.rectangle((ox + 18, oy + ah + 30, ox + w - 19, oy + h - 22), fill=CREAM + (255,))
    f = font(FONT_TEXT, 34 if len(name) < 14 else 29)
    tw = d.textlength(name, font=f)
    d.text((ox + w / 2 - tw / 2, oy + ah + 36), name, font=f, fill=(43, 29, 20, 255))
    d.ellipse((0, 0, 70, 70), fill=(40, 86, 184, 255), outline=NIGHT + (255,), width=5)
    d.ellipse((8, 8, 62, 62), fill=(111, 180, 255, 255))
    cf = font(FONT_TEXT, 44)
    d.text((35 - d.textlength(str(cost), font=cf) / 2, 8), str(cost), font=cf, fill=(255, 255, 255, 255), stroke_width=3, stroke_fill=NIGHT + (255,))
    _cache[key] = c
    return c


# ------------------------------------------------------------------ séquences

def seg_intro(t):
    """0 - 4,5 s : le château au crépuscule sort de la nuit, braises, première phrase."""
    bg = cover(art("assets/bg/menu.png"), 1.0 + 0.05 * t / 4.5, 0.5, 0.45)
    bg = darken(bg, 1 - ease_out(t / 1.6) * 0.72)
    bg = EMBERS.draw(bg, t, 0.6 * ease_out(t / 2))
    bg = with_vignette(bg)
    return caption(bg, t, 1.2, 4.3, SUBS["cues"][0]["fr"], y=540, size=64, band=False)


def seg_logo(t):
    """4,5 - 8,5 s : coup d'éclat, le logo s'impose, le slogan apparaît."""
    lt = t - 4.5
    shake = 14 * max(0, 1 - lt / 0.4) * math.sin(lt * 90)
    bg = cover(art("assets/bg/menu.png"), 1.05 + 0.03 * lt / 4, 0.5 + shake / W, 0.45)
    bg = darken(bg, 0.45)
    bg = EMBERS.draw(bg, t, 1.0)
    bg = SPARKS.draw(bg, t, 0.8)
    bg = with_vignette(bg)
    sc = 1.35 - 0.35 * ease_out_back(lt / 0.45)
    paste(bg, logo_layer(), W / 2 + shake, 440, clamp01(lt / 0.15), sc)
    a = fade(t, 5.2, 8.45, 0.5, 0.2)
    paste(bg, text_layer("Duel de cartes au cœur du Royaume", 58, CREAM), W / 2, 600 + 14 * (1 - ease_out((t - 5.2) / 0.5)), a)
    return flash(bg, 0.9 * (1 - lt / 0.35) if lt < 0.35 else 0)


CARDS = [("hydre", "Hydre des abysses", 8), ("liche", "Liche", 5), ("dragon", "Dragon ancien", 7), ("paladine", "Paladine sacrée", 3), ("pyromancienne", "Pyromancienne", 4)]


def seg_cards(t):
    """8,5 - 12,5 s : les cartes arrivent en éventail."""
    lt = t - 8.5
    bg = cover(art("tools/trailer/art_duel.png"), 1.1, 0.5, 0.5).filter(ImageFilter.GaussianBlur(8))
    bg = darken(bg, 0.62)
    bg = EMBERS.draw(bg, t, 0.5)
    bg = with_vignette(bg)
    frame = bg.convert("RGBA")
    order = [0, 4, 1, 3, 2]   # le dragon (au centre) arrive en dernier, au premier plan
    for k, i in enumerate(order):
        cid, name, cost = CARDS[i]
        p = ease_out_back((lt - 0.12 * k) / 0.55)
        if p <= 0:
            continue
        slot = i - 2
        ang = -slot * 9 + 3 * math.sin(t * 1.3 + i)
        x = W / 2 + slot * 345
        y = 500 + abs(slot) * 38 + (1 - p) * 800 + 8 * math.sin(t * 2 + i)
        im = card_image(cid, name, cost).rotate(ang, Image.BICUBIC, expand=True)
        sc = 0.7 if i != 2 else 0.8
        paste(frame, im, x, y, clamp01(p * 2), sc)
    frame = frame.convert("RGB")
    frame = caption(frame, t, 8.9, 12.3, SUBS["cues"][2]["fr"])
    return flash(frame, 0.5 * (1 - lt / 0.2) if lt < 0.2 else 0)


def clip(t, t0, src, zoom=(1.0, 1.0), center=(0.5, 0.5), speed=1.0, dur=2.0):
    """Extrait de gameplay : image src + (t - t0) * 30 * speed, recadrage animé (zoom de début à fin)."""
    lt = t - t0
    n = src + int(lt * FPS * speed)
    z = zoom[0] + (zoom[1] - zoom[0]) * clamp01(lt / dur)
    return cover(gameplay(n), z, center[0], center[1])


def seg_draw(t):
    """12,5 - 16 s : pile ou face, puis la pioche au choix."""
    if t < 14.2:
        f = clip(t, 12.5, 40, (1.12, 1.2), (0.43, 0.42), dur=1.7)
    else:
        f = clip(t, 14.2, 492, (1.05, 1.15), (0.43, 0.45), dur=1.8)
    f = with_vignette(f, 0.6)
    f = caption(f, t, 12.7, 15.9, SUBS["cues"][3]["fr"])
    lt = t - 12.5 if t < 14.2 else t - 14.2
    return flash(f, 0.45 * (1 - lt / 0.2) if lt < 0.2 else 0)


def seg_spells(t):
    """16 - 21 s : blizzard, chaîne d'éclairs, boule de feu (recadrés sur l'action)."""
    if t < 18.0:
        f, lt = clip(t, 16.0, 712, (1.45, 1.3), (0.45, 0.3)), t - 16.0
    elif t < 19.0:
        f, lt = clip(t, 18.0, 793, (1.3, 1.2), (0.36, 0.38), dur=1.0), t - 18.0
    else:
        f, lt = clip(t, 19.0, 866, (1.35, 1.2), (0.45, 0.33)), t - 19.0
    f = with_vignette(f, 0.7)
    f = caption(f, t, 16.2, 20.9, SUBS["cues"][4]["fr"], size=70, color=(200, 230, 255))
    return flash(f, 0.55 * (1 - lt / 0.18) if lt < 0.18 else 0)


def seg_break(t):
    """21 - 23,5 s : la musique retient son souffle. Le chevalier attend dans la salle du trône."""
    lt = t - 21.0
    bg = cover(art("tools/trailer/art_duel.png"), 1.0 + 0.04 * lt / 2.5, 0.5, 0.5)
    bg = darken(bg, 1 - 0.55 * ease_out(lt / 1.2))
    bg = with_vignette(bg)
    return caption(bg, t, 21.3, 23.45, SUBS["cues"][5]["fr"], y=540, size=66, band=False)


def seg_dragon(t):
    """23,5 - 27,5 s : coup de tonnerre, le dragon et les niveaux d'IA."""
    lt = t - 23.5
    shake = 20 * max(0, 1 - lt / 0.6) * math.sin(lt * 70)
    bg = cover(art("tools/trailer/art_dragon.png"), 1.12 - 0.06 * lt / 4, 0.45 + shake / W, 0.5)
    pulse = 0.12 + 0.1 * math.sin(lt * 6)
    bg = Image.blend(bg, Image.new("RGB", bg.size, (140, 20, 0)), pulse)
    bg = EMBERS.draw(bg, t, 1.2)
    bg = with_vignette(bg)
    bg = caption(bg, t, 23.7, 27.4, SUBS["cues"][6]["fr"])
    return flash(bg, 1.0 * (1 - lt / 0.4) if lt < 0.4 else 0, (255, 220, 180))


def seg_inferno(t):
    """27,5 - 31,5 s : pluie de météores puis souffle du dragon, en jeu."""
    if t < 29.5:
        f, lt = clip(t, 27.5, 936, (1.25, 1.1), (0.4, 0.42)), t - 27.5
    else:
        f, lt = clip(t, 29.5, 1066, (1.2, 1.05), (0.42, 0.5)), t - 29.5
    f = Image.blend(f, Image.new("RGB", f.size, (120, 20, 0)), 0.08)
    f = with_vignette(f, 0.8)
    f = caption(f, t, 27.6, 31.4, SUBS["cues"][7]["fr"], size=76, color=(255, 190, 90), glow=(255, 60, 0))
    return flash(f, 0.6 * (1 - lt / 0.2) if lt < 0.2 else 0, (255, 200, 150))


def seg_online(t):
    """31,5 - 35,5 s : la grande salle, les joueurs du Royaume se retrouvent."""
    lt = t - 31.5
    bg = cover(art("tools/trailer/art_hall.png"), 1.15 - 0.1 * lt / 4, 0.3 + 0.3 * lt / 4, 0.5)
    bg = darken(bg, 0.2)
    bg = SPARKS.draw(bg, t, 0.6)
    bg = with_vignette(bg)
    bg = caption(bg, t, 31.7, 35.4, SUBS["cues"][8]["fr"])
    return flash(bg, 0.5 * (1 - lt / 0.2) if lt < 0.2 else 0)


def seg_custom(t):
    """35,5 - 39,5 s : la personnalisation (plateaux, puis titres)."""
    lt = t - 35.5
    if lt < 2.0:
        src = Image.open(os.path.join(HERE, "shot_plateaux.png")).convert("RGB").crop((40, 170, 840, 620))
        f = cover(src, 1.0 + 0.1 * lt / 2, 0.45, 0.5)
    else:
        src = Image.open(os.path.join(HERE, "shot_titres.png")).convert("RGB").crop((40, 170, 840, 620))
        f = cover(src, 1.1 - 0.1 * (lt - 2) / 2, 0.5, 0.5)
    f = with_vignette(f, 0.6)
    f = caption(f, t, 35.7, 39.4, SUBS["cues"][9]["fr"], size=56)
    k = lt if lt < 2 else lt - 2
    return flash(f, 0.45 * (1 - k / 0.18) if k < 0.18 else 0)


MONTAGE = [  # 39,5 - 55,5 s : 8 plans de 2 s, un par mesure
    (1880, (1.15, 1.25), (0.45, 0.55)),   # boule de feu en partie
    (797, (1.0, 1.1), (0.4, 0.4)),        # chaîne d'éclairs
    (2604, (1.05, 1.12), (0.43, 0.45)),   # pioche au choix
    (938, (1.0, 1.08), (0.45, 0.45)),     # météores, plan large
    (1522, (1.25, 1.35), (0.43, 0.3)),    # carte jouée
    (2326, (1.2, 1.3), (0.43, 0.55)),     # attaque d'un serviteur
    (1068, (1.0, 1.1), (0.45, 0.5)),      # arrivée du dragon
    (2996, (1.0, 1.08), (0.43, 0.5)),     # victoire
]


def seg_montage(t):
    lt = t - 39.5
    i = min(int(lt / 2.0), len(MONTAGE) - 1)
    src, zoom, center = MONTAGE[i]
    f = clip(t, 39.5 + 2.0 * i, src, zoom, center)
    f = with_vignette(f, 0.6)
    f = caption(f, t, 39.8, 47.3, SUBS["cues"][10]["fr"])
    f = caption(f, t, 47.7, 55.3, SUBS["cues"][11]["fr"])
    k = lt - 2.0 * i
    return flash(f, 0.4 * (1 - k / 0.15) if k < 0.15 else 0)


PLATFORMS = ["Windows", "macOS", "Linux", "Android"]


def badge(name):
    key = ("badge", name)
    if key not in _cache:
        f = font(FONT_TEXT, 54)
        tw = int(ImageDraw.Draw(Image.new("RGBA", (1, 1))).textlength(name, font=f))
        w, h = tw + 90, 104
        b = Image.new("RGBA", (w + 16, h + 16), (0, 0, 0, 0))
        d = ImageDraw.Draw(b)
        d.rectangle((8, 14, w + 8, h + 14), fill=(0, 0, 0, 140))
        d.rectangle((0, 0, w, h), fill=GOLD + (255,))
        d.rectangle((5, 5, w - 5, h - 5), fill=NIGHT + (255,))
        d.rectangle((10, 10, w - 10, h - 10), fill=(61, 42, 28, 255))
        d.text((45, 20), name, font=f, fill=CREAM + (255,), stroke_width=3, stroke_fill=NIGHT + (255,))
        _cache[key] = b
    return _cache[key]


def seg_platforms(t):
    """55,5 - 65,5 s : gratuit, sur 4 systèmes, tout le monde ensemble."""
    lt = t - 55.5
    bg = cover(art("assets/bg/menu.png"), 1.2, 0.5, 0.4).filter(ImageFilter.GaussianBlur(10))
    bg = darken(bg, 0.55)
    bg = EMBERS.draw(bg, t, 0.8)
    bg = with_vignette(bg)
    a = fade(t, 55.8, 65.3, 0.3, 0.4)
    sc = 1.4 - 0.4 * ease_out_back((t - 55.8) / 0.4)
    paste(bg, text_layer("GRATUIT", 170, GOLD, FONT_TITLE, stroke=8, shadow=12, glow=(255, 150, 40)), W / 2, 330, a, sc)
    total = sum(badge(p).width for p in PLATFORMS) + 40 * 3
    x = W / 2 - total / 2
    for i, p in enumerate(PLATFORMS):
        b = badge(p)
        k = ease_out_back((t - (57.5 + i * 0.97)) / 0.35)
        paste(bg, b, x + b.width / 2, 590 + (1 - k) * 60, clamp01(k * 2) * fade(t, 57.4, 65.3, 0.01, 0.4))
        x += b.width + 40
    paste(bg, text_layer("Tout le monde joue ensemble, sur le même serveur", 50, CREAM), W / 2, 790,
          fade(t, 61.6, 65.3, 0.5, 0.4))
    return flash(bg, 0.7 * (1 - lt / 0.25) if lt < 0.25 else 0)


def seg_end(t):
    """65,5 - 72 s : écran final, logo et adresse du site, fondu au noir."""
    lt = t - 65.5
    bg = cover(art("assets/bg/menu.png"), 1.02 + 0.03 * lt / 6.5, 0.5, 0.45)
    bg = darken(bg, 0.5)
    bg = EMBERS.draw(bg, t, 0.9)
    bg = SPARKS.draw(bg, t, 0.5)
    bg = with_vignette(bg)
    paste(bg, logo_layer(), W / 2, 380, clamp01(lt / 0.5), 1.0 + 0.02 * math.sin(lt * 2))
    paste(bg, text_layer("Duel de cartes au cœur du Royaume", 54, CREAM), W / 2, 530, fade(t, 66.0, 72, 0.5, 0.01))
    paste(bg, text_layer("Téléchargez-le gratuitement", 64, GOLD), W / 2, 700, fade(t, 66.6, 72, 0.5, 0.01))
    paste(bg, text_layer("arcanes.example.com", 50, (159, 216, 255)), W / 2, 790, fade(t, 67.0, 72, 0.5, 0.01))
    bg = flash(bg, 0.8 * (1 - lt / 0.3) if lt < 0.3 else 0)
    return darken(bg, clamp01((t - 70.9) / 1.0))


TIMELINE = [(0.0, seg_intro), (4.5, seg_logo), (8.5, seg_cards), (12.5, seg_draw), (16.0, seg_spells),
            (21.0, seg_break), (23.5, seg_dragon), (27.5, seg_inferno), (31.5, seg_online), (35.5, seg_custom),
            (39.5, seg_montage), (55.5, seg_platforms), (65.5, seg_end)]


def render(t):
    seg = TIMELINE[0][1]
    for start, fn in TIMELINE:
        if t >= start:
            seg = fn
    return seg(t)


# ------------------------------------------------------------------ sous-titres et encodage

def ts(s, sep):
    h, m = int(s // 3600), int(s % 3600 // 60)
    return f"{h:02d}:{m:02d}:{s % 60:06.3f}".replace(".", sep)


def write_subtitles():
    paths = {}
    for lang in SUBS["languages"]:
        srt = os.path.join(OUT, f"arcanes_trailer_{lang}.srt")
        vtt = os.path.join(OUT, f"arcanes_trailer_{lang}.vtt")
        with open(srt, "w", encoding="utf-8") as fs, open(vtt, "w", encoding="utf-8") as fv:
            fv.write("WEBVTT\n\n")
            for i, c in enumerate(SUBS["cues"], 1):
                fs.write(f"{i}\n{ts(c['start'], ',')} --> {ts(c['end'], ',')}\n{c[lang]}\n\n")
                fv.write(f"{ts(c['start'], '.')} --> {ts(c['end'], '.')}\n{c[lang]}\n\n")
        paths[lang] = srt
    return paths


ISO639_2 = {"fr": "fre", "en": "eng", "de": "ger", "es": "spa", "it": "ita", "pt": "por"}


def main():
    global FRAMES
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        sys.exit(1)
    FRAMES = args[0]
    os.makedirs(OUT, exist_ok=True)
    for a in sys.argv[1:]:
        if a.startswith("--preview="):   # une image fixe pour vérifier une séquence
            for s in a.split("=", 1)[1].split(","):
                render(float(s)).save(os.path.join(OUT, f"preview_{float(s):05.1f}.jpg"), quality=90)
            return
    video = os.path.join(OUT, "video_sans_sous_titres.mp4")
    music = os.path.join(HERE, "music.mp3")
    enc = subprocess.Popen([FFMPEG, "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS),
                            "-i", "-", "-i", music, "-t", str(DUR), "-map", "0:v", "-map", "1:a",
                            "-af", f"afade=t=out:st={DUR - 1.2}:d=1.2", "-c:v", "libx264", "-preset", "slow", "-crf", "19",
                            "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", video],
                           stdin=subprocess.PIPE)
    total = int(DUR * FPS)
    for n in range(total):
        frame = render(n / FPS)
        if n == int(6.5 * FPS):
            frame.save(os.path.join(OUT, "poster.jpg"), quality=90)
        enc.stdin.write(frame.tobytes())
        if n % 150 == 0:
            print(f"  {n / FPS:5.1f} s / {DUR:.0f} s", flush=True)
    enc.stdin.close()
    if enc.wait() != 0:
        sys.exit("ÉCHEC de l'encodage vidéo.")
    subs = write_subtitles()
    final = os.path.join(OUT, "arcanes_trailer.mp4")
    cmd = [FFMPEG, "-v", "error", "-y", "-i", video]
    for lang in SUBS["languages"]:
        cmd += ["-i", subs[lang]]
    cmd += ["-map", "0:v", "-map", "0:a"]
    for i, _ in enumerate(SUBS["languages"]):
        cmd += ["-map", f"{i + 1}:s"]
    cmd += ["-c:v", "copy", "-c:a", "copy", "-c:s", "mov_text", "-metadata:s:a:0", "language=zxx"]
    for i, lang in enumerate(SUBS["languages"]):
        cmd += [f"-metadata:s:s:{i}", f"language={ISO639_2[lang]}", f"-metadata:s:s:{i}", f"title={SUBS['languages'][lang]}"]
    cmd += ["-movflags", "+faststart", final]
    if subprocess.run(cmd).returncode != 0:
        sys.exit("ÉCHEC de l'ajout des sous-titres.")
    os.remove(video)
    for lang in SUBS["languages"]:
        os.remove(subs[lang])
    print(f"Bande-annonce : {final} ({os.path.getsize(final) / 1048576:.1f} Mo)")


if __name__ == "__main__":
    main()
