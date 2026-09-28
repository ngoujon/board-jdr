"""Post-traitement des images générées par ComfyUI (tools/raw) -> assets du jeu.

- Réduction en « vrai » pixel art (moyenne par bloc + palette limitée, sans tramage).
- Recadrage des sprites détourés (icônes).
- Composition des éléments d'interface (cadres de cartes, panneaux, boutons, cadre de héros)
  à partir des textures générées (parchemin, pierre, bois).

Usage : python tools/postprocess_assets.py
"""

import json
import os

from PIL import Image, ImageDraw, ImageEnhance

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "tools", "raw")


def p(*parts):
    return os.path.join(ROOT, *parts)


def quantize(img, colors=32):
    if img.mode == "RGBA":
        alpha = img.getchannel("A").point(lambda a: 255 if a >= 128 else 0)
        rgb = img.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
        rgb.putalpha(alpha)
        return rgb
    return img.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")


def pixelize(src, size, colors=32):
    img = Image.open(src).convert("RGB")
    img = img.resize(tuple(size), Image.BOX)
    return quantize(img, colors)


def sprite(src, size, colors=24):
    img = Image.open(src).convert("RGBA")
    bbox = img.getchannel("A").point(lambda a: 255 if a >= 100 else 0).getbbox()
    if bbox:
        img = img.crop(bbox)
    w, h = img.size
    side = int(max(w, h) * 1.06)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - w) // 2, (side - h) // 2))
    # Prémultiplication légère pour éviter les franges blanches du fond d'origine.
    small = canvas.resize((size, size), Image.BOX)
    return quantize(small, colors)


