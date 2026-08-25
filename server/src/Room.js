import { randomUUID } from "node:crypto";
import { MessageType, ProtocolError, encode } from "./protocol.js";

const MOVE_SPEED = 4.0;
const WORLD_LIMIT = 12.0;
const RECONNECT_GRACE_MS = 60_000;

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function currentPlayerId(publicState) {
  const players = Array.isArray(publicState?.players) ? publicState.players : [];
  const index = Number(publicState?.current_player_index) || 0;
  return String(players[index]?.id || "");
}

export class Room {
  constructor(code, maxPlayers, { turnDurationMs = 60_000 } = {}) {
    this.code = code;
    this.maxPlayers = Math.min(maxPlayers, 4);
    this.players = new Map();
    this.spectators = new Map();
    this.nextPlayerNumber = 1;
    this.nextCpuNumber = 1;
    this.nextSpectatorNumber = 1;
    this.snapshotSequence = 0;
    this.hostPlayerId = "";
    this.started = false;
    this.gameSequence = 0;
    this.gameBusy = false;
    this.pendingAction = null;
    this.pendingReadyPlayers = new Set();
    this.publicState = null;
    this.privateStates = {};
    this.authorityState = null;
    this.turnDurationMs = Math.max(100, Number(turnDurationMs) || 60_000);
    this.turnDeadlineMs = 0;
  }

  addPlayer(socket, nickname, identityId = "") {
    if (this.started) throw new ProtocolError("GAME_ALREADY_STARTED", "The game has already started");
    if (this.players.size >= this.maxPlayers) throw new ProtocolError("ROOM_FULL", "Room is full");
    const number = this.nextPlayerNumber++;
    const player = {
      id: `player_${number}`,
      nickname,
      identityId: String(identityId || ""),
      colorIndex: (number - 1) % 8,
      position: { x: (number - 1) * 2 - 1, y: 0.6, z: 0 },
      direction: { x: 0, z: 0 },
      inputSequence: 0,
      socket,
      isCpu: false,
      connected: true,
      reconnectToken: randomUUID(),
      disconnectedAt: 0,
    };
    if (!this.hostPlayerId) this.hostPlayerId = player.id;
    this.players.set(player.id, player);
    return player;
  }

  addSpectator(socket, nickname, identityId = "") {
    const number = this.nextSpectatorNumber++;
    const spectator = {
      id: `spectator_${number}`,
      nickname,
      identityId: String(identityId || ""),
      socket,
      connected: true,
      reconnectToken: randomUUID(),
      disconnectedAt: 0,
    };
    this.spectators.set(spectator.id, spectator);
    return spectator;
  }

  reconnect(socket, token) {
    if (this.isGameFinished()) throw new ProtocolError("GAME_FINISHED", "Finished games cannot be resumed");
    const player = [...this.players.values()].find((candidate) => !candidate.isCpu && candidate.reconnectToken === token);
    if (!player) throw new ProtocolError("RECONNECT_FAILED", "Session token is invalid or expired");
    if (player.socket && player.socket.readyState === 1) player.socket.close(4001, "Reconnected elsewhere");
    player.socket = socket;
    player.connected = true;
    player.disconnectedAt = 0;
    return player;
  }

  reconnectSpectator(socket, token) {
    if (this.isGameFinished()) throw new ProtocolError("GAME_FINISHED", "Finished games cannot be resumed");
    const spectator = [...this.spectators.values()].find((candidate) => candidate.reconnectToken === token);
    if (!spectator) throw new ProtocolError("RECONNECT_FAILED", "Spectator token is invalid or expired");
    if (spectator.socket && spectator.socket.readyState === 1) spectator.socket.close(4001, "Reconnected elsewhere");
    spectator.socket = socket;
    spectator.connected = true;
    spectator.disconnectedAt = 0;
    return spectator;
  }

  markDisconnected(playerId, socket, now = Date.now()) {
    const player = this.players.get(playerId);
    if (!player || player.isCpu) return null;
    if (player.socket !== socket) return null;
    player.socket = null;
    player.connected = false;
    player.disconnectedAt = now;
    this.pendingReadyPlayers.delete(playerId);
    this.tryUnlockGame();
    if (this.started && playerId === this.hostPlayerId) this.migrateHost();
    return player;
  }

  markSpectatorDisconnected(spectatorId, socket, now = Date.now()) {
    const spectator = this.spectators.get(spectatorId);
    if (!spectator || spectator.socket !== socket) return null;
    spectator.socket = null;
    spectator.connected = false;
    spectator.disconnectedAt = now;
    return spectator;
  }

