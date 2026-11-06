staff_sales_greeting — Pixelbolt export

staff_sales_greeting.png: transparent RGBA sprite sheet
staff_sales_greeting.atlas.json: TexturePacker-style frames, named animation sequences and Aseprite-style frame tags
staff_sales_greeting.tres: Godot 4 SpriteFrames; it finds staff_sales_greeting.png in its own folder, so keep the two together
staff_sales_greeting.css: CSS classes with per-frame timing
frames/: individual PNGs
animations/: animated PNGs (APNG)
staff_sales_greeting.pixel.json: editable source
player.js: dependency-free Canvas player
preview.html: open directly in a browser, or serve this folder

Canvas: import { SpritePlayer } from './player.js';
const player = await SpritePlayer.load(canvas, './staff_sales_greeting.atlas.json');
player.play('still');

Godot 4: copy staff_sales_greeting.png and staff_sales_greeting.tres into one folder of your project, give an AnimatedSprite2D the Sprite Frames staff_sales_greeting.tres and play("still"). Set the node's Texture Filter to Nearest for crisp pixels.

CSS: <link rel="stylesheet" href="staff_sales_greeting.css">
<span class="pf-staff_sales_greeting pf-staff_sales_greeting-still"></span>

Timing:
greet: 14 frames of 140 to 2140 ms, 6000 ms in all, plays once
