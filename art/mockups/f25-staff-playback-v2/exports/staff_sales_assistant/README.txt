staff_sales_assistant — Pixelbolt export

staff_sales_assistant.png: transparent RGBA sprite sheet
staff_sales_assistant.atlas.json: TexturePacker-style frames, named animation sequences and Aseprite-style frame tags
staff_sales_assistant.tres: Godot 4 SpriteFrames; it finds staff_sales_assistant.png in its own folder, so keep the two together
staff_sales_assistant.css: CSS classes with per-frame timing
frames/: individual PNGs
animations/: animated PNGs (APNG)
staff_sales_assistant.pixel.json: editable source
player.js: dependency-free Canvas player
preview.html: open directly in a browser, or serve this folder

Canvas: import { SpritePlayer } from './player.js';
const player = await SpritePlayer.load(canvas, './staff_sales_assistant.atlas.json');
player.play('still');

Godot 4: copy staff_sales_assistant.png and staff_sales_assistant.tres into one folder of your project, give an AnimatedSprite2D the Sprite Frames staff_sales_assistant.tres and play("still"). Set the node's Texture Filter to Nearest for crisp pixels.

CSS: <link rel="stylesheet" href="staff_sales_assistant.css">
<span class="pf-staff_sales_assistant pf-staff_sales_assistant-still"></span>

Timing:
idle: 21 frames of 100 to 1800 ms, 18000 ms in all
