import assert from "node:assert/strict";
import test from "node:test";
import { WebSocket } from "ws";
import { createGameServer } from "../src/server.js";
import { MessageType, encode } from "../src/protocol.js";

function inbox(socket) {
  const queued = [];
  const waiters = [];
  socket.on("message", (raw) => {
    const message = JSON.parse(raw.toString());
    const waiterIndex = waiters.findIndex((waiter) => waiter.type === message.type);
    if (waiterIndex >= 0) waiters.splice(waiterIndex, 1)[0].resolve(message);
    else queued.push(message);
  });
  return (type, timeoutMs = 1500) => {
    const queuedIndex = queued.findIndex((message) => message.type === type);
    if (queuedIndex >= 0) return Promise.resolve(queued.splice(queuedIndex, 1)[0]);
    return new Promise((resolve, reject) => {
      const waiter = { type, resolve };
      waiters.push(waiter);
      setTimeout(() => {
        const index = waiters.indexOf(waiter);
        if (index >= 0) waiters.splice(index, 1);
        reject(new Error(`Timed out waiting for ${type}`));
      }, timeoutMs).unref();
    });
  };
}

async function connect(url) {
  const socket = new WebSocket(url);
  const next = inbox(socket);
  await new Promise((resolve, reject) => {
    socket.once("open", resolve);
    socket.once("error", reject);
  });
  await next(MessageType.HELLO);
  return { socket, next };
}

test("two players can join, move, remain room-isolated, and leave", async () => {
  const server = createGameServer();
  await new Promise((resolve) => server.httpServer.listen(0, "127.0.0.1", resolve));
  const { port } = server.httpServer.address();
  const url = `ws://127.0.0.1:${port}/ws`;

  const page = await (await fetch(`http://127.0.0.1:${port}/`)).text();
  assert.match(page, /src="index\.devbuild\.js"/);
  assert.match(page, /"executable":"index\.devbuild"/);
  const versionedAsset = await fetch(`http://127.0.0.1:${port}/index.devbuild.js`, { method: "HEAD" });
  assert.equal(versionedAsset.status, 200);
  assert.equal(versionedAsset.headers.get("cache-control"), "public, max-age=31536000, immutable");

  const a = await connect(url);
  const b = await connect(url);
  const outsider = await connect(url);
  const unnamed = await connect(url);

  unnamed.socket.send(encode(MessageType.CREATE_ROOM, { nickname: "   " }));
  const nicknameError = await unnamed.next(MessageType.ERROR);
  assert.equal(nicknameError.payload.code, "INVALID_NICKNAME");
  unnamed.socket.close();

  a.socket.send(encode(MessageType.CREATE_ROOM, { nickname: "A" }));
  const created = await a.next(MessageType.ROOM_CREATED);
  assert.match(created.payload.room_code, /^[A-Z2-9]{4}$/);

  b.socket.send(encode(MessageType.JOIN_ROOM, {
    nickname: "B",
    room_code: created.payload.room_code,
  }));
  const joined = await b.next(MessageType.ROOM_JOINED);
  assert.equal(joined.payload.players.length, 2);
  assert.notEqual(joined.payload.player_id, created.payload.player_id);
  assert.equal((await a.next(MessageType.PLAYER_JOINED)).payload.player.nickname, "B");

  outsider.socket.send(encode(MessageType.CREATE_ROOM, { nickname: "Other" }));
  await outsider.next(MessageType.ROOM_CREATED);

  const before = await b.next(MessageType.PLAYER_STATE);
  const beforeA = before.payload.players.find((player) => player.player_id === created.payload.player_id);
  a.socket.send(encode(MessageType.PLAYER_INPUT, { direction: { x: 1, z: 0 }, sequence: 1 }));

  let afterA = beforeA;
  for (let i = 0; i < 8 && afterA.position.x <= beforeA.position.x; i += 1) {
    const snapshot = await b.next(MessageType.PLAYER_STATE);
    assert.equal(snapshot.payload.room_code, created.payload.room_code);
    assert.equal(snapshot.payload.players.length, 2);
    afterA = snapshot.payload.players.find((player) => player.player_id === created.payload.player_id);
  }
  assert.ok(afterA.position.x > beforeA.position.x);

  a.socket.send(encode(MessageType.CHAT_SEND, { text: "hello room" }));
  const chat = await b.next(MessageType.CHAT_MESSAGE);
  assert.equal(chat.payload.player_id, created.payload.player_id);
  assert.equal(chat.payload.nickname, "A");
  assert.equal(chat.payload.text, "hello room");
  assert.equal(chat.payload.room_code, created.payload.room_code);

  b.socket.send(encode(MessageType.UPDATE_NICKNAME, { nickname: "Renamed B" }));
  const renamed = await a.next(MessageType.NICKNAME_UPDATED);
  assert.equal(renamed.payload.player_id, joined.payload.player_id);
  assert.equal(renamed.payload.nickname, "Renamed B");
  assert.equal(server.roomManager.getRoom(created.payload.room_code).players.get(joined.payload.player_id).nickname, "Renamed B");

  b.socket.close();
  assert.equal((await a.next(MessageType.PLAYER_LEFT)).payload.player_id, joined.payload.player_id);

  a.socket.close();
  outsider.socket.close();
  await server.close();
});

