extends Node

@onready var lobby: LobbyUI = $Lobby
@onready var game: CamelOnlineGameController = $Game

func _ready() -> void:
	lobby.room_entered.connect(_on_room_entered)
	NetworkClient.connection_status_changed.connect(_on_connection_status_changed)
	game.visible = false
	game.set_room_active(false)

func _on_room_entered(payload: Dictionary) -> void:
	lobby.visible = false
	game.visible = true
	game.set_room_active(true)
	game.start_room(payload)

func _on_connection_status_changed(status: String) -> void:
	if status != "Disconnected" or not game.visible:
		return
	# Keep the board and hand visible while NetworkClient attempts token reconnect.
	game.online_ui.show_error("연결이 끊겼습니다. 같은 플레이어로 다시 연결하는 중입니다...")
