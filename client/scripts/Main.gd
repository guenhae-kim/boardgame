extends Node

@onready var lobby: LobbyUI = $Lobby
@onready var game: GameManager = $Game

func _ready() -> void:
	lobby.room_entered.connect(_on_room_entered)
	NetworkClient.connection_status_changed.connect(_on_connection_status_changed)
	game.visible = false

func _on_room_entered(payload: Dictionary) -> void:
	lobby.visible = false
	game.visible = true
	game.start_room(payload)

func _on_connection_status_changed(status: String) -> void:
	if status != "Disconnected" or not game.visible:
		return
	game.clear_room()
	game.visible = false
	lobby.visible = true