test("voluntary leave removes the lobby slot and invalidates reconnect", async () => {
  const server = createGameServer();
  await new Promise((resolve) => server.httpServer.listen(0, "127.0.0.1", resolve));
  const { port } = server.httpServer.address();
  const url = `ws://127.0.0.1:${port}/ws`;
  const host = await connect(url);
  const guest = await connect(url);
  host.socket.send(encode(MessageType.CREATE_ROOM, { nickname: "Host" }));
  const created = await host.next(MessageType.ROOM_CREATED);
  await host.next(MessageType.LOBBY_STATE);
  guest.socket.send(encode(MessageType.JOIN_ROOM, { nickname: "Guest", room_code: created.payload.room_code }));
  const joined = await guest.next(MessageType.ROOM_JOINED);
  await host.next(MessageType.PLAYER_JOINED);
  await host.next(MessageType.LOBBY_STATE);

  guest.socket.send(encode(MessageType.LEAVE_ROOM));
  const leftAck = await guest.next(MessageType.ROOM_LEFT);
  assert.equal(leftAck.payload.player_id, joined.payload.player_id);
  const leftBroadcast = await host.next(MessageType.PLAYER_LEFT);
  assert.equal(leftBroadcast.payload.player_id, joined.payload.player_id);
  assert.equal(leftBroadcast.payload.reconnecting, false);
  const lobby = await host.next(MessageType.LOBBY_STATE);
  assert.equal(lobby.payload.players.length, 1);

  guest.socket.send(encode(MessageType.RECONNECT, {
    room_code: created.payload.room_code,
    reconnect_token: joined.payload.reconnect_token,
  }));
  const rejected = await guest.next(MessageType.ERROR);
  assert.equal(rejected.payload.code, "RECONNECT_FAILED");
  host.socket.close();
  guest.socket.close();
  await server.close();
});

