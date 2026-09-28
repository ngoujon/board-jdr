"""Génère des images du manifeste (tools/assets_manifest.json) avec ComfyUI puis les convertit en pixel art.

Usage : python tools/gen_images.py <id> [<id> ...] [--seed-offset=N]
- ComfyUI doit tourner sur 127.0.0.1:8188 (SDXL + LoRA pixel-art-xl).
- Image brute -> tools/raw/<id>.png ; image du jeu -> chemin « out » du manifeste (taille « size »).
- --seed-offset : essaie une autre graine sans modifier le manifeste (à reporter dans « seed » si retenue).
"""
import json
import os
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from postprocess_assets import RAW, p, pixelize, save, sprite  # noqa: E402

COMFY = "http://127.0.0.1:8188"


def call(path, data=None):
    req = urllib.request.Request(COMFY + path, data=json.dumps(data).encode() if data is not None else None,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def generate(item, manifest, seed_offset=0):
    wf = open(p("tools", "comfy_workflows", item["workflow"] + ".json"), encoding="utf-8").read()
    prompt = manifest["style_prefix"] + item["prompt"] + manifest["style_suffix"]
    for k, v in {"__PROMPT__": prompt, "__NEGATIVE__": manifest["negative"], "__PREFIX__": "arcanes_" + item["id"]}.items():
        wf = wf.replace(k, json.dumps(v)[1:-1])
    for k, v in {"__WIDTH__": item["w"], "__HEIGHT__": item["h"], "__SEED__": item["seed"] + seed_offset}.items():
        wf = wf.replace('"%s"' % k, str(v))
    graph = {k: v for k, v in json.loads(wf).items() if not k.startswith("_")}
    pid = json.loads(call("/prompt", {"prompt": graph}))["prompt_id"]
    while True:
        time.sleep(2)
        hist = json.loads(call("/history/" + pid))
        if pid in hist:
            break
    for out in hist[pid]["outputs"].values():
        for im in out.get("images", []):
            q = "filename=%s&subfolder=%s&type=%s" % (im["filename"], im.get("subfolder", ""), im.get("type", "output"))
            with urllib.request.urlopen(COMFY + "/view?" + q, timeout=60) as r:
                raw = r.read()
            os.makedirs(RAW, exist_ok=True)
            src = os.path.join(RAW, item["id"] + ".png")
            with open(src, "wb") as f:
                f.write(raw)
            return src
    raise RuntimeError("aucune image produite pour " + item["id"])


def main():
    ids = [a for a in sys.argv[1:] if not a.startswith("--")]
    offset = next((int(a.split("=", 1)[1]) for a in sys.argv[1:] if a.startswith("--seed-offset=")), 0)
    manifest = json.load(open(p("tools", "assets_manifest.json"), encoding="utf-8"))
    items = {it["id"]: it for it in manifest["images"]}
    for i in ids:
        item = items[i]
        src = generate(item, manifest, offset)
        img = sprite(src, item["size"][0]) if item["workflow"] == "pixel_art_sprite_nobg" else pixelize(src, item["size"], 32)
        save(img, *item["out"].split("/"))


if __name__ == "__main__":
    main()