  leaveSpectator(spectatorId, socket) {
    const spectator = this.spectators.get(spectatorId);
    if (!spectator || spectator.socket !== socket) {
      throw new ProtocolError("NOT_IN_ROOM", "Spectator is not in this room");
    }
    spectator.reconnectToken = "";
    this.spectators.delete(spectatorId);
    return spectator;
  }

  leave(playerId, socket) {
    const player = this.players.get(playerId);
    if (!player || player.isCpu || player.socket !== socket) {
      throw new ProtocolError("NOT_IN_ROOM", "Player is not in this room");
    }
    if (this.started && !this.isGameFinished()) {
      this.takeOverWithCpu(player, "explicit_leave");
    } else {
      this.pendingReadyPlayers.delete(playerId);
      this.players.delete(playerId);
      if (this.hostPlayerId === playerId) {
        const nextHost = [...this.players.values()].find((candidate) => !candidate.isCpu && candidate.connected);
        this.hostPlayerId = nextHost?.id || "";
      }
    }
    return player;
  }

  isGameFinished() {
    return this.publicState?.phase === "GAME_OVER";
  }

  playerForToken(token) {
    return [...this.players.values()].find(
      (candidate) => !candidate.isCpu && candidate.reconnectToken && candidate.reconnectToken === token,
    ) || null;
  }

  sessionStatus(token) {
    const player = this.playerForToken(token);
    if (!player) {
      const spectator = [...this.spectators.values()].find((candidate) => candidate.reconnectToken === token);
      if (!spectator) return { status: "invalid" };
      return this.isGameFinished()
        ? { status: "finished", role: "spectator", spectator }
        : { status: "active", role: "spectator", spectator };
    }
    if (this.isGameFinished()) return { status: "finished", player };
    return { status: "active", role: "player", player };
  }

  leaveByToken(token) {
    const player = this.playerForToken(token);
    if (!player) {
      const spectator = [...this.spectators.values()].find((candidate) => candidate.reconnectToken === token);
      if (!spectator) throw new ProtocolError("RECONNECT_FAILED", "Session token is invalid or expired");
      spectator.reconnectToken = "";
      this.spectators.delete(spectator.id);
      return { role: "spectator", member: spectator };
    }
    if (this.started && !this.isGameFinished()) this.takeOverWithCpu(player, "explicit_leave");
    else this.removeHuman(player);
    return { role: "player", member: player };
  }

  removeHuman(player) {
    player.reconnectToken = "";
    this.pendingReadyPlayers.delete(player.id);
    this.players.delete(player.id);
    if (this.hostPlayerId === player.id) {
      this.hostPlayerId = "";
      const nextHost = [...this.players.values()].find((candidate) => !candidate.isCpu && candidate.connected);
      this.hostPlayerId = nextHost?.id || "";
    }
    this.tryUnlockGame();
  }

  takeOverWithCpu(player, reason = "reconnect_timeout") {
    const wasHost = player.id === this.hostPlayerId;
    player.reconnectToken = "";
    player.socket = null;
    player.isCpu = true;
    player.connected = true;
    player.disconnectedAt = 0;
    this.pendingReadyPlayers.delete(player.id);
    for (const state of [this.publicState, this.authorityState]) {
      const statePlayer = state?.players?.find((candidate) => String(candidate.id) === player.id);
      if (statePlayer) {
        statePlayer.is_cpu = true;
        statePlayer.connected = true;
      }
    }
    if (wasHost) {
      this.hostPlayerId = "";
      this.migrateHost();
    }
    this.broadcast(MessageType.PLAYER_TAKEOVER, {
      room_code: this.code, player_id: player.id, nickname: player.nickname,
      reason, is_cpu: true,
    });
    this.broadcastLobby();
    this.tryUnlockGame();
    return player;
  }

  updateNickname(playerId, nickname) {
    const player = this.players.get(playerId);
    if (!player || player.isCpu) throw new ProtocolError("INVALID_ACTOR", "Human player is required");
    player.nickname = nickname;
    for (const state of [this.publicState, this.authorityState]) {
      const statePlayer = state?.players?.find((candidate) => String(candidate.id) === playerId);
      if (statePlayer) statePlayer.name = nickname;
    }
    this.broadcast(MessageType.NICKNAME_UPDATED, {
      room_code: this.code, player_id: playerId, nickname,
    });
    this.broadcastLobby();
  }