test("host authority, CPU lobby, private state routing, action order, and reconnect", async () => {
  const server = createGameServer();
  await new Promise((resolve) => server.httpServer.listen(0, "127.0.0.1", resolve));
  const { port } = server.httpServer.address();
  const url = `ws://127.0.0.1:${port}/ws`;
  const host = await connect(url);
  const guest = await connect(url);
  host.socket.send(encode(MessageType.CREATE_ROOM, { nickname: "Host" }));
  const created = await host.next(MessageType.ROOM_CREATED);
  guest.socket.send(encode(MessageType.JOIN_ROOM, { nickname: "Guest", room_code: created.payload.room_code }));
  const joined = await guest.next(MessageType.ROOM_JOINED);

  host.socket.send(encode(MessageType.LOBBY_CPU, { count: 2 }));
  let withCpus;
  for (let i = 0; i < 4; i += 1) {
    const lobby = await host.next(MessageType.LOBBY_STATE);
    if (lobby.payload.players.length === 4) { withCpus = lobby; break; }
  }
  assert.ok(withCpus);
  assert.equal(withCpus.payload.players.filter((player) => player.is_cpu).length, 2);
  host.socket.send(encode(MessageType.START_GAME, { fill_cpu: true }));
  const authorityRequest = await host.next(MessageType.GAME_AUTHORITY_REQUEST);
  assert.equal(authorityRequest.payload.players.length, 4);

  const players = authorityRequest.payload.players.map((player) => ({
    id: player.player_id, name: player.nickname, is_cpu: player.is_cpu, money: 3,
  }));
  const publicState = { players, current_player_index: 1, phase: "PLAYING" };
  const privateStates = Object.fromEntries(players.map((player) => [player.id, {
    player_id: player.id, final_cards: [`secret_${player.id}`],
  }]));
  host.socket.send(encode(MessageType.GAME_COMMIT, {
    actor_id: "", events: [], public_state: publicState,
    private_states: privateStates, authority_state: { ...publicState, privateStates },
  }));
  const hostUpdate = await host.next(MessageType.GAME_UPDATE);
  const guestUpdate = await guest.next(MessageType.GAME_UPDATE);
  assert.ok(hostUpdate.payload.authority_state);
  assert.equal(guestUpdate.payload.authority_state, undefined);
  assert.deepEqual(guestUpdate.payload.private_state.final_cards, [`secret_${joined.payload.player_id}`]);
  assert.doesNotMatch(JSON.stringify(guestUpdate.payload), /secret_player_1/);
  host.socket.send(encode(MessageType.GAME_READY, { game_sequence: 1 }));
  guest.socket.send(encode(MessageType.GAME_READY, { game_sequence: 1 }));
  await host.next(MessageType.GAME_UNLOCK);
  await guest.next(MessageType.GAME_UNLOCK);

  guest.socket.send(encode(MessageType.GAME_ACTION, {
    request_id: "guest-action-1", action: { type: "ROLL_DIE", data: {} },
  }));
  const request = await host.next(MessageType.GAME_ACTION_REQUEST);
  assert.equal(request.payload.actor_id, joined.payload.player_id);
  const advanced = { ...publicState, current_player_index: 2 };
  host.socket.send(encode(MessageType.GAME_COMMIT, {
    actor_id: joined.payload.player_id,
    events: [{ type: "DIE_ROLLED", data: { die: "blue", camel: "blue", value: 3 } }],
    public_state: advanced, private_states: privateStates,
    authority_state: { ...advanced, privateStates },
  }));
  assert.equal((await guest.next(MessageType.GAME_UPDATE)).payload.game_sequence, 2);

  guest.socket.close();
  await host.next(MessageType.PLAYER_LEFT);
  const resumed = await connect(url);
  resumed.socket.send(encode(MessageType.RECONNECT, {
    room_code: created.payload.room_code, reconnect_token: joined.payload.reconnect_token,
  }));
  const rejoined = await resumed.next(MessageType.ROOM_JOINED);
  assert.equal(rejoined.payload.player_id, joined.payload.player_id);
  const restored = await resumed.next(MessageType.GAME_UPDATE);
  assert.equal(restored.payload.game_sequence, 2);
  assert.deepEqual(restored.payload.private_state.final_cards, [`secret_${joined.payload.player_id}`]);

  host.socket.close();
  resumed.socket.close();
  await server.close();
});

test("host can fill all three empty slots with CPU players", async () => {
  const server = createGameServer();
  await new Promise((resolve) => server.httpServer.listen(0, "127.0.0.1", resolve));
  const { port } = server.httpServer.address();
  const host = await connect(`ws://127.0.0.1:${port}/ws`);
  host.socket.send(encode(MessageType.CREATE_ROOM, { nickname: "Solo Host" }));
  await host.next(MessageType.ROOM_CREATED);
  host.socket.send(encode(MessageType.LOBBY_CPU, { count: 3 }));
  host.socket.send(encode(MessageType.START_GAME, { fill_cpu: true }));
  const request = await host.next(MessageType.GAME_AUTHORITY_REQUEST);
  assert.equal(request.payload.players.length, 4);
  assert.equal(request.payload.players.filter((player) => player.is_cpu).length, 3);
  host.socket.close();
  await server.close();
});

