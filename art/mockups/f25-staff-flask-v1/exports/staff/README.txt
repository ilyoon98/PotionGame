staff_brewing_flask — Pixelbolt export

staff_brewing_flask.png: transparent RGBA sprite sheet
staff_brewing_flask.atlas.json: TexturePacker-style frames, named animation sequences and Aseprite-style frame tags
staff_brewing_flask.tres: Godot 4 SpriteFrames; it finds staff_brewing_flask.png in its own folder, so keep the two together
staff_brewing_flask.css: CSS classes with per-frame timing
frames/: individual PNGs
animations/: animated PNGs (APNG)
staff_brewing_flask.pixel.json: editable source
player.js: dependency-free Canvas player
preview.html: open directly in a browser, or serve this folder

Canvas: import { SpritePlayer } from './player.js';
const player = await SpritePlayer.load(canvas, './staff_brewing_flask.atlas.json');
player.play('still');

Godot 4: copy staff_brewing_flask.png and staff_brewing_flask.tres into one folder of your project, give an AnimatedSprite2D the Sprite Frames staff_brewing_flask.tres and play("still"). Set the node's Texture Filter to Nearest for crisp pixels.

CSS: <link rel="stylesheet" href="staff_brewing_flask.css">
<span class="pf-staff_brewing_flask pf-staff_brewing_flask-still"></span>

Timing:
shake: 18 frames of 100 to 2440 ms, 6000 ms in all, plays once