  updateSpectatorNickname(spectatorId, nickname) {
    const spectator = this.spectators.get(spectatorId);
    if (!spectator) throw new ProtocolError("NOT_IN_ROOM", "Spectator is not in this room");
    spectator.nickname = nickname;
    this.broadcastLobby();
  }

  migrateHost() {
    const nextHost = [...this.players.values()].find((candidate) => !candidate.isCpu && candidate.connected);
    if (!nextHost || nextHost.id === this.hostPlayerId) return;
    this.hostPlayerId = nextHost.id;
    this.broadcastLobby();
    this.sendTo(nextHost.id, MessageType.GAME_AUTHORITY_REQUEST, {
      room_code: this.code,
      players: this.publicPlayers(),
      reason: "host_migration",
      authority_state: this.authorityState,
    });
    if (this.pendingAction) {
      this.sendTo(nextHost.id, this.pendingAction.automatic ? MessageType.GAME_TIMEOUT_REQUEST : MessageType.GAME_ACTION_REQUEST, {
        actor_id: this.pendingAction.playerId,
        request_id: this.pendingAction.requestId,
        action: this.pendingAction.action,
        reason: this.pendingAction.automatic ? "turn_timeout" : "host_migration",
      });
    }
  }

  expireDisconnected(now = Date.now()) {
    for (const player of [...this.players.values()]) {
      if (player.isCpu || player.connected || now - player.disconnectedAt < RECONNECT_GRACE_MS) continue;
      if (this.started && !this.isGameFinished()) this.takeOverWithCpu(player, "reconnect_timeout");
      else this.removeHuman(player);
    }
    for (const spectator of [...this.spectators.values()]) {
      if (spectator.connected || now - spectator.disconnectedAt < RECONNECT_GRACE_MS) continue;
      spectator.reconnectToken = "";
      this.spectators.delete(spectator.id);
    }
  }

  addCpu() {
    if (this.started) throw new ProtocolError("GAME_ALREADY_STARTED", "The game has already started");
    if (this.players.size >= this.maxPlayers) throw new ProtocolError("ROOM_FULL", "All four slots are occupied");
    const number = this.nextCpuNumber++;
    const player = {
      id: `cpu_${number}`,
      nickname: `CPU ${number}`,
      colorIndex: this.players.size % 8,
      position: { x: 0, y: 0.6, z: 0 }, direction: { x: 0, z: 0 }, inputSequence: 0,
      socket: null, isCpu: true, connected: true, reconnectToken: "", disconnectedAt: 0,
    };
    this.players.set(player.id, player);
    return player;
  }

  removeCpu() {
    const player = [...this.players.values()].filter((candidate) => candidate.isCpu).at(-1);
    if (player) this.players.delete(player.id);
    return player || null;
  }

  publicPlayer(player) {
    return {
      player_id: player.id, nickname: player.nickname, color_index: player.colorIndex,
      position: player.position, direction: player.direction, is_cpu: player.isCpu,
      connected: player.connected, is_host: player.id === this.hostPlayerId,
    };
  }

  publicPlayers() {
    return [...this.players.values()].map((player) => this.publicPlayer(player));
  }

  publicSpectators() {
    return [...this.spectators.values()].map((spectator) => ({
      spectator_id: spectator.id,
      nickname: spectator.nickname,
      connected: spectator.connected,
      role: "spectator",
    }));
  }

  lobbyPayload() {
    return {
      room_code: this.code, host_player_id: this.hostPlayerId, started: this.started,
      max_slots: this.maxPlayers, players: this.publicPlayers(),
      spectators: this.publicSpectators(), spectator_count: this.spectators.size,
    };
  }

  broadcastLobby() { this.broadcast(MessageType.LOBBY_STATE, this.lobbyPayload()); }

  setInput(playerId, direction, sequence) {
    const player = this.players.get(playerId);
    if (!player || player.isCpu) return;
    const rawX = Number(direction?.x) || 0;
    const rawZ = Number(direction?.z) || 0;
    const length = Math.hypot(rawX, rawZ);
    player.direction = length > 1 ? { x: rawX / length, z: rawZ / length } : { x: clamp(rawX, -1, 1), z: clamp(rawZ, -1, 1) };
    player.inputSequence = Math.max(player.inputSequence, Number(sequence) || 0);
  }

  setCpuCount(requesterId, desiredCount) {
    if (requesterId !== this.hostPlayerId) throw new ProtocolError("HOST_ONLY", "Only the host can change CPU slots");
    if (this.started) throw new ProtocolError("GAME_ALREADY_STARTED", "The game has already started");
    const humanCount = [...this.players.values()].filter((player) => !player.isCpu).length;
    const target = clamp(Number(desiredCount) || 0, 0, this.maxPlayers - humanCount);
    let current = [...this.players.values()].filter((player) => player.isCpu).length;
    while (current < target) { this.addCpu(); current += 1; }
    while (current > target) { this.removeCpu(); current -= 1; }
    this.broadcastLobby();
  }

