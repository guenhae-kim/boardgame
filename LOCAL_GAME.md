# Camel Up 로컬 규칙 엔진

이 단계의 메인 씬은 네트워크와 독립된 패스앤플레이 규칙 테스트 화면입니다. 기존 `scenes/Main.tscn`, `scripts/network`, `server`는 수정하지 않았습니다.

## 실행과 자동 테스트

```bash
cd client
godot --editor project.godot
```

F6/F5를 누르면 `LocalGame.tscn`이 열립니다. 기본 화면에서는 현재 플레이어가 하단의 큰 행동 버튼 중 하나를 선택합니다. 이름 변경, 강제 주사위, 강제 스택, 로그와 Reset은 오른쪽 위 `DEV`를 눌렀을 때만 나타납니다.

```bash
godot --headless --path client --script res://tests/RuleTests.gd
godot --headless --path client --script res://tests/FlowTests.gd
godot --headless --path client --script res://tests/DiceSafetyTests.gd
```

규칙 테스트 63개는 피라미드가 한 구간에서 남은 주사위만 비복원 추첨하는지와 직렬화 가능한 구간 주사위 기록까지 검증합니다. Flow 통합 테스트는 실제 3D 물리 주사위, 강제 3단 스택 착지, 3D 주사위 기록 슬롯, GameState와 연동된 베팅 카드 더미, Event Queue 종료 후 다음 플레이어 입력 활성화를 검증합니다. Dice 안전 테스트는 여섯 색을 연속으로 낙하시켜 결과가 1~3이고 모두 투명 상단 가드 안에서 정지하는지 확인합니다.

## 코드 경계

- `GameState.gd`: 한 판을 저장/복원하는 순수 데이터. 플레이어 EP와 보유 타일/카드, 낙타 위치와 칸별 아래→위 스택, 관중 타일, 남은 주사위, 최종 베팅 순서, 턴·구간·종료 상태를 담습니다.
- `GameAction.gd`: `TAKE_LEG_BET`, `PLACE_SPECTATOR`, `ROLL_DIE`, `FINAL_BET`, `PARTNER` 요청 형식입니다.
- `GameRules.gd`: `validate_action` 뒤에만 상태를 바꾸고 `CamelEvent` 목록을 반환하는 권위 규칙 엔진입니다. UI나 네트워크 API를 호출하지 않습니다.
- `GameEvent.gd`: 이동, 스택, 주사위, 타일, 돈, 정산, 종료 등 이후 3D 연출이 소비할 결과입니다.
- `GameFlowController.gd`: 명시적 턴 상태 머신을 관리하고 모든 연출을 `await`한 뒤에만 다음 턴 입력을 엽니다.
- `GameEventQueue.gd`: 규칙 Event를 순서대로 하나씩 재생하는 Animation Queue입니다.
- `LocalGameUI.gd`: 패스앤플레이 입력을 Action으로 변환하고 둥근 Player/코인 HUD, 현재 턴, 구간 진행, 반응형 행동 바와 숨김 Debug Panel을 표시합니다.
- `BoardVisual.gd`: GameState와 Event를 읽어 장난감 트랙, 동물 스택, 관중 타일, 실제 베팅 카드 더미, 비공개 최종 예측 더미와 5칸 주사위 기록 트레이를 표시합니다.
- `PieceVisual.gd`: `play_idle/walk/jump/land/squashed/happy` 교체 가능한 말 표현 API입니다.
- `DiceController.gd`: 피라미드 하단 해치에서 선택된 색의 1/2/3 `RigidBody3D` 주사위를 떨어뜨리고, 높은 트레이 벽 안에서 충돌·정지·timeout·윗면 판정·이탈 복구를 수행합니다.
- `CameraDirector.gd`: 전체 보드, 주사위, 이동 말, 베팅 더미, 최종 예측, 주사위 기록 구역 사이를 Tween으로 이동하는 await 가능 카메라입니다.
- `GameDebug.gd`: 강제 주사위, 강제 스택/돈, 결승 직전, 구간/게임 강제 정산, 전체 상태 출력을 규칙 코드 밖에서 제공합니다.

나중에 중앙 authoritative 서버는 클라이언트가 보낸 Action을 역직렬화해 `GameRules.apply_action(player_id, action)`만 호출하면 됩니다. 비밀 최종 베팅은 전체 authoritative GameState에는 저장하되, 각 클라이언트로 snapshot을 보낼 때 별도 projection에서 숨겨야 합니다.

