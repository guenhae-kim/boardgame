export const PROTOCOL_VERSION = 1;

export const MessageType = Object.freeze({
  HELLO: "HELLO",
  CREATE_ROOM: "CREATE_ROOM",
  ROOM_CREATED: "ROOM_CREATED",
  JOIN_ROOM: "JOIN_ROOM",
  ROOM_JOINED: "ROOM_JOINED",
  PLAYER_JOINED: "PLAYER_JOINED",
  PLAYER_LEFT: "PLAYER_LEFT",
  PLAYER_INPUT: "PLAYER_INPUT",
  PLAYER_STATE: "PLAYER_STATE",
  ERROR: "ERROR",
  PING: "PING",
  PONG: "PONG",
});

const CLIENT_MESSAGE_TYPES = new Set([
  MessageType.HELLO,
  MessageType.CREATE_ROOM,
  MessageType.JOIN_ROOM,
  MessageType.PLAYER_INPUT,
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