def save(img, *parts):
    path = p(*parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("->", os.path.relpath(path, ROOT))


# ---------------------------------------------------------------- composition UI

DARK = (26, 18, 32, 255)
GOLD = (201, 160, 67, 255)
GOLD_HI = (255, 226, 140, 255)
GOLD_LO = (122, 86, 30, 255)


def tex_crop(name, size, brightness=1.0):
    """Texture générée, réduite en pixel art puis recadrée / répétée à la taille voulue."""
    base = pixelize(os.path.join(RAW, name), (128, 128), 24).convert("RGBA")
    if brightness != 1.0:
        base = ImageEnhance.Brightness(base).enhance(brightness)
    out = Image.new("RGBA", size)
    for x in range(0, size[0], 128):
        for y in range(0, size[1], 128):
            out.paste(base, (x, y))
    return out


def rect(d, box, color, width=1):
    x0, y0, x1, y1 = box
    for i in range(width):
        d.rectangle((x0 + i, y0 + i, x1 - i, y1 - i), outline=color)


def bevel_frame(img, box, main, hi, lo, width=3):
    """Bordure biseautée façon 8-bit : contour sombre, reflet clair en haut/gauche."""
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = box
    rect(d, box, DARK, 1)
    for i in range(1, width + 1):
        d.line((x0 + i, y0 + i, x1 - i, y0 + i), fill=hi if i == 1 else main)
        d.line((x0 + i, y0 + i, x0 + i, y1 - i), fill=hi if i == 1 else main)
        d.line((x0 + i, y1 - i, x1 - i, y1 - i), fill=lo if i == 1 else main)
        d.line((x1 - i, y0 + i, x1 - i, y1 - i), fill=lo if i == 1 else main)
    rect(d, (x0 + width + 1, y0 + width + 1, x1 - width - 1, y1 - width - 1), DARK, 1)


def corner_gems(img, box, color):
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = box
    for cx, cy in ((x0 + 2, y0 + 2), (x1 - 2, y0 + 2), (x0 + 2, y1 - 2), (x1 - 2, y1 - 2)):
        d.polygon([(cx, cy - 4), (cx + 4, cy), (cx, cy + 4), (cx - 4, cy)], fill=color, outline=DARK)


def card_frame(kind):
    W, H = 160, 224
    parchment = tex_crop("ui_parchment.png", (W, H), 1.05)
    img = parchment.copy()
    d = ImageDraw.Draw(img)
    if kind == "minion":
        main, hi, lo = GOLD, GOLD_HI, GOLD_LO
        ribbon, ribbon_hi = (122, 31, 31, 255), (170, 60, 50, 255)
    else:
        main, hi, lo = (120, 150, 205, 255), (200, 220, 255, 255), (50, 70, 120, 255)
        ribbon, ribbon_hi = (31, 58, 122, 255), (70, 100, 170, 255)
    # Bande de titre au-dessus de l'illustration (zone du coût).
    d.rectangle((4, 4, W - 5, 21), fill=(0, 0, 0, 0))
    header = tex_crop("ui_stone.png", (W, 24), 0.7)
    img.paste(header.crop((0, 0, W - 8, 18)), (4, 4))
    # Fenêtre de l'illustration (transparente) + cadre.
    d.rectangle((8, 22, 151, 133), fill=(0, 0, 0, 0))
    rect(d, (6, 20, 153, 135), DARK, 2)
    d.line((8, 134, 151, 134), fill=lo)
    # Ruban du nom.
    d.rectangle((3, 136, W - 4, 156), fill=ribbon, outline=DARK)
    d.line((4, 137, W - 5, 137), fill=ribbon_hi)
    d.polygon([(0, 140), (3, 136), (3, 156), (0, 152)], fill=ribbon, outline=DARK)
    d.polygon([(W - 1, 140), (W - 4, 136), (W - 4, 156), (W - 1, 152)], fill=ribbon, outline=DARK)
    # Zone de texte plus claire.
    text_area = ImageEnhance.Brightness(parchment.crop((10, 159, 150, 207))).enhance(1.12)
    img.paste(text_area, (10, 159))
    rect(d, (9, 158, 150, 207), (140, 110, 70, 255), 1)
    bevel_frame(img, (0, 0, W - 1, H - 1), main, hi, lo, 3)
    corner_gems(img, (0, 0, W - 1, H - 1), hi)
    return img


def nine_panel(texture, size=48, brightness=0.55, border=GOLD):
    img = tex_crop(texture, (size, size), brightness)
    bevel_frame(img, (0, 0, size - 1, size - 1), border, GOLD_HI, GOLD_LO, 3)
    corner_gems(img, (0, 0, size - 1, size - 1), GOLD_HI)
    return img


def button(brightness, border, hi):
    img = tex_crop("ui_wood.png", (48, 24), brightness)
    d = ImageDraw.Draw(img)
    rect(d, (0, 0, 47, 23), DARK, 1)
    d.line((1, 1, 46, 1), fill=hi)
    d.line((1, 22, 46, 22), fill=(20, 12, 8, 255))
    rect(d, (1, 2, 46, 21), border, 1)
    return img


def hero_frame():
    S = 128
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bevel_frame(img, (0, 0, S - 1, S - 1), GOLD, GOLD_HI, GOLD_LO, 5)
    d = ImageDraw.Draw(img)
    d.rectangle((7, 7, S - 8, S - 8), fill=(0, 0, 0, 0))
    rect(d, (6, 6, S - 7, S - 7), DARK, 1)
    for cx, cy in ((4, 4), (S - 5, 4), (4, S - 5), (S - 5, S - 5)):
        d.polygon([(cx, cy - 7), (cx + 7, cy), (cx, cy + 7), (cx - 7, cy)], fill=GOLD_HI, outline=DARK)
        d.polygon([(cx, cy - 3), (cx + 3, cy), (cx, cy + 3), (cx - 3, cy)], fill=(200, 40, 40, 255))
    return img


def main():
    manifest = json.load(open(p("tools", "assets_manifest.json"), encoding="utf-8"))
    for item in manifest["images"]:
        src = os.path.join(RAW, item["id"] + ".png")
        if not os.path.exists(src):
            print("!! manquant :", src)
            continue
        if item["id"].startswith("ui_") and item["id"] != "ui_card_back":
            continue  # textures brutes : utilisées pour composer l'interface
        if item["workflow"] == "pixel_art_sprite_nobg":
            img = sprite(src, item["size"][0])
        else:
            size = item["size"]
            if item["id"] == "ui_card_back":
                size = [80, 112]
            img = pixelize(src, size, 32)
        save(img, *item["out"].split("/"))

    for i in range(1, 9):
        src = os.path.join(RAW, "avatar_%d.png" % i)
        if os.path.exists(src):
            save(pixelize(src, (96, 96), 32), "assets", "avatars", "avatar_%d.png" % i)

    save(card_frame("minion"), "assets", "ui", "card_frame_minion.png")
    save(card_frame("spell"), "assets", "ui", "card_frame_spell.png")
    save(nine_panel("ui_stone.png"), "assets", "ui", "panel.png")
    save(nine_panel("ui_parchment.png", brightness=1.0), "assets", "ui", "parchment_panel.png")
    save(button(0.9, (110, 70, 35, 255), (190, 140, 90, 255)), "assets", "ui", "button.png")
    save(button(1.25, GOLD, GOLD_HI), "assets", "ui", "button_hover.png")
    save(button(0.6, GOLD_LO, (90, 60, 30, 255)), "assets", "ui", "button_pressed.png")
    save(hero_frame(), "assets", "ui", "hero_frame.png")


if __name__ == "__main__":
    main()
