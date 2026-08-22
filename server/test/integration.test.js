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

  b.socket.close();
  assert.equal((await a.next(MessageType.PLAYER_LEFT)).payload.player_id, joined.payload.player_id);

  a.socket.close();
  outsider.socket.close();
  await server.close();
});
