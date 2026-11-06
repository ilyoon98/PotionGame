staff_brewing_assistant — Pixelbolt export

staff_brewing_assistant.png: transparent RGBA sprite sheet
staff_brewing_assistant.atlas.json: TexturePacker-style frames, named animation sequences and Aseprite-style frame tags
staff_brewing_assistant.tres: Godot 4 SpriteFrames; it finds staff_brewing_assistant.png in its own folder, so keep the two together
staff_brewing_assistant.css: CSS classes with per-frame timing
frames/: individual PNGs
animations/: animated PNGs (APNG)
staff_brewing_assistant.pixel.json: editable source
player.js: dependency-free Canvas player
preview.html: open directly in a browser, or serve this folder

Canvas: import { SpritePlayer } from './player.js';
const player = await SpritePlayer.load(canvas, './staff_brewing_assistant.atlas.json');
player.play('still');

Godot 4: copy staff_brewing_assistant.png and staff_brewing_assistant.tres into one folder of your project, give an AnimatedSprite2D the Sprite Frames staff_brewing_assistant.tres and play("still"). Set the node's Texture Filter to Nearest for crisp pixels.

CSS: <link rel="stylesheet" href="staff_brewing_assistant.css">
<span class="pf-staff_brewing_assistant pf-staff_brewing_assistant-still"></span>

Timing:
idle: 19 frames of 200 to 1750 ms, 18000 ms in all
