"""Publish the approved F26 dawn-lighthouse art into the runtime folders (additive only).

Copies the validated, user-approved sprites from art/mockups/f26-region-potions-v1/ byte-for-byte:

  sprites/{id}_bottle.png  -> assets/pixel_v1/potions/{id}.png            (shelf/handover bottle, 8x12 or 8x16)
  pots/{id}-{0,1,2}.png    -> assets/pixel_v1/pots/{id}-{0,1,2}.png       (cauldron liquid frames, 32x32)
  sprites/{id}_icon.png    -> assets/content_expansion_v1/potions/{id}_icon.png   (32x40 potion icon)
  sprites/{id}_recipe.png  -> assets/content_expansion_v1/recipes/{id}_recipe.png (32x40 recipe icon)
  sprites/dawn_bloom_icon.png      -> assets/content_expansion_v1/materials/dawn_bloom_icon.png
  sprites/dawn_lighthouse_icon.png -> assets/content_expansion_v1/regions/dawn_lighthouse_icon.png

and adds to assets/pixel_v1/catalog.json only:
  - four `potions` rows (liquid ramp/colour, bottle, three pot frames) and their `sources` hashes;
  - four `characters.<customer>.bindings` rows per customer (the bottle's hand-grip point used when a customer
    catches and carries the bottle), solved with the same rule that produced the existing 144 bindings
    (tools/build_flying_workshop_v9.py catch_binding; the script first re-solves the existing bindings and stops
    unless all 144 come out identical).
Existing files and catalog rows are never rewritten: an existing identical row is kept, a different one stops the
script. No growth sheet (64x80) is published: it was outside the approval scope. prepare_pixel_runtime_v1.py is
NOT re-run. Needs Pillow + NumPy for the binding solve, e.g.
  C:\\Users\\imtl\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\python\\python.exe tools/publish_f26_region_potions_v1.py
"""
from __future__ import annotations

import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOCK = ROOT / "art/mockups/f26-region-potions-v1"
PIXEL = ROOT / "assets/pixel_v1"
EXPANSION = ROOT / "assets/content_expansion_v1"
CUSTOMERS = ("traveler", "mage", "elf", "rogue")
# Names and families follow data/content_expansion.json; liquid ramps/colours and sizes the approved validation.json.
POTIONS = (
    {"id": "sunrise", "name": "해돋이", "family": "vitality"},
    {"id": "beacon", "name": "등대불", "family": "craft"},
    {"id": "sea_spray", "name": "물보라", "family": "nature"},
    {"id": "sun_moon_elixir", "name": "일월의 물약", "family": "arcane"},
)
ICONS = (("dawn_bloom_icon", "materials/dawn_bloom_icon.png"), ("dawn_lighthouse_icon", "regions/dawn_lighthouse_icon.png"))


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def import_settings(png: Path) -> None:
    # Same lossless/no-border-fill settings as the other additive publish scripts; Godot --import fills the rest.
    settings = Path(str(png) + ".import")
    if settings.exists():
        return
    resource = "res://" + png.relative_to(ROOT).as_posix()
    dest = "res://.godot/imported/" + png.name + "-" + hashlib.md5(resource.encode()).hexdigest() + ".ctex"
    with open(settings, "w", encoding="utf-8", newline="\n") as handle:
        handle.write('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\npath="' + dest + '"\n\n[deps]\nsource_file="' + resource
            + '"\ndest_files=["' + dest + '"]\n\n[params]\ncompress/mode=0\nmipmaps/generate=false\nprocess/fix_alpha_border=false\nprocess/premult_alpha=false\n')