  startGame(requesterId, fillCpu = true) {
    if (requesterId !== this.hostPlayerId) throw new ProtocolError("HOST_ONLY", "Only the host can start the game");
    if (this.started) throw new ProtocolError("GAME_ALREADY_STARTED", "The game has already started");
    if (fillCpu) while (this.players.size < this.maxPlayers) this.addCpu();
    if (this.players.size < 2) throw new ProtocolError("NOT_ENOUGH_PLAYERS", "At least two players are required");
    this.started = true;
    this.gameBusy = true;
    this.broadcastLobby();
    this.sendTo(this.hostPlayerId, MessageType.GAME_AUTHORITY_REQUEST, { room_code: this.code, players: this.publicPlayers(), reason: "start" });
  }

  requestGameAction(playerId, action, requestId) {
    if (!this.started || !this.publicState) throw new ProtocolError("GAME_NOT_READY", "The game is not ready");
    if (this.isGameFinished()) throw new ProtocolError("GAME_FINISHED", "Finished games do not accept gameplay actions");
    if (this.gameBusy) throw new ProtocolError("GAME_BUSY", "The previous action is still resolving");
    const player = this.players.get(playerId);
    if (!player || player.isCpu) throw new ProtocolError("INVALID_ACTOR", "Only a connected human can send this action");
    if (currentPlayerId(this.publicState) !== playerId) throw new ProtocolError("NOT_YOUR_TURN", "It is not your turn");
    if (!action || typeof action !== "object") throw new ProtocolError("INVALID_ACTION", "Action is required");
    const claimedPlayerId = String(action.player_id || action.actor_id || action.data?.player_id || "");
    if (claimedPlayerId && claimedPlayerId !== playerId) {
      throw new ProtocolError("PLAYER_OWNERSHIP_MISMATCH", "A client may only submit its own action");
    }
    this.turnDeadlineMs = 0;
    this.gameBusy = true;
    this.pendingAction = { playerId, requestId: String(requestId || randomUUID()), action, automatic: false };
    this.sendTo(this.hostPlayerId, MessageType.GAME_ACTION_REQUEST, { actor_id: playerId, request_id: this.pendingAction.requestId, action });
  }

  commitGame(authorityId, payload) {
    if (authorityId !== this.hostPlayerId) throw new ProtocolError("AUTHORITY_ONLY", "Only the host authority may commit state");
    if (!this.started) throw new ProtocolError("GAME_NOT_STARTED", "The game has not started");
    const { public_state: publicState, authority_state: authorityState, private_states: privateStates, events } = payload;
    if (!publicState || typeof publicState !== "object" || Array.isArray(publicState)) throw new ProtocolError("INVALID_STATE", "Public state is required");
    if (!authorityState || typeof authorityState !== "object" || Array.isArray(authorityState)) throw new ProtocolError("INVALID_STATE", "Authority state is required");
    if (!privateStates || typeof privateStates !== "object" || Array.isArray(privateStates)) throw new ProtocolError("INVALID_STATE", "Private states are required");
    if (!Array.isArray(events) || events.length > 100) throw new ProtocolError("INVALID_EVENTS", "Events must be an array");
    const actorId = String(payload.actor_id || "");
    if (this.publicState) {
      const expected = currentPlayerId(this.publicState);
      const actor = this.players.get(actorId);
      if (actorId !== expected) throw new ProtocolError("INVALID_ACTOR", "Commit actor does not match the authoritative turn");
      if (!actor?.isCpu && this.pendingAction?.playerId !== actorId) throw new ProtocolError("ACTION_NOT_REQUESTED", "Human action was not requested through the server");
    }
    this.publicState = structuredClone(publicState);
    this.privateStates = structuredClone(privateStates);
    this.authorityState = structuredClone(authorityState);
    this.gameSequence += 1;
    this.gameBusy = true;
    this.pendingAction = null;
    this.pendingReadyPlayers = new Set(
      [...this.players.values()]
        .filter((player) => !player.isCpu && player.connected)
        .map((player) => player.id),
    );
    for (const player of this.players.values()) this.sendGameUpdate(player, events, actorId);
    for (const spectator of this.spectators.values()) this.sendSpectatorGameUpdate(spectator, events, actorId);
    this.tryUnlockGame();
  }

