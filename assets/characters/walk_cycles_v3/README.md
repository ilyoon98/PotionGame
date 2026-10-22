# Walking assembly correction v3

Restores the original animation-v1 idle pixels above the legs, including clothing, instead of cropping at the waist. Traveler and keeper assets are unchanged. Previous v2 output is retained only as a rejected draft; the animation preview now consumes v3.

- Elf: original rows 0–47 preserved; short loincloth and bow restored.
- Mage: original rows 0–54 preserved; full robe silhouette restored.
- Rogue: original rows 0–47 preserved; shorts and thigh proportions restored.
- Four 48x64 walk frames, 96x128 row-major sheet, 8fps.
- The GIF's first character is the unchanged traveler idle for design comparison.

No new generation in this revision. Existing image_gen.imagegen lower-leg artwork is registered at the correct clothing boundary using `tools/prepare_walk_cycles_v3.gd`. Original generation prompts are in `assets/source/walk_cycles_v2/generation.json`. Actual game sprites are not changed.
