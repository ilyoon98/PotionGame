"""Register the generated portrait, then use the shared pixel-art pipeline."""
import json
import shutil
import subprocess
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / "art/easter-eggs/window-visitor-pixel-v1"
SOURCE = FOLDER / "source/generated.png"
# One crop of the same complete portrait: enlarge its glasses/expression within
# the 20x16 viewport. Never combine features from other images or repaint them.
CROP = (280, 55, 1120, 727)
image = Image.open(SOURCE).convert("RGBA")
image.crop(CROP).save(FOLDER / "source/registered.png")
(FOLDER / "source/registration.json").write_text(json.dumps({
    "source": str(SOURCE.relative_to(ROOT)), "crop": CROP,
    "target": [20,16], "purpose": "face-and-glasses framing for window viewport",
}, indent=2)+"\n", encoding="utf-8")
subprocess.run([sys.executable, str(ROOT / "tools/process_pixel_art.py"),
                "art/easter-eggs/window-visitor-pixel-v1/manifest.json"], cwd=ROOT, check=True)
report = json.loads((FOLDER / "validation.json").read_text(encoding="utf-8"))
assert report["status"] == "passed"
shutil.copyfile(FOLDER / "window-visitor-native.png", ROOT / "assets/easter_eggs/window-visitor-pixel-v1.png")
