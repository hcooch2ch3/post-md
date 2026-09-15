[English](README.md) | **한국어**

# post-md

MarkEdit에서 선택한 마크다운을 macOS 데스크탑에 **플로팅 스티커**로 띄우는 도구.

![데스크탑에 띄운 post-md 스티커](assets/hero.png)

두 컴포넌트로 구성됩니다:

- **발신 측** — **MarkEdit 확장**(`extension/`) 또는 **Obsidian 플러그인**(`obsidian/`) — 이 에디터에서 선택한 마크다운을 `post-md://` URL 스킴을 통해 전송합니다.
- **컴패니언 앱 post-md**(`app/`)는 URL을 받아 데스크탑에 반투명 스티커 창으로 표시합니다(📌로 고정한 것만 항상 위).

두 컴포넌트는 커스텀 URL 스킴 하나(`post-md://`)로만 느슨하게 연결됩니다. 앱은 어느 에디터가 보냈는지 모르므로, 이 스킴만 말할 줄 알면 어떤 발신 측이든 동작합니다.

## 요구사항

- **post-md 앱**: macOS 14 이상
- **MarkEdit**: [MarkEdit](https://github.com/MarkEdit-app/MarkEdit). Homebrew cask(`brew install --cask markedit`)는 현재 macOS 15 이상을 요구하므로, macOS 14에서는 [GitHub 릴리스](https://github.com/MarkEdit-app/MarkEdit/releases)에서 호환 버전을 직접 설치하세요.
- **Obsidian 플러그인**(선택): macOS의 Obsidian 1.4 이상.
- 빌드: Swift 5.9+ (Xcode 또는 CLI 툴체인), Node 18+

## 설치

> ⚠️ **앱을 먼저 실행하세요.** 컴패니언 앱이 실행되면서 `post-md://` URL 핸들러를 시스템에 등록합니다. 앱이 미설치 상태이면 Extension이 전송한 URL은 조용히 사라집니다.

### 1. 컴패니언 앱

```bash
cd app
./make-app.sh      # 빌드 → .app 조립 → Launch Services 등록 → 실행
```

`build/post-md.app`이 생성되고 실행됩니다. Dock에는 나타나지 않고(LSUIElement) 메뉴바에 `note.text` 아이콘으로 상주합니다.

### 2. MarkEdit 확장

> ⚠️ **먼저 MarkEdit을 설치하고 한 번 실행하세요.** MarkEdit이 처음 실행되면서 스크립트 컨테이너를 생성하며 Homebrew로 설치했다면 첫 실행 시 Gatekeeper 승인(“열기”)이 필요할 수 있습니다. 컨테이너가 없으면 아래 `deploy`가 명확한 오류 메시지를 남기고 중단됩니다.

```bash
cd extension
npm install
npm run deploy     # 빌드 후 MarkEdit scripts 디렉토리로 배포
```

MarkEdit을 재시작하면 **Extensions ▸ Pop as Sticky** 메뉴가 나타납니다.

### 3. Obsidian 플러그인 (선택)

macOS 전용이며, 컴패니언 앱이 실행 중이어야 합니다. 아직 미리 빌드된 번들이 없으므로 한 번 빌드하세요.

```bash
cd obsidian
npm install
npm run build
```

`manifest.json`(리포 루트)과 `obsidian/main.js`를 `<보관함>/.obsidian/plugins/post-md/`에 복사한 뒤, 설정 ▸ 커뮤니티 플러그인에서 **post-md**를 켜세요. 커뮤니티 스토어 등록은 예정되어 있습니다.

## 사용

스티커를 만드는 방법은 네 가지입니다.

- **MarkEdit에서**: 마크다운을 선택한 뒤 **Extensions ▸ Pop as Sticky** 클릭. 선택 없이 저장된 문서를 띄우면 그 파일에 **연결**됩니다(Live Sync). 일부만 선택하거나 저장 안 된 문서는 스냅샷으로 뜹니다.
- **Obsidian에서**: 명령 팔레트, 리본 아이콘, 또는 에디터 우클릭 메뉴에서 **Pop as Sticky** 실행. 선택 없이 노트를 띄우면 그 파일에 **연결**됩니다(Live Sync). 일부만 선택하면 스냅샷으로 뜹니다.
- **클립보드에서**: 메뉴바 아이콘 ▸ **클립보드에서 스티커**.
- **파일에서**: 메뉴바 아이콘 ▸ **마크다운 파일 열기…**, 또는 `.md` 파일을 메뉴바 아이콘에 드래그. 파일로 연 스티커는 그 파일에 연결됩니다(아래 Live Sync 참고).

스티커 상단 바는 호버하면 진해집니다. **✕** 닫기(삭제), **📌** 고정, **🎨** 색상(노랑, 분홍, 파랑, 초록, 보라), **투명도** 슬라이더, **✏️** 편집이 있습니다. 본문을 드래그해 이동하고 가장자리로 크기를 조절합니다.

- **핀 안 한 스티커**는 다른 앱으로 작업하면 뒤로 덮여 화면을 가리지 않습니다.
- **📌로 고정한 스티커**만 항상 맨 위에 떠 있어 작업 중에도 계속 보입니다.

위치, 크기, 투명도, 고정 상태, 색상은 저장되어 앱을 재시작해도 복원됩니다. 메뉴바 아이콘에서는 스티커 목록, **모두 숨기기/보이기**(한 번에 치웠다가 되띄우기, 삭제 아님), 모두 앞으로, 스티커 내보내기, 모두 닫기, 최근 오류, post-md에 관하여, 종료도 이용할 수 있습니다.

## 편집과 Live Sync

- **인라인 편집**: 본문을 더블클릭하거나 **✏️**를 누릅니다. **⌘Return**으로 저장, **Esc**로 취소합니다.
- `.md` 파일로 연 스티커는 그 파일에 **연결**되며 버튼 두 개가 더 생깁니다.
  - **⬆️**는 편집 내용을 원본 파일에 다시 씁니다. post-md 밖에서 파일이 바뀐 경우 덮어쓰기 전에 확인합니다.
  - **🔗**은 Finder에서 보기, 원본 편집기로 열기, 연결 해제(내용은 남기고 링크만 끊기)를 엽니다.
- **Live Sync**: 연결된 파일을 아무 편집기에서나 고치면 스티커가 알아서 갱신됩니다. 파일과 스티커가 둘 다 바뀌면 배너에서 **파일 가져오기** 또는 **내 편집 유지**를 고를 수 있습니다. 확인 없이 덮어쓰는 일은 없습니다.
- **내보내기**: 메뉴바 아이콘 ▸ **스티커 내보내기**로 스티커를 `.md` 파일로 저장합니다.

## 제약

- 스티커는 최대 30장, 각 내용은 약 1MB까지입니다(사실상 모든 마크다운 문서 커버). 초과 시 잘리지 않고 안내 후 거부합니다.
- 마크다운은 GFM 표준을 렌더합니다.

## 개발

```bash
cd app && swift test          # 코어 로직 단위 테스트 (파서, 스토어)
cd extension && npm test      # 인코딩 단위 테스트 + Obsidian 복사본·도출 가드
cd obsidian && npm run build  # Obsidian 플러그인을 obsidian/main.js로 번들
```

## 라이선스와 크레딧

이 프로젝트는 [MIT 라이선스](LICENSE)로 배포됩니다.

- 마크다운 렌더링: [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) (MIT)
- MarkEdit API 타입: [MarkEdit-api](https://github.com/MarkEdit-app/MarkEdit-api)
