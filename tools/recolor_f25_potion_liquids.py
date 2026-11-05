"""Recolor potions whose liquid matched the cauldron body (#86548E).

User report 2026-11-05: four potions brewed "invisibly" because their pot liquid
was the cauldron's own purple. Only the liquid changes, inside approved ramps:
bottle liquid (mid -> new color, dark -> new shade) and the pot's exact liquid
mask (catalog liquid_pixels). Approved originals stay untouched; recolored
sources go to art/mockups/f25-potion-liquid-fix-v1/ and are published to
assets/pixel_v1 with catalog sources and liquid_ramp/liquid_color updated.
Needs Pillow (codex runtime python).
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/pixel_v1"
ART = ROOT / "art/mockups/f25-potion-liquid-fix-v1"
OLD = {"mid": (0x86, 0x54, 0x8E), "dark": (0x50, 0x31, 0x5F)}
# id -> (ramp, liquid color, bottle shade); all from art/ramps.json.
NEW = {
    "stealth": ("leaf", "#718C59", "#3D544D"),
    "nightwalk": ("teal", "#3BA8A3", "#24566A"),
    "arcane_amplification": ("purple", "#C38EB5", "#86548E"),
    "shadow_elixir": ("purple", "#C38EB5", "#86548E"),
}


def rgb(hex_color: str) -> tuple[int, int, int]:
    return tuple(int(hex_color[i:i + 2], 16) for i in (1, 3, 5))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    catalog_path = OUT / "catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    mask = [tuple(p) for p in catalog["liquid_pixels"]]
    report = {}
    for pid, (ramp, color, shade) in NEW.items():
        entry = catalog["potions"][pid]
        assert entry["liquid_color"].upper() == "#86548E", pid
        changed = {}
        bottle = Image.open(OUT / f"potions/{pid}.png").convert("RGBA")
        swap = {OLD["mid"]: rgb(color), OLD["dark"]: rgb(shade)}
        count = 0
        for y in range(bottle.height):
            for x in range(bottle.width):
                r, g, b, a = bottle.getpixel((x, y))
                if a and (r, g, b) in swap:
                    bottle.putpixel((x, y), swap[(r, g, b)] + (a,)); count += 1
        target = ART / f"bottles/{pid}.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        bottle.save(target)
        changed[f"potions/{pid}.png"] = (target, count)
        for frame in range(3):
            pot = Image.open(OUT / f"pots/{pid}-{frame}.png").convert("RGBA")
            count = 0
            for x, y in mask:
                r, g, b, a = pot.getpixel((x, y))
                if (r, g, b) == OLD["mid"]:
                    pot.putpixel((x, y), rgb(color) + (a,)); count += 1
            target = ART / f"pots/{pid}-{frame}.png"
            target.parent.mkdir(parents=True, exist_ok=True)
            pot.save(target)
            changed[f"pots/{pid}-{frame}.png"] = (target, count)
        for published, (source, count) in changed.items():
            if count == 0: raise SystemExit(f"No liquid pixels changed in {published}")
            (OUT / published).write_bytes(source.read_bytes())
            catalog["sources"][published] = {"source": source.relative_to(ROOT).as_posix(), "sha256": sha(source)}
        entry["liquid_ramp"], entry["liquid_color"] = ramp, color
        report[pid] = {"ramp": ramp, "liquid": color, "shade": shade, "pixels": {k: v[1] for k, v in changed.items()}}
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (ART / "recolor.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