test("four human clients occupy four stable slots without CPU fill", async () => {
  const server = createGameServer();
  await new Promise((resolve) => server.httpServer.listen(0, "127.0.0.1", resolve));
  const { port } = server.httpServer.address();
  const url = `ws://127.0.0.1:${port}/ws`;
  const clients = await Promise.all([connect(url), connect(url), connect(url), connect(url)]);
  clients[0].socket.send(encode(MessageType.CREATE_ROOM, { nickname: "P1" }));
  const created = await clients[0].next(MessageType.ROOM_CREATED);
  for (let index = 1; index < clients.length; index += 1) {
    clients[index].socket.send(encode(MessageType.JOIN_ROOM, { room_code: created.payload.room_code, nickname: `P${index + 1}` }));
    await clients[index].next(MessageType.ROOM_JOINED);
  }
  clients[0].socket.send(encode(MessageType.START_GAME, { fill_cpu: false }));
  const request = await clients[0].next(MessageType.GAME_AUTHORITY_REQUEST);
  assert.deepEqual(request.payload.players.map((player) => player.player_id), ["player_1", "player_2", "player_3", "player_4"]);
  assert.equal(request.payload.players.some((player) => player.is_cpu), false);
  for (const client of clients) client.socket.close();
  await server.close();
});

test("server-owned turn deadline rejects ownership spoofing and requests timeout action", async () => {
  const server = createGameServer({ turnDurationMs: 140 });
  await new Promise((resolve) => server.httpServer.listen(0, "127.0.0.1", resolve));
  const { port } = server.httpServer.address();
  const url = `ws://127.0.0.1:${port}/ws`;
  const host = await connect(url);
  const guest = await connect(url);
  host.socket.send(encode(MessageType.CREATE_ROOM, { nickname: "A" }));
  const created = await host.next(MessageType.ROOM_CREATED);
  guest.socket.send(encode(MessageType.JOIN_ROOM, { nickname: "B", room_code: created.payload.room_code }));
  const joined = await guest.next(MessageType.ROOM_JOINED);
  host.socket.send(encode(MessageType.START_GAME, { fill_cpu: true }));
  const authority = await host.next(MessageType.GAME_AUTHORITY_REQUEST);
  const players = authority.payload.players.map((player) => ({
    id: player.player_id, name: player.nickname, is_cpu: player.is_cpu, money: 3,
  }));
  const publicState = { players, current_player_index: 1, phase: "PLAYING" };
  const privateStates = Object.fromEntries(players.map((player) => [player.id, { final_cards: ["red"] }]));
  host.socket.send(encode(MessageType.GAME_COMMIT, {
    actor_id: "", events: [], public_state: publicState,
    private_states: privateStates, authority_state: publicState,
  }));
  await host.next(MessageType.GAME_UPDATE);
  await guest.next(MessageType.GAME_UPDATE);
  host.socket.send(encode(MessageType.GAME_READY, { game_sequence: 1 }));
  guest.socket.send(encode(MessageType.GAME_READY, { game_sequence: 1 }));
  const unlocked = await guest.next(MessageType.GAME_UNLOCK);
  await host.next(MessageType.GAME_UNLOCK);
  assert.ok(unlocked.payload.turn_deadline_ms > unlocked.payload.server_time);

  guest.socket.send(encode(MessageType.GAME_ACTION, {
    request_id: "spoof", action: { type: "ROLL_DIE", player_id: created.payload.player_id, data: {} },
  }));
  const ownershipError = await guest.next(MessageType.ERROR);
  assert.equal(ownershipError.payload.code, "PLAYER_OWNERSHIP_MISMATCH");

  const timeout = await host.next(MessageType.GAME_TIMEOUT_REQUEST, 1500);
  assert.equal(timeout.payload.actor_id, joined.payload.player_id);
  const advanced = { ...publicState, current_player_index: 2 };
  host.socket.send(encode(MessageType.GAME_COMMIT, {
    actor_id: joined.payload.player_id,
    events: [{ type: "TURN_TIMED_OUT", data: { player_id: joined.payload.player_id } }],
    public_state: advanced, private_states: privateStates, authority_state: advanced,
  }));
  const afterTimeout = await guest.next(MessageType.GAME_UPDATE);
  assert.equal(afterTimeout.payload.events[0].type, "TURN_TIMED_OUT");
  assert.equal(afterTimeout.payload.public_state.current_player_index, 2);
  host.socket.close();
  guest.socket.close();
  await server.close();
});

