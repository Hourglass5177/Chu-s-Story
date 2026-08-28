extends Control
class_name AchievementDetailPanel

@onready var card_image: TextureRect = $Panel/Content/CardImage
@onready var name_label: Label = $Panel/Content/Info/Name
@onready var score_label: Label = $Panel/Content/Info/Score
@onready var description_label: Label = $Panel/Content/Info/Description
@onready var guide_button: Button = $Panel/BtnGuide
@onready var close_button: TextureButton = $Panel/BtnClose
@onready var close_mask: TextureRect = $Panel/BtnClose/Mask

var _card: 成就牌 = null
var _hud: HUD = null
var _modal_lease: int = -1
var _modal_session_generation: int = -1
var _modal_turn_epoch: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hud = get_tree().get_first_node_in_group("HUD") as HUD
	guide_button.pressed.connect(_open_guide)
	close_button.pressed.connect(close_panel)
	_setup_close_button_feedback()
	hide()


func show_detail(card: 成就牌) -> void:
	if card == null:
		return
	_card = card
	card_image.texture = card.image_of_front
	name_label.text = card.card_name
	score_label.text = "+%d分" % card.score_value
	description_label.text = card.description
	if not visible:
		_begin_modal()
	show()
	close_button.grab_focus()


func _open_guide() -> void:
	if _card == null:
		return
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group("HUD") as HUD
	if _hud == null:
		return
	_hud.open_game_guide(GuideOpenContext.new(
		GuideOpenContext.Source.CARD,
		&"achievements",
		DiscoveryManager.KIND_ACHIEVEMENT,
		_card.achievement_id,
		guide_button,
		&"current_achievements"
	))


func close_panel() -> void:
	if not visible:
		return
	hide()
	_card = null
	_release_modal()


func _setup_close_button_feedback() -> void:
	if close_button.texture_normal == null:
		return
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(close_button.texture_normal.get_image())
	close_button.texture_click_mask = bitmap
	close_button.mouse_entered.connect(func() -> void: close_mask.show())
	close_button.mouse_exited.connect(func() -> void: close_mask.hide())
	close_button.button_down.connect(func() -> void: close_mask.modulate = Color(0, 0, 0, 0.7))
	close_button.button_up.connect(func() -> void: close_mask.modulate = Color(0, 0, 0, 0.4))


func _begin_modal() -> void:
	_modal_session_generation = TurnManager.get_session_generation()
	_modal_turn_epoch = TurnManager.get_turn_epoch()
	_modal_lease = TurnManager.acquire_modal(
		&"achievement_detail",
		TurnManager.ModalResumePolicy.RESUME_REMAINING,
		true
	)


func _release_modal() -> void:
	var same_context: bool = (
		_modal_session_generation == TurnManager.get_session_generation()
		and _modal_turn_epoch == TurnManager.get_turn_epoch()
	)
	if _modal_lease >= 0 and same_context:
		TurnManager.release_modal(_modal_lease)
	_modal_lease = -1
	_modal_session_generation = -1
	_modal_turn_epoch = -1
