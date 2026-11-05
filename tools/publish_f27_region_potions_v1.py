"""Publish the approved F27 aurora-snowfield art into the runtime folders (additive only).

Approved 2026-11-05 ("그림은 그대로 수치만 바꿔": every candidate sprite exactly as is). Copies the validated
sprites from art/mockups/f27-region-potions-v1/ byte-for-byte, the same way as publish_f26_region_potions_v1.py:

  sprites/{id}_bottle.png  -> assets/pixel_v1/potions/{id}.png            (shelf/handover bottle, 8x12)
  pots/{id}-{0,1,2}.png    -> assets/pixel_v1/pots/{id}-{0,1,2}.png       (cauldron liquid frames, 32x32)
  sprites/{id}_icon.png    -> assets/content_expansion_v1/potions/{id}_icon.png   (32x40 potion icon)
  sprites/{id}_recipe.png  -> assets/content_expansion_v1/recipes/{id}_recipe.png (32x40 recipe icon)
  sprites/frost_flower_icon.png      -> assets/content_expansion_v1/materials/frost_flower_icon.png
  sprites/aurora_snowfield_icon.png  -> assets/content_expansion_v1/regions/aurora_snowfield_icon.png
  growth/frost_flower_growth.png     -> assets/content_expansion_v1/materials/frost_flower_growth.png (64x80 planter
                                        growth sheet; same out-of-rule exception as the other growth sheets)

and adds only:
  - assets/pixel_v1/catalog.json: four `potions` rows and their `sources` hashes, four `characters.<customer>.bindings`
    rows per customer (hand grip solved with the rule behind the existing bindings; the script first re-solves the
    existing 144 + 16 F26 bindings and stops unless all come out identical);
  - assets/content_expansion_v1/catalog.json: one `materials` row for frost flower (icon_path + growth_path), like the
    F26 dawn bloom row;
  - assets/ui_pixel_v2/: the list/recipe icon of each new potion, packaged with the same rule as
    tools/build_ui_pixel_v2_potions.py (approved bottle at exactly 2x on a transparent 32x32 canvas, no repainting), and
    the catalog keys `{id}` and `recipe:{id}`. The rule is first re-run on the existing 40 potions and must reproduce
    their published icons pixel for pixel.

No new art is made. The UI v2 32x32 region/material icons are freshly generated art (not a packaging of an approved
sprite), so none is made for aurora_snowfield/frost_flower: they keep their approved 32x40 F27 icons (ItemArt falls
back when the UI v2 catalog has no entry). Existing files and catalog rows are never rewritten: an identical existing
row is kept, a different one stops the script. Needs Pillow + NumPy, e.g.
  C:\\Users\\imtl\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\python\\python.exe tools/publish_f27_region_potions_v1.py
"""
from __future__ import annotations

import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOCK = ROOT / "art/mockups/f27-region-potions-v1"
MOCK_REL = "art/mockups/f27-region-potions-v1"
PIXEL = ROOT / "assets/pixel_v1"
EXPANSION = ROOT / "assets/content_expansion_v1"
UI = ROOT / "assets/ui_pixel_v2"
CUSTOMERS = ("traveler", "mage", "elf", "rogue")
F26_POTIONS = ("sunrise", "beacon", "sea_spray", "sun_moon_elixir")
# Names and families follow data/content_expansion.json; liquid colours the approved validation.json.
POTIONS = (
    {"id": "warmth", "name": "온기", "family": "vitality"},
    {"id": "thin_ice", "name": "살얼음", "family": "craft"},
    {"id": "pine_wind", "name": "솔바람", "family": "nature"},
    {"id": "aurora_elixir", "name": "오로라의 물약", "family": "arcane"},
)
ICONS = (("frost_flower_icon", "materials/frost_flower_icon.png"), ("aurora_snowfield_icon", "regions/aurora_snowfield_icon.png"))
GROWTH = ("growth/frost_flower_growth.png", "materials/frost_flower_growth.png")


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, data, trailing_newline: bool = True) -> None:
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(data, ensure_ascii=False, indent=2) + ("\n" if trailing_newline else ""))


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


