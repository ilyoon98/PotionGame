/** Reproducible Pixelbolt alignment candidate. The editable text grids are authoritative. */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { renderProject, encodePNG, importPNG, formatJSON, decodePNG } from './pixelbolt/node_modules/pixelbolt/src/index.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'art/mockups/f25-staff-alignment-v1');
const OLD = path.join(ROOT, 'art/mockups/f25-staff-motion-v1/source');
const CLI = path.join(ROOT, 'tools/pixelbolt/node_modules/pixelbolt/bin/pixelbolt.js');
const rel = p => path.relative(ROOT, p).replaceAll('\\', '/');
const json = (p, v) => fs.writeFileSync(p, JSON.stringify(v, null, 2) + '\n');
const read = p => JSON.parse(fs.readFileSync(p, 'utf8'));
const hash = b => createHash('sha256').update(b).digest('hex');
const meta = read(path.join(OLD, 'generation.json'));
const sourceNotes = read(path.join(OUT, 'source/alignment-notes.json'));
const NOTES = { standard: sourceNotes.standard || sourceNotes.common_landmarks, assets: Array.isArray(sourceNotes.assets) ? Object.fromEntries(sourceNotes.assets.map(a => [a.id, { ...a, eyes: a.eyes || { x: a.eyes_x, y: a.eyes_y } }])) : sourceNotes.assets };
const palette = Object.fromEntries(Object.entries(meta.legend).map(([k, v]) => [k, v.color]));
const approved = new Set(fs.readFileSync(path.join(ROOT, 'art/palette.hex'), 'utf8').trim().split(/\r?\n/).map(x => '#' + x.toUpperCase()));
if (read(path.join(ROOT, 'tools/pixelbolt/node_modules/pixelbolt/package.json')).version !== '0.11.0') throw Error('Requires the pinned Pixelbolt 0.11.0');
for (const folder of ['before', 'after', 'references', 'recipes', 'exports', 'reviews', 'logs', 'pipeline']) fs.mkdirSync(path.join(OUT, folder), { recursive: true });
json(path.join(OUT, 'validation.json'), { status: 'building', art_status: 'candidate', runtime_integrated: false });
fs.copyFileSync(path.join(ROOT, 'tools/pixelbolt/node_modules/pixelbolt/LICENSE'), path.join(OUT, 'PIXELBOLT-LICENSE.txt'));
const commands = [];
function command(name, args, label) {
  const run = spawnSync(process.execPath, [CLI, name, ...args, ...(name === 'validate' ? [] : ['--force'])], { cwd: ROOT, encoding: 'utf8', maxBuffer: 24 * 1024 * 1024 });
  commands.push({ command: name, arguments: args.map(a => path.isAbsolute(a) ? rel(a) : a), exit: run.status });
  if (run.status !== 0) throw Error(`${label}: ${run.stderr || run.stdout}`);
  const parsed = JSON.parse(run.stdout);
  // Keep evidence portable across clones and user accounts.
  json(path.join(OUT, 'logs', label + '.json'), JSON.parse(JSON.stringify(parsed).replaceAll(ROOT.replaceAll('\\', '\\\\'), '.').replaceAll(ROOT.replaceAll('\\', '/'), '.')));
  return parsed;
}
function rgba(data, x, y) { return [...data.slice((y * 32 + x) * 4, (y * 32 + x) * 4 + 4)]; }
function color(data, x, y) { const p = rgba(data, x, y); return p[3] ? '#' + p.slice(0, 3).map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase() : 'transparent'; }
function metrics(frame) {
  const colors = new Set(), boundary = [], partial = [];
  let bottom = -1;
  const visible = (x, y) => x >= 0 && x < 32 && y >= 0 && y < 48 && frame.data[(y * 32 + x) * 4 + 3] !== 0;
  for (let y = 0; y < 48; y++) for (let x = 0; x < 32; x++) {
    const a = frame.data[(y * 32 + x) * 4 + 3];
    if (a !== 0 && a !== 255) partial.push([x, y]);
    if (!a) continue;
    bottom = Math.max(bottom, y);
    const c = color(frame.data, x, y); colors.add(c);
    if ([[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]].some(([xx, yy]) => !visible(xx, yy)) && c !== '#241C32') boundary.push([x, y]);
  }
  return { colors: [...colors].sort(), partial_alpha: partial, invalid_boundary: boundary, foot_row: bottom, outside_palette: [...colors].filter(c => !approved.has(c)) };
}
function diff(a, b) { let n = 0; for (let i = 0; i < a.length; i += 4) if ([0, 1, 2, 3].some(k => a[i + k] !== b[i + k])) n++; return n; }
function gridFile(file) { const rows = fs.readFileSync(file, 'utf8').trimEnd().split(/\r?\n/); if (rows.length !== 48 || rows.some(r => r.length !== 32)) throw Error('Expected 32x48 text grid: ' + file); return rows; }
function gridRecipe(name, rows) { return { version: 1, name, width: 32, height: 48, palette, anchor: [14, 46], frames: [{ name: 'still', duration: 1000, ops: [{ op: 'grid', rows }] }], animations: { still: { frames: ['still'], loop: true } }, sheet: { columns: 4, scale: 1, trim: false } }; }
function framePng(file, frame) { fs.writeFileSync(file, encodePNG(frame.data, 32, 48)); }
function timeline() {
  const points = new Set([0, 750, 2250, 3750, 4280, 4400, 5250, 6750, 8250, 8780, 8900, 9000]);
  const sorted = [...points].sort((a, b) => a - b);
  return sorted.slice(0, -1).map((t, i) => ({ name: `idle_${i}`, time: t, duration: sorted[i + 1] - t, breath: t % 3000 >= 750 && t % 3000 < 2250, blink: t % 4500 >= 4280 && t % 4500 < 4400 }));
}
const phases = timeline();
const results = [], previews = [], allFrames = [];
const IDs = ['staff_sales_assistant', 'staff_cultivation_assistant', 'staff_brewing_assistant', 'staff_expedition_guide'];
for (const id of IDs) {
  const note = NOTES.assets[id];
  if (!note?.eyes) throw Error('Missing reviewed eye landmarks: ' + id);
  const rows = gridFile(path.join(OUT, 'source', id + '.txt'));
  const oldPath = path.join(OLD, id + '.png');
  fs.copyFileSync(oldPath, path.join(OUT, 'before', id + '.png'));
  const old = decodePNG(fs.readFileSync(oldPath));
  const base = gridRecipe(id, rows);
  const skinSymbol = Object.entries(palette).find(([k, c]) => c === meta.staff[id].materials.skin || c === meta.staff[id].materials.skin_tan)?.[0];
  if (!skinSymbol) throw Error('Missing skin material: ' + id);
  const blink = rows.map(r => [...r]);
  for (const x of note.eyes.x) {
    if (rows[22][x] !== '#' || rows[23][x] !== '#') throw Error(`${id}: eyes not at 22/23`);
    blink[22][x] = skinSymbol;
  }
  const toRows = matrix => matrix.map(r => Array.isArray(r) ? r.join('') : r);
  const breath = source => source.map((row, y) => [...row].map((c, x) => y < 30 && (id !== 'staff_expedition_guide' || (x >= 8 && y >= 7)) ? source[y + 1][x] : c).join(''));
  const states = { still: rows, inhale: breath(rows), blink: toRows(blink), inhale_blink: breath(toRows(blink)) };
  base.frames = Object.entries(states).map(([name, r]) => ({ name, duration: 1000, ops: [{ op: 'grid', rows: r }] }));
  for (const p of phases) base.frames.push({ name: p.name, from: p.breath ? (p.blink ? 'inhale_blink' : 'inhale') : (p.blink ? 'blink' : 'still'), duration: p.duration });
  base.animations.idle = { frames: phases.map(p => p.name), loop: true };
  const rendered = renderProject(base), still = rendered.frames[0];
  const originalColors = metrics({ data: old.data }).colors;
  if (JSON.stringify(metrics(still).colors) !== JSON.stringify(originalColors)) throw Error('Original role colors changed: ' + id);
  const checkpoints = { neck: [14, 27], chest: [14, 31], waist: [14, 35], hip: [14, 37], left_knee: [12, 40], right_knee: [17, 40], left_foot: [11, 46], right_foot: [17, 46] };
  const sampled = Object.fromEntries(Object.entries(checkpoints).map(([k, [x, y]]) => [k, { position: [x, y], pixel: color(still.data, x, y) }]));
  if (Object.values(sampled).some(v => v.pixel === 'transparent')) throw Error(`${id}: empty anatomical landmark: ${JSON.stringify(sampled)}`);
  const masks = note.semantic_masks;
  if (!masks) throw Error('Missing independently reviewed anatomical regions: ' + id);
  const expandRuns = runs => runs.flatMap(([y, x0, x1]) => Array.from({ length: x1 - x0 + 1 }, (_, i) => [x0 + i, y]));
  const inRuns = (runs, x, y) => runs.some(([yy, x0, x1]) => yy === y && x >= x0 && x <= x1);
  for (const mask of Object.values(masks)) if (!mask.interior_colors) {
    const pixels = expandRuns(mask.runs);
    mask.outline_color = '#241C32';
    mask.interior_colors = mask.interior_chars.map(c => palette[c]);
    mask.interior_runs = pixels.filter(([x, y]) => mask.interior_chars.includes(rows[y][x])).map(([x, y]) => [y, x, x]);
    mask.pixel_count = pixels.length;
    mask.bbox = pixels.length ? [Math.min(...pixels.map(p => p[0])), Math.min(...pixels.map(p => p[1])), Math.max(...pixels.map(p => p[0])) + 1, Math.max(...pixels.map(p => p[1])) + 1] : null;
  }
  const semanticChecks = {};
  for (const [part, mask] of Object.entries(masks)) {
    const pixels = expandRuns(mask.runs);
    const allowedColors = mask.allowed_chars ? mask.allowed_chars.map(c => palette[c]) : [mask.outline_color, ...mask.interior_colors];
    for (const [x, y] of pixels) if (!allowedColors.includes(color(still.data, x, y))) throw Error(`${id}/${part}: unexpected material at ${x},${y}`);
    if (mask.expected_counts) {
      const counts = {};
      for (const [x, y] of pixels) counts[rows[y][x]] = (counts[rows[y][x]] || 0) + 1;
      const keys = new Set([...Object.keys(counts), ...Object.keys(mask.expected_counts)]);
      for (const key of keys) if ((counts[key] || 0) !== (mask.expected_counts[key] || 0)) throw Error(`${id}/${part}: outdated material count for ${key}`);
    }
    for (const [x, y] of expandRuns(mask.interior_runs)) if (!mask.interior_colors.includes(color(still.data, x, y))) throw Error(`${id}/${part}: lost interior at ${x},${y}`);
    if (pixels.length !== mask.pixel_count) throw Error('Outdated anatomical mask: ' + id + '/' + part);
    semanticChecks[part] = { pixels: pixels.length, material_check: true, bbox: mask.bbox };
    if (part === 'left_leg' || part === 'right_leg') {
      const set = new Set(pixels.map(([x, y]) => `${x},${y}`)), visited = new Set(), queue = [pixels[0]];
      while (queue.length) {
        const [x, y] = queue.pop(), key = `${x},${y}`;
        if (visited.has(key) || !set.has(key)) continue;
        visited.add(key);
        for (const [xx, yy] of [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]]) queue.push([xx, yy]);
      }
      if (visited.size !== pixels.length || Math.min(...pixels.map(p => p[1])) !== 40 || Math.max(...pixels.map(p => p[1])) !== 46) throw Error(`${id}/${part}: disconnected or misaligned leg`);
      semanticChecks[part].connected_knee_to_ground = true;
    }
  }
  const landmarkParts = { neck: 'neck', chest: 'torso_core', waist: 'waist', hip: 'hip', left_knee: 'left_leg', right_knee: 'right_leg', left_foot: 'left_leg', right_foot: 'right_leg' };
  for (const [landmark, part] of Object.entries(landmarkParts)) {
    const [x, y] = checkpoints[landmark];
    const mask = masks[part];
    if (!inRuns(landmark.endsWith('foot') ? mask.runs : mask.interior_runs, x, y)) throw Error(`${id}: ${landmark} falls outside its reviewed ${part} region`);
  }
  const frameChecks = rendered.frames.map(f => {
    const check = metrics(f);
    const lowerChanged = diff(f.data.slice(30 * 32 * 4), still.data.slice(30 * 32 * 4));
    const phase = phases.find(p => p.name === f.name);
    const raised = f.name.startsWith('inhale') || phase?.breath;
    const closed = f.name.includes('blink') || phase?.blink;
    const topEyeY = 22 - (raised ? 1 : 0), lowEyeY = topEyeY + 1;
    for (const x of note.eyes.x) {
      for (let y = (closed ? lowEyeY : topEyeY) - 1; y <= lowEyeY + 1; y++) for (let xx = x - 1; xx <= x + 1; xx++) {
        const pupil = xx === x && (y === lowEyeY || (!closed && y === topEyeY));
        if (color(f.data, xx, y) !== (pupil ? '#241C32' : palette[skinSymbol])) throw Error(`${id}/${f.name}: pupil or skin margin at ${xx},${y}`);
      }
    }
    for (let y = 40; y <= 46; y++) if (color(f.data, 14, y) !== 'transparent') throw Error(`${id}/${f.name}: legs touch at 14,${y}`);
    if (id === 'staff_expedition_guide') for (let y = 0; y < 48; y++) for (let x = 0; x < 32; x++) {
      if ((x < 8 || y < 7) && color(f.data, x, y) !== color(still.data, x, y)) throw Error('Staff or lantern moves during idle');
    }
    for (const part of ['left_hand', 'right_hand', 'props']) for (const [x, y] of expandRuns(masks[part].runs)) if (color(f.data, x, y) !== color(still.data, x, y)) throw Error(`${id}/${f.name}: ${part} moved`);
    if (check.colors.length > 5 || check.partial_alpha.length || check.invalid_boundary.length || check.outside_palette.length || check.foot_row !== 46 || lowerChanged) throw Error(`${id}/${f.name}: ${JSON.stringify({ check, lowerChanged })}`);
    return { name: f.name, duration: f.duration, colors: check.colors.length, boundary_errors: 0, partial_alpha: 0, foot_row: 46, lower_body_changed: 0, eye_skin_margin: true, legs_separated: true, prop_fixed: true };
  });
  if (diff(rendered.frames.find(f => f.name === phases[0].name).data, rendered.frames.find(f => f.name === phases.at(-1).name).data)) throw Error('Loop seam: ' + id);
  const recipePath = path.join(OUT, 'recipes', id + '.json');
  fs.writeFileSync(recipePath, formatJSON(base));
  framePng(path.join(OUT, 'after', id + '.png'), still);
  command('validate', [recipePath], id + '-validate');
  const expectation = path.join(OUT, 'recipes', id + '.expect.json');
  json(expectation, { width: 32, height: 48, frames: 11, colors: 5, transparent: true, loop: true });
  const exported = command('render', [recipePath, '--out', path.join(OUT, 'exports', id), '--animation', 'idle', '--expect', expectation], id + '-render');
  if (exported.check?.ok === false) throw Error('Export check: ' + id);
  command('inspect', [recipePath, '--frames', 'still,inhale,blink,inhale_blink', '--out', path.join(OUT, 'reviews', id + '.png'), '--native', '--scale', '3', '--diagnostics'], id + '-inspect');
  command('gif', [recipePath, '--out', path.join(OUT, 'reviews', id + '.gif'), '--animation', 'idle', '--scale', '3'], id + '-gif');
  results.push({ id, name: meta.staff[id].name, before_sha256: hash(fs.readFileSync(oldPath)), after_sha256: hash(fs.readFileSync(path.join(OUT, 'after', id + '.png'))), changed_pixels: diff(old.data, still.data), eyes: note.eyes, landmarks: sampled, semantic_regions: semanticChecks, frames: frameChecks, loop_ms: 9000, loop_seam_changed: 0 });
  previews.push({ id, name: meta.staff[id].name, before: old, after: still, rows, note });
  for (const f of rendered.frames) allFrames.push({ id: id + '-' + f.name, source: rel(path.join(OUT, 'exports', id, 'frames', f.name + '.png')), source_id: id });
  console.log(`${meta.staff[id].name}: actual landmarks, 5 colors, outline and 9s loop verified`);
}