  acknowledgeGameReady(playerId, sequence) {
    if (Number(sequence) !== this.gameSequence) return;
    this.pendingReadyPlayers.delete(playerId);
    this.tryUnlockGame();
  }

  tryUnlockGame() {
    if (!this.started || !this.publicState || !this.gameBusy || this.pendingAction) return;
    if (this.pendingReadyPlayers.size > 0) return;
    this.gameBusy = false;
    const current = this.players.get(currentPlayerId(this.publicState));
    this.turnDeadlineMs = current && !current.isCpu && this.publicState?.phase === "PLAYING"
      ? Date.now() + this.turnDurationMs
      : 0;
    this.broadcast(MessageType.GAME_UNLOCK, {
      room_code: this.code,
      game_sequence: this.gameSequence,
      current_player_id: currentPlayerId(this.publicState),
      turn_deadline_ms: this.turnDeadlineMs,
      server_time: Date.now(),
    });
  }

  checkTurnTimeout(now = Date.now()) {
    if (!this.started || !this.publicState || this.publicState.phase !== "PLAYING") return;
    if (this.gameBusy || !this.turnDeadlineMs || now < this.turnDeadlineMs) return;
    const playerId = currentPlayerId(this.publicState);
    const player = this.players.get(playerId);
    if (!player || player.isCpu) return;
    this.turnDeadlineMs = 0;
    this.gameBusy = true;
    this.pendingAction = {
      playerId,
      requestId: `timeout-${this.gameSequence}-${now}`,
      action: null,
      automatic: true,
    };
    this.sendTo(this.hostPlayerId, MessageType.GAME_TIMEOUT_REQUEST, {
      actor_id: playerId,
      request_id: this.pendingAction.requestId,
      reason: "turn_timeout",
    });
  }

  sendGameUpdate(player, events = [], actorId = "") {
    if (!player || player.isCpu || !player.socket || player.socket.readyState !== 1 || !this.publicState) return;
    const payload = {
      room_code: this.code, game_sequence: this.gameSequence, actor_id: actorId, events,
      public_state: this.publicState, private_state: this.privateStates[player.id] || {}, game_busy: this.gameBusy,
      turn_deadline_ms: this.turnDeadlineMs, server_time: Date.now(),
    };
    if (player.id === this.hostPlayerId) payload.authority_state = this.authorityState;
    player.socket.send(encode(MessageType.GAME_UPDATE, payload));
  }

  sendSpectatorGameUpdate(spectator, events = [], actorId = "") {
    if (!spectator || !spectator.socket || spectator.socket.readyState !== 1 || !this.publicState) return;
    spectator.socket.send(encode(MessageType.GAME_UPDATE, {
      room_code: this.code,
      role: "spectator",
      spectator_id: spectator.id,
      game_sequence: this.gameSequence,
      actor_id: actorId,
      events,
      public_state: this.publicState,
      game_busy: this.gameBusy,
      turn_deadline_ms: this.turnDeadlineMs,
      server_time: Date.now(),
    }));
  }

  sendTo(playerId, type, payload) {
    const player = this.players.get(playerId);
    if (player?.socket?.readyState === 1) player.socket.send(encode(type, payload));
  }

  simulate(deltaSeconds) {
    this.expireDisconnected();
    this.checkTurnTimeout();
    for (const player of this.players.values()) {
      if (player.isCpu) continue;
      player.position.x = clamp(player.position.x + player.direction.x * MOVE_SPEED * deltaSeconds, -WORLD_LIMIT, WORLD_LIMIT);
      player.position.z = clamp(player.position.z + player.direction.z * MOVE_SPEED * deltaSeconds, -WORLD_LIMIT, WORLD_LIMIT);
    }
  }

  broadcast(type, payload, exceptSocket = null) {
    const data = encode(type, payload);
    for (const player of this.players.values()) {
      if (!player.isCpu && player.socket !== exceptSocket && player.socket?.readyState === 1) player.socket.send(data);
    }
    for (const spectator of this.spectators.values()) {
      if (spectator.socket !== exceptSocket && spectator.socket?.readyState === 1) spectator.socket.send(data);
    }
  }

  broadcastSnapshot(serverTime) {
    if (this.started) return;
    this.snapshotSequence += 1;
    this.broadcast(MessageType.PLAYER_STATE, {
      room_code: this.code, snapshot_sequence: this.snapshotSequence, server_time: serverTime,
      players: this.publicPlayers().map((player) => ({ ...player, input_sequence: this.players.get(player.player_id).inputSequence })),
    });
  }
}
