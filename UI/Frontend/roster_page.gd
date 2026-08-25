class_name FrontendRosterPage
extends FrontendScreen

## 本地开局的最终阵容总览。页面只读取草稿并发出编辑/开始意图，
## 不直接提交 GameManager，也不切换场景。

signal edit_player_requested(slot_index: int)
signal start_requested
signal previous_requested

const CARD_SCENE: PackedScene = preload("res://UI/Frontend/roster_player_card.tscn")
const MAX_COLUMNS: int = 3
const CARD_WIDTH: float = 620.0
const CARD_SEPARATION: float = 24.0

@onready var _cards_flow: HFlowContainer = %CardsFlow
@onready var _lineup_center: CenterContainer = %LineupCenter
@onready var _ready_panel: PanelContainer = %ReadyPanel
@onready var _ready_count_label: Label = %ReadyCountLabel
@onready var _ready_caption: Label = %ReadyCaption
@onready var _preview_accent: ColorRect = %PreviewAccent
@onready var _preview_identity: Label = %PreviewIdentity
@onready var _preview_meta: Label = %PreviewMeta
@onready var _preview_skill: Label = %PreviewSkill
@onready var _validation_error: Label = %ValidationError
@onready var _previous_button: Button = %PreviousButton
@onready var _start_button: Button = %StartButton

var _setup: SessionSetup = null
var _cards: Array[FrontendRosterPlayerCard] = []
var _ui_preferences: FrontendUIPreferences = null
var _preferred_focus_slot := -1
var _preview_slot := -1
var _layout_columns := 1