test("connected human receives host authority after the host disconnects", async () => {
  const server = createGameServer();
  await new Promise((resolve) => server.httpServer.listen(0, "127.0.0.1", resolve));
  const { port } = server.httpServer.address();
  const url = `ws://127.0.0.1:${port}/ws`;
  const host = await connect(url);
  const guest = await connect(url);
  host.socket.send(encode(MessageType.CREATE_ROOM, { nickname: "Host" }));
  const created = await host.next(MessageType.ROOM_CREATED);
  guest.socket.send(encode(MessageType.JOIN_ROOM, { nickname: "Next Host", room_code: created.payload.room_code }));
  const joined = await guest.next(MessageType.ROOM_JOINED);
  host.socket.send(encode(MessageType.START_GAME, { fill_cpu: true }));
  const request = await host.next(MessageType.GAME_AUTHORITY_REQUEST);
  const players = request.payload.players.map((player) => ({ id: player.player_id, name: player.nickname, is_cpu: player.is_cpu }));
  const state = { players, current_player_index: 1, phase: "PLAYING" };
  const privateStates = Object.fromEntries(players.map((player) => [player.id, { final_cards: ["blue"] }]));
  host.socket.send(encode(MessageType.GAME_COMMIT, {
    actor_id: "", events: [], public_state: state, private_states: privateStates, authority_state: state,
  }));
  await host.next(MessageType.GAME_UPDATE);
  await guest.next(MessageType.GAME_UPDATE);
  host.socket.close();
  let lobby;
  for (let index = 0; index < 6; index += 1) {
    lobby = await guest.next(MessageType.LOBBY_STATE);
    if (lobby.payload.host_player_id === joined.payload.player_id) break;
  }
  assert.equal(lobby.payload.host_player_id, joined.payload.player_id);
  const migration = await guest.next(MessageType.GAME_AUTHORITY_REQUEST);
  assert.equal(migration.payload.reason, "host_migration");
  assert.deepEqual(migration.payload.authority_state, state);
  guest.socket.close();
  await server.close();
});

test("session check validates before resume and detached leave revokes the token", async () => {
  const server = createGameServer();
  await new Promise((resolve) => server.httpServer.listen(0, "127.0.0.1", resolve));
  const { port } = server.httpServer.address();
  const url = `ws://127.0.0.1:${port}/ws`;
  const host = await connect(url);
  host.socket.send(encode(MessageType.CREATE_ROOM, { nickname: "Persistent", identity_id: "browser-id" }));
  const created = await host.next(MessageType.ROOM_CREATED);
  host.socket.close();

  const checker = await connect(url);
  checker.socket.send(encode(MessageType.SESSION_CHECK, {
    room_code: created.payload.room_code, reconnect_token: created.payload.reconnect_token,
  }));
  const status = await checker.next(MessageType.SESSION_STATUS);
  assert.equal(status.payload.status, "active");
  assert.equal(status.payload.player_id, created.payload.player_id);

  checker.socket.send(encode(MessageType.LEAVE_SESSION, {
    room_code: created.payload.room_code, reconnect_token: created.payload.reconnect_token,
  }));
  await checker.next(MessageType.ROOM_LEFT);
  checker.socket.send(encode(MessageType.RECONNECT, {
    room_code: created.payload.room_code, reconnect_token: created.payload.reconnect_token,
  }));
  const rejected = await checker.next(MessageType.ERROR);
  assert.ok(["ROOM_NOT_FOUND", "RECONNECT_FAILED"].includes(rejected.payload.code));
  checker.socket.close();
  await server.close();
});