def ramp_of(colour: str) -> str:
    ramps = read(ROOT / "art/ramps.json")["ramps"]
    names = [name for name, ramp in ramps.items() if name != "outline" and colour.upper() in (c.upper() for c in ramp["colors"])]
    if len(names) != 1:
        raise SystemExit(f"{colour}: expected exactly one approved ramp, got {names}")
    return names[0]


def bindings(liquids: dict) -> dict:
    sys.path.insert(0, str(ROOT / "tools"))
    import build_flying_workshop_v9 as v9  # the rule behind the existing catalog bindings

    catalog = read(PIXEL / "catalog.json")
    recipes = read(v9.ENV / "potions/recipes.json")["recipes"]
    f26_report = read(ROOT / "art/mockups/f26-region-potions-v1/validation.json")
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
        for pid in F26_POTIONS:
            bottle = ROOT / f"art/mockups/f26-region-potions-v1/sprites/{pid}_bottle.png"
            liquid = f26_report["liquid_colours"]["new"][pid]["liquid"]
            if v9.catch_binding(cid, {"id": pid, "bottle_path": str(bottle), "liquid_color": liquid}, frames, grips) != catalog["characters"][cid]["bindings"][pid]:
                raise SystemExit(f"{cid}/{pid}: re-solved F26 binding differs; rule mismatch")
        result[cid] = {}
        for item in POTIONS:
            pid = item["id"]
            bottle = MOCK / f"sprites/{pid}_bottle.png"
            # An absolute bottle_path replaces v9's ENV/potions prefix (pathlib join with an absolute path).
            result[cid][pid] = v9.catch_binding(cid, {"id": pid, "bottle_path": str(bottle), "liquid_color": liquids[pid]}, frames, grips)
    return result


def ui_icons(catalog: dict) -> dict:
    """Package the new bottles with the exact UI v2 rule after proving it reproduces the published 40."""
    sys.path.insert(0, str(ROOT / "tools"))
    import numpy as np
    from PIL import Image
    import build_ui_pixel_v2_potions as ui

    palette = ui.palette(ROOT / "art/palette.hex")
    ui_catalog = read(UI / "catalog.json")
    existing = {pid: row for pid, row in catalog["potions"].items() if pid not in {p["id"] for p in POTIONS}}
    images, index, report = ui.package_potions({"potions": existing}, palette)
    for pid, image in images.items():
        published = UI / "icons" / f"{pid}.png"
        if ui_catalog["icons"].get(pid) != index[pid] or ui_catalog["icons"].get("recipe:" + pid) != index[pid]:
            raise SystemExit(f"{pid}: UI v2 catalog keys differ from the packaging rule")
        if not np.array_equal(np.asarray(Image.open(published).convert("RGBA")), np.asarray(image)):
            raise SystemExit(f"{pid}: re-packaged UI v2 icon differs from the published one; rule mismatch")
    new = {p["id"]: catalog["potions"][p["id"]] for p in POTIONS}
    images, index, report = ui.package_potions({"potions": new}, palette)
    if report["status"] != "passed":
        raise SystemExit("UI v2 packaging validation failed: " + json.dumps(report, ensure_ascii=False)[:400])
    for pid, image in images.items():
        dest = UI / "icons" / f"{pid}.png"
        if dest.exists() and not np.array_equal(np.asarray(Image.open(dest).convert("RGBA")), np.asarray(image)):
            raise SystemExit(f"Refusing to overwrite a different existing UI icon: {dest.relative_to(ROOT)}")
        image.save(dest)
        if Image.open(dest).convert("RGBA").tobytes() != image.tobytes():
            raise SystemExit(f"PNG roundtrip changed {pid}")
        import_settings(dest)
        report["icons"][pid]["png_rgba_roundtrip_exact"] = True
        report["icons"][pid]["output_sha256"] = sha256(dest)
        add(ui_catalog["icons"], pid, index[pid])
        add(ui_catalog["icons"], "recipe:" + pid, index[pid])
    write(UI / "catalog.json", ui_catalog)
    write(MOCK / "ui-pixel-v2-potions.json", report)
    return index


