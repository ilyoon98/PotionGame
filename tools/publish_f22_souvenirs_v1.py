"""Publish the approved F22 regular souvenirs into assets/pixel_v1 (additive only).

Copies the four validated 32x32 sprites byte-for-byte and adds a `souvenirs`
catalog key. Existing published files and catalog entries are left unchanged.
Standard library only, so the system Python can run it.
"""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/pixel_v1"
MOCK = ROOT / "art/mockups/f22-regulars-souvenirs-v1"
IDS = ("souvenir_compass", "souvenir_bookmark", "souvenir_leaf_brooch", "souvenir_silver_bell")


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def import_settings(png: Path) -> None:
    # Same lossless/no-border-fill settings as publish_f21_rest_aging_v1.py.
    resource = "res://" + png.relative_to(ROOT).as_posix()
    dest = "res://.godot/imported/" + png.name + "-" + hashlib.md5(resource.encode()).hexdigest() + ".ctex"
    Path(str(png) + ".import").write_text(
        '[remap]\nimporter="texture"\ntype="CompressedTexture2D"\npath="' + dest + '"\n\n[deps]\nsource_file="' + resource
        + '"\ndest_files=["' + dest + '"]\n\n[params]\ncompress/mode=0\nmipmaps/generate=false\nprocess/fix_alpha_border=false\nprocess/premult_alpha=false\n',
        encoding="utf-8")


def main() -> int:
    report = read(MOCK / "validation.json")
    approval = read(MOCK / "approval.json")
    if not report["passed"] or not approval["approved_by_user"]:
        raise SystemExit("Only passed, user-approved art is published")
    catalog_path = OUT / "catalog.json"
    catalog = read(catalog_path)
    souvenirs = {}
    for id in IDS:
        source = MOCK / f"sprites/{id}.png"
        target = f"souvenirs/{id}.png"
        dest = OUT / target
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, dest)
        if sha256(dest) != sha256(source):
            raise SystemExit(f"Published {target} differs from the approved sprite")
        import_settings(dest)
        catalog["sources"][target] = {"source": source.relative_to(ROOT).as_posix(), "sha256": sha256(source)}
        souvenirs[id] = "res://assets/pixel_v1/" + target
    catalog["souvenirs"] = souvenirs
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Published F22 souvenirs: " + ", ".join(IDS))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
