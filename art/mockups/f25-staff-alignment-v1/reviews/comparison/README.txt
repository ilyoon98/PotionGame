staff_alignment_comparison — Pixelbolt export

staff_alignment_comparison.png: transparent RGBA sprite sheet
staff_alignment_comparison.atlas.json: TexturePacker-style frames, named animation sequences and Aseprite-style frame tags
staff_alignment_comparison.tres: Godot 4 SpriteFrames; it finds staff_alignment_comparison.png in its own folder, so keep the two together
staff_alignment_comparison.css: CSS classes with per-frame timing
frames/: individual PNGs
animations/: animated PNGs (APNG)
staff_alignment_comparison.pixel.json: editable source
player.js: dependency-free Canvas player
preview.html: open directly in a browser, or serve this folder

Canvas: import { SpritePlayer } from './player.js';
const player = await SpritePlayer.load(canvas, './staff_alignment_comparison.atlas.json');
player.play('default');

Godot 4: copy staff_alignment_comparison.png and staff_alignment_comparison.tres into one folder of your project, give an AnimatedSprite2D the Sprite Frames staff_alignment_comparison.tres and play("default"). Set the node's Texture Filter to Nearest for crisp pixels.

CSS: <link rel="stylesheet" href="staff_alignment_comparison.css">
<span class="pf-staff_alignment_comparison pf-staff_alignment_comparison-default"></span>
