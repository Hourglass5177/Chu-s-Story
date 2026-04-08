extends Node2D
signal game_start
#@onready var tile_map = $MapBackground/TileMapLayer
#@onready var player = $Player

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var players: Array[PlayerClass] = [$Player, $Player2]
	$Player.start_coord = Vector3i(0,0,0)
	$Player2.start_coord = Vector3i(7, -6, -1)
	TurnManager.start_game(players)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _input(event):
	pass
