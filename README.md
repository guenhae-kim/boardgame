# Godot 4 Web 3D Multiplayer Prototype

모바일 브라우저 두 대가 같은 Room에 접속해 각자의 Cube를 동시에 움직이는 최소 완성형 프로젝트입니다. Node.js 서버가 Room과 위치의 권위를 가지며, Godot 클라이언트는 입력을 보내고 15 Hz snapshot을 60 fps 렌더링에서 보간합니다.

## 구현 범위

- HTTPS 페이지와 같은 origin의 `WSS /ws`에 자동 연결
- `Connecting`, `Connected`, `Disconnected`, `Error` 상태
- 닉네임, 4자리 Room Code 생성/참가
- Room별 충돌 없는 `player_1`, `player_2`, ... ID
- Room 격리와 최대 인원 설정
- Plane, Camera3D, DirectionalLight3D, 색이 다른 Cube
- 모바일 터치 방향키와 PC WASD/방향키
- 서버 30 Hz 시뮬레이션, 15 Hz snapshot, 클라이언트 20 Hz 입력
- 매 렌더 프레임 exponential interpolation
- heartbeat, 비정상 연결 timeout, 퇴장 Cube 제거
- 서버 cold start를 위한 2.5초 연결 재시도
- 프로토콜 버전과 명시적 JSON 메시지 타입
- reconnect token 추가 위치를 예약한 응답 필드

## 폴더 구조

```text
boardgame-network/
├── client/
│   ├── project.godot
│   ├── export_presets.cfg
│   ├── scenes/
│   │   ├── Main.tscn
│   │   ├── Lobby.tscn
│   │   ├── Game.tscn
│   │   └── Player.tscn
│   ├── scripts/
│   │   ├── Main.gd
│   │   ├── network/{NetworkClient,NetworkConfig,Protocol}.gd
│   │   ├── game/{GameManager,Player}.gd
│   │   └── ui/LobbyUI.gd
│   └── build/web/          # 배포 가능한 release export
├── server/
│   ├── package.json
│   ├── Dockerfile
│   ├── src/{server,protocol,RoomManager,Room}.js
│   └── test/integration.test.js
├── scripts/{export_web,verify}.sh
└── render.yaml
```

## 구조와 데이터 흐름

```text
터치/WASD → GameManager → NetworkClient → PLAYER_INPUT
                                      ↓
                               Node Room (권위 상태)
                                      ↓ 15 Hz PLAYER_STATE
Player visual ← GameManager ← NetworkClient ← snapshot
     ↓
매 프레임 목표 position/rotation으로 interpolation
```

`Protocol.gd`/`protocol.js`가 전송 형식을 담당하고, `Room`이 서버 상태와 시뮬레이션을 담당하며, `Player.gd`는 표현과 보간만 담당합니다. 따라서 Cube를 동물 Scene으로 교체해도 Room과 네트워크 계층은 유지됩니다.

## 로컬 실행

필수 도구는 Godot 4.3 이상(GDScript Web single-thread export 지원)과 Node.js 20 이상입니다.

```bash
cd server
npm ci
npm start
```

서버가 `http://127.0.0.1:8080`에서 Web build도 함께 제공합니다. 브라우저에서 해당 주소를 열거나, Godot Editor에서 `client/project.godot`을 열고 F6/F5로 실행합니다.

전체 자동 검증:

```bash
./scripts/verify.sh
```

서버 통합 테스트는 실제 WebSocket 클라이언트 3개로 생성, 참가, 이동, Room 격리, 퇴장을 검사합니다.

## Web export

Godot Editor에서 `client/project.godot`을 연 뒤:

1. Editor → Manage Export Templates에서 현재 Godot 버전의 template을 설치합니다.
2. Project → Export → Web을 선택합니다.
3. Export Project를 눌러 `client/build/web/index.html`로 내보냅니다.

CLI에서는 다음 한 줄로 동일하게 export합니다.

```bash
./scripts/export_web.sh
```

프로젝트는 Compatibility renderer, WebGL 2.0, single-thread Web export를 사용합니다. Thread support를 끄기 때문에 COOP/COEP 헤더가 필요 없고 모바일 Safari/Chrome에서 호환성이 더 좋습니다. `index.html`을 `file://`로 직접 열지 말고 반드시 HTTP(S) 서버에서 제공해야 합니다.

## 서버 주소 변경 위치

- Web export: 페이지와 같은 host의 `/ws`를 자동 사용합니다. 예를 들어 게임이 `https://my-game.onrender.com`에 있으면 자동으로 `wss://my-game.onrender.com/ws`에 연결됩니다. 변경할 주소가 없습니다.
- Godot Editor/native export: `client/scripts/network/NetworkConfig.gd`의 `LOCAL_SERVER_URL` 한 곳을 변경합니다.

