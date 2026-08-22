import { MessageType, encode } from "./protocol.js";

const MOVE_SPEED = 4.0;
const WORLD_LIMIT = 12.0;

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

export class Room {
  constructor(code, maxPlayers) {
    this.code = code;
    this.maxPlayers = maxPlayers;
    this.players = new Map();
    this.nextPlayerNumber = 1;
    this.snapshotSequence = 0;
  }

  addPlayer(socket, nickname) {
    if (this.players.size >= this.maxPlayers) {
      throw new Error("ROOM_FULL");
    }

    const number = this.nextPlayerNumber++;
    const player = {
      id: `player_${number}`,
      nickname,
      colorIndex: (number - 1) % 8,
      position: { x: (number - 1) * 2 - 1, y: 0.6, z: 0 },
      direction: { x: 0, z: 0 },
      inputSequence: 0,
      socket,
    };
    this.players.set(player.id, player);
    return player;
  }

  removePlayer(playerId) {
    const player = this.players.get(playerId);
    this.players.delete(playerId);
    return player;
  }

  publicPlayer(player) {
    return {
      player_id: player.id,
      nickname: player.nickname,
      color_index: player.colorIndex,
      position: player.position,
      direction: player.direction,
    };
  }

  publicPlayers() {
    return [...this.players.values()].map((player) => this.publicPlayer(player));
  }

  setInput(playerId, direction, sequence) {
    const player = this.players.get(playerId);
    if (!player) return;

    const rawX = Number(direction?.x) || 0;
    const rawZ = Number(direction?.z) || 0;
    const length = Math.hypot(rawX, rawZ);
    player.direction = length > 1
      ? { x: rawX / length, z: rawZ / length }
      : { x: clamp(rawX, -1, 1), z: clamp(rawZ, -1, 1) };
    player.inputSequence = Math.max(player.inputSequence, Number(sequence) || 0);
  }

  simulate(deltaSeconds) {
    for (const player of this.players.values()) {
      player.position.x = clamp(
        player.position.x + player.direction.x * MOVE_SPEED * deltaSeconds,
        -WORLD_LIMIT,
        WORLD_LIMIT,
      );
      player.position.z = clamp(
        player.position.z + player.direction.z * MOVE_SPEED * deltaSeconds,
        -WORLD_LIMIT,
        WORLD_LIMIT,
      );
    }
  }

  broadcast(type, payload, exceptSocket = null) {
    const data = encode(type, payload);
    for (const player of this.players.values()) {
      if (player.socket !== exceptSocket && player.socket.readyState === 1) {
        player.socket.send(data);
      }
    }
  }

  broadcastSnapshot(serverTime) {
    this.snapshotSequence += 1;
    this.broadcast(MessageType.PLAYER_STATE, {
      room_code: this.code,
      snapshot_sequence: this.snapshotSequence,
      server_time: serverTime,
      players: this.publicPlayers().map((player) => ({
        ...player,
        input_sequence: this.players.get(player.player_id).inputSequence,
      })),
    });
  }
}
