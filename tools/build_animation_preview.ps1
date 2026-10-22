$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$outputRoot = Join-Path $projectRoot 'assets/characters/animations_v1'
$manifest = Get-Content -LiteralPath (Join-Path $outputRoot 'manifest.json') -Raw | ConvertFrom-Json
$names = @('keeper', 'traveler', 'mage', 'elf', 'rogue')
$labels = @('주인공', '여행자', '마법사', '엘프 궁수', '고양이 도적')
$characters = @()
for ($index = 0; $index -lt $names.Count; $index++) {
    $name = $names[$index]
    $entry = $manifest.characters.$name
    $frames = @($entry.frames | ForEach-Object {
        'data:image/png;base64,' + [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $outputRoot $_)))
    })
    $motionCount = 2
    $fps = if ($name -eq 'keeper') { 4 } else { 6 }
    $characters += @{ name = $name; label = $labels[$index]; frames = $frames; motionCount = $motionCount; fps = $fps }
}
$json = ConvertTo-Json -InputObject @($characters) -Depth 6 -Compress
$html = @'
<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>달그늘 물약상점 · 캐릭터 동작</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#1d1924;color:#eee6d9;font:15px/1.6 system-ui,'Malgun Gothic',sans-serif}main{max-width:1120px;margin:auto;padding:32px 24px}h1{font-size:26px;margin:0 0 6px}p{color:#bfb2c9;margin:4px 0 20px}.controls{display:flex;gap:8px;flex-wrap:wrap;margin:24px 0}button,select{border:1px solid #65516e;border-radius:8px;background:#31273d;color:#eee6d9;padding:9px 13px;font:inherit;cursor:pointer}button[aria-pressed=true]{background:#715678;border-color:#c4a3c5}.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(185px,1fr));gap:14px}.card{border:1px solid #46364f;border-radius:12px;background:#272031;padding:16px 12px;text-align:center}.card h2{font-size:17px;margin:0 0 12px}.stage{height:272px;display:grid;place-items:center;border-bottom:1px solid #44364e;background:radial-gradient(ellipse at center,#393044,#272031 75%)}.sprite{width:192px;height:256px;image-rendering:pixelated;object-fit:contain}.status{color:#dfbb88;min-height:25px;margin-top:12px}.strip{display:grid;grid-template-columns:repeat(4,1fr);gap:2px;margin-top:15px}.strip img{width:100%;image-rendering:pixelated}.strip small{display:block;font-size:10px;color:#bfb2c9;white-space:nowrap}.note{margin-top:24px;font-size:13px}a{color:#dfbb88}footer{margin-top:24px;color:#a799b2;font-size:12px}
</style><main>
<h1>달그늘 물약상점 · 캐릭터 동작</h1><p>주인공과 손님 4명. 캐릭터마다 48 × 64 픽셀, 4프레임.</p>
<div class="controls" aria-label="재생 설정"><button data-mode="cycle" aria-pressed="true">전체 순서</button><button data-mode="idle" aria-pressed="false">Idle</button><button data-mode="motion" aria-pressed="false">걷기 / 제조</button><button data-mode="action" aria-pressed="false">구매 완료 / 판매</button><button id="pause">일시정지</button><select id="scale" aria-label="확대 배율"><option value="2">게임 표시 크기 · 2배</option><option value="4" selected>도트 확인 · 4배</option></select></div>
<section class="cards" id="cards"></section>
<p class="note">손님: idle → 걷기 1·2 → 구매 완료 / 주인공: idle → 제조 1·2 → 판매<br>물약과 솥은 게임에서 별도로 표시하는 오브젝트입니다. 이 미리보기는 캐릭터 동작만 보여줍니다.</p>
<footer>스프라이트 시트: 96 × 128 PNG, 왼쪽 위부터 행 순서로 0·1·2·3. 현재 게임에 적용하기 전의 동작 에셋입니다.</footer>
</main><script>
const characters=__CHARACTER_DATA__;
const cards=document.querySelector('#cards');
const labelsFor=c=>c.name==='keeper'?['idle','제조 1','제조 2','판매']:['idle',...Array.from({length:c.motionCount},(_,i)=>'걷기 '+(i+1)),'구매 완료'];
for(const c of characters){const article=document.createElement('article');article.className='card';const title=document.createElement('h2');title.textContent=c.label;article.append(title);const stage=document.createElement('div');stage.className='stage';c.image=document.createElement('img');c.image.className='sprite';c.image.alt=c.label;c.image.src=c.frames[0];stage.append(c.image);article.append(stage);c.status=document.createElement('div');c.status.className='status';c.status.textContent='idle';article.append(c.status);const strip=document.createElement('div');strip.className='strip';c.frames.forEach((src,i)=>{const cell=document.createElement('div');const image=document.createElement('img');image.src=src;image.alt=labelsFor(c)[i];const text=document.createElement('small');text.textContent=labelsFor(c)[i];cell.append(image,text);strip.append(cell)});article.append(strip);cards.append(article)}
let mode='cycle',paused=false,time=0,last=performance.now();
document.querySelectorAll('[data-mode]').forEach(button=>button.addEventListener('click',()=>{mode=button.dataset.mode;time=0;document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)))}));
document.querySelector('#pause').addEventListener('click',e=>{paused=!paused;e.target.textContent=paused?'재생':'일시정지'});
document.querySelector('#scale').addEventListener('change',e=>{const scale=Number(e.target.value);for(const c of characters){c.image.style.width=48*scale+'px';c.image.style.height=64*scale+'px'}});
function tick(now){const delta=Math.min(now-last,100);last=now;if(!paused)time+=delta;for(const c of characters){const speed=c.fps;const phase=time%4500;let index=0;if(mode==='action')index=c.frames.length-1;else if(mode==='motion')index=1+(Math.floor(time/1000*speed)%c.motionCount);else if(mode==='cycle'){if(phase>=1200&&phase<3300)index=1+(Math.floor((phase-1200)/1000*speed)%c.motionCount);else if(phase>=3300)index=c.frames.length-1}if(c.index!==index){c.index=index;c.image.src=c.frames[index];c.status.textContent=labelsFor(c)[index]}}requestAnimationFrame(tick)}requestAnimationFrame(tick);
</script></html>
'@
$html = $html.Replace('__CHARACTER_DATA__', $json)
[IO.File]::WriteAllText((Join-Path $outputRoot 'animation-preview.html'), $html, (New-Object Text.UTF8Encoding($false)))
Write-Output ('Created animation-preview.html: ' + $characters.Count + ' characters, ' + ($characters.frames.Count) + ' embedded frames.')
