# F21 수면·기절·숙성 아트 후보 v1

**2026-10-21 승인:** 사용자 “진행해 A안으로” → `approval.json`(수면 A·기절·벽 숙성통·인장). `tools/publish_f21_rest_aging_v1.py`로 `assets/pixel_v1`에 추가 게시하고 런타임에 연결했다. 검증: `tools/verify_f21_rest_art.gd`, `.verification/f21-rest-art-20261021/`. 아래 `review.html`은 승인 당시의 검토 페이지(후보 시점 문구 포함)로 보존한다.

- 검토 페이지: `review.html` (상대 경로 이미지를 쓰므로 로컬 정적 서버나 브라우저에서 파일로 연다)
- 재현: `python tools/build_f21_rest_aging_v1.py` (Pillow+NumPy). 원본 지도 → 등록 PNG → `tools/process_pixel_art.py` → 추가 검사 → 작업실 합성/GIF → `review.html`
- 주인공 프레임: `art/characters/rest-v1/keeper/` (`source/*.txt`, `manifest.json`, `pipeline/`, `frames/`, `validation.json`, `generation.json`)
- 소품: `props/` (`source/*.txt`, `manifest.json`, `pipeline/`, `generation.json`)
- 검사 전체: `validation.json` — 주인공 3프레임(주인공 5색, 외곽선 위반0, 반투명0, 감은 눈 1×1 두 개, 바닥행46, 승인 머리 픽셀 재사용), 호흡(하체 동일, 상체1행), 소품7종(5색 이하, 외곽선, 32×32), 인장×병36종(병 내부81%↑ 보임, 마개/목 미가림, 병 수정0), 배치(UI 영역/주인공9프레임 겹침0)
- 작업실 합성은 게시된 `assets/pixel_v1` 그림을 읽기만 해서 원본180×83에 놓고 3배 확대했다. 상태 글자는 HTML DOM이다.

선택지: 수면 A(제자리 앉아 졸기, 추천)/B(깔개+이불), 기절(머리 젖힘+별), 숙성통 벽 선반(추천, 표시219,0)/바닥(판매대 왼쪽 끝 앞). 해먹·책상·완전히 누운 포즈는 배치/32×48 제한으로 제외했다(review.html 참고).
