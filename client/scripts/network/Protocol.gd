class_name Protocol
extends RefCounted

const VERSION := 1

const HELLO := "HELLO"
const CREATE_ROOM := "CREATE_ROOM"
const ROOM_CREATED := "ROOM_CREATED"
const JOIN_ROOM := "JOIN_ROOM"
const ROOM_JOINED := "ROOM_JOINED"
const RECONNECT := "RECONNECT"
const SESSION_CHECK := "SESSION_CHECK"
const SESSION_STATUS := "SESSION_STATUS"
const LEAVE_ROOM := "LEAVE_ROOM"
const LEAVE_SESSION := "LEAVE_SESSION"
const ROOM_LEFT := "ROOM_LEFT"
const UPDATE_NICKNAME := "UPDATE_NICKNAME"
const NICKNAME_UPDATED := "NICKNAME_UPDATED"
const PLAYER_TAKEOVER := "PLAYER_TAKEOVER"
const PLAYER_JOINED := "PLAYER_JOINED"
const PLAYER_LEFT := "PLAYER_LEFT"
const PLAYER_INPUT := "PLAYER_INPUT"
const PLAYER_STATE := "PLAYER_STATE"
const LOBBY_STATE := "LOBBY_STATE"
const LOBBY_CPU := "LOBBY_CPU"
const START_GAME := "START_GAME"
const GAME_AUTHORITY_REQUEST := "GAME_AUTHORITY_REQUEST"
const GAME_ACTION := "GAME_ACTION"
const GAME_ACTION_REQUEST := "GAME_ACTION_REQUEST"
const GAME_COMMIT := "GAME_COMMIT"
const GAME_UPDATE := "GAME_UPDATE"
const GAME_READY := "GAME_READY"
const GAME_UNLOCK := "GAME_UNLOCK"
const GAME_TIMEOUT_REQUEST := "GAME_TIMEOUT_REQUEST"
const CHAT_SEND := "CHAT_SEND"
const CHAT_MESSAGE := "CHAT_MESSAGE"
const ERROR := "ERROR"
const PING := "PING"
const PONG := "PONG"

static func encode_message(type: String, payload: Dictionary = {}) -> String:
	return JSON.stringify({
		"version": VERSION,
		"type": type,
		"payload": payload,
	})

static func decode_message(text: String) -> Dictionary:
	var value: Variant = JSON.parse_string(text)
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var message := value as Dictionary
	if int(message.get("version", -1)) != VERSION:
		return {}
	if typeof(message.get("type")) != TYPE_STRING:
		return {}
	if typeof(message.get("payload", {})) != TYPE_DICTIONARY:
		message["payload"] = {}
	return message
