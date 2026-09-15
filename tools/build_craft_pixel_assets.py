"""Normalize this phase's generated craft assets; preserve every source image."""
from __future__ import annotations

import json
import hashlib
from pathlib import Path

import numpy as np
import cv2
from PIL import Image
from build_pixel_assets import ART, alpha_image, normalized_strip, save_atlas


def grid(source: str, target: str, columns: int, rows: int, frame_size=(128, 128), key="green"):
    image = alpha_image(ART / "source" / source, key)
    data = np.array(image)
    if key == "green":
        rgb = data[:,:,:3].astype(np.float32)
        chroma = (rgb[:,:,1] > 35) & (rgb[:,:,1] > rgb[:,:,0]*1.4+8) & (rgb[:,:,1] > rgb[:,:,2]*1.4+8)
        candidates = chroma | (data[:,:,3] == 0)
        _, labels = cv2.connectedComponents(candidates.astype(np.uint8), connectivity=4)
        border = np.unique(np.concatenate((labels[0],labels[-1],labels[:,0],labels[:,-1])))
        data[chroma & np.isin(labels,border[border != 0]),3] = 0
    else:
        # The generated transparent strip has almost invisible stray alpha outside
        # the bubbles. Remove it before bounding-box normalization to prevent shrinkage.
        data[data[:,:,3] < 128,3] = 0
    data[data[:,:,3] == 0,:3] = 0
    image = Image.fromarray(data)
    boxes = [[round(x * image.width / columns), round(y * image.height / rows),
              round((x + 1) * image.width / columns), round((y + 1) * image.height / rows)]
             for y in range(rows) for x in range(columns)]
    frames = normalized_strip(image, boxes, frame_size)
    save_atlas(frames, ART / "runtime" / target, columns)
    return frames


def main():
    output = ART / "runtime" / "craft"
    output.mkdir(parents=True, exist_ok=True)
    for task in ["tianmen_tang_su", "gu_pen_ge", "ezhou_diaohua_jianzhi"]:
        suffix = "-v2" if task == "ezhou_diaohua_jianzhi" else ""
        image = Image.open(ART / "source" / f"{task}-background{suffix}.png").convert("RGBA")
        image.resize((500, 300), Image.Resampling.NEAREST).save(output / f"{task}-background.png")
    stage = Image.open(ART / "source" / "huangmei_xi-background.png").convert("RGBA")
    for row, name in enumerate(["closed", "open"]):
        stage.crop((0, row * stage.height // 2, stage.width, (row + 1) * stage.height // 2)).resize(
            (500, 300), Image.Resampling.NEAREST).save(output / f"huangmei_xi-{name}.png")
    tube_tips = {}
    for task in ["tianmen_tang_su", "gu_pen_ge", "ezhou_diaohua_jianzhi", "huangmei_xi"]:
        frames = grid(f"{task}-avatars.png", f"craft/{task}-avatars.png", 6, 6)
        if task == "tianmen_tang_su":
            for row, identity in enumerate(["travel","life","business","food","adventure","magic"]):
                tips = []
                for frame in frames[row*6:row*6+6]:
                    ys,xs = np.where(np.array(frame)[:,:,3] > 128)
                    x = int(xs.max())
                    tips.append([x,int(np.median(ys[xs >= x-1]))])
                tube_tips[identity+"_blogger"] = tips
    grid("gu_pen_ge-teacher.png", "craft/gu_pen_ge-teacher.png", 6, 1, (160, 160))
    grid("tianmen_tang_su-bubbles.png", "craft/tianmen_tang_su-bubbles.png", 6, 1, (160, 160), "none")
    hands = grid("ezhou_diaohua_jianzhi-hands.png", "craft/ezhou_diaohua_jianzhi-hands.png", 3, 1, (160, 160))
    tips = []
    for frame in hands[:2]:
        mask = np.array(frame)[:, :, 3] > 128
        ys, xs = np.where(mask)
        top = int(ys.min())
        tips.append([int(np.median(xs[ys == top])), top])
    alpha_image(ART / "source" / "ezhou_diaohua_jianzhi-artwork-v2.png", "green").resize(
        (500, 300), Image.Resampling.NEAREST).save(output / "ezhou_diaohua_jianzhi-artwork.png")
    (output / "anchors.json").write_text(json.dumps({"knife_tip": tips,"tube_tip":tube_tips}, indent=2), encoding="utf-8")
    prefixes = ("tianmen_tang_su", "gu_pen_ge", "ezhou_diaohua_jianzhi", "huangmei_xi")
    sources = [{"file":str(path.relative_to(ART)),"sha256":hashlib.sha256(path.read_bytes()).hexdigest()}
               for path in sorted((ART/"source").glob("*.png")) if path.name.startswith(prefixes)]
    files = []
    for path in sorted(output.glob("*.png")):
        image = Image.open(path).convert("RGBA")
        alpha = np.array(image)[:,:,3]
        files.append({"file":str(path.relative_to(ART)),"size":list(image.size),
                      "sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
                      "transparent_pixels":int((alpha == 0).sum()),
                      "status":"normalized; see craft engine review for actual validation"})
    (ART/"craft-asset-manifest.json").write_text(json.dumps({"source_files":sources,"runtime_files":files,
        "generation_log":"source/craft-art-generation-log.json", "identity_rows":["travel","life","business","food","adventure","magic"],
        "avatar_columns":["ready","prepare","action","release","miss","recover"],
        "cultural_pending":["鼓盆歌鼓板形制与握法、真实原声","鄂州雕花剪纸刻制近景与蜡盘操作"]},ensure_ascii=False,indent=2),encoding="utf-8")
    print(f"Craft assets normalized. Knife tip anchors: {tips}. Sources preserved.")


if __name__ == "__main__":
    main()
