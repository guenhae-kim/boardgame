# Boardgame Online — Godot 4 Web

Godot 4.7/GDScript로 만든 3D 동물 경주 보드게임과 Node.js WebSocket 서버입니다. 방 생성/참가부터 4인 로비, CPU, 비공개 손패, 직접 보드 상호작용, 동기화된 주사위·말 연출, 채팅, 재접속까지 한 서비스에서 실행합니다.

현재 공개 서비스: <https://godot-boardgame-prototype.onrender.com/>

## 현재 플레이 흐름

1. 닉네임으로 방을 만들거나 4자리 코드로 참가합니다.
2. Host가 CPU 수를 조절하고 빈 자리를 CPU로 채워 게임을 시작합니다.
3. Host의 `GameRules` 하나만 authoritative state를 계산합니다.
4. 서버는 공개 상태와 각 수신자 전용 비공개 손패를 따로 전송합니다.
5. 모든 접속자가 받은 `GameEvent` 연출을 끝내고 `GAME_READY`를 보낸 뒤에만 서버가 다음 행동을 엽니다.
6. 자기 턴에는 손패 카드→예측 구역, 관중 타일→트랙 칸, 구간 베팅→3D 카드 더미처럼 보드를 직접 누릅니다.
7. CPU도 사람과 같은 `Action → GameRules` 경로를 사용합니다.
8. Human 턴은 서버가 관리하는 60초 deadline을 가지며, 만료되면 모든 합법 Action 중 하나가 같은 규칙 경로로 자동 실행됩니다.

## 구조

```text
boardgame-network/
├── client/
│   ├── project.godot, export_presets.cfg
│   ├── scenes/{Main,Lobby,OnlineGame,LocalGame}.tscn
│   ├── scripts/
│   │   ├── rules/{GameState,GameRules,GameAction,GameEvent}.gd
│   │   ├── network/{NetworkClient,NetworkConfig,Protocol,GameProjection}.gd
│   │   ├── game/{OnlineGameController,CPUController}.gd
│   │   ├── flow/{GameFlowController,GameEventQueue}.gd
│   │   ├── local/BoardVisual.gd
│   │   ├── visual/{DiceController,PieceVisual,CameraDirector,SoundManager}.gd
│   │   └── ui/{LobbyUI,RoomLobbyUI,OnlineGameUI,LocalGameUI}.gd
│   ├── tests/
│   └── build/web/
├── server/
│   ├── src/{server,RoomManager,Room,protocol}.js
│   ├── test/integration.test.js
│   └── Dockerfile
├── scripts/{export_web,verify}.sh
├── render.yaml
└── THIRD_PARTY_ASSETS.md
```

`LocalGame.tscn`은 빠른 룰/연출 개발용입니다. 실제 시작 Scene은 `Main.tscn`이며 온라인 로비와 `OnlineGame.tscn`을 사용합니다.

## 권위 상태와 비공개 정보

```text
Human UI / CPUController
          ↓ GameAction
Node Room 검증 → Host GameRules.apply_action()
          ↓ GAME_COMMIT
Node Room: authority_state + public_state + private_states[player_id]
          ↓ 수신자별 GAME_UPDATE
각 Client GameEventQueue → 3D 연출 완료 → GAME_READY
          ↓ 모두 완료
       GAME_UNLOCK → 다음 행동
```

- `authority_state`: Host에게만 전송되는 완전한 저장 상태
- `public_state`: 말 위치/스택, 턴, 공개 주사위, 돈, 남은 베팅 카드, prediction 카드의 제출 순서/소유자
- `private_state`: 해당 플레이어 자신의 `final_cards`만 포함
- 다른 플레이어의 비밀 예측 내용은 서버 패킷 자체에 포함되지 않습니다.

현재 버전은 **Host-authoritative rules + Node room authority**입니다. Node가 player ownership, action lock, turn deadline과 client별 state routing을 검증합니다. Host가 끊기면 연결 중인 다음 Human으로 authority가 이동하고, 일반 플레이어는 reconnect token으로 같은 slot/hand를 복구합니다.

## 새 온라인 메시지

기본 `HELLO/CREATE_ROOM/JOIN_ROOM/PING/PONG/ERROR`에 다음 흐름을 사용합니다.

- 로비: `RECONNECT`, `LOBBY_STATE`, `LOBBY_CPU`, `START_GAME`
- 세션 수명주기: `SESSION_CHECK`, `SESSION_STATUS`, `LEAVE_ROOM`, `LEAVE_SESSION`, `ROOM_LEFT`
- 플레이어 정보: `UPDATE_NICKNAME`, `NICKNAME_UPDATED`, `PLAYER_TAKEOVER`
- 권위 게임: `GAME_AUTHORITY_REQUEST`, `GAME_ACTION`, `GAME_ACTION_REQUEST`, `GAME_COMMIT`, `GAME_UPDATE`
- 시간 초과: `GAME_TIMEOUT_REQUEST` (Node deadline 만료 → 현재 authority가 완전한 legal Action 생성)
- 연출 장벽: `GAME_READY`, `GAME_UNLOCK`
- 채팅: `CHAT_SEND`, `CHAT_MESSAGE`