Web 게임과 WebSocket 서버를 한 Render 서비스에서 제공하므로 mixed-content, CORS, 서로 다른 배포 URL 동기화 문제를 피합니다.

## Render 배포

현재 공식 정책상 Render 무료 Web Service는 public WebSocket, 관리형 TLS, `onrender.com` URL을 지원합니다. 15분간 유입 요청/WebSocket 메시지가 없으면 sleep하며 다음 접속에서 약 1분의 cold start가 생길 수 있습니다. 프로토타입에는 적합하지만 상시 게임 서버는 이후 유료 인스턴스가 적합합니다.

배포 전 `./scripts/verify.sh`를 실행하고 생성된 `client/build/web`도 Git에 포함해 저장소에 push합니다. 그 다음:

1. [Render Dashboard](https://dashboard.render.com/)에 로그인합니다.
2. New → Blueprint를 선택합니다.
3. 이 프로젝트가 들어 있는 GitHub/GitLab 저장소를 연결합니다.
4. 저장소 루트의 `render.yaml`을 승인합니다.
5. `godot-boardgame-prototype` Free Web Service 생성을 승인합니다.
6. deploy 완료 후 `https://<생성된 이름>.onrender.com/health`에서 `{"ok":true}`를 확인합니다.
7. 같은 URL의 `/`에 접속하면 게임이 실행됩니다. WSS endpoint는 자동으로 `wss://<생성된 이름>.onrender.com/ws`입니다.

계정 로그인과 Git 저장소 연결/승인은 사용자 계정 권한이 필요합니다. 코드에는 API key나 비밀번호가 필요하지 않습니다.

Docker로 다른 Linux 서비스에 배포할 수도 있습니다.

```bash
docker build -f server/Dockerfile -t godot-boardgame .
docker run --rm -p 8080:8080 -e PORT=8080 godot-boardgame
```

컨테이너는 `0.0.0.0:$PORT`를 사용하며 앞단 reverse proxy에서 HTTPS/WSS를 종료하면 됩니다.

## 휴대폰 두 대 최종 테스트

무료 서버가 sleep 중일 수 있으므로 먼저 게임 URL을 열고 `Connected`가 될 때까지 최대 약 1분 기다립니다.

Phone A:

1. Wi-Fi에 연결하고 Chrome/Safari에서 게임 HTTPS URL을 엽니다.
2. 닉네임 `A`를 입력하고 `방 만들기`를 누릅니다.
3. 화면 왼쪽 위 `ROOM: XXXX`를 Phone B에 전달합니다.

Phone B:

1. Wi-Fi를 끄고 LTE/5G에 연결합니다.
2. 같은 HTTPS URL을 엽니다.
3. 닉네임 `B`와 전달받은 코드를 입력하고 `방 참가`를 누릅니다.

확인 항목:

- 양쪽 화면에 빨강/파랑 Cube와 두 닉네임이 보인다.
- 양쪽에서 터치 방향키를 동시에 눌러도 각자 자신의 Cube가 움직인다.
- 상대 Cube가 순간이동하지 않고 보간되어 움직인다.
- 한쪽 탭을 닫은 뒤 heartbeat/close가 처리되면 상대 화면에서 Cube가 사라진다.
- 잘못된 Room Code는 `ROOM_NOT_FOUND`를 표시한다.

iOS Safari에서 화면이 빈 경우 기기가 WebGL 2.0을 지원하는지, 저전력 모드/콘텐츠 차단 설정, Safari Web Inspector 오류를 확인합니다. HTTPS 페이지에서 `ws://`로 수동 변경하면 mixed-content로 차단되므로 Web에서는 자동 same-origin 설정을 유지합니다.

## 향후 실제 게임으로 확장할 위치

- 동물/애니메이션: `Player.tscn`과 `Player.gd`의 visual만 교체
- 턴/돈/베팅/CPU: 서버 `Room.js`의 authoritative state와 별도 규칙 모듈 추가
- reconnect: 현재 `reconnect_token` 응답 필드와 connection context에 token 복구 처리 추가
- spectator: Room 참가 역할과 읽기 전용 클라이언트 타입 추가
- binary protocol: `Protocol.gd`와 `protocol.js`의 codec만 교체
- 주사위 물리: Node 서버를 Godot Headless 시뮬레이터로 교체하거나 별도 simulation adapter를 붙이고, `PLAYER_STATE`와 같은 방식으로 dice transform/velocity snapshot을 전송

주사위 확장 시 클라이언트는 `DiceVisual`이 timestamp가 있는 snapshot buffer를 소비하게 하고, 서버만 `RigidBody3D`를 실제 계산합니다. 네트워크 transport와 Room API는 그대로 유지할 수 있습니다.
# boardgame
