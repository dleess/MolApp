# iPadOS Mol* 3D Molecule Viewer Plan

## Summary

SwiftUI 기반 iPadOS 앱을 만들고, 중앙 3D 렌더러는 `WKWebView` 안의 Mol* WebGL 뷰어로 구현한다. 1차 범위는 Core Viewer이며, 터치 제스처, 풀스크린 뷰포트, 플로팅 툴바, 바텀 시트, 선택 강조, 로컬 파일 열기와 PDB ID 불러오기를 포함한다.

## Key Changes

- SwiftUI 앱 셸을 구성한다: 풀스크린 `MoleculeViewerView`, 플로팅 툴바, 하단 바텀 시트, 파일 열기, PDB ID 입력 UI.
- `WKWebView` 안에 Mol* viewer 번들을 로드하고 Swift ↔ JavaScript 메시지 브리지를 둔다.
- 공개 브리지 명령은 최소로 고정한다: `loadLocalStructure`, `loadPdbId`, `setRepresentation`, `toggleVisibility`, `focusSelection`, `setSelection`, `clearSelection`.
- Mol* 기본 camera controls를 사용하되 iPad 제스처 매핑을 보정한다: 1손가락 회전, 2손가락 pan, pinch zoom, double tap center & zoom.
- 툴바에는 representation 전환 `Ribbon`, `Surface`, `Stick`과 빠른 토글 `Water`, `Ligand`, `Disulfide`를 둔다.
- 바텀 시트에는 선택된 원자/잔기 상세 정보와 sequence 영역을 표시하고, 접힘/중간/확장 상태를 지원한다.
- 터치 선택 시 선택 대상은 강조하고 나머지 구조는 dimming 처리한다.

## Implementation Details

- 네이티브 쪽은 SwiftUI로 작성하고, Mol*는 앱 번들 내 정적 web asset으로 포함한다.
- 로컬 파일은 iPad Files picker에서 `pdb`, `cif`, `mmcif`를 받아 WebView로 전달한다.
- PDB ID fetch는 1차 구현에서 RCSB 다운로드 URL을 사용해 Mol* 쪽에서 구조를 로드한다.
- 구조/체인 네비게이터와 Apple Pencil 고급 기능은 1차 범위에서 제외하되, 브리지 이벤트 구조는 나중에 확장 가능하게 둔다.
- Apple Pencil hover, 측정, 스크린샷 주석은 별도 2차 기능으로 계획한다.

## Test Plan

- iPad Simulator 또는 실제 iPad에서 로컬 PDB/mmCIF 파일 로드가 성공하는지 확인한다.
- PDB ID 입력 후 구조가 표시되고 로딩/실패 상태가 정상 표시되는지 확인한다.
- 1손가락 회전, 2손가락 pan, pinch zoom, double tap focus가 의도대로 동작하는지 확인한다.
- representation 버튼과 Water/Ligand/Disulfide 토글이 Mol* 상태를 즉시 바꾸는지 확인한다.
- 원자/잔기 선택 시 highlight, dimming, 바텀 시트 상세 정보가 함께 갱신되는지 확인한다.
- 큰 구조 파일에서 UI 패널 조작이 뷰포트 조작을 방해하지 않는지 확인한다.

## Assumptions

- 현재 repo에는 앱 코드가 없으므로 새 iPadOS 프로젝트를 스캐폴딩하는 계획이다.
- “Native iPadOS + Mol*”는 SwiftUI 앱 안에 `WKWebView`를 포함하는 하이브리드 네이티브 구조로 해석한다.
- 1차 목표는 전문가용 Core Viewer이며, 대용량 구조 네비게이터와 Apple Pencil 기능은 후속 단계로 둔다.
