# MolApp — App Store 제출 체크리스트

버전 0.1 · iPad 전용 분자 뷰어 (SwiftUI + Mol*)

---

## 1. 코드/설정 준비 완료 (이 저장소에 반영됨)

| 항목 | 값 | 위치 |
|------|-----|------|
| Marketing Version | `0.1` | `MARKETING_VERSION` (project.pbxproj, 4개 config) |
| Build Number | `1` | `CURRENT_PROJECT_VERSION` |
| Bundle ID | `com.donghan.MolApp` | pbxproj |
| App Category | `public.app-category.education` | `INFOPLIST_KEY_LSApplicationCategoryType` |
| 암호화 | `ITSAppUsesNonExemptEncryption = NO` | Info.plist |
| Device Family | iPad 전용 (`2`) | `TARGETED_DEVICE_FAMILY = 2` |
| Deployment Target | iOS 18.0 | `IPHONEOS_DEPLOYMENT_TARGET` |
| App Icon | 전체 세트 (iPhone/iPad/1024) | `Assets.xcassets/AppIcon.appiconset` |
| Privacy Manifest | 추적 없음, 데이터 수집 없음 | `PrivacyInfo.xcprivacy` (타깃 포함됨) |
| Orientation | Portrait + Landscape | pbxproj |

Release 빌드 + `-validate-for-store` 검증 통과 확인함.

---

## 2. 남은 수동 단계 (Apple Developer 계정 필요 — 코드로 불가)

### 2.1 서명 / 팀
- `DEVELOPMENT_TEAM = ABCDE12345` 는 **placeholder**. 실제 Team ID로 교체 필수.
  - Xcode → 타깃 → Signing & Capabilities → Team 선택 (자동 서명).
- Distribution 인증서 + App Store provisioning profile (자동 관리 권장).

### 2.2 App Store Connect 레코드 생성
- https://appstoreconnect.apple.com → Apps → **+** → New App
  - Platform: iOS
  - Name: `MolApp` (전역 유일해야 함 — 중복 시 대체명 필요)
  - Primary Language: Korean 또는 English
  - Bundle ID: `com.donghan.MolApp` (Developer Portal에 먼저 등록)
  - SKU: 임의 (예: `molapp-001`)

### 2.3 스토어 메타데이터 (아래 §3 초안 사용)
- 설명, 키워드, 지원 URL, 프로모션 텍스트.

### 2.4 스크린샷 (필수)
- iPad 13" (2048×2732 또는 2064×2752) 최소 1장, 권장 3~5장.
- 시뮬레이터에서 캡처 가능:
  ```
  xcrun simctl io booted screenshot shot.png
  ```
- 추천 장면: 구조 로드 / Surface Potential / Superpose / Secondary Structure / Manual.

### 2.5 App Privacy 설문 (App Store Connect)
- Data Collection: **No** (앱은 데이터 수집/추적 안 함, PrivacyInfo와 일치).

### 2.6 빌드 업로드
```
xcodebuild -project MolApp.xcodeproj -scheme MolApp \
  -configuration Release -sdk iphoneos \
  -archivePath build/MolApp.xcarchive archive
xcodebuild -exportArchive -archivePath build/MolApp.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export
xcrun altool --upload-app -f build/export/MolApp.ipa \
  -t ios --apiKey <KEY> --apiIssuer <ISSUER>
```
(또는 Xcode → Product → Archive → Distribute App.)
`ExportOptions.plist` 는 저장소에 존재하나 `teamID` 실제 값 확인 필요.

### 2.7 심사 제출
- 빌드 선택 → Age Rating 설문 → Export Compliance (암호화 없음) → Submit for Review.

---

## 3. 스토어 메타데이터 초안

**이름:** MolApp — Molecular Viewer

**부제 (30자):** Interactive protein structure viewer

**설명:**
> MolApp is an iPad molecular structure viewer built on Mol*. Load PDB files
> locally or by PDB ID and explore proteins with cartoon, surface, stick, and
> ball-and-stick representations.
>
> Features:
> • Load multiple structures; per-structure visibility from the Objects panel
> • Surface electrostatic potential map (screened-Coulomb / APBS-style)
> • Superposition and sequence-independent structural alignment
> • Secondary structure (DSSP) coloring
> • Morphing between conformations
> • Command-line interface and built-in manual
>
> All computation runs on-device. No account, no data collection, no tracking.

**키워드:** molecule,protein,PDB,structure,viewer,molstar,chemistry,biology,science,DSSP

**지원 URL:** (필수 — 개인 페이지/깃허브 등 입력)

**연령 등급:** 4+

**개인정보 처리방침 URL:** (데이터 미수집이라도 URL 하나 필요)

---

## 4. 알려진 확인사항
- `DEVELOPMENT_TEAM` placeholder → 실제 값 교체 전 실기기 서명/업로드 불가.
- 지원 URL, 개인정보 URL, 스크린샷은 사람이 준비해야 함.
- 앱 이름 전역 유일성은 App Store Connect에서 등록 시 확정됨.
