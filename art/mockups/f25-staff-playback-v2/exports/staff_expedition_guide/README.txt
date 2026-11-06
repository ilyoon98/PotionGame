staff_expedition_guide — Pixelbolt export

staff_expedition_guide.png: transparent RGBA sprite sheet
staff_expedition_guide.atlas.json: TexturePacker-style frames, named animation sequences and Aseprite-style frame tags
staff_expedition_guide.tres: Godot 4 SpriteFrames; it finds staff_expedition_guide.png in its own folder, so keep the two together
staff_expedition_guide.css: CSS classes with per-frame timing
frames/: individual PNGs
animations/: animated PNGs (APNG)
staff_expedition_guide.pixel.json: editable source
player.js: dependency-free Canvas player
preview.html: open directly in a browser, or serve this folder

Canvas: import { SpritePlayer } from './player.js';
const player = await SpritePlayer.load(canvas, './staff_expedition_guide.atlas.json');
player.play('still');

Godot 4: copy staff_expedition_guide.png and staff_expedition_guide.tres into one folder of your project, give an AnimatedSprite2D the Sprite Frames staff_expedition_guide.tres and play("still"). Set the node's Texture Filter to Nearest for crisp pixels.

CSS: <link rel="stylesheet" href="staff_expedition_guide.css">
<span class="pf-staff_expedition_guide pf-staff_expedition_guide-still"></span>

Timing:
idle: 21 frames of 50 to 1850 ms, 18000 ms in all