test("explicit leave during a running game immediately creates a CPU takeover and revokes reconnect", async () => {
  const server = createGameServer();
  await new Promise((resolve) => server.httpServer.listen(0, "127.0.0.1", resolve));
  const { port } = server.httpServer.address();
  const url = `ws://127.0.0.1:${port}/ws`;
  const host = await connect(url);
  const guest = await connect(url);
  host.socket.send(encode(MessageType.CREATE_ROOM, { nickname: "Host" }));
  const created = await host.next(MessageType.ROOM_CREATED);
  guest.socket.send(encode(MessageType.JOIN_ROOM, { nickname: "Leaving", room_code: created.payload.room_code }));
  const joined = await guest.next(MessageType.ROOM_JOINED);
  host.socket.send(encode(MessageType.START_GAME, { fill_cpu: true }));
  const request = await host.next(MessageType.GAME_AUTHORITY_REQUEST);
  const players = request.payload.players.map((player) => ({ id: player.player_id, name: player.nickname, is_cpu: player.is_cpu }));
  const state = { players, current_player_index: 1, phase: "PLAYING", leg_number: 2 };
  const privateStates = Object.fromEntries(players.map((player) => [player.id, { player_id: player.id, final_cards: ["secret"] }]));
  host.socket.send(encode(MessageType.GAME_COMMIT, {
    actor_id: "", events: [], public_state: state, private_states: privateStates, authority_state: structuredClone(state),
  }));
  await host.next(MessageType.GAME_UPDATE);
  await guest.next(MessageType.GAME_UPDATE);

  guest.socket.send(encode(MessageType.LEAVE_ROOM));
  await guest.next(MessageType.ROOM_LEFT);
  const takeover = await host.next(MessageType.PLAYER_TAKEOVER);
  assert.equal(takeover.payload.player_id, joined.payload.player_id);
  assert.equal(takeover.payload.reason, "explicit_leave");
  const room = server.roomManager.getRoom(created.payload.room_code);
  const seat = room.players.get(joined.payload.player_id);
  assert.equal(seat.isCpu, true);
  assert.equal(seat.reconnectToken, "");
  assert.equal(room.publicState.players.find((player) => player.id === joined.payload.player_id).is_cpu, true);

  const attacker = await connect(url);
  attacker.socket.send(encode(MessageType.RECONNECT, {
    room_code: created.payload.room_code, reconnect_token: joined.payload.reconnect_token,
  }));
  assert.equal((await attacker.next(MessageType.ERROR)).payload.code, "RECONNECT_FAILED");
  host.socket.close();
  guest.socket.close();
  attacker.socket.close();
  await server.close();
});

test("finished game is not resumable and stale session check cleans membership", async (t) => {
  const server = createGameServer();
  await new Promise((resolve) => server.httpServer.listen(0, "127.0.0.1", resolve));
  const { port } = server.httpServer.address();
  const url = `ws://127.0.0.1:${port}/ws`;
  const host = await connect(url);
  const guest = await connect(url);
  let checker;
  t.after(async () => {
    host.socket.close();
    guest.socket.close();
    checker?.socket.close();
    await server.close();
  });
  host.socket.send(encode(MessageType.CREATE_ROOM, { nickname: "Host" }));
  const created = await host.next(MessageType.ROOM_CREATED);
  guest.socket.send(encode(MessageType.JOIN_ROOM, { nickname: "Finisher", room_code: created.payload.room_code }));
  const joined = await guest.next(MessageType.ROOM_JOINED);
  host.socket.send(encode(MessageType.START_GAME, { fill_cpu: true }));
  const request = await host.next(MessageType.GAME_AUTHORITY_REQUEST);
  const players = request.payload.players.map((player) => ({ id: player.player_id, name: player.nickname, is_cpu: player.is_cpu, money: 3 }));
  const finished = { players, current_player_index: 0, phase: "GAME_OVER", leg_number: 5 };
  host.socket.send(encode(MessageType.GAME_COMMIT, {
    actor_id: "", events: [], public_state: finished,
    private_states: Object.fromEntries(players.map((player) => [player.id, {}])), authority_state: structuredClone(finished),
  }));
  await host.next(MessageType.GAME_UPDATE);
  await guest.next(MessageType.GAME_UPDATE);
  guest.socket.close();

  checker = await connect(url);
  checker.socket.send(encode(MessageType.SESSION_CHECK, {
    room_code: created.payload.room_code, reconnect_token: joined.payload.reconnect_token,
  }));
  assert.equal((await checker.next(MessageType.SESSION_STATUS)).payload.status, "finished");
  checker.socket.send(encode(MessageType.RECONNECT, {
    room_code: created.payload.room_code, reconnect_token: joined.payload.reconnect_token,
  }));
  assert.equal((await checker.next(MessageType.ERROR)).payload.code, "GAME_FINISHED");
});