def copy(source: Path, dest: Path) -> None:
    if dest.exists() and sha256(dest) != sha256(source):
        raise SystemExit(f"Refusing to overwrite a different existing file: {dest.relative_to(ROOT)}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, dest)
    if sha256(dest) != sha256(source):
        raise SystemExit(f"Published {dest.relative_to(ROOT)} differs from the approved sprite")
    import_settings(dest)


def add(table: dict, key: str, value) -> None:
    if key in table and table[key] != value:
        raise SystemExit(f"catalog already has a different {key}; this script only adds rows")
    table[key] = value


def bindings(liquids: dict) -> dict:
    sys.path.insert(0, str(ROOT / "tools"))
    import build_flying_workshop_v9 as v9  # the rule behind the existing catalog bindings

    catalog = read(PIXEL / "catalog.json")
    recipes = read(v9.ENV / "potions/recipes.json")["recipes"]
    result = {}
    for cid in CUSTOMERS:
        root = ROOT / f"art/characters/actions-v1/{cid}"
        grips = v9.read(root / "contact-validation.json")["hand_grips"]
        if grips != catalog["characters"][cid]["grips"]:
            raise SystemExit(f"{cid}: catalog grips differ from the approved action grips")
        meta = v9.read(root / "actions.json")
        poses = ["idle", "walk_contact_a", "walk_pass_a", "walk_contact_b", "walk_pass_b", "receive_extend", "receive_hold", *meta["new_carry_poses"]]
        frames = {pose: v9.im(root / "frames" / f"{pose}.png") for pose in poses}
        for recipe in recipes:
            if v9.catch_binding(cid, recipe, frames, grips) != catalog["characters"][cid]["bindings"][recipe["id"]]:
                raise SystemExit(f"{cid}/{recipe['id']}: re-solved binding differs; rule mismatch")
        result[cid] = {}
        for item in POTIONS:
            pid = item["id"]
            bottle = MOCK / f"sprites/{pid}_bottle.png"
            # An absolute bottle_path replaces v9's ENV/potions prefix (pathlib join with an absolute path).
            result[cid][pid] = v9.catch_binding(cid, {"id": pid, "bottle_path": str(bottle), "liquid_color": liquids[pid]}, frames, grips)
    return result


def main() -> int:
    approval = read(MOCK / "approval.json")
    report = read(MOCK / "validation.json")
    if approval.get("status") != "approved" or not approval.get("approved_by_user") or report.get("status") != "passed":
        raise SystemExit("Only passed, user-approved art is published")
    catalog_path = PIXEL / "catalog.json"
    catalog = read(catalog_path)
    liquids = {}
    for item in POTIONS:
        pid = item["id"]
        new = report["liquid_colours"]["new"][pid]
        sprite = report["sprites"][pid + "_bottle"]
        pot = report["pots"]["potions"][pid]
        if not pot["passed"] or pot["liquid"] != new["liquid"]:
            raise SystemExit(f"{pid}: pot validation does not match the approved liquid")
        liquids[pid] = new["liquid"]
        bottle_source = MOCK / f"sprites/{pid}_bottle.png"
        copy(bottle_source, PIXEL / f"potions/{pid}.png")
        add(catalog["sources"], f"potions/{pid}.png", {"source": bottle_source.relative_to(ROOT).as_posix(), "sha256": sha256(bottle_source)})
        pots = []
        for index in range(3):
            pot_source = MOCK / f"pots/{pid}-{index}.png"
            copy(pot_source, PIXEL / f"pots/{pid}-{index}.png")
            add(catalog["sources"], f"pots/{pid}-{index}.png", {"source": pot_source.relative_to(ROOT).as_posix(), "sha256": sha256(pot_source)})
            pots.append(f"res://assets/pixel_v1/pots/{pid}-{index}.png")
        for kind, folder in (("icon", "potions"), ("recipe", "recipes")):
            copy(MOCK / f"sprites/{pid}_{kind}.png", EXPANSION / f"{folder}/{pid}_{kind}.png")
        add(catalog["potions"], pid, {
            "id": pid, "name": item["name"], "family": item["family"], "rare": False,
            "liquid_ramp": new["ramp"], "liquid_color": new["liquid"],
            "bottle_path": f"art/mockups/f26-region-potions-v1/sprites/{pid}_bottle.png",
            "bottle_size": list(sprite["native_size"]),
            "body_silhouette_source": f"art/mockups/f26-region-potions-v1/sprites/{pid}_bottle.png",
            "runtime_bottle_source": f"art/mockups/f26-region-potions-v1/sprites/{pid}_bottle.png",
            "pot_frames": [f"art/mockups/f26-region-potions-v1/pots/{pid}-{i}.png" for i in range(3)],
            "bottle": f"res://assets/pixel_v1/potions/{pid}.png",
            "pots": pots,
        })
    for sprite_id, target in ICONS:
        copy(MOCK / f"sprites/{sprite_id}.png", EXPANSION / target)
    for cid, rows in bindings(liquids).items():
        for pid, binding in rows.items():
            if not all(check["passed"] for check in binding["checks"]):
                raise SystemExit(f"{cid}/{pid}: no passing hand grip")
            add(catalog["characters"][cid]["bindings"], pid, binding)
    with open(catalog_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    print("Published F26 art: " + ", ".join(item["id"] for item in POTIONS) + " + dawn_bloom/dawn_lighthouse icons + customer bindings")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