채팅은 Room 안에서만 broadcast되며 공백 차단, 200자 제한, 350ms rate limit이 적용됩니다. 게임 Action 처리와 별도 경로입니다.

브라우저의 영구 `player identity`(identity id/닉네임)와 일시적인 `room session`(방 코드/좌석/reconnect token)은 별도 저장됩니다. 새 페이지는 로컬 세션만으로 자동 입장하지 않고 `SESSION_CHECK`로 서버의 active session 여부를 검증합니다. 명시적 Leave는 서버 ACK 뒤에만 room session을 지우며, 진행 중인 좌석은 즉시 CPU로 전환되고 기존 token은 폐기됩니다. 종료된 게임은 active resume 후보가 아닙니다.

## 로컬 실행과 검증

요구 사항: Godot 4.7.x, Node.js 20 이상.

```bash
cd server
npm ci
npm start
```

그 후 <http://127.0.0.1:8080/>을 열면 Web Export가 실행됩니다. Godot Editor에서는 `client/project.godot`을 연 뒤 **F6가 아니라 F5**로 온라인 Main Scene을 실행합니다. `LocalGame.tscn`의 F6 실행은 개발용 dropdown/debug 화면입니다.

```bash
./scripts/verify.sh
godot --headless --path client --script res://tests/OnlineNetworkE2E.gd
godot --headless --path client --script res://tests/OnlineNetworkE2E.gd -- --server-url=wss://godot-boardgame-prototype.onrender.com/ws
./scripts/verify_full_online.sh
```

검증 범위:

- 규칙 69개: 이동/스택/관중 타일/구간 정산/최종 예측/승자/private projection/CPU 완주
- 3D Flow: 이벤트 큐가 끝난 뒤에만 다음 턴
- Dice Safety: 여섯 색, 약/강 투척 모두 트레이 내부 유지
- Online UI: 손패, 내 턴 잠금, prediction/track 직접 대상
- Node 통합: Room 격리, Host/CPU, private routing, action order, ownership spoof reject, server timeout, reconnect, host migration
- 실제 Godot+Node E2E: 두 WebSocket 클라이언트가 동일 sequence의 주사위/이동 Event 수신
- Full Online E2E: Human 2 + CPU 2, 첫 Human timeout, private hand, ownership, reconnect를 포함해 GAME_OVER까지 완주

테스트 종료 때 표시되는 dummy-renderer RID 경고는 강제 종료형 headless Scene 테스트의 정리 경고이며 assertion 실패가 아닙니다.

## Web Export와 서버 주소

```bash
./scripts/export_web.sh
```

결과는 `client/build/web/index.html`입니다. Compatibility renderer와 single-thread Web export를 사용합니다.

- Web: 현재 페이지와 같은 origin의 `/ws`를 사용합니다. HTTPS에서는 자동으로 WSS입니다.
- Editor/native: `client/scripts/network/NetworkConfig.gd`의 `LOCAL_SERVER_URL`만 변경합니다.

따라서 배포 URL을 GDScript 여러 곳에 hard-code하지 않으며 mixed-content도 발생하지 않습니다.

## Render 배포

이 저장소의 `render.yaml`은 Web build 정적 파일과 Node WebSocket 서버를 한 서비스로 배포합니다.

```bash
git add .
git commit -m "Add playable authoritative online board game"
git push origin main
```

연결된 Render Blueprint가 자동 배포된 뒤 확인합니다.

- Health: <https://godot-boardgame-prototype.onrender.com/health>
- Game: <https://godot-boardgame-prototype.onrender.com/>
- WebSocket: `wss://godot-boardgame-prototype.onrender.com/ws`

무료 인스턴스가 sleep 상태면 첫 접속에 시간이 걸릴 수 있습니다. 다른 Linux 서비스에서는 `server/Dockerfile`로 동일하게 배포할 수 있습니다.

## 휴대폰 두 대 테스트

Phone A(Wi-Fi):

1. 게임 URL 접속 → `Connected` 대기
2. 닉네임 A → 방 만들기
3. Room Code 확인

Phone B(LTE/5G):

1. 같은 URL 접속
2. 닉네임 B와 Room Code → 참가
3. 양쪽 로비에서 두 Human slot 확인

Host:

1. `빈 자리 CPU로 채우기` 활성화
2. 게임 시작
3. 자기 턴에 손패/보드 대상을 직접 선택

확인 항목: Host만 Start, CPU 2명, 서로 다른 private hand, 내 턴만 Action, 동일 주사위/말 이동/돈/턴, 3D history 5개 후 구간 정산, 같은 Room 채팅, 페이지 refresh 후 동일 player 복구.

## 에셋

한글 폰트 라이선스와 사운드 구현은 [THIRD_PARTY_ASSETS.md](THIRD_PARTY_ASSETS.md)에 기록했습니다. SFX는 외부 파일을 내려받지 않고 런타임에서 합성하므로 추가 저작권 파일이 없습니다.