test("network disconnect keeps reconnect grace, then independently converts the seat to CPU", async (t) => {
  const server = createGameServer();
  await new Promise((resolve) => server.httpServer.listen(0, "127.0.0.1", resolve));
  const { port } = server.httpServer.address();
  const url = `ws://127.0.0.1:${port}/ws`;
  const host = await connect(url);
  const guest = await connect(url);
  t.after(async () => { host.socket.close(); guest.socket.close(); await server.close(); });
  host.socket.send(encode(MessageType.CREATE_ROOM, { nickname: "Host" }));
  const created = await host.next(MessageType.ROOM_CREATED);
  guest.socket.send(encode(MessageType.JOIN_ROOM, { nickname: "Temporary", room_code: created.payload.room_code }));
  const joined = await guest.next(MessageType.ROOM_JOINED);
  const room = server.roomManager.getRoom(created.payload.room_code);
  room.started = true;
  room.publicState = {
    phase: "PLAYING", current_player_index: 1,
    players: room.publicPlayers().map((player) => ({ id: player.player_id, name: player.nickname, is_cpu: player.is_cpu })),
  };
  room.authorityState = structuredClone(room.publicState);
  guest.socket.close();
  await host.next(MessageType.PLAYER_LEFT);
  assert.equal(room.players.get(joined.payload.player_id).isCpu, false);
  assert.equal(room.players.get(joined.payload.player_id).reconnectToken, joined.payload.reconnect_token);
  room.expireDisconnected(Date.now() + 61_000);
  const takeover = await host.next(MessageType.PLAYER_TAKEOVER);
  assert.equal(takeover.payload.reason, "reconnect_timeout");
  assert.equal(room.players.get(joined.payload.player_id).isCpu, true);
  assert.equal(room.players.get(joined.payload.player_id).reconnectToken, "");
});
test("TV spectator never occupies a player slot, receives public-only state, and cannot act", async () => {
  const server = createGameServer();
  await new Promise((resolve) => server.httpServer.listen(0, "127.0.0.1", resolve));
  const { port } = server.httpServer.address();
  const url = `ws://127.0.0.1:${port}/ws`;
  const clients = await Promise.all(Array.from({ length: 5 }, () => connect(url)));
  const [host, p2, p3, p4, tv] = clients;
  host.socket.send(encode(MessageType.CREATE_ROOM, { nickname: "Host" }));
  const created = await host.next(MessageType.ROOM_CREATED);
  await host.next(MessageType.LOBBY_STATE);
  for (const [index, client] of [p2, p3, p4].entries()) {
    client.socket.send(encode(MessageType.JOIN_ROOM, { room_code: created.payload.room_code, nickname: `P${index + 2}` }));
    await client.next(MessageType.ROOM_JOINED);
  }
  tv.socket.send(encode(MessageType.JOIN_SPECTATOR, { room_code: created.payload.room_code, nickname: "Living Room TV" }));
  const joined = await tv.next(MessageType.SPECTATOR_JOINED);
  assert.equal(joined.payload.role, "spectator");
  assert.equal(joined.payload.players.length, 4);
  assert.equal(joined.payload.lobby.players.length, 4);
  assert.equal(joined.payload.lobby.spectator_count, 1);
  const room = server.roomManager.getRoom(created.payload.room_code);
  assert.equal(room.players.size, 4);
  assert.equal(room.spectators.size, 1);

  tv.socket.send(encode(MessageType.GAME_ACTION, {
    request_id: "forged-tv-action",
    action: { type: "ROLL_DIE", player_id: created.payload.player_id, data: {} },
  }));
  const forbidden = await tv.next(MessageType.ERROR);
  assert.equal(forbidden.payload.code, "SPECTATOR_FORBIDDEN");

  host.socket.send(encode(MessageType.START_GAME, { fill_cpu: true }));
  await host.next(MessageType.GAME_AUTHORITY_REQUEST);
  const publicState = {
    phase: "PLAYING", current_player_index: 0,
    players: [{ id: created.payload.player_id, name: "Host", money: 3 }],
  };
  host.socket.send(encode(MessageType.GAME_COMMIT, {
    actor_id: "",
    public_state: publicState,
    authority_state: { ...publicState, server_secret: "authority-only" },
    private_states: { [created.payload.player_id]: { final_cards: ["red"], private_secret: "hidden" } },
    events: [],
  }));
  const update = await tv.next(MessageType.GAME_UPDATE);
  assert.equal(update.payload.role, "spectator");
  assert.deepEqual(update.payload.public_state, publicState);
  assert.equal("private_state" in update.payload, false);
  assert.equal("private_states" in update.payload, false);
  assert.equal("authority_state" in update.payload, false);
  assert.equal("reconnect_token" in update.payload, false);

  tv.socket.close();
  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.equal(room.players.size, 4);
  assert.deepEqual(room.publicState, publicState);
  for (const client of [host, p2, p3, p4]) client.socket.close();
  await server.close();
});
