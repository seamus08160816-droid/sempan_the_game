# 셈판 🧮

**한국어** | [English](README.en.md)

사칙연산으로 몹을 쓰러뜨리는 덱빌딩 로그라이크입니다.
숫자 카드와 기호 카드로 수식을 만들어 피해를 주고, 갈림길을 골라 오르며 덱을 키워 나갑니다.

## 플레이 방법

- 손패에서 숫자와 기호를 번갈아 골라 최대 5장(숫자 3, 기호 2)짜리 수식을 만듭니다.
- 수식은 왼쪽부터 순서대로 계산하며, 결과만큼 몹에게 피해를 줍니다.
- 계산 기회 안에 몹 체력을 0으로 만들면 승리하고, 그러지 못하면 게임 오버입니다.
- 승리하면 골드를 받고 특전을 골라 카드를 강화합니다.

## 주요 시스템

**갈림길 지도**
막마다 10층짜리 지도가 무작위로 생성됩니다. 층마다 1~3갈래 길이 생기며, 몹 · 정예 · 상점 중 갈 곳을 고릅니다. 10층 보스를 잡으면 다음 막으로 넘어갑니다.

**경제**
골드 = 처치 보상 + 초과 피해 골드 + 남은 계산 × 단가 + 남은 버리기 × 단가

- 초과 피해 골드는 로그 곡선으로 빠르게 꺾이며 상한이 있습니다.
- 모든 보상과 상점 가격은 적 체력과 함께 지수적으로 커집니다.
- 상점에서 산 카드는 같은 종류의 덱 카드와 교환됩니다. 덱 크기는 항상 그대로입니다.

**카드 강화**
| 종류 | 효과 |
|---|---|
| 황금 | 최종 결과 ×2 |
| 불꽃 | 최종 결과에 보너스 추가 |
| 행운 | 25% 확률로 최종 결과 ×5 |
| 증폭 (+) | 오른쪽 수를 세 배로 더함 |
| 적립 (+) | 보너스를 더하고, 쓸 때마다 보너스 증가 |
| 역전 (−) | 빼서 음수가 되면 빼는 대신 두 수를 더하고 ×4 |
| 정확 (÷) | 나누어떨어지면 나누는 대신 곱하고 ×2 (나누어떨어지는 손패 숫자는 후광으로 표시) |

× 카드는 강력한 대신 강화할 수 없습니다.

**숫자 변신 (막별 해금)**
| 해금 | 변신 | 입력 상한 |
|---|---|---|
| 2막 | 제곱 n² | 20 |
| 3막 | 2의 거듭제곱 2ⁿ | 15 |
| 4막 | 자연지수 eⁿ | 12 |
| 5막 | 팩토리얼 n! | 10 |

## 다운로드와 실행

**바로 플레이: https://sempan.vercel.app** (진행상황은 브라우저에 저장됩니다)

[Releases](https://github.com/seamus08160816-droid/sempan_the_game/releases)에서 세 가지 버전을 받을 수 있습니다. 모두 같은 규칙과 밸런스입니다.

| 파일 | 플랫폼 | 실행 방법 |
|---|---|---|
| `sempan-<버전>.html` | 웹 브라우저 | 파일을 브라우저로 열기 (인터넷 연결 없이도 동작) |
| `sempan-<버전>.apk` | 안드로이드 7.0 이상 | 휴대폰에서 설치 (출처를 알 수 없는 앱 허용 필요) |
| `sempan-xcode-<버전>.zip` | iOS · iPadOS · macOS · visionOS | 압축을 풀고 `sempan_the_game.xcodeproj`를 Xcode로 열어 실행 |

## 직접 빌드하기

```bash
# iOS / macOS (Xcode)
open sempan_the_game.xcodeproj

# 웹: web/index.html에 Gaegu 글꼴을 넣어 web/dist/sempan.html 한 파일로 만듭니다 (pip install fonttools)
python3 web/build.py
# 웹 배포 (Vercel): 빌드 후 web/dist를 올립니다
cd web/dist && npx vercel deploy --prod

# 안드로이드: 웹 버전을 WebView로 감싼 APK (Android SDK build-tools 35, JDK 11+)
android/build.sh 1.0.0-beta.1 1
```

웹 버전과 안드로이드 버전은 같은 `web/index.html`을 사용합니다. 게임 규칙을 바꿀 때는 Swift(`Game/`)와 웹(`web/index.html`)을 함께 수정해야 합니다.

## 밸런스 조정

대부분의 수치는 `sempan_the_game/Game/GameModels.swift` 맨 위의 `CFG`와 `Transform` 열거형에 있습니다. 웹 버전은 `web/index.html` 스크립트 맨 위의 `CFG`와 `TR`입니다.

| 항목 | 설명 |
|---|---|
| `baseHP`, `actGrowth`, `growthAfter` | 1층 체력과 막별 층당 체력 배율 |
| `econPow` | 보상·가격이 체력을 따라가는 정도 |
| `goldA`, `goldK`, `goldCap` | 초과 피해 골드 곡선 |
| `playGold`, `discGold` | 남은 계산·버리기 단가 |
| `fireBase`, `firePow` | 불꽃 보너스 크기 |
| `Transform.cap` | 변신별 입력 상한 |

## 구조

| 경로 | 내용 |
|---|---|
| `Game/GameModels.swift` | 밸런스 값, 카드·강화·변신, 지도, 체력·경제 공식 |
| `Game/GameSession.swift` | 지도 생성, 전투·수식 계산, 특전, 상점 |
| `Game/Progress.swift` | 저장 슬롯 3개, 업적, 카드 도감 |
| `Views/` | 메인 메뉴, 지도, 전투(부채꼴 손패), 상점, 테마 |
| `web/` | 웹 버전 (한 파일 HTML)과 글꼴 임베드 빌드 스크립트 |
| `android/` | 웹 버전을 띄우는 안드로이드 WebView 앱과 빌드 스크립트 |

## 기술 스택

- Swift, SwiftUI, Observation (외부 라이브러리 없음)
- 웹: Vanilla JavaScript, HTML, CSS (외부 라이브러리 없음), 안드로이드: Java WebView
- 진행상황은 슬롯별로 저장 (Apple: Application Support/Saves의 JSON, 웹·안드로이드: localStorage)
- 라이트/다크 모드, 가로·세로 화면, 터치·마우스 지원
