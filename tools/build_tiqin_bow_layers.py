"""Slice authored continuous-bow layers, retaining source and anchor metadata."""
import json
from collections import deque
from PIL import Image
from build_pixel_assets import ART, alpha_image

IDS = ["travel", "life", "business", "food", "adventure", "magic"]
SOURCE = ART / "source/tiqin-bow-layers-v2.png"
TARGET = ART / "runtime/tiqin-bow-v2"
ANCHORS = {
    "travel": ([38, 90], [81, 104]),
    "life": ([42, 92], [85, 104]),
    "business": ([35, 89], [84, 104]),
    "food": ([39, 89], [84, 104]),
    "adventure": ([40, 90], [85, 104]),
    "magic": ([39, 88], [91, 102]),
}

def body_bounds(image):
    """Ignore detached ground shadows; retain the complete authored body component."""
    alpha = image.getchannel("A")
    pixels = alpha.load()
    visited = set()
    largest = []
    for y in range(image.height):
        for x in range(image.width):
            if (x,y) in visited or pixels[x,y] < 32: continue
            queue = deque([(x,y)])
            component = []
            visited.add((x,y))
            while queue:
                point = queue.popleft()
                component.append(point)
                px, py = point
                for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
                    nx, ny = px+dx, py+dy
                    if 0 <= nx < image.width and 0 <= ny < image.height and (nx,ny) not in visited and pixels[nx,ny] >= 32:
                        visited.add((nx,ny))
                        queue.append((nx,ny))
            if len(component) > len(largest): largest = component
    return (max(0,min(x for x,y in largest)-1), max(0,min(y for x,y in largest)-1),
            min(image.width,max(x for x,y in largest)+2), min(image.height,max(y for x,y in largest)+2))


def build():
    image = alpha_image(SOURCE, "green")
    metadata = {}
    for row, name in enumerate(IDS):
        folder = TARGET / name
        folder.mkdir(parents=True, exist_ok=True)
        parts = {}
        columns = [(0, 275), (285, 490), (500, 715), (730, 1024)]
        for column, part in enumerate(["body", "upper_arm", "forearm_hand", "bow"]):
            cell = image.crop((columns[column][0], row * image.height // 6,
                               columns[column][1], (row + 1) * image.height // 6))
            bounds = body_bounds(cell) if part == "body" else cell.getbbox()
            if bounds is None: raise ValueError(f"Missing {name}/{part}")
            crop = cell.crop(bounds)
            if part == "body":
                scale = 120 / crop.height
                size = (round(crop.width * scale), 120)
                output = Image.new("RGBA", (128, 128))
                offset = ((128-size[0])//2, 4)
                output.alpha_composite(crop.resize(size, Image.Resampling.NEAREST), offset)
                parts[part] = {"source_bounds": list(bounds), "scale": scale, "offset": offset}
            else:
                output = crop
                parts[part] = {"source_bounds": list(bounds), "size": list(crop.size)}
            output.save(folder / f"{part}.png")
        shoulder, contact = ANCHORS[name]
        metadata[name + "_blogger"] = {"parts": parts, "shoulder": shoulder, "string_contact": contact}
    TARGET.mkdir(parents=True, exist_ok=True)
    (TARGET / "anchors.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print("Sliced six continuous-bow layer sets; originals preserved.")


if __name__ == "__main__": build()