## 반영한 규칙

- 5개 경주 낙타와 2개 역주행 낙타의 룰북 초기 배치
- 같은 칸 아래→위 스택, 선택 낙타와 위쪽 전체 이동, 도착 스택 맨 위 착지
- 회색 주사위와 붙어 있는 역주행 낙타 둘 중 위 낙타만 움직이는 예외
- 구간 베팅 타일 5/3/2/2, 피라미드 타일, 여섯 주사위 중 다섯 번째 뒤 구간 종료
- 오아시스 +1(위 착지), 신기루 -1(아래 삽입), 소유자 1 EP 및 배치 제한
- 우승/준우승/그 외 구간 정산, 피라미드 타일 정산, EP가 0 아래로 내려가지 않는 규칙
- 6명 이상 파트너 교환과 상대의 양수 타일 하나를 복제하는 구간 보너스
- 우승/꼴찌 최종 베팅, 카드 색별 1회, 제출 순서대로 8/5/3/2/1 및 오답 -1
- 결승선 통과 즉시 구간+최종 정산, 최고 EP 공동 승자 처리

## 명시한 해석

- “가장 어린 사람부터”는 로컬 이름 정보만으로 판단할 수 없어 입력 순서의 첫 플레이어가 시작합니다.
- 초기 같은 칸의 낙타 순서는 주사위를 처리한 순서로 아래에서 위에 놓습니다. 실물 규칙의 자유로운 초기 스택 순서는 디지털 게임에서 재현 가능한 순서로 고정했습니다.
- 회색 주사위의 두 번째 초기 굴림에서 색 면은 무시하고 아직 놓지 않은 역주행 낙타를 해당 숫자 칸에 놓습니다.
- 최종 공동 승자는 룰북의 추가 타이브레이커가 없으므로 모두 승자로 기록합니다.

## 실제 턴 흐름

`TURN_START → WAITING_FOR_ACTION → ROLLING_DICE → RESOLVING_ACTION → PLAYING_MOVEMENT_ANIMATION → PLAYING_EFFECT_ANIMATION → TURN_END → 다음 TURN_START` 순서입니다. 주사위 물리 윗면이 확정된 뒤 그 값을 `GameRules`에 넘기고, 반환된 Event Queue가 완전히 비어야 다음 플레이어의 버튼을 활성화합니다. 구간/게임 종료는 각각 `ROUND_END`, `GAME_END`로 전환합니다.

주사위는 버튼으로 기본 세기 낙하를 실행하거나, 3D 피라미드를 마우스/터치로 잡아 직접 흔들 수 있습니다. 잡는 순간 Action 입력이 잠기고, 좌우 흔들기 거리와 아래 방향 드래그 거리가 1.0~3.4의 낙하 강도, 측면 impulse, torque로 환산됩니다. 트레이는 낮은 불투명 난간과 투명 아크릴 상단 벽으로 보여 주되 전체 높이의 충돌은 유지합니다.

한 주사위의 물리·이동·스택 연출이 끝나면 그 색과 숫자가 적힌 작은 3D 주사위가 구간 기록 트레이의 다음 빈 슬롯으로 이동합니다. 다섯 번째 주사위가 안착한 뒤에만 구간 완료 배너와 정산이 재생됩니다. 베팅 카드와 최종 예측 카드도 Event 연출 후 `GameState`의 실제 더미/제출 수로 다시 동기화되며, 최종 예측의 동물 색은 카드 뒷면으로 숨깁니다.

화면 비율은 `expand`를 사용합니다. 가로에서는 한 줄 행동 바와 넓은 보드를, 세로에서는 읽기 쉬운 큰 글자·두 열 터치 버튼·가로 폭을 유지하는 보드 카메라를 사용하며 화면 회전은 `GameState`를 다시 만들지 않습니다.

빠른 확인은 Debug Panel에서 `3단 스택 착지 상황 만들기`를 누른 뒤 `지정 결과로 3D 주사위 굴리기`를 누릅니다. red가 2번 칸에서 4번 칸의 blue/yellow 스택 위로 이동하고, 아래 말 squash와 위 말 bounce가 끝난 뒤 Player 2 턴이 열립니다.

최종 모델/애니메이션은 `PieceVisual.gd` API와 `CAMEL_MOVED`, `CAMELS_STACKED`, `SPECTATOR_TRIGGERED` Event handler에 연결합니다. UI/Visual에서는 돈이나 논리 위치를 직접 바꾸지 않습니다.
