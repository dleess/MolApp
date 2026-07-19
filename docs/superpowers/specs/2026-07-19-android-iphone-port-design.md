# MolApp Android + iPhone 포팅 설계

**작성:** 2026-07-19 · **전략 결정:** 네이티브 셸 2개 (사용자 선택)

## 목표

현재 iPadOS 전용 MolApp을 Android와 iPhone에서도 구동.

## 현재 구조 (핵심 통찰)

앱의 90%는 이미 웹이다:

- **웹 코어** — `MolApp/Resources/viewer.html` (2122줄) + `molstar/molstar.js` (4.8MB) + `molstar.css`.
  분자 렌더링, 명령 처리(`handleNativeCommand`), 선택, 측정, morph, surface, superpose,
  secondary structure, 상태 직렬화, 이미지 캡처 — **모든 뷰어 로직이 여기 있고 플랫폼 독립적**.
- **네이티브 셸 (Apple 전용)** — SwiftUI ~2226줄. WKWebView 호스트 + JSON 명령 브릿지 +
  UI 크롬(메뉴/패널/명령바) + 명령 파서 + 선택식 파서 + 파일 로드.

브릿지 프로토콜: 네이티브→JS는 `evaluateJavaScript("window.molapp.handleNativeCommand(<envelope>)")`,
JS→네이티브는 현재 `window.webkit.messageHandlers.molapp.postMessage(obj)` (iOS 하드코딩, ~10곳).

## 아키텍처

두 네이티브 셸이 **동일한 웹 코어**를 감싼다. 셸은 WebView 호스트, 네이티브↔JS 전송, UI 크롬만 다르다.

### 공유 변경: viewer.html 브릿지 추상화

JS→네이티브 전송을 `postToNative(obj)` shim 하나로 통일:

```js
function postToNative(obj) {
  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.molapp) {
    window.webkit.messageHandlers.molapp.postMessage(obj);          // iOS
  } else if (window.MolAppAndroid && window.MolAppAndroid.postMessage) {
    window.MolAppAndroid.postMessage(JSON.stringify(obj));          // Android @JavascriptInterface
  }
}
```

~10개의 인라인 webkit 블록을 `postToNative(...)`로 교체. iOS 동작 완전 보존.

### iOS (기존 SwiftUI) — iPhone 추가

- `TARGETED_DEVICE_FAMILY = 2` → `"1,2"` (iPhone+iPad).
- `menuBar`의 6개 텍스트 메뉴(File/Edit/Display/Calculation/Measure/Help)가 좁은 iPhone 폭에서 오버플로우.
  compact 폭에서 가로 스크롤 또는 축약 레이아웃으로 처리. 나머지 오버레이(정보 카드/objects 패널/명령바)는
  `maxWidth` 캡과 가장자리 앵커로 이미 대체로 동작 — 실제 깨지는 것만 수정.
- 검증: iPhone 시뮬레이터 빌드+실행.

### Android (신규 Kotlin 모듈) — 새 셸

- `android/` 새 Gradle 프로젝트 (Kotlin + Jetpack Compose + WebView).
- **에셋 공유**: molstar 4.8MB를 git에 중복 커밋하지 않는다. Gradle 태스크가 빌드 시
  `../MolApp/Resources`의 `viewer.html` + `molstar/`를 `app/src/main/assets`로 복사. 복사본은 gitignore.
  단일 소스 = MolApp/Resources.
- WebView가 `file:///android_asset/viewer.html` 로드 → 상대경로 `molstar/molstar.js` 그대로 해석.
- `MolStarBridge.kt`: `@JavascriptInterface`로 JS 이벤트 수신(JSON 파싱), 명령 송신(envelope JSON →
  `evaluateJavascript`). Swift `MolStarBridge` 미러.
- `SelectionExpressionParser.kt` + 명령 파서(`executeCommand`) Kotlin 포팅 — 순수 로직, 플랫폼 무관.
- Compose UI: 메뉴바(6 드롭다운), 정보 카드(status+Open+PDB), objects 패널, 명령바. 핵심 기능 동등성.
- 파일 열기: SAF `ACTION_OPEN_DOCUMENT` → pdb/cif 텍스트 → `loadLocalStructure`.
- 검증: `gradle assembleDebug`, `test34.avd` 에뮬레이터 설치+실행, PDB 로드하여 렌더링 확인.

## 툴체인 (검증 완료)

- Android SDK (platforms 34/35/36, build-tools, ndk, emulator), system-image android-34, AVD `test34.avd`.
- JDK: `brew openjdk@17` (`JAVA_HOME=/opt/homebrew/opt/openjdk@17`).
- Gradle: wrapper 사용 (services.gradle.org 접근 가능, 200).
- Xcode 26.6 + iPhone 시뮬레이터.

## 범위 밖 (YAGNI)

- Play Store / App Store 제출 (별도 작업). 이번 목표는 "구동".
- Android용 Apple Pencil hover (물리 iPad 전용 기능, Android 무관).
- 픽셀 단위 UI 일치 — 핵심 기능 동등성만.
