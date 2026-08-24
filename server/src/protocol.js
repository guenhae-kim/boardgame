export const PROTOCOL_VERSION = 1;

export const MessageType = Object.freeze({
  HELLO: "HELLO",
  CREATE_ROOM: "CREATE_ROOM",
  ROOM_CREATED: "ROOM_CREATED",
  JOIN_ROOM: "JOIN_ROOM",
  ROOM_JOINED: "ROOM_JOINED",
  RECONNECT: "RECONNECT",
  PLAYER_JOINED: "PLAYER_JOINED",
  PLAYER_LEFT: "PLAYER_LEFT",
  PLAYER_INPUT: "PLAYER_INPUT",
  PLAYER_STATE: "PLAYER_STATE",
  LOBBY_STATE: "LOBBY_STATE",
  LOBBY_CPU: "LOBBY_CPU",
  START_GAME: "START_GAME",
  GAME_AUTHORITY_REQUEST: "GAME_AUTHORITY_REQUEST",
  GAME_ACTION: "GAME_ACTION",
  GAME_ACTION_REQUEST: "GAME_ACTION_REQUEST",
  GAME_COMMIT: "GAME_COMMIT",
  GAME_UPDATE: "GAME_UPDATE",
  GAME_READY: "GAME_READY",
  GAME_UNLOCK: "GAME_UNLOCK",
  CHAT_SEND: "CHAT_SEND",
  CHAT_MESSAGE: "CHAT_MESSAGE",
  ERROR: "ERROR",
  PING: "PING",
  PONG: "PONG",
});

const CLIENT_MESSAGE_TYPES = new Set([
  MessageType.HELLO,
  MessageType.CREATE_ROOM,
  MessageType.JOIN_ROOM,
  MessageType.RECONNECT,
  MessageType.PLAYER_INPUT,
  MessageType.LOBBY_CPU,
  MessageType.START_GAME,
  MessageType.GAME_ACTION,
  MessageType.GAME_COMMIT,
  MessageType.GAME_READY,
  MessageType.CHAT_SEND,
  MessageType.PING,
  MessageType.PONG,
]);

export function encode(type, payload = {}) {
  return JSON.stringify({ version: PROTOCOL_VERSION, type, payload });
}

export function decode(raw) {
  let message;
  try {
    message = JSON.parse(raw.toString());
  } catch {
    throw new ProtocolError("INVALID_JSON", "Message must be valid JSON");
  }

  if (!message || typeof message !== "object" || Array.isArray(message)) {
    throw new ProtocolError("INVALID_MESSAGE", "Message must be an object");
  }
  if (message.version !== PROTOCOL_VERSION) {
    throw new ProtocolError(
      "UNSUPPORTED_VERSION",
      `Expected protocol version ${PROTOCOL_VERSION}`,
    );
  }
  if (!CLIENT_MESSAGE_TYPES.has(message.type)) {
    throw new ProtocolError("UNKNOWN_TYPE", "Unknown client message type");
  }
  if (!message.payload || typeof message.payload !== "object" || Array.isArray(message.payload)) {
    message.payload = {};
  }
  return message;
}

export class ProtocolError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}
