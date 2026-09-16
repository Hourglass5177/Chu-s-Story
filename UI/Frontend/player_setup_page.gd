class_name FrontendPlayerSetupPage
extends FrontendScreen

## 单个席位的开局配置页。
## 页面直接编辑传入的 SessionSetup 草稿；正式会话仍只由前端壳层提交。

signal player_confirmed(slot_index: int, return_to_roster: bool)
signal previous_requested(slot_index: int)
signal invalid_action(message: String)
signal player_draft_changed(slot_index: int)
signal map_preview_requested

const PROFESSION_CARD_SCENE: PackedScene = preload("res://UI/Frontend/stateful_card.tscn")

@onready var slot_label: Label = %SlotLabel
@onready var control_kind_label: Label = %ControlKindLabel
@onready var progress_label: Label = %ProgressLabel
@onready var name_input: LineEdit = %NameInput
@onready var profession_grid: GridContainer = %ProfessionGrid
@onready var portrait: TextureRect = %Portrait
@onready var profession_name_label: Label = %ProfessionName
@onready var skill_name_label: Label = %SkillName
@onready var skill_description_label: Label = %SkillDescription
@onready var birthplace_preview_label: Label = %BirthplacePreview
@onready var map_zoom_button: Button = %MapZoomButton
@onready var birthplace_list: GridContainer = %BirthplaceList
@onready var message_label: Label = %Message
@onready var previous_button: Button = %PreviousButton
@onready var confirm_button: Button = %ConfirmButton

var difficulty_box: VBoxContainer
var difficulty_buttons: Array[Button] = []
var difficulty_description: Label

var _setup: SessionSetup
var _slot_index := -1
var _return_to_roster := false
var _refreshing := false
var _displayed_profession_type := PlayerSetup.UNSELECTED
var _hovered_profession_type := PlayerSetup.UNSELECTED
var _hovered_region := PlayerSetup.UNSELECTED
var _profession_cards: Dictionary = {}
var _region_buttons: Dictionary = {}
var _region_order: Array[int] = []
## 自动生成但尚未轮到的 BOT 配置可以为前序玩家让位；一旦玩家按下确认，
## 其选择就和真人一样受到保护，返回修改其他席位时不会被静默改写。
var _confirmed_player_ids: Dictionary[int, bool] = {}
var _bound_setup_id := 0
var _confirm_locked := false
var _confirm_unlock_serial := 0


