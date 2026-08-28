extends Control
class_name ProfessionDetailPanel

@onready var portrait: TextureRect = $Panel/Content/Portrait
@onready var profession_name: Label = $Panel/Content/Info/ProfessionName
@onready var skill_name: Label = $Panel/Content/Info/SkillName
@onready var description: Label = $Panel/Content/Info/Description
@onready var status: Label = $Panel/Content/Info/StatusPanel/Status
@onready var guide_button: Button = $Panel/BtnGuide
@onready var close_button: TextureButton = $Panel/BtnClose
@onready var close_mask: TextureRect = $Panel/BtnClose/Mask

var _player: PlayerClass = null
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


func show_for_player(player: PlayerClass) -> void:
	if player == null or visible:
		return
	var definition = ProfessionManager.get_definition(player)
	if definition == null:
		return
	_player = player
	portrait.texture = player.立绘精二
	profession_name.text = str(definition.profession_name)
	skill_name.text = str(definition.skill_name)
	description.text = str(definition.description)
	_refresh_status()
	show()
	_modal_session_generation = TurnManager.get_session_generation()
	_modal_turn_epoch = TurnManager.get_turn_epoch()
	if TurnManager.GameOn:
		_modal_lease = TurnManager.acquire_modal(
			&"profession_detail",
			TurnManager.ModalResumePolicy.RESUME_REMAINING
		)
	close_button.grab_focus()


func _open_guide() -> void:
	if _player == null:
		return
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group("HUD") as HUD
	if _hud == null:
		return
	var definition := ProfessionManager.get_definition(_player)
	if definition == null:
		return
	_hud.open_game_guide(GuideOpenContext.new(
		GuideOpenContext.Source.PROFESSION,
		&"professions",
		DiscoveryManager.KIND_PROFESSION,
		definition.profession_id,
		guide_button,
		definition.profession_id
	))


func close_panel() -> void:
	if not visible:
		return
	hide()
	_player = null
	_release_modal()


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


func _refresh_status() -> void:
	if _player == null:
		status.text = ""
		return
	var blocked_turns := ProfessionManager.get_blocked_turns(_player)
	if blocked_turns > 0:
		status.text = "技能封锁 · %d回合" % blocked_turns
		status.add_theme_color_override("font_color", Color("9a4b35"))
		return
	if _player.player_types == PlayerClass.PlayerCharacter.美食博主:
		status.text = "本回合享用 %d/%d" % [
			_player.food_used_count_this_turn,
			ProfessionManager.get_food_use_limit(_player),
		]
	else:
		status.text = "技能可用"
	status.add_theme_color_override("font_color", Color("ad691f"))


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
