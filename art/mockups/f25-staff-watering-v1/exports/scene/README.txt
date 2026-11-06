watering_scene — Pixelbolt export

watering_scene.png: transparent RGBA sprite sheet
watering_scene.atlas.json: TexturePacker-style frames, named animation sequences and Aseprite-style frame tags
watering_scene.tres: Godot 4 SpriteFrames; it finds watering_scene.png in its own folder, so keep the two together
watering_scene.css: CSS classes with per-frame timing
frames/: individual PNGs
animations/: animated PNGs (APNG)
watering_scene.pixel.json: editable source
player.js: dependency-free Canvas player
preview.html: open directly in a browser, or serve this folder

Canvas: import { SpritePlayer } from './player.js';
const player = await SpritePlayer.load(canvas, './watering_scene.atlas.json');
player.play('watering');

Godot 4: copy watering_scene.png and watering_scene.tres into one folder of your project, give an AnimatedSprite2D the Sprite Frames watering_scene.tres and play("watering"). Set the node's Texture Filter to Nearest for crisp pixels.

CSS: <link rel="stylesheet" href="watering_scene.css">
<span class="pf-watering_scene pf-watering_scene-watering"></span>

Timing:
watering: 24 frames of 100 to 1400 ms, 5200 ms in all, plays once
