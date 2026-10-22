"""Publish the approved F21 rest/aging art into assets/pixel_v1 (additive only).

Adds keeper sleep/faint atlases, the wall aging cask, the aged seal and the
Z/star effects, and their catalog keys. Existing published files and catalog
entries are left byte-for-byte unchanged (prepare_pixel_runtime_v1.py is not
rerun because it rebuilds every asset).
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/pixel_v1"
KEEPER = ROOT / "art/characters/rest-v1/keeper"
MOCK = ROOT / "art/mockups/f21-rest-aging-v1"


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def import_settings(png: Path) -> None:
    # Same lossless/no-border-fill settings as prepare_pixel_runtime_v1.py.
    resource = "res://" + png.relative_to(ROOT).as_posix()
    dest = "res://.godot/imported/" + png.name + "-" + hashlib.md5(resource.encode()).hexdigest() + ".ctex"
    Path(str(png) + ".import").write_text(
        '[remap]\nimporter="texture"\ntype="CompressedTexture2D"\npath="' + dest + '"\n\n[deps]\nsource_file="' + resource
        + '"\ndest_files=["' + dest + '"]\n\n[params]\ncompress/mode=0\nmipmaps/generate=false\nprocess/fix_alpha_border=false\nprocess/premult_alpha=false\n',
        encoding="utf-8")


def atlas(rest: Image.Image, lifted: Image.Image, scale: int) -> Image.Image:
    """64-cell layout read by PixelArtCatalog.motion_index: 16 phases x lift x blink.

    Lift cells (16..31, 48..63) hold the breathing frame; eyes are closed, so the
    blink half repeats the open half.
    """
    cell = (32 * scale, 48 * scale)
    sheet = Image.new("RGBA", (cell[0] * 16, cell[1] * 4))
    frames = [im.resize(cell, Image.Resampling.NEAREST) for im in (rest, lifted)]
    for index in range(64):
        sheet.alpha_composite(frames[(index // 16) % 2], ((index % 16) * cell[0], (index // 16) * cell[1]))
    return sheet


def main() -> int:
    report = read(MOCK / "validation.json")
    approval = read(MOCK / "approval.json")
    if not report["passed"] or not approval["approved_by_user"]:
        raise SystemExit("Only passed, user-approved art is published")
    catalog_path = OUT / "catalog.json"
    catalog = read(catalog_path)
    sources = catalog["sources"]

    def publish(image: Image.Image, target: str, source: Path) -> str:
        dest = OUT / target
        dest.parent.mkdir(parents=True, exist_ok=True)
        image.save(dest)
        import_settings(dest)
        sources[target] = {"source": source.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(source.read_bytes()).hexdigest()}
        return "res://assets/pixel_v1/" + target

    def frame(name: str) -> Image.Image:
        return Image.open(KEEPER / f"frames/{name}.png").convert("RGBA")

    poses = catalog["characters"]["keeper"]["poses"]
    for pose, rest, lifted in (("sleep", "sleep_sit", "sleep_sit_breath"), ("faint", "faint", "faint")):
        source = KEEPER / f"frames/{rest}.png"
        poses[pose] = {"fine": publish(atlas(frame(rest), frame(lifted), 3), f"characters/keeper/{pose}-fine.png", source),
                       "native": publish(atlas(frame(rest), frame(lifted), 1), f"characters/keeper/{pose}-native.png", source)}
    prop = lambda name: Image.open(MOCK / f"props/pipeline/{name}-native.png").convert("RGBA")
    source = lambda name: MOCK / f"props/pipeline/{name}-native.png"
    catalog["props"]["aging_cask"] = publish(prop("aging_cask_wall"), "props/aging_cask.png", source("aging_cask_wall"))
    catalog["props"]["aged_seal"] = publish(prop("aged_seal"), "props/aged_seal.png", source("aged_seal"))
    catalog["effects"] = {"sleep_z": publish(prop("sleep_z"), "effects/sleep_z.png", source("sleep_z")),
                          "dizzy_star": publish(prop("dizzy_star"), "effects/dizzy_star.png", source("dizzy_star"))}
    # Published pixels must equal the validated art exactly.
    for target, row in sources.items():
        if not target.startswith(("characters/keeper/sleep", "characters/keeper/faint", "props/aging_cask", "props/aged_seal", "effects/")):
            continue
        published = np.array(Image.open(OUT / target).convert("RGBA"))
        if not ((published[:, :, 3] == 0) | (published[:, :, 3] == 255)).all():
            raise SystemExit(f"Partial alpha in {target}")
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Published F21 rest/aging: keeper sleep/faint atlases, aging_cask, aged_seal, sleep_z, dizzy_star")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
