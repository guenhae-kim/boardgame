import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readFile, stat } from "node:fs/promises";
import { WebSocketServer } from "ws";
import { MessageType, ProtocolError, decode, encode, PROTOCOL_VERSION } from "./protocol.js";
import { RoomManager } from "./RoomManager.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_STATIC_DIR = path.resolve(__dirname, "../../client/build/web");
const MAX_MESSAGE_BYTES = 128 * 1024;
const SIMULATION_HZ = 30;
const SNAPSHOT_HZ = 15;

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
};

function validatedNickname(value) {
  const nickname = Array.from(String(value || "").trim()).slice(0, 20).join("");
  if (!nickname) throw new ProtocolError("INVALID_NICKNAME", "Nickname is required");
  return nickname;
}

function safeChatText(value) {
  return Array.from(String(value || "").replace(/[\r\n\t]+/g, " ").trim())
    .slice(0, 200)
    .join("");
}

function send(socket, type, payload = {}) {
  if (socket.readyState === 1) socket.send(encode(type, payload));
}

function sendError(socket, code, message) {
  send(socket, MessageType.ERROR, { code, message });
}

function normalizedBuildVersion(value) {
  return String(value || "devbuild").replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 12) || "devbuild";
}

async function serveStatic(request, response, staticDir, buildVersion) {
  const requestUrl = new URL(request.url, "http://localhost");
  if (requestUrl.pathname === "/health") {
    response.writeHead(200, { "content-type": "application/json; charset=utf-8" });
    response.end(JSON.stringify({ ok: true, protocol_version: PROTOCOL_VERSION }));
    return;
  }

  let pathname = decodeURIComponent(requestUrl.pathname);
  if (pathname === "/") pathname = "/index.html";

  const versionedPrefix = `/index.${buildVersion}.`;
  const isVersionedAsset = pathname.startsWith(versionedPrefix);
  if (isVersionedAsset) {
    pathname = `/index.${pathname.slice(versionedPrefix.length)}`;
  }
  const resolved = path.resolve(staticDir, `.${pathname}`);
  if (!resolved.startsWith(`${path.resolve(staticDir)}${path.sep}`)) {
    response.writeHead(403).end("Forbidden");
    return;
  }

  try {
    const fileStat = await stat(resolved);
    if (!fileStat.isFile()) throw new Error("not a file");
    let data = await readFile(resolved);
    if (pathname === "/index.html") {
      data = Buffer.from(
        data.toString("utf8")
          .replaceAll("index.", `index.${buildVersion}.`)
          .replace('"executable":"index"', `"executable":"index.${buildVersion}"`),
      );
    }
    const shouldRevalidate = pathname === "/index.html" || path.extname(resolved) === ".pck";
    response.writeHead(200, {
      "content-type": MIME_TYPES[path.extname(resolved)] || "application/octet-stream",
      "cache-control": isVersionedAsset
        ? "public, max-age=31536000, immutable"
        : shouldRevalidate ? "no-cache" : "public, max-age=3600",
    });
    response.end(data);
  } catch {
    response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    response.end("Godot Web build not found. Run the documented web export command.");
  }
}