// Exact first registered frame of each existing character. Hats and props stay visible.
const references = [];
for (const id of ['keeper', 'traveler', 'mage', 'elf', 'rogue']) {
  const src = path.join(ROOT, `assets/pixel_v1/characters/${id}/idle-native.png`);
  const imported = importPNG(fs.readFileSync(src), { name: 'reference_' + id, atlas: { frames: { still: { frame: { x: 0, y: 0, w: 32, h: 48 }, duration: 1000 } }, meta: { scale: '1' } } });
  const recipe = imported.project || imported.recipe;
  const rendered = renderProject(recipe);
  const file = path.join(OUT, 'references', id + '.png');
  framePng(file, rendered.frames[0]);
  references.push({ id, image: file, source: rel(src), sha256: hash(fs.readFileSync(src)) });
}

// Use the project's existing material-aware pipeline; the native sprites must not be recolored.
const sourceManifest = read(path.join(OLD, 'original-manifest.json'));
const manifest = { ...sourceManifest, feature: 'F25 aligned staff candidate', output: rel(path.join(OUT, 'pipeline')), assets: allFrames.map(f => ({ ...sourceManifest.assets.find(a => a.id === f.source_id), id: f.id, source: f.source, position: [0, 0] })) };
json(path.join(OUT, 'manifest.json'), manifest);
const bundledPython = path.join(process.env.USERPROFILE || '', '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe');
const python = process.env.PYTHON || (fs.existsSync(bundledPython) ? bundledPython : 'python');
const pipeline = spawnSync(python, ['tools/process_pixel_art.py', rel(path.join(OUT, 'manifest.json'))], { cwd: ROOT, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
if (pipeline.status !== 0) throw Error(pipeline.stdout + pipeline.stderr);
for (const item of allFrames) {
  const a = decodePNG(fs.readFileSync(path.join(ROOT, item.source))), b = decodePNG(fs.readFileSync(path.join(OUT, 'pipeline', item.id + '-native.png')));
  if (diff(a.data, b.data)) throw Error('Material pipeline changed native art: ' + item.id);
}

// Before/after board: all characters remain at the same exact 3x, with anatomy guides behind them.
const board = { version: 1, name: 'staff_alignment_comparison', width: 208, height: 114, palette, frames: [{ name: 'comparison', ops: [] }], sheet: { scale: 3 } };
const ops = board.frames[0].ops;
ops.push({ op: 'rect', w: 208, h: 114, color: '#F3EFE5' });
for (const [row, kind] of ['before', 'after'].entries()) for (const [i, entry] of previews.entries()) {
  const x = 10 + i * 50, y = row === 0 ? 6 : 62;
  ops.push({ op: 'rect', x: x - 3, y: y - 2, w: 38, h: 51, color: '#E2E8DC' });
  for (const [yy, c] of [[11, '#B7C7D4'], [27, '#B7C7D4'], [31, '#D9B5AF'], [35, '#D8C9A4'], [40, '#B7C7D4'], [46, '#AABDA6']]) ops.push({ op: 'line', x: x - 2, x2: x + 33, y: y + yy, y2: y + yy, color: c });
  const sourceRows = kind === 'after' ? entry.rows : gridFile(path.join(OLD, entry.id + '.txt'));
  ops.push({ op: 'grid', x, y, rows: sourceRows });
}
fs.writeFileSync(path.join(OUT, 'recipes/comparison.json'), formatJSON(board));
// Export board scale through Pixelbolt's renderer rather than raster resampling.
command('render', [path.join(OUT, 'recipes/comparison.json'), '--out', path.join(OUT, 'reviews/comparison')], 'comparison');
fs.copyFileSync(path.join(OUT, 'reviews/comparison/staff_alignment_comparison.png'), path.join(OUT, 'comparison-3x.png'));

json(path.join(OUT, 'validation.json'), { status: 'passed', art_status: 'candidate', runtime_integrated: false, size: [32, 48], display_scale: 3, engine: 'Pixelbolt 0.11.0', standard: NOTES.standard, pipeline_changed_pixels: 0, references: references.map(r => ({ ...r, image: rel(r.image) })), assets: results });
json(path.join(OUT, 'commands.json'), commands);
fs.writeFileSync(path.join(OUT, 'asset.brief.md'), '# 직원 공통 신체 기준 정렬\n\n기존 기획: 머리 y11~26, 어깨/몸통 y27~39, 다리 y40~46, 발 y46. 여행자·마법사 자료의 머리 프레임 [3,11,25,27]과 여행자의 체간/다리 중심을 참고했다. 이번 추가 정렬 결정은 중심축 x14, 목(14,27), 가슴(14,31), 허리(14,35), 골반(14,37), 무릎(12,40)/(17,40), 접지(11,46)/(17,46)이다. 기존 모든 캐릭터가 이 세부 좌표와 동일하다는 뜻은 아니다. 모자·후드·머리 장식·소품의 외곽은 신체 기준에서 제외한다.\n\n원본 색과 역할별 의상은 유지하며 위치 정렬에 필요한 이동과 목/허리/다리 접합 픽셀을 수정했다. 원본과 이전 후보는 보존했다. 정지 상태에서 공통 기준점을 비교하며 호흡에는 머리/목이 1px 올라간다. 팔·가슴 y30 이후·다리·발·지팡이는 호흡에서 고정한다. UI 역할 아이콘과 실제 게임 배치는 바꾸지 않았다.\n\n재현: node tools/build_f25_staff_alignment_v1.mjs\n');

const uri = file => 'data:image/png;base64,' + fs.readFileSync(file).toString('base64');
const staffData = previews.map(p => ({ id: p.id, name: p.name, before: uri(path.join(OUT, 'before', p.id + '.png')), states: Object.fromEntries(['still', 'inhale', 'blink', 'inhale_blink'].map(s => [s, uri(path.join(OUT, 'exports', p.id, 'frames', s + '.png'))])), note: p.note }));
const refNames = { keeper: '상점 주인', traveler: '여행자 · 기준형', mage: '여마법사', elf: '엘프', rogue: '고양이 도적' };
const html = `<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>직원 4명 · 신체 기준 정렬</title><style>
*{box-sizing:border-box}body{margin:0;background:#f3efe5;color:#241c32;font:15px/1.65 system-ui,'Malgun Gothic',sans-serif}main{max-width:1120px;margin:auto;padding:32px 24px}h1{font-size:28px;margin:5px 0}h2{font-size:18px;margin:0 0 8px}.kicker{font-size:12px;letter-spacing:.13em;color:#53695b}p{margin:8px 0}.note{padding:12px 16px;border-left:4px solid #718c59;background:#e5eadc}.refs{display:flex;gap:15px;flex-wrap:wrap;margin:20px 0}.refs figure{margin:0;text-align:center;min-width:150px}.sprite{width:96px;height:144px;image-rendering:pixelated}.stage{position:relative;width:96px;height:144px;background:#e2e8dc;margin:0 auto;isolation:isolate}.stage img,.stage canvas{position:absolute;inset:0;z-index:1}.stage .lines{position:absolute;inset:0;z-index:2;pointer-events:none;opacity:.65}.lines i{position:absolute;left:0;right:0;border-top:1px solid #598196}.lines b{position:absolute;left:42px;top:27px;bottom:0;border-left:1px dashed #a0776c}.hide-guides .lines{display:none}.cards{display:grid;grid-template-columns:repeat(4,1fr);gap:16px}.card{background:#fffdf7;border:1px solid #d1d8ca;border-radius:12px;padding:17px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:10px;text-align:center}.label{font-size:12px;color:#596958;margin:5px 0}.native{display:flex;gap:18px;justify-content:center;margin-top:10px}.native img{width:32px;height:48px;image-rendering:pixelated}.changes{font-size:13px;min-height:72px;margin-top:12px;color:#58634f}.toolbar{display:flex;gap:14px;align-items:center;flex-wrap:wrap;margin:20px 0}button{font:inherit;padding:7px 16px;border:1px solid #b2bfaa;background:white;border-radius:7px;cursor:pointer}.legend{font-size:13px;color:#65725d}table{border-collapse:collapse;width:100%;font-size:14px;margin-top:20px}th,td{text-align:left;border-bottom:1px solid #d3d9cc;padding:8px}a{color:#24566a}.full{max-width:100%;image-rendering:pixelated;margin-top:20px}@media(max-width:1000px){.cards{grid-template-columns:repeat(2,1fr)}}@media(max-width:580px){.cards{grid-template-columns:1fr}main{padding:20px 12px}}
</style><main><div class="kicker">F25 / ALIGNMENT STUDY / PIXELBOLT 0.11.0</div><h1>직원 4명, 같은 신체 기준으로</h1><p>정지 상태의 머리·목·가슴·허리·다리를 맞춘 새 후보입니다. 모든 그림은 32×48, 표시 크기는 공통 3배입니다.</p><p class="note">기존 그림의 색·역할별 의상을 유지하며 정렬에 필요한 위치와 접합을 수정했습니다. 게임에는 아직 연결하지 않았습니다.</p>
<h2 style="margin-top:24px">기존 캐릭터 참조</h2><div class="refs">${references.map(r => `<figure><div class="stage"><img class="sprite" src="${uri(r.image)}" alt="${refNames[r.id]}"><div class="lines">${[11,27,31,35,40,46].map(y=>`<i style="top:${y*3}px"></i>`).join('')}<b></b></div></div><figcaption>${refNames[r.id]}</figcaption></figure>`).join('')}</div><p class="legend">여행자의 체간·다리 축과 기존 머리 기준 프레임을 참조했습니다. 상점 주인은 원본부터 눈이 더 높으며, 기존 승인 그림은 수정하지 않았습니다.</p>
<div class="toolbar"><label><input id="guides" type="checkbox" checked> 기준선 표시</label><button id="play">움직임 재생</button><button id="reset">정지 기준으로</button><span id="status">정지 · 비교 기준</span></div><p class="legend">선: 머리 시작 11 · 목/어깨 27 · 가슴 31 · 허리 35 · 다리 40 · 발 46 / 점선: 신체 중심축 x14</p>
<section class="cards">${staffData.map((p,i)=>`<article class="card"><h2>${p.name}</h2><div class="pair"><div><div class="stage"><img class="sprite" src="${p.before}" alt="${p.name} 수정 전"><div class="lines">${[11,27,31,35,40,46].map(y=>`<i style="top:${y*3}px"></i>`).join('')}<b></b></div></div><div class="label">수정 전</div></div><div><div class="stage"><canvas class="sprite" width="32" height="48" data-index="${i}" aria-label="${p.name} 수정 후"></canvas><div class="lines">${[11,27,31,35,40,46].map(y=>`<i style="top:${y*3}px"></i>`).join('')}<b></b></div></div><div class="label">수정 후</div></div></div><div class="native"><img src="${p.before}" alt="수정 전 1배"><img src="${p.states.still}" alt="수정 후 1배"></div><p class="changes">${p.note.summary || '눈·턱·가슴·허리·다리와 접지 기준을 공통 좌표에 맞췄습니다.'}</p></article>`).join('')}</section>
<table><thead><tr><th>기준</th><th>공통 좌표</th><th>근거</th></tr></thead><tbody><tr><td>머리 / 몸통 / 다리</td><td>y11~26 / 27~39 / 40~46</td><td>기존 기획</td></tr><tr><td>눈 / 턱 / 발</td><td>y22~23 / 26 / 46</td><td>여행자·마법사 기준</td></tr><tr><td>목 / 가슴 / 허리 / 골반</td><td>(14,27) / (14,31) / (14,35) / (14,37)</td><td>기존 비율에 맞춰 이번에 공통 좌표 확정</td></tr><tr><td>무릎 / 발 접지점</td><td>(12,40), (17,40) / (11,46), (17,46)</td><td>여행자 다리 구조 참조</td></tr></tbody></table>
<p>모자·머리 장식·외투 끝·소품·방향에 따른 눈의 가로 위치는 골격 기준과 구분합니다. 호흡 중에는 머리와 목이 1px 올라가며, 비교는 기본 정지 자세에서 진행합니다.</p><p><a href="validation.json">검증 기록</a> · <a href="source/alignment-notes.json">부위별 수정 기록</a> · <a href="comparison-3x.png">정지 전후 이미지</a></p><p class="legend">픽셀·접합 검사와 미술적 승인은 별개입니다. 아직 외형 후보이며 작업실 직원 배치와 관리 화면 역할 아이콘은 바꾸지 않았습니다.</p></main>
<script>const items=${JSON.stringify(staffData)}, phases=${JSON.stringify(phases)};let playing=false,time=0,last=performance.now();const imageBank={};Promise.all(items.flatMap(a=>Object.entries(a.states).map(([s,src])=>new Promise(resolve=>{const im=new Image();im.onload=()=>{imageBank[a.id+'/'+s]=im;resolve()};im.src=src})))).then(()=>requestAnimationFrame(tick));document.getElementById('guides').onchange=e=>document.body.classList.toggle('hide-guides',!e.target.checked);document.getElementById('play').onclick=()=>{playing=!playing;document.getElementById('play').textContent=playing?'일시정지':'움직임 재생'};document.getElementById('reset').onclick=()=>{playing=false;time=0;document.getElementById('play').textContent='움직임 재생'};function tick(now){if(playing)time+=(now-last);last=now;const t=time%9000,p=phases.find(p=>t>=p.time&&t<p.time+p.duration),state=p.breath?(p.blink?'inhale_blink':'inhale'):(p.blink?'blink':'still');document.querySelectorAll('canvas').forEach((c,i)=>{const ctx=c.getContext('2d');ctx.imageSmoothingEnabled=false;ctx.clearRect(0,0,32,48);ctx.drawImage(imageBank[items[i].id+'/'+state],0,0)});document.getElementById('status').textContent=time===0?'정지 · 비교 기준':(t/1000).toFixed(1)+' / 9.0초';requestAnimationFrame(tick)}</script></html>`;
fs.writeFileSync(path.join(OUT, 'review.html'), html);
console.log('Created ' + rel(path.join(OUT, 'review.html')));
