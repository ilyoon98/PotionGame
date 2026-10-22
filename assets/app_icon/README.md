# 달그늘 물약상점 앱 아이콘

보라색 픽셀 물약병에 금빛 초승달과 별을 넣었습니다. 배경은 투명합니다.

작업표시줄에서 작아 보이는 문제를 줄이기 위해 병의 폭을 25%, 높이를 10% 키우고 위아래 투명 여백을 줄였습니다. 별은 오른쪽 위 여백 안에 유지합니다. 실행 중인 게임은 다시 열면 변경된 ICO를 불러옵니다.

- `res://icon.svg`: 편집 가능한 32 × 32 픽셀 격자의 벡터 원본. 프로젝트 아이콘으로 연결.
- `res://icon.png`: Godot SVG 렌더러로 만든 256 × 256 PNG.
- `res://icon.ico`: Windows용 16 / 24 / 32 / 48 / 64 / 128 / 256 크기. `application/config/windows_native_icon`에 연결.
- `preview.png`: 밝은 배경과 어두운 배경의 실제 16~64픽셀 미리보기.
- 프로젝트 폴더의 `달그늘 물약상점.lnk`: 새 아이콘을 표시하는 Windows 실행 바로가기. 기존 `play.cmd`를 실행합니다. 프로젝트 폴더를 이동하면 바로가기의 대상과 아이콘 경로도 수정해야 합니다.

SVG를 수정한 뒤 아래 순서로 다시 생성합니다. `godot`는 설치된 Godot 4.6 실행 파일로, `python`은 Pillow가 설치된 Python으로 바꿀 수 있습니다. 프로젝트 폴더에서 실행하세요.

```powershell
godot --headless --path . --log-file .verification/app-icon-render.log --script res://tools/prepare_app_icon.gd
python tools/prepare_app_icon.py
godot --headless --editor --path . --log-file .verification/app-icon-import.log --import
```

Windows 내보내기에서 별도 아이콘을 지정하지 않으면 프로젝트에 연결된 아이콘을 사용합니다. 현재 `play.cmd`는 설치된 Godot 실행 파일로 게임을 실행하므로, 배포 EXE 및 시작 메뉴 바로가기 표시는 Windows 빌드를 내보낸 후 확인해야 합니다.

ICO의 모든 크기와 투명도를 재독해 확인했으며, Windows의 `System.Drawing.Icon`으로 32픽셀 아이콘 읽기를 확인했습니다. 기존 크기의 작업표시줄 표시는 사용자 스크린샷으로 확인했습니다. 확대 후 실제 작업표시줄·작업관리자·시작 메뉴 화면과 Windows 배포 빌드는 아직 확인하지 않았습니다.

참고: [Godot 4.6 Windows 아이콘 문서](https://docs.godotengine.org/en/4.6/tutorials/export/changing_application_icon_for_windows.html).
