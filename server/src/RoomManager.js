import { randomInt } from "node:crypto";
import { Room } from "./Room.js";

const ROOM_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export class RoomManager {
  constructor({ maxPlayers = 8 } = {}) {
    this.rooms = new Map();
    this.maxPlayers = maxPlayers;
  }

  createRoom() {
    let code;
    do {
      code = Array.from({ length: 4 }, () => ROOM_ALPHABET[randomInt(ROOM_ALPHABET.length)]).join("");
    } while (this.rooms.has(code));

    const room = new Room(code, this.maxPlayers);
    this.rooms.set(code, room);
    return room;
  }

  getRoom(code) {
    return this.rooms.get(String(code || "").trim().toUpperCase());
  }

  removeIfEmpty(room) {
    if (room && room.players.size === 0) {
      this.rooms.delete(room.code);
    }
  }

  simulate(deltaSeconds) {
    for (const room of this.rooms.values()) {
      room.simulate(deltaSeconds);
      this.removeIfEmpty(room);
    }
  }

  broadcastSnapshots(serverTime) {
    for (const room of this.rooms.values()) room.broadcastSnapshot(serverTime);
  }
}
