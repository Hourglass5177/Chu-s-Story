extends Node2D
signal game_start
@onready var tile_map = $MapBackground/TileMapLayer
@onready var player = $Player

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var card_path = "Cards/鄂州/牌子锣.tres"
	var new_card = load(card_path) as CardData
	player.draw_card(new_card)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _input(event):
	pass
