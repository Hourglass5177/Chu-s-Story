extends TextureButton
class_name 事件牌缩略图

signal request_open_detail(card_data: 事件牌)
signal request_use_card(card_data: 事件牌)

var card_data: 事件牌
var holder: PlayerClass

@onready var mask: ColorRect = $Mask


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(func(): mask.show())
	mouse_exited.connect(func(): mask.hide())
	button_down.connect(func(): mask.color = Color(0, 0, 0, 0.7))
	button_up.connect(func(): mask.color = Color(0, 0, 0, 0.4))
	pressed.connect(_on_primary_action)


func setup(data: 事件牌, owner_player: PlayerClass) -> void:
	card_data = data
	holder = owner_player
	texture_normal = card_data.image_of_front
	tooltip_text = card_data.card_name


func _on_primary_action() -> void:
	if card_data != null:
		request_open_detail.emit(card_data)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		if card_data != null:
			request_use_card.emit(card_data)
