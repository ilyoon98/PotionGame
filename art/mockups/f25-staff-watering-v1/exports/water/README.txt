watering_fx — Pixelbolt export

watering_fx.png: transparent RGBA sprite sheet
watering_fx.atlas.json: TexturePacker-style frames, named animation sequences and Aseprite-style frame tags
watering_fx.tres: Godot 4 SpriteFrames; it finds watering_fx.png in its own folder, so keep the two together
watering_fx.css: CSS classes with per-frame timing
frames/: individual PNGs
animations/: animated PNGs (APNG)
watering_fx.pixel.json: editable source
player.js: dependency-free Canvas player
preview.html: open directly in a browser, or serve this folder

Canvas: import { SpritePlayer } from './player.js';
const player = await SpritePlayer.load(canvas, './watering_fx.atlas.json');
player.play('flow');

Godot 4: copy watering_fx.png and watering_fx.tres into one folder of your project, give an AnimatedSprite2D the Sprite Frames watering_fx.tres and play("flow"). Set the node's Texture Filter to Nearest for crisp pixels.

CSS: <link rel="stylesheet" href="watering_fx.css">
<span class="pf-watering_fx pf-watering_fx-flow"></span>

Timing:
flow: 4 frames of 100 ms (10 fps)