func _ready() -> void:
	super._ready()
	name_input.text_changed.connect(_on_name_changed)
	previous_button.pressed.connect(_on_previous_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	map_zoom_button.pressed.connect(func(): map_preview_requested.emit())
	for state in ["normal", "disabled"]:
		map_zoom_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["hover", "pressed", "focus"]:
		map_zoom_button.add_theme_stylebox_override(state, MainUI.theme().get_stylebox("focus", "Button"))
	var map_frame := map_zoom_button.get_parent().get_parent() as PanelContainer
	map_frame.add_theme_stylebox_override("panel", FrontendStyle.make_box(
		Color("f8eac9"), Color("a9794e"), 2, 12, Vector4(12, 12, 12, 12)))
	_build_difficulty_controls()
	_build_profession_cards()
	_build_birthplace_controls()
	_wire_focus_navigation()
	refresh_view()


func bind_setup(
		setup: SessionSetup,
		slot_index: int,
		return_to_roster: bool = false
) -> void:
	var setup_id := setup.get_instance_id() if setup != null else 0
	if setup_id != _bound_setup_id:
		_confirmed_player_ids.clear()
		_bound_setup_id = setup_id
	_setup = setup
	_slot_index = slot_index
	_return_to_roster = return_to_roster
	_displayed_profession_type = PlayerSetup.UNSELECTED
	_hovered_profession_type = PlayerSetup.UNSELECTED
	_hovered_region = PlayerSetup.UNSELECTED
	if is_node_ready():
		refresh_view()
		call_deferred("grab_initial_focus")


func refresh_view() -> void:
	if not is_node_ready():
		return
	var player := _get_current_player()
	var valid_binding := player != null
	difficulty_box.visible = valid_binding and player.is_bot()
	name_input.editable = valid_binding
	confirm_button.disabled = not valid_binding
	previous_button.disabled = _slot_index < 0
	if not valid_binding:
		slot_label.text = "未绑定席位"
		control_kind_label.text = ""
		progress_label.text = ""
		_refreshing = true
		name_input.text = ""
		_refreshing = false
		_clear_profession_details()
		_update_profession_cards(null)
		_update_birthplace_controls(null)
		return

	_refreshing = true
	slot_label.text = "P%d" % (_slot_index + 1)
	control_kind_label.text = "AI" if player.is_bot() else ""
	progress_label.text = "%d / %d" % [_slot_index + 1, _setup.players.size()]
	name_input.placeholder_text = "P%d" % (_slot_index + 1)
	name_input.text = player.display_name
	_refreshing = false

	_refresh_difficulty(player)
	_update_profession_cards(player)
	_update_birthplace_controls(player)
	var detail_type := player.profession_type
	if not player.has_valid_profession():
		detail_type = _first_profession_type()
	_show_profession_details(detail_type)
	_show_region_preview(player.starting_region)
	_clear_message()


func grab_initial_focus() -> void:
	if not visible or not is_interaction_enabled():
		return
	var player := _get_current_player()
	if player != null and _profession_cards.has(player.profession_type):
		(_profession_cards[player.profession_type] as Control).grab_focus()
		return
	var first_type := _first_profession_type()
	if _profession_cards.has(first_type):
		(_profession_cards[first_type] as Control).grab_focus()
	else:
		name_input.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _handle_gamepad_accept(event): return
	if not handle_cancel_action or screen_state != ScreenState.ACTIVE:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_previous_pressed()
		get_viewport().set_input_as_handled()


func _build_profession_cards() -> void:
	if not _profession_cards.is_empty():
		return
	for definition: ProfessionDefinition in ProfessionManager.get_all_definitions():
		if definition == null:
			continue
		var profession_type := int(definition.profession_type)
		var card := PROFESSION_CARD_SCENE.instantiate() as FrontendStatefulCard
		card.name = "Profession_%s" % definition.profession_id
		card.title = definition.profession_name
		card.subtitle = definition.short_description
		card.artwork = definition.selection_portrait
		card.blocked_reason = "该职业已被选择"
		card.set_meta(&"profession_type", profession_type)
		card.add_to_group(&"frontend_profession_card")
		profession_grid.add_child(card)
		card.activated.connect(_on_profession_activated.bind(profession_type))
		card.activation_blocked.connect(_on_profession_blocked)
		card.focus_entered.connect(_show_profession_details.bind(profession_type))
		card.mouse_entered.connect(_on_profession_mouse_entered.bind(profession_type))
		card.mouse_exited.connect(_on_profession_mouse_exited.bind(profession_type))
		_profession_cards[profession_type] = card


func _build_birthplace_controls() -> void:
	if not _region_buttons.is_empty():
		return
	for region_variant: Variant in MapSection.出生点坐标.keys():
		var region := int(region_variant)
		_region_order.append(region)

		var list_button := Button.new()
		list_button.name = "Birthplace_%s" % _region_name(region)
		list_button.custom_minimum_size = Vector2(0.0, 58.0)
		list_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_button.focus_mode = Control.FOCUS_ALL
		list_button.toggle_mode = true
		list_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		list_button.set_meta(&"region", region)
		list_button.add_to_group(&"frontend_birthplace_option")
		birthplace_list.add_child(list_button)
		list_button.pressed.connect(_on_region_activated.bind(region))
		list_button.focus_entered.connect(_show_region_preview.bind(region))
		list_button.mouse_entered.connect(_on_region_mouse_entered.bind(region))
		list_button.mouse_exited.connect(_on_region_mouse_exited.bind(region))
		_region_buttons[region] = list_button


func _update_profession_cards(player: PlayerSetup) -> void:
	for profession_variant: Variant in _profession_cards.keys():
		var profession_type := int(profession_variant)
		var card := _profession_cards[profession_type] as FrontendStatefulCard
		var owner := _find_profession_owner(profession_type)
		var owner_can_yield := owner >= 0 and _is_yieldable_future_bot(owner)
		var is_selected := player != null and player.profession_type == profession_type
		card.interactable = player != null
		card.blocked_reason = (
			"P%d 已选择该职业" % (owner + 1) if owner >= 0 else "该职业不可选择"
		)
		if owner >= 0 and not owner_can_yield:
			card.set_occupied("P%d" % (owner + 1))
		elif is_selected:
			card.set_selected(true)
		else:
			card.presentation_state = FrontendStyle.CardState.NORMAL


func _update_birthplace_controls(player: PlayerSetup) -> void:
	for region: int in _region_order:
		var owner := _find_region_owner(region)
		var owner_can_yield := owner >= 0 and _is_yieldable_future_bot(owner)
		var selected := player != null and player.starting_region == region
		var region_name := _region_name(region)
		var text := region_name
		var state := FrontendStyle.CardState.NORMAL
		if owner >= 0 and not owner_can_yield:
			text = "%s  ·  P%d已选" % [region_name, owner + 1]
			state = FrontendStyle.CardState.OCCUPIED
		elif selected:
			text = "✓ %s" % region_name
			state = FrontendStyle.CardState.SELECTED

		var list_button := _region_buttons[region] as Button
		list_button.text = text
		list_button.button_pressed = selected and (owner < 0 or owner_can_yield)
		list_button.disabled = player == null
		_apply_region_button_style(list_button, state, player != null)


func _apply_region_button_style(
		button: Button,
		state: FrontendStyle.CardState,
		interactable: bool
) -> void:
	button.add_theme_stylebox_override(
		"normal",
		FrontendStyle.card_style(state, false, false, false, interactable)
	)
	button.add_theme_stylebox_override(
		"hover",
		FrontendStyle.card_style(state, true, false, false, interactable)
	)
	button.add_theme_stylebox_override(
		"focus",
		FrontendStyle.card_style(state, false, true, false, interactable)
	)
	button.add_theme_stylebox_override(
		"pressed",
		FrontendStyle.card_style(state, false, false, true, interactable)
	)
	# List rows need button padding, not the large inset used by profession cards.
	for style_name in ["normal", "hover", "focus", "pressed"]:
		var compact := button.get_theme_stylebox(style_name).duplicate() as StyleBox
		compact.content_margin_top = 6
		compact.content_margin_bottom = 6
		compact.content_margin_left = 12
		compact.content_margin_right = 12
		button.add_theme_stylebox_override(style_name, compact)
	if button.is_in_group(&"frontend_birthplace_option"):
		button.custom_minimum_size.y = 72
	var color := FrontendStyle.card_title_color(state, interactable)
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", color)
	button.add_theme_color_override("font_focus_color", color)
	button.add_theme_color_override("font_pressed_color", color)


func _show_profession_details(profession_type: int) -> void:
	var definition := ProfessionManager.get_definition_by_type(profession_type)
	if definition == null:
		_clear_profession_details()
		return
	_displayed_profession_type = profession_type
	portrait.texture = definition.selection_portrait
	portrait.visible = definition.selection_portrait != null
	profession_name_label.text = definition.profession_name
	skill_name_label.text = definition.skill_name
	skill_description_label.text = definition.description


func _clear_profession_details() -> void:
	_displayed_profession_type = PlayerSetup.UNSELECTED
	portrait.texture = null
	portrait.visible = false
	profession_name_label.text = "请选择职业"
	skill_name_label.text = ""
	skill_description_label.text = ""


func _on_profession_mouse_entered(profession_type: int) -> void:
	_hovered_profession_type = profession_type
	_show_profession_details(profession_type)


func _on_profession_mouse_exited(profession_type: int) -> void:
	if _hovered_profession_type != profession_type:
		return
	_hovered_profession_type = PlayerSetup.UNSELECTED
	# 卡片之间切换时，下一张卡的 mouse_entered 会先更新该值；延后一帧可避免
	# 预览短暂闪回已选职业。
	call_deferred("_restore_default_profession_preview_after_hover")


func _restore_default_profession_preview_after_hover() -> void:
	if _hovered_profession_type != PlayerSetup.UNSELECTED:
		return
	var player := _get_current_player()
	if player != null and player.has_valid_profession():
		_show_profession_details(player.profession_type)
		return
	var default_type := _first_profession_type()
	if default_type == PlayerSetup.UNSELECTED:
		_clear_profession_details()
	else:
		_show_profession_details(default_type)


func _show_region_preview(region: int) -> void:
	if not MapSection.出生点坐标.has(region):
		birthplace_preview_label.text = "请选择出生点"
		return
	var owner := _find_region_owner(region)
	if owner >= 0:
		birthplace_preview_label.text = "%s  ·  P%d已选" % [_region_name(region), owner + 1]
	else:
		birthplace_preview_label.text = "出生点：%s" % _region_name(region)


func _on_region_mouse_entered(region: int) -> void:
	_hovered_region = region
	_show_region_preview(region)


func _on_region_mouse_exited(region: int) -> void:
	if _hovered_region != region:
		return
	_hovered_region = PlayerSetup.UNSELECTED
	# 在出生点按钮之间移动时，新控件的 mouse_entered
	# 会先更新该值；延迟恢复可避免标题短暂闪回已选起点。
	call_deferred("_restore_default_region_preview_after_hover")


func _restore_default_region_preview_after_hover() -> void:
	if _hovered_region != PlayerSetup.UNSELECTED:
		return
	var player := _get_current_player()
	if player != null and player.has_valid_starting_region():
		_show_region_preview(player.starting_region)
	else:
		_show_region_preview(PlayerSetup.UNSELECTED)


func _on_name_changed(value: String) -> void:
	if _refreshing:
		return
	var player := _get_current_player()
	if player == null:
		return
	player.display_name = value
	_clear_message()
	player_draft_changed.emit(_slot_index)


func _on_profession_activated(profession_type: int) -> void:
	_show_profession_details(profession_type)
	var player := _get_current_player()
	if player == null:
		_show_invalid("玩家配置不可用")
		return
	var owner := _find_profession_owner(profession_type)
	if owner >= 0:
		if not _reassign_future_bot_profession(owner, profession_type):
			_show_invalid("该职业已由P%d选择" % (owner + 1))
			return
	player.profession_type = profession_type
	_clear_message()
	_update_profession_cards(player)
	player_draft_changed.emit(_slot_index)


func _on_profession_blocked(reason: String) -> void:
	_show_invalid(reason)


func _on_region_activated(region: int) -> void:
	_show_region_preview(region)
	var player := _get_current_player()
	if player == null:
		_show_invalid("玩家配置不可用")
		return
	var owner := _find_region_owner(region)
	if owner >= 0:
		if not _reassign_future_bot_region(owner, region):
			_show_invalid("该出生点已由P%d选择" % (owner + 1))
			_update_birthplace_controls(player)
			return
	player.starting_region = region
	_clear_message()
	_update_birthplace_controls(player)
	_show_region_preview(region)
	player_draft_changed.emit(_slot_index)
	if _region_buttons.has(region):
		_restore_region_focus.call_deferred(region, _slot_index)


func _restore_region_focus(region: int, slot_index: int) -> void:
	# A confirm/back action may leave this page before the deferred focus runs.
	if not is_visible_in_tree() or not is_interaction_enabled() or slot_index != _slot_index:
		return
	var option := _region_buttons.get(region) as Control
	if _can_focus(option): option.grab_focus()


func _on_confirm_pressed() -> void:
	if _confirm_locked:
		return
	var player := _get_current_player()
	if player == null:
		_show_invalid("玩家配置不可用")
		return
	if not player.has_valid_profession():
		_show_invalid("请选择职业")
		return
	var profession_owner := _find_profession_owner(player.profession_type)
	if profession_owner >= 0:
		if not _reassign_future_bot_profession(profession_owner, player.profession_type):
			_show_invalid("该职业已由P%d选择" % (profession_owner + 1))
			return
	if not player.has_valid_starting_region():
		_show_invalid("请选择出生点")
		return
	var region_owner := _find_region_owner(player.starting_region)
	if region_owner >= 0:
		if not _reassign_future_bot_region(region_owner, player.starting_region):
			_show_invalid("该出生点已由P%d选择" % (region_owner + 1))
			return
	player.normalize_display_name()
	_confirmed_player_ids[player.get_instance_id()] = true
	_refreshing = true
	name_input.text = player.display_name
	_refreshing = false
	_clear_message()
	_lock_confirmation_briefly()
	player_draft_changed.emit(_slot_index)
	player_confirmed.emit(_slot_index, _return_to_roster)


func _lock_confirmation_briefly() -> void:
	_confirm_locked = true
	_confirm_unlock_serial += 1
	var serial := _confirm_unlock_serial
	get_tree().create_timer(0.28, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(self) and serial == _confirm_unlock_serial:
			_confirm_locked = false
	, CONNECT_ONE_SHOT)


func _on_previous_pressed() -> void:
	if _slot_index < 0:
		_show_invalid("玩家配置不可用")
		return
	previous_requested.emit(_slot_index)


func _find_profession_owner(profession_type: int) -> int:
	if _setup == null:
		return -1
	for index: int in _setup.players.size():
		if index == _slot_index:
			continue
		var player := _setup.players[index]
		if player != null and player.profession_type == profession_type:
			return index
	return -1


func _find_region_owner(region: int) -> int:
	if _setup == null:
		return -1
	for index: int in _setup.players.size():
		if index == _slot_index:
			continue
		var player := _setup.players[index]
		if player != null and player.starting_region == region:
			return index
	return -1


func _is_yieldable_future_bot(owner_index: int) -> bool:
	var current := _get_current_player()
	if _setup == null or current == null or _return_to_roster:
		return false
	if owner_index <= _slot_index or owner_index >= _setup.players.size():
		return false
	var owner := _setup.players[owner_index]
	return owner != null \
		and owner.is_bot() \
		and not _confirmed_player_ids.has(owner.get_instance_id())


func _reassign_future_bot_profession(owner_index: int, desired_type: int) -> bool:
	if not _is_yieldable_future_bot(owner_index):
		return false
	var used: Dictionary[int, bool] = {desired_type: true}
	for index: int in _setup.players.size():
		if index == _slot_index or index == owner_index:
			continue
		var player := _setup.players[index]
		if player != null and player.has_valid_profession():
			used[player.profession_type] = true
	var replacement := PlayerSetup.UNSELECTED
	for definition: ProfessionDefinition in ProfessionManager.get_all_definitions():
		if definition == null:
			continue
		var profession_type := int(definition.profession_type)
		if not used.has(profession_type):
			replacement = profession_type
			break
	if replacement == PlayerSetup.UNSELECTED:
		return false
	_setup.players[owner_index].profession_type = replacement
	return true


func _reassign_future_bot_region(owner_index: int, desired_region: int) -> bool:
	if not _is_yieldable_future_bot(owner_index):
		return false
	var used: Dictionary[int, bool] = {desired_region: true}
	for index: int in _setup.players.size():
		if index == _slot_index or index == owner_index:
			continue
		var player := _setup.players[index]
		if player != null and player.has_valid_starting_region():
			used[player.starting_region] = true
	var replacement := PlayerSetup.UNSELECTED
	for region: int in _region_order:
		if not used.has(region):
			replacement = region
			break
	if replacement == PlayerSetup.UNSELECTED:
		return false
	_setup.players[owner_index].starting_region = replacement
	return true


func _get_current_player() -> PlayerSetup:
	if _setup == null or _slot_index < 0 or _slot_index >= _setup.players.size():
		return null
	return _setup.players[_slot_index]


func _first_profession_type() -> int:
	var definitions := ProfessionManager.get_all_definitions()
	if definitions.is_empty() or definitions[0] == null:
		return PlayerSetup.UNSELECTED
	return int(definitions[0].profession_type)


func _region_name(region: int) -> String:
	var key: Variant = MapSection.REGION.find_key(region)
	return String(key) if key != null else "未知"


func _show_invalid(message: String) -> void:
	message_label.text = message
	message_label.visible = true
	invalid_action.emit(message)


func _clear_message() -> void:
	message_label.text = ""
	message_label.visible = false


func _wire_focus_navigation() -> void:
	var cards: Array[Control] = []
	for definition: ProfessionDefinition in ProfessionManager.get_all_definitions():
		if definition == null:
			continue
		var profession_type := int(definition.profession_type)
		if _profession_cards.has(profession_type):
			cards.append(_profession_cards[profession_type] as Control)
	var region_controls: Array[Control] = []
	for region: int in _region_order:
		region_controls.append(_region_buttons[region] as Control)
	if cards.is_empty() or region_controls.is_empty():
		return

	name_input.focus_neighbor_bottom = cards[0].get_path()
	name_input.focus_next = cards[0].get_path()
	name_input.focus_neighbor_top = previous_button.get_path()
	name_input.focus_neighbor_left = name_input.get_path()
	name_input.focus_neighbor_right = name_input.get_path()
	for index: int in cards.size():
		var card := cards[index]
		var row := index / 3
		var column := index % 3
		card.focus_neighbor_left = (
			cards[index - 1].get_path() if column > 0 else card.get_path()
		)
		card.focus_neighbor_right = (
			cards[index + 1].get_path()
			if column < 2 and index + 1 < cards.size()
			else region_controls[mini(index, region_controls.size() - 1)].get_path()
		)
		card.focus_neighbor_top = (
			cards[index - 3].get_path() if row > 0 else name_input.get_path()
		)
		card.focus_neighbor_bottom = (
			cards[index + 3].get_path()
			if index + 3 < cards.size()
			else confirm_button.get_path()
		)

	for index: int in region_controls.size():
		var region_control := region_controls[index]
		region_control.focus_neighbor_left = (region_controls[index - 1] if index % 2 == 1 else cards[mini(index, cards.size() - 1)]).get_path()
		region_control.focus_neighbor_right = (region_controls[index + 1] if index % 2 == 0 else region_control).get_path()
		region_control.focus_neighbor_top = (
			region_controls[index - 2].get_path() if index >= 2 else map_zoom_button.get_path()
		)
		region_control.focus_neighbor_bottom = (
			region_controls[index + 2].get_path()
			if index + 2 < region_controls.size()
			else confirm_button.get_path()
		)
		region_control.focus_next = (region_controls[index + 1] if index + 1 < region_controls.size() else confirm_button).get_path()
		region_control.focus_previous = (region_controls[index - 1] if index > 0 else map_zoom_button).get_path()
	map_zoom_button.focus_neighbor_top = name_input.get_path()
	map_zoom_button.focus_neighbor_bottom = region_controls[0].get_path()
	map_zoom_button.focus_neighbor_left = cards[2].get_path()
	map_zoom_button.focus_neighbor_right = map_zoom_button.get_path()
	map_zoom_button.focus_next = region_controls[0].get_path()

	previous_button.focus_neighbor_right = confirm_button.get_path()
	previous_button.focus_neighbor_left = confirm_button.get_path()
	previous_button.focus_neighbor_top = cards.back().get_path()
	previous_button.focus_neighbor_bottom = name_input.get_path()
	confirm_button.focus_neighbor_left = previous_button.get_path()
	confirm_button.focus_neighbor_right = previous_button.get_path()
	confirm_button.focus_neighbor_top = region_controls.back().get_path()
	confirm_button.focus_neighbor_bottom = name_input.get_path()

func _build_difficulty_controls() -> void:
	var content := name_input.get_parent().get_parent()
	difficulty_box = VBoxContainer.new()
	difficulty_box.name = "DifficultyControls"
	difficulty_box.add_theme_constant_override("separation", 8)
	content.add_child(difficulty_box)
	content.move_child(difficulty_box, name_input.get_parent().get_index() + 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	difficulty_box.add_child(row)
	var caption := Label.new()
	caption.text = "电脑难度"
	caption.add_theme_font_size_override("font_size", 34)
	row.add_child(caption)
	var group := ButtonGroup.new()
	for index: int in 3:
		var button := Button.new()
		button.name = "Difficulty%d" % index
		button.custom_minimum_size = Vector2(220, 64)
		button.toggle_mode = true
		button.button_group = group
		button.add_theme_font_size_override("font_size", 34)
		button.add_theme_color_override("font_color", Color("#51331F"))
		button.add_theme_constant_override("outline_size", 0)
		button.pressed.connect(_on_difficulty_selected.bind(index))
		row.add_child(button)
		difficulty_buttons.append(button)
	difficulty_description = Label.new()
	difficulty_description.add_theme_font_size_override("font_size", 30)
	difficulty_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	difficulty_box.add_child(difficulty_description)

func _on_difficulty_selected(value: int) -> void:
	var player := _get_current_player()
	if player == null or not player.is_bot(): return
	if not is_interaction_enabled():
		_refresh_difficulty(player)
		return
	player.ai_difficulty = value as PlayerSetup.AIDifficulty
	_refresh_difficulty(player)
	player_draft_changed.emit(_slot_index)

func _refresh_difficulty(player: PlayerSetup) -> void:
	if not player.is_bot():
		_wire_focus_navigation()
		return
	for index: int in difficulty_buttons.size():
		var button := difficulty_buttons[index]
		var selected := int(player.ai_difficulty) == index
		button.set_pressed_no_signal(selected)
		button.text = ("已选 · " if selected else "") + AIProfile.LABELS[index]
		button.tooltip_text = AIProfile.DESCRIPTIONS[index]
		button.add_theme_stylebox_override("normal", FrontendStyle.make_box(Color("#F6E6C6"), Color("#947052"), 2, 10, Vector4(18, 6, 18, 6)))
		button.add_theme_stylebox_override("pressed", FrontendStyle.make_box(Color("#6A4939"), Color("#E8B66A"), 4, 10, Vector4(18, 6, 18, 6)))
		button.add_theme_color_override("font_pressed_color", Color("#FFF3D5"))
		button.focus_neighbor_top = name_input.get_path()
		button.focus_neighbor_left = difficulty_buttons[maxi(0, index - 1)].get_path()
		button.focus_neighbor_right = difficulty_buttons[mini(2, index + 1)].get_path()
		if not _profession_cards.is_empty(): button.focus_neighbor_bottom = (_profession_cards.values()[0] as Control).get_path()
		difficulty_buttons[index].focus_next = difficulty_buttons[(index + 1) % 3].get_path() if index < 2 else (_profession_cards.values()[0] as Control).get_path()
	difficulty_description.text = AIProfile.DESCRIPTIONS[int(player.ai_difficulty)]
	_wire_focus_navigation()
	name_input.focus_neighbor_bottom = difficulty_buttons[int(player.ai_difficulty)].get_path()
	name_input.focus_next = difficulty_buttons[0].get_path()
	var index := 0
	for card: Control in _profession_cards.values():
		if index < 3: card.focus_neighbor_top = difficulty_buttons[index].get_path()
		index += 1
