extends TextureButton
class_name 成就牌缩略图

signal request_open_detail(card_data: 成就牌)

var card_data: 成就牌 = null

@onready var score_label: Label = $ScoreBadge/Score
@onready var mask: ColorRect = $Mask


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


func setup(data: 成就牌) -> void:
	card_data = data
	texture_normal = data.image_of_front
	score_label.text = str(data.score_value)
	tooltip_text = data.card_name


func _on_pressed() -> void:
	if card_data != null:
		request_open_detail.emit(card_data)


func _on_mouse_entered() -> void:
	mask.show()


func _on_mouse_exited() -> void:
	mask.hide()


func _on_button_down() -> void:
	mask.color = Color(0, 0, 0, 0.65)


func _on_button_up() -> void:
	mask.color = Color(0.35, 0.19, 0.05, 0.28)
