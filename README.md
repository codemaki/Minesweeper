# MacosMinesweeper

[ReversingMinesweeper](../ReversingMinesweeper)(Windows XP 지뢰찾기 역공학 소스)를 Swift + AppKit으로 옮긴 macOS 네이티브 지뢰찾기입니다.

## 빌드 & 실행

```sh
swift run                      # 바로 실행
./Scripts/build-app.sh         # build/Minesweeper.app 생성 (universal, 아이콘 포함)
open build/Minesweeper.app
```

Xcode에서는 `Package.swift`를 열면 됩니다. macOS 13 이상.

## 조작

| 동작 | 방법 |
| --- | --- |
| 칸 열기 | 클릭 |
| 깃발 → ? → 해제 | 우클릭 / Control-클릭 |
| 주변 한꺼번에 열기(chord) | 좌+우 동시, 가운데 버튼, Shift/Option-클릭 |
| 새 게임 | 스마일 클릭, F2, ⌘N |
| 난이도 | ⌘1 초급 · ⌘2 중급 · ⌘3 고급 · ⌘4 사용자 지정 |
| 확대/축소 | Game ▸ Zoom (100–300%), ⌘+ / ⌘- |

Marks(?), Color(흑백 모드), Sound, Best Times(최고 기록/이름 저장) 메뉴도 원본과 같습니다.
설정과 기록은 레지스트리 대신 `UserDefaults`에 같은 키 이름(`Difficulty`, `Time1`, `Name1` …)으로 저장됩니다.

## 원본과의 대응

| 원본 (C / Win32) | 이 프로젝트 |
| --- | --- |
| `game.c` | `Game.swift` — 같은 블록 바이트 레이아웃(폭탄 0x80, 열림 0x40, 상태 0x1F)과 테두리 배열 |
| `drawing.c` + 비트맵 리소스 | `BoardView.swift`, `Sprites.swift` — 같은 픽셀 좌표계, 스프라이트는 코드로 그린 픽셀 아트 |
| `windowing.c` | `AppDelegate.swift`(메뉴·창·대화상자), `BoardView.swift`(마우스·키보드) |
| `config.c` | `Config.swift` |
| `sound.c` + WAV 리소스 | `Sound.swift` — 효과음을 실행 중에 합성 |

역공학 코드에 `WIERD`로 표시된 버그 등은 `// FIX:` 주석과 함께 고쳤습니다.
- 테두리 초기화 루프가 `row++`여서 끝나지 않던 문제
- 첫 클릭이 지뢰일 때 옮길 자리를 찾는 루프가 마지막 행/열을 건너뛰던 문제
- 3x3 클릭에서 깃발 수를 마스크 안 한 바이트와 비교해서 chord가 동작하지 않던 문제
- 누른 칸 표시에서 마스크 안 한 비교 때문에 지뢰 칸이 눌려 보이지 않던 문제
- 빈 칸 확장용 100칸 링버퍼가 큰 판에서 넘칠 수 있던 문제 → 일반 큐로 교체

이스터에그 `XYZZY`도 있습니다: xyzzy 입력 → Shift → 칸 위에 마우스를 올리면 창 왼쪽 위 1픽셀이 지뢰면 검정, 아니면 흰색이 됩니다.