export function createGameServer(options = {}) {
  const staticDir = options.staticDir || process.env.STATIC_DIR || DEFAULT_STATIC_DIR;
  const buildVersion = normalizedBuildVersion(
    options.buildVersion || process.env.RENDER_GIT_COMMIT || "devbuild",
  );
  const roomManager = new RoomManager({
    maxPlayers: Number(options.maxPlayers || process.env.MAX_ROOM_PLAYERS) || 8,
    turnDurationMs: Number(options.turnDurationMs || process.env.TURN_DURATION_MS) || 60_000,
  });
  const httpServer = http.createServer((req, res) => serveStatic(req, res, staticDir, buildVersion));
  const wsServer = new WebSocketServer({ noServer: true, maxPayload: MAX_MESSAGE_BYTES });

  httpServer.on("upgrade", (request, socket, head) => {
    const pathname = new URL(request.url, "http://localhost").pathname;
    if (pathname !== "/ws") {
      socket.write("HTTP/1.1 404 Not Found\r\n\r\n");
      socket.destroy();
      return;
    }
    wsServer.handleUpgrade(request, socket, head, (webSocket) => {
      wsServer.emit("connection", webSocket, request);
    });
  });

  wsServer.on("connection", (socket) => {
    socket.context = { room: null, role: "", playerId: null, spectatorId: null, alive: true, lastChatAt: 0 };
    socket.on("pong", () => { socket.context.alive = true; });
    send(socket, MessageType.HELLO, {
      protocol_version: PROTOCOL_VERSION,
      server_time: Date.now(),
      heartbeat_ms: 20_000,
    });

    socket.on("message", (raw) => {
      try {
        const { type, payload } = decode(raw);
        if (type === MessageType.HELLO) return;
        if (type === MessageType.PING) {
          send(socket, MessageType.PONG, { client_time: payload.client_time, server_time: Date.now() });
          return;
        }
        if (type === MessageType.PONG) return;

        if (type === MessageType.CREATE_ROOM) {
          if (socket.context.room) throw new ProtocolError("ALREADY_IN_ROOM", "Already in a room");
          const room = roomManager.createRoom();
          const player = room.addPlayer(socket, validatedNickname(payload.nickname), payload.identity_id);
          socket.context = { ...socket.context, room, role: "player", playerId: player.id, spectatorId: null };
          send(socket, MessageType.ROOM_CREATED, {
            room_code: room.code,
            player_id: player.id,
            reconnect_token: player.reconnectToken,
            players: room.publicPlayers(),
            lobby: room.lobbyPayload(),
          });
          room.broadcastLobby();
          return;
        }

        if (type === MessageType.JOIN_ROOM) {
          if (socket.context.room) throw new ProtocolError("ALREADY_IN_ROOM", "Already in a room");
          const room = roomManager.getRoom(payload.room_code);
          if (!room) throw new ProtocolError("ROOM_NOT_FOUND", "Room code was not found");
          const nickname = validatedNickname(payload.nickname);
          let player;
          player = room.addPlayer(socket, nickname, payload.identity_id);
          socket.context = { ...socket.context, room, role: "player", playerId: player.id, spectatorId: null };
          send(socket, MessageType.ROOM_JOINED, {
            room_code: room.code,
            player_id: player.id,
            reconnect_token: player.reconnectToken,
            players: room.publicPlayers(),
            lobby: room.lobbyPayload(),
          });
          room.broadcast(MessageType.PLAYER_JOINED, { player: room.publicPlayer(player) }, socket);
          room.broadcastLobby();
          return;
        }

        if (type === MessageType.JOIN_SPECTATOR) {
          if (socket.context.room) throw new ProtocolError("ALREADY_IN_ROOM", "Already in a room");
          const room = roomManager.getRoom(payload.room_code);
          if (!room) throw new ProtocolError("ROOM_NOT_FOUND", "Room code was not found");
          const spectator = room.addSpectator(socket, validatedNickname(payload.nickname), payload.identity_id);
          socket.context = { ...socket.context, room, role: "spectator", playerId: null, spectatorId: spectator.id };
          send(socket, MessageType.SPECTATOR_JOINED, {
            room_code: room.code,
            role: "spectator",
            spectator_id: spectator.id,
            reconnect_token: spectator.reconnectToken,
            players: room.publicPlayers(),
            lobby: room.lobbyPayload(),
            started: room.started,
          });
          room.broadcastLobby();
          if (room.started) room.sendSpectatorGameUpdate(spectator);
          return;
        }

        if (type === MessageType.RECONNECT) {
          if (socket.context.room) throw new ProtocolError("ALREADY_IN_ROOM", "Already in a room");
          const room = roomManager.getRoom(payload.room_code);
          if (!room) throw new ProtocolError("ROOM_NOT_FOUND", "Room code was not found");
          const token = String(payload.reconnect_token || "");
          const existingPlayer = room.playerForToken(token);
          if (!existingPlayer) {
            const spectator = room.reconnectSpectator(socket, token);
            socket.context = { ...socket.context, room, role: "spectator", playerId: null, spectatorId: spectator.id };
            send(socket, MessageType.SPECTATOR_JOINED, {
              room_code: room.code, role: "spectator", spectator_id: spectator.id,
              reconnect_token: spectator.reconnectToken, players: room.publicPlayers(),
              lobby: room.lobbyPayload(), reconnected: true, started: room.started,
            });
            room.broadcastLobby();
            if (room.started) room.sendSpectatorGameUpdate(spectator);
            return;
          }
          const player = room.reconnect(socket, token);
          socket.context = { ...socket.context, room, role: "player", playerId: player.id, spectatorId: null };
          send(socket, MessageType.ROOM_JOINED, {
            room_code: room.code,
            player_id: player.id,
            reconnect_token: player.reconnectToken,
            players: room.publicPlayers(),
            lobby: room.lobbyPayload(),
            reconnected: true,
          });
          room.broadcastLobby();
          if (room.started) room.sendGameUpdate(player);
          return;
        }

        if (type === MessageType.SESSION_CHECK) {
          if (socket.context.room) throw new ProtocolError("ALREADY_IN_ROOM", "Already in a room");
          const room = roomManager.getRoom(payload.room_code);
          if (!room) {
            send(socket, MessageType.SESSION_STATUS, { status: "invalid", reason: "room_not_found" });
            return;
          }
          const result = room.sessionStatus(String(payload.reconnect_token || ""));
          if (result.status === "finished") {
            const member = result.player || result.spectator;
            room.leaveByToken(String(payload.reconnect_token || ""));
            send(socket, MessageType.SESSION_STATUS, {
              status: "finished", room_code: room.code, role: result.role || "player",
              player_id: result.player?.id || "", spectator_id: result.spectator?.id || "",
            });
            roomManager.removeIfEmpty(room);
            return;
          }
          if (result.status !== "active") {
            send(socket, MessageType.SESSION_STATUS, { status: "invalid", reason: "token_invalid" });
            return;
          }
          const member = result.player || result.spectator;
          send(socket, MessageType.SESSION_STATUS, {
            status: "active", room_code: room.code, role: result.role || "player",
            player_id: result.player?.id || "", spectator_id: result.spectator?.id || "",
            nickname: member.nickname, started: room.started,
            round: Number(room.publicState?.leg_number || 0),
          });
          return;
        }

        if (type === MessageType.LEAVE_ROOM) {
          const { room, role, playerId, spectatorId } = socket.context;
          if (!room) throw new ProtocolError("NOT_IN_ROOM", "Join a room first");
          if (role === "spectator") {
            room.leaveSpectator(spectatorId, socket);
            socket.context = { ...socket.context, room: null, role: "", playerId: null, spectatorId: null };
            send(socket, MessageType.ROOM_LEFT, { room_code: room.code, role: "spectator", spectator_id: spectatorId });
          } else {
            if (!playerId) throw new ProtocolError("NOT_IN_ROOM", "Join a room first");
            room.leave(playerId, socket);
            socket.context = { ...socket.context, room: null, role: "", playerId: null, spectatorId: null };
            send(socket, MessageType.ROOM_LEFT, { room_code: room.code, role: "player", player_id: playerId });
            room.broadcast(MessageType.PLAYER_LEFT, { player_id: playerId, reconnecting: false });
          }
          room.broadcastLobby();
          roomManager.removeIfEmpty(room);
          return;
        }

        if (type === MessageType.LEAVE_SESSION) {
          if (socket.context.room) throw new ProtocolError("ALREADY_IN_ROOM", "Use LEAVE_ROOM for an attached session");
          const room = roomManager.getRoom(payload.room_code);
          if (!room) throw new ProtocolError("ROOM_NOT_FOUND", "Room code was not found");
          const result = room.leaveByToken(String(payload.reconnect_token || ""));
          const member = result.member;
          send(socket, MessageType.ROOM_LEFT, {
            room_code: room.code, role: result.role,
            player_id: result.role === "player" ? member.id : "",
            spectator_id: result.role === "spectator" ? member.id : "",
          });
          if (result.role === "player") room.broadcast(MessageType.PLAYER_LEFT, { player_id: member.id, reconnecting: false, cpu_takeover: room.started && !room.isGameFinished() });
          room.broadcastLobby();
          roomManager.removeIfEmpty(room);
          return;
        }

        if (type === MessageType.UPDATE_NICKNAME) {
          const { room, playerId, spectatorId, role } = socket.context;
          if (role === "spectator") {
            if (!room || !spectatorId) throw new ProtocolError("NOT_IN_ROOM", "Join a room first");
            room.updateSpectatorNickname(spectatorId, validatedNickname(payload.nickname));
            return;
          }
          if (!room || !playerId) throw new ProtocolError("NOT_IN_ROOM", "Join a room first");
          room.updateNickname(playerId, validatedNickname(payload.nickname));
          return;
        }

        if (type === MessageType.PLAYER_INPUT) {
          const { room, playerId, role } = socket.context;
          if (role === "spectator") throw new ProtocolError("SPECTATOR_FORBIDDEN", "Spectators cannot send player input");
          if (!room || !playerId) throw new ProtocolError("NOT_IN_ROOM", "Join a room first");
          room.setInput(playerId, payload.direction, payload.sequence);
          return;
        }

        if (type === MessageType.LOBBY_CPU) {
          const { room, playerId, role } = socket.context;
          if (role === "spectator") throw new ProtocolError("SPECTATOR_FORBIDDEN", "Spectators cannot edit player slots");
          if (!room || !playerId) throw new ProtocolError("NOT_IN_ROOM", "Join a room first");
          room.setCpuCount(playerId, payload.count);
          return;
        }

        if (type === MessageType.START_GAME) {
          const { room, playerId, role } = socket.context;
          if (role === "spectator") throw new ProtocolError("SPECTATOR_FORBIDDEN", "Spectators cannot start games");
          if (!room || !playerId) throw new ProtocolError("NOT_IN_ROOM", "Join a room first");
          room.startGame(playerId, payload.fill_cpu !== false);
          return;
        }

        if (type === MessageType.GAME_ACTION) {
          const { room, playerId, role } = socket.context;
          if (role === "spectator") throw new ProtocolError("SPECTATOR_FORBIDDEN", "TV spectators cannot perform game actions");
          if (!room || !playerId) throw new ProtocolError("NOT_IN_ROOM", "Join a room first");
          room.requestGameAction(playerId, payload.action, payload.request_id);
          return;
        }

        if (type === MessageType.GAME_COMMIT) {
          const { room, playerId, role } = socket.context;
          if (role === "spectator") throw new ProtocolError("SPECTATOR_FORBIDDEN", "TV spectators cannot commit game state");
          if (!room || !playerId) throw new ProtocolError("NOT_IN_ROOM", "Join a room first");
          room.commitGame(playerId, payload);
          return;
        }

        if (type === MessageType.GAME_READY) {
          const { room, playerId, role } = socket.context;
          if (role === "spectator") throw new ProtocolError("SPECTATOR_FORBIDDEN", "TV spectators do not participate in turn readiness");
          if (!room || !playerId) throw new ProtocolError("NOT_IN_ROOM", "Join a room first");
          room.acknowledgeGameReady(playerId, payload.game_sequence);
          return;
        }

        if (type === MessageType.CHAT_SEND) {
          const { room, playerId, spectatorId, role } = socket.context;
          const memberId = role === "spectator" ? spectatorId : playerId;
          if (!room || !memberId) throw new ProtocolError("NOT_IN_ROOM", "Join a room first");
          const now = Date.now();
          if (now - socket.context.lastChatAt < 350) {
            throw new ProtocolError("CHAT_RATE_LIMIT", "Please wait before sending another message");
          }
          const text = safeChatText(payload.text);
          if (!text) throw new ProtocolError("EMPTY_CHAT", "Chat message cannot be empty");
          socket.context.lastChatAt = now;
          const member = role === "spectator" ? room.spectators.get(spectatorId) : room.players.get(playerId);
          room.broadcast(MessageType.CHAT_MESSAGE, {
            room_code: room.code,
            player_id: role === "player" ? playerId : "",
            spectator_id: role === "spectator" ? spectatorId : "",
            role,
            nickname: member.nickname,
            text,
            server_time: now,
          });
          return;
        }
      } catch (error) {
        if (error instanceof ProtocolError) sendError(socket, error.code, error.message);
        else sendError(socket, "SERVER_ERROR", "Unable to process message");
      }
    });

    socket.on("close", () => {
      const { room, playerId, spectatorId, role } = socket.context;
      if (!room) return;
      if (role === "spectator") {
        const spectator = room.markSpectatorDisconnected(spectatorId, socket);
        if (spectator) room.broadcastLobby();
        roomManager.removeIfEmpty(room);
        return;
      }
      if (!playerId) return;
      const player = room.markDisconnected(playerId, socket);
      if (player) {
        room.broadcast(MessageType.PLAYER_LEFT, { player_id: playerId, reconnecting: true });
        room.broadcastLobby();
      }
      roomManager.removeIfEmpty(room);
    });
  });

  let lastSimulation = Date.now();
  const simulationTimer = setInterval(() => {
    const now = Date.now();
    const delta = Math.min((now - lastSimulation) / 1000, 0.1);
    lastSimulation = now;
    roomManager.simulate(delta);
  }, 1000 / SIMULATION_HZ);
  const snapshotTimer = setInterval(() => roomManager.broadcastSnapshots(Date.now()), 1000 / SNAPSHOT_HZ);
  const heartbeatTimer = setInterval(() => {
    for (const socket of wsServer.clients) {
      if (!socket.context.alive) {
        socket.terminate();
        continue;
      }
      socket.context.alive = false;
      socket.ping();
    }
  }, 20_000);

  function close() {
    clearInterval(simulationTimer);
    clearInterval(snapshotTimer);
    clearInterval(heartbeatTimer);
    for (const socket of wsServer.clients) socket.terminate();
    return new Promise((resolve) => httpServer.close(resolve));
  }

  return { httpServer, wsServer, roomManager, close };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT) || 8080;
  const host = process.env.HOST || "0.0.0.0";
  const gameServer = createGameServer();
  gameServer.httpServer.listen(port, host, () => {
    console.log(`Godot boardgame server listening on http://${host}:${port}`);
  });
}
