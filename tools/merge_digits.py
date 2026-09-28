"""Crée assets/fonts/ArcanesPixel.ttf : Pixelify Sans dont les chiffres (peu lisibles) sont remplacés
par ceux de Press Start 2P. À lancer depuis assets/fonts :  python ../../tools/merge_digits.py"""
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen

base = TTFont("PixelifySans.ttf")
src = TTFont("PressStart2P.ttf")
bcmap, scmap = base.getBestCmap(), src.getBestCmap()
S = 0.72                     # 1 pixel PS2P (125) -> 90 unités, chiffres de 630 de haut (comme Pixelify)
DX, DY = 45, -125 * S        # demi-pixel d'approche à gauche, ligne de base alignée
src_glyf = src["glyf"]
gs = src.getGlyphSet()
for ch in "0123456789":
    bname, sname = bcmap[ord(ch)], scmap[ord(ch)]
    pen = TTGlyphPen(None)
    gs[sname].draw(TransformPen(pen, (S, 0, 0, S, DX, DY)))
    g = pen.glyph()
    base["glyf"][bname] = g
    g.recalcBounds(base["glyf"])
    base["hmtx"][bname] = (int(round(1000 * S)), g.xMin)
    base["gvar"].variations[bname] = []      # chiffres identiques quel que soit le poids
if "HVAR" in base:
    del base["HVAR"]                           # les avances se déduisent alors de gvar
# Police modifiée : nouveau nom (clause OFL sur les noms réservés).
for rec in base["name"].names:
    if rec.nameID in (1, 3, 4, 6, 16, 17, 21, 25):
        txt = rec.toUnicode()
        rec.string = txt.replace("Pixelify Sans", "Arcanes Pixel").replace("PixelifySans", "ArcanesPixel")
base.save("ArcanesPixel.ttf")
t = TTFont("ArcanesPixel.ttf")
print("OK", t["name"].getDebugName(1), t["hmtx"][t.getBestCmap()[ord("7")]])