def main() -> int:
    approval = read(MOCK / "approval.json")
    report = read(MOCK / "validation.json")
    if approval.get("status") != "approved" or not approval.get("approved_by_user") or report.get("status") != "passed":
        raise SystemExit("Only passed, user-approved art is published")
    catalog_path = PIXEL / "catalog.json"
    catalog = read(catalog_path)
    if json.dumps(catalog, ensure_ascii=False, indent=2) + "\n" != catalog_path.read_text(encoding="utf-8"):
        raise SystemExit("pixel_v1 catalog formatting changed; refusing to rewrite it")
    liquids = {}
    for item in POTIONS:
        pid = item["id"]
        new = report["liquid_colours"]["new"][pid]
        sprite = report["sprites"][pid + "_bottle"]
        pot = report["pots"]["potions"][pid]
        if not pot["passed"] or pot["liquid"] != new["liquid"] or not sprite.get("passed", True):
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
            "liquid_ramp": ramp_of(new["liquid"]), "liquid_color": new["liquid"],
            "bottle_path": f"{MOCK_REL}/sprites/{pid}_bottle.png",
            "bottle_size": list(sprite["native_size"]),
            "body_silhouette_source": f"{MOCK_REL}/sprites/{pid}_bottle.png",
            "runtime_bottle_source": f"{MOCK_REL}/sprites/{pid}_bottle.png",
            "pot_frames": [f"{MOCK_REL}/pots/{pid}-{i}.png" for i in range(3)],
            "bottle": f"res://assets/pixel_v1/potions/{pid}.png",
            "pots": pots,
        })
    for sprite_id, target in ICONS:
        copy(MOCK / f"sprites/{sprite_id}.png", EXPANSION / target)
    growth = report["growth"]
    import numpy as np
    from PIL import Image
    # validation.json records the hash of the sheet's RGBA pixel array (build_f27_region_potions_v1.py).
    pixels_hash = hashlib.sha256(np.array(Image.open(MOCK / GROWTH[0]).convert("RGBA")).tobytes()).hexdigest()
    if not growth["checks"]["passed"] or pixels_hash != growth["native_sha256"]:
        raise SystemExit("Growth sheet differs from the validated candidate")
    copy(MOCK / GROWTH[0], EXPANSION / GROWTH[1])
    for cid, rows in bindings(liquids).items():
        for pid, binding in rows.items():
            if not all(check["passed"] for check in binding["checks"]):
                raise SystemExit(f"{cid}/{pid}: no passing hand grip")
            add(catalog["characters"][cid]["bindings"], pid, binding)
    write(catalog_path, catalog)
    # Content-expansion catalog: one materials row (like the F26 dawn bloom row), so ItemArt finds the growth sheet.
    expansion_path = EXPANSION / "catalog.json"
    expansion = read(expansion_path)
    if json.dumps(expansion, ensure_ascii=False, indent=2) != expansion_path.read_text(encoding="utf-8"):
        raise SystemExit("content_expansion_v1 catalog formatting changed; refusing to rewrite it")
    row = {
        "category": "materials",
        "growth_path": "res://assets/content_expansion_v1/" + GROWTH[1],
        "growth_source": "res://" + MOCK_REL + "/" + GROWTH[0],
        "icon_path": "res://assets/content_expansion_v1/materials/frost_flower_icon.png",
        "id": "frost_flower",
        "name": "서리꽃",
        "status": "approved_2026-11-05",
    }
    existing = [asset for asset in expansion["assets"] if asset["id"] == "frost_flower" and asset["category"] == "materials"]
    if existing and existing != [row]:
        raise SystemExit("content_expansion_v1 catalog already has a different frost_flower row")
    if not existing:
        expansion["assets"].append(row)
    write(expansion_path, expansion, trailing_newline=False)
    ui_icons(read(catalog_path))
    print("Published F27 art: " + ", ".join(item["id"] for item in POTIONS) + " + frost_flower/aurora_snowfield icons + frost_flower growth sheet + customer bindings + UI v2 potion/recipe icons")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
