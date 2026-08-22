import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readFile, stat } from "node:fs/promises";
import { WebSocketServer } from "ws";
import { MessageType, ProtocolError, decode, encode, PROTOCOL_VERSION } from "./protocol.js";
import { RoomManager } from "./RoomManager.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_STATIC_DIR = path.resolve(__dirname, "../../client/build/web");
const MAX_MESSAGE_BYTES = 16 * 1024;
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
  const roomManager = new RoomManager({ maxPlayers: Number(process.env.MAX_ROOM_PLAYERS) || 8 });
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
    socket.context = { room: null, playerId: null, alive: true, lastChatAt: 0 };
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
          const player = room.addPlayer(socket, validatedNickname(payload.nickname));
          socket.context = { ...socket.context, room, playerId: player.id };
          send(socket, MessageType.ROOM_CREATED, {
            room_code: room.code,
            player_id: player.id,
            reconnect_token: null,
            players: room.publicPlayers(),
          });
          return;
        }

        if (type === MessageType.JOIN_ROOM) {
          if (socket.context.room) throw new ProtocolError("ALREADY_IN_ROOM", "Already in a room");
          const room = roomManager.getRoom(payload.room_code);
          if (!room) throw new ProtocolError("ROOM_NOT_FOUND", "Room code was not found");
          const nickname = validatedNickname(payload.nickname);
          let player;
          try {
            player = room.addPlayer(socket, nickname);
          } catch {
            throw new ProtocolError("ROOM_FULL", "Room is full");
          }
          socket.context = { ...socket.context, room, playerId: player.id };
          send(socket, MessageType.ROOM_JOINED, {
            room_code: room.code,
            player_id: player.id,
            reconnect_token: null,
            players: room.publicPlayers(),
          });
          room.broadcast(MessageType.PLAYER_JOINED, { player: room.publicPlayer(player) }, socket);
          return;
        }

        if (type === MessageType.PLAYER_INPUT) {
          const { room, playerId } = socket.context;
          if (!room || !playerId) throw new ProtocolError("NOT_IN_ROOM", "Join a room first");
          room.setInput(playerId, payload.direction, payload.sequence);
          return;
        }

        if (type === MessageType.CHAT_SEND) {
          const { room, playerId } = socket.context;
          if (!room || !playerId) throw new ProtocolError("NOT_IN_ROOM", "Join a room first");
          const now = Date.now();
          if (now - socket.context.lastChatAt < 350) {
            throw new ProtocolError("CHAT_RATE_LIMIT", "Please wait before sending another message");
          }
          const text = safeChatText(payload.text);
          if (!text) throw new ProtocolError("EMPTY_CHAT", "Chat message cannot be empty");
          socket.context.lastChatAt = now;
          const player = room.players.get(playerId);
          room.broadcast(MessageType.CHAT_MESSAGE, {
            room_code: room.code,
            player_id: playerId,
            nickname: player.nickname,
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
      const { room, playerId } = socket.context;
      if (!room || !playerId) return;
      const player = room.removePlayer(playerId);
      if (player) room.broadcast(MessageType.PLAYER_LEFT, { player_id: playerId });
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
