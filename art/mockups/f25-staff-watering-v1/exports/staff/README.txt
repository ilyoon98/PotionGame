staff_cultivation_watering — Pixelbolt export

staff_cultivation_watering.png: transparent RGBA sprite sheet
staff_cultivation_watering.atlas.json: TexturePacker-style frames, named animation sequences and Aseprite-style frame tags
staff_cultivation_watering.tres: Godot 4 SpriteFrames; it finds staff_cultivation_watering.png in its own folder, so keep the two together
staff_cultivation_watering.css: CSS classes with per-frame timing
frames/: individual PNGs
animations/: animated PNGs (APNG)
staff_cultivation_watering.pixel.json: editable source
player.js: dependency-free Canvas player
preview.html: open directly in a browser, or serve this folder

Canvas: import { SpritePlayer } from './player.js';
const player = await SpritePlayer.load(canvas, './staff_cultivation_watering.atlas.json');
player.play('still');

Godot 4: copy staff_cultivation_watering.png and staff_cultivation_watering.tres into one folder of your project, give an AnimatedSprite2D the Sprite Frames staff_cultivation_watering.tres and play("still"). Set the node's Texture Filter to Nearest for crisp pixels.

CSS: <link rel="stylesheet" href="staff_cultivation_watering.css">
<span class="pf-staff_cultivation_watering pf-staff_cultivation_watering-still"></span>

Timing:
watering: 9 frames of 180 to 1600 ms, 5200 ms in all, plays once