func _ready() -> void:
	super()
	_previous_button.pressed.connect(_on_previous_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	resized.connect(_request_grid_layout_update)
	_lineup_center.resized.connect(_request_grid_layout_update)
	refresh_view()
	call_deferred("_update_grid_layout")


func _request_grid_layout_update() -> void:
	call_deferred("_update_grid_layout")


func set_ui_preferences(preferences: FrontendUIPreferences) -> void:
	super.set_ui_preferences(preferences)
	_ui_preferences = preferences
	for card: FrontendRosterPlayerCard in _cards:
		card.set_ui_preferences(preferences)


func bind_setup(setup: SessionSetup) -> void:
	_setup = setup
	if is_node_ready():
		refresh_view()


func refresh_view() -> void:
	if not is_node_ready():
		return
	_clear_cards()
	if _setup != null:
		for player: PlayerSetup in _setup.players:
			if player != null:
				_create_player_card(player)
	_update_validation()
	_update_grid_layout()
	var next_preview := _preferred_focus_slot if _preferred_focus_slot >= 0 else _preview_slot
	if next_preview < 0 and not _cards.is_empty():
		next_preview = _cards[0].player_setup.slot_index
	_update_preview(next_preview)
	_wire_focus_neighbors()


func grab_initial_focus() -> void:
	if not visible or not is_interaction_enabled():
		return
	if _preferred_focus_slot >= 0 and _preferred_focus_slot < _cards.size():
		_cards[_preferred_focus_slot].grab_focus()
		_preferred_focus_slot = -1
		return
	if not _cards.is_empty():
		_cards[0].grab_focus()
	elif not _start_button.disabled:
		_start_button.grab_focus()
	else:
		_previous_button.grab_focus()


func prefer_player_focus(slot_index: int) -> void:
	_preferred_focus_slot = slot_index
	if screen_state == ScreenState.ACTIVE:
		call_deferred("grab_initial_focus")


func _create_player_card(player: PlayerSetup) -> void:
	var card: FrontendRosterPlayerCard = CARD_SCENE.instantiate() as FrontendRosterPlayerCard
	card.name = "PlayerCard%d" % (player.slot_index + 1)
	card.set_compact(_setup != null and _setup.players.size() > 3)
	card.bind_player(player)
	card.activated.connect(_on_card_activated)
	card.preview_requested.connect(_update_preview)
	if _ui_preferences != null:
		card.set_ui_preferences(_ui_preferences)
	_cards_flow.add_child(card)
	_cards.append(card)


func _clear_cards() -> void:
	for card: FrontendRosterPlayerCard in _cards:
		if is_instance_valid(card):
			_cards_flow.remove_child(card)
			card.free()
	_cards.clear()


func _update_validation() -> void:
	var errors := PackedStringArray(["阵容未准备好"]) if _setup == null else _setup.validate()
	var has_errors: bool = not errors.is_empty()
	var total := _setup.players.size() if _setup != null else 0
	var ready_count := 0
	if _setup != null:
		for player: PlayerSetup in _setup.players:
			if player != null and player.is_configured():
				ready_count += 1
	_ready_count_label.text = "%d / %d" % [ready_count, total]
	_ready_caption.text = "全员就绪" if total > 0 and ready_count == total and not has_errors else "等待配置"
	_ready_panel.add_theme_stylebox_override(
		"panel",
		FrontendStyle.make_box(
			Color("#5F7F54") if not has_errors else FrontendStyle.BROWN,
			FrontendStyle.GOLD_LIGHT,
			4,
			20,
			Vector4(28.0, 12.0, 28.0, 12.0)
		)
	)
	_start_button.disabled = has_errors
	_validation_error.visible = has_errors
	_validation_error.text = errors[0] if has_errors else ""


func _update_preview(slot_index: int) -> void:
	if _setup == null or slot_index < 0 or slot_index >= _setup.players.size():
		_preview_slot = -1
		_preview_identity.text = "选择席位查看详情"
		_preview_meta.text = ""
		_preview_skill.text = ""
		return
	var player: PlayerSetup = _setup.players[slot_index]
	if player == null:
		return
	_preview_slot = slot_index
	_preview_accent.color = FrontendRosterPlayerCard.accent_for_slot(slot_index)
	_preview_identity.text = "P%d  %s" % [slot_index + 1, player.normalized_display_name()]
	var profession_name := "未选择职业"
	var skill_text := ""
	if player.has_valid_profession():
		var definition := ProfessionManager.get_definition_by_type(player.profession_type)
		if definition != null:
			profession_name = definition.profession_name
			skill_text = "%s · %s" % [definition.skill_name, definition.short_description]
	var region_name := "未选择出生点"
	if player.has_valid_starting_region():
		region_name = String(MapSection.REGION.find_key(player.starting_region))
	_preview_meta.text = "%s · %s" % [profession_name, region_name]
	_preview_skill.text = skill_text


func _update_grid_layout() -> void:
	if not is_node_ready() or not is_inside_tree():
		return
	var available_width: float = _lineup_center.size.x
	if available_width <= 0.0:
		available_width = size.x
	var card_count := _cards.size()
	var columns: int = 1
	match card_count:
		2:
			columns = 2
		3:
			columns = 3
		4:
			columns = 2
		_:
			columns = MAX_COLUMNS if card_count >= 5 else 1
	if available_width < 1320.0:
		columns = 1
	elif available_width < 1980.0:
		columns = mini(columns, 2)
	columns = mini(columns, maxi(card_count, 1))
	var compact := card_count > 3 or columns < mini(card_count, MAX_COLUMNS)
	for card: FrontendRosterPlayerCard in _cards:
		card.set_compact(compact)
	_layout_columns = columns
	_cards_flow.custom_minimum_size.x = (
		CARD_WIDTH * float(columns) + CARD_SEPARATION * float(maxi(columns - 1, 0))
	)
	_cards_flow.queue_sort()
	_wire_focus_neighbors()


func get_layout_columns() -> int:
	return _layout_columns


func _wire_focus_neighbors() -> void:
	if not is_node_ready() or not is_inside_tree():
		return
	var card_count: int = _cards.size()
	for card: FrontendRosterPlayerCard in _cards:
		if not is_instance_valid(card) or not card.is_inside_tree():
			return
	if not _previous_button.is_inside_tree() or not _start_button.is_inside_tree():
		return
	var columns: int = mini(maxi(_layout_columns, 1), maxi(card_count, 1))
	for index: int in card_count:
		var card: FrontendRosterPlayerCard = _cards[index]
		var row_start: int = (index / columns) * columns
		var row_end: int = mini(row_start + columns, card_count) - 1
		var left_index: int = row_end if index == row_start else index - 1
		var right_index: int = row_start if index == row_end else index + 1
		card.focus_neighbor_left = _cards[left_index].get_path()
		card.focus_neighbor_right = _cards[right_index].get_path()
		var column: int = index % columns
		if index >= columns:
			card.focus_neighbor_top = _cards[index - columns].get_path()
		else:
			card.focus_neighbor_top = _footer_target(column, columns).get_path()
		if index + columns < card_count:
			card.focus_neighbor_bottom = _cards[index + columns].get_path()
		else:
			card.focus_neighbor_bottom = _footer_target(column, columns).get_path()

	var first_focus: Control = _cards[0] if card_count > 0 else _previous_button
	var last_focus: Control = _cards[card_count - 1] if card_count > 0 else _previous_button
	_previous_button.focus_neighbor_left = (
		_start_button.get_path() if not _start_button.disabled else last_focus.get_path()
	)
	_previous_button.focus_neighbor_right = (
		_start_button.get_path() if not _start_button.disabled else first_focus.get_path()
	)
	_previous_button.focus_neighbor_top = _bottom_card_for_column(0, columns).get_path() if card_count > 0 else _previous_button.get_path()
	_previous_button.focus_neighbor_bottom = first_focus.get_path()
	_start_button.focus_neighbor_left = _previous_button.get_path()
	_start_button.focus_neighbor_right = _previous_button.get_path()
	_start_button.focus_neighbor_top = last_focus.get_path()
	_start_button.focus_neighbor_bottom = first_focus.get_path()

	var tab_order: Array[Control] = []
	for card: FrontendRosterPlayerCard in _cards:
		tab_order.append(card)
	tab_order.append(_previous_button)
	if not _start_button.disabled:
		tab_order.append(_start_button)
	for index: int in tab_order.size():
		var previous_index: int = (index - 1 + tab_order.size()) % tab_order.size()
		var next_index: int = (index + 1) % tab_order.size()
		tab_order[index].focus_previous = tab_order[previous_index].get_path()
		tab_order[index].focus_next = tab_order[next_index].get_path()


func _footer_target(column: int, columns: int) -> Control:
	if _start_button.disabled or column < columns / 2:
		return _previous_button
	return _start_button


func _bottom_card_for_column(column: int, columns: int) -> Control:
	if _cards.is_empty():
		return _previous_button
	var index: int = column
	while index + columns < _cards.size():
		index += columns
	if index >= _cards.size():
		index = _cards.size() - 1
	return _cards[index]


func _on_card_activated(slot_index: int) -> void:
	edit_player_requested.emit(slot_index)


func _on_start_pressed() -> void:
	_update_validation()
	_wire_focus_neighbors()
	if not _start_button.disabled:
		start_requested.emit()


func _on_previous_pressed() -> void:
	previous_requested.emit()
