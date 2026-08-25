class_name FrontendRosterPlayerCard
extends PanelContainer

## 阵容确认页的玩家席位卡。角色是第一视觉层级，席位色负责多人识别，
## “就绪”仅作为状态徽标，不再用整张绿色底板表达。

signal activated(slot_index: int)
signal preview_requested(slot_index: int)

const PLAYER_ACCENTS: Array[Color] = [
	Color("#D66A3D"),
	Color("#4E79B8"),
	Color("#5C9765"),
	Color("#9B68AA"),
	Color("#D19B35"),
	Color("#3D948C"),
]

@onready var _slot_badge: PanelContainer = %SlotBadge
@onready var _slot_label: Label = %SlotLabel
@onready var _control_badge: PanelContainer = %ControlBadge
@onready var _control_label: Label = %ControlLabel
@onready var _ready_badge: PanelContainer = %ReadyBadge
@onready var _ready_label: Label = %ReadyLabel
@onready var _portrait_frame: PanelContainer = %PortraitFrame
@onready var _portrait: TextureRect = %Portrait
@onready var _name_label: Label = %PlayerName
@onready var _profession_label: Label = %ProfessionLabel
@onready var _region_label: Label = %RegionLabel

var player_setup: PlayerSetup = null
var definition: ProfessionDefinition = null
var title := ""
var subtitle := ""
var artwork: Texture2D = null

var _hovered := false
var _focused := false
var _pressed := false
var _motion_tween: Tween = null
var _preferences: FrontendUIPreferences = null
var _accent := PLAYER_ACCENTS[0]
var _compact := true


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	resized.connect(_update_pivot)
	_update_pivot()
	_apply_density()
	_sync_content()
	_refresh_visuals()


func bind_player(player: PlayerSetup) -> void:
	player_setup = player
	definition = null
	if player != null and player.has_valid_profession():
		definition = ProfessionManager.get_definition_by_type(player.profession_type)
	_accent = accent_for_slot(player.slot_index if player != null else 0)
	_sync_content()
	_refresh_visuals()


func set_ui_preferences(preferences: FrontendUIPreferences) -> void:
	if _preferences != null and _preferences.reduce_motion_changed.is_connected(_on_reduce_motion_changed):
		_preferences.reduce_motion_changed.disconnect(_on_reduce_motion_changed)
	_preferences = preferences
	if _preferences != null and not _preferences.reduce_motion_changed.is_connected(_on_reduce_motion_changed):
		_preferences.reduce_motion_changed.connect(_on_reduce_motion_changed)


func set_compact(compact: bool) -> void:
	_compact = compact
	_apply_density()


static func accent_for_slot(slot_index: int) -> Color:
	return PLAYER_ACCENTS[clampi(slot_index, 0, PLAYER_ACCENTS.size() - 1)]


func _apply_density() -> void:
	custom_minimum_size = Vector2(620.0, 430.0 if _compact else 500.0)
	if is_node_ready():
		_portrait_frame.custom_minimum_size.y = 190.0 if _compact else 245.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		_pressed = mouse_event.pressed
		_refresh_visuals()
		accept_event()
		if not mouse_event.pressed:
			_activate()
		return
	if has_focus() and event.is_action_pressed("ui_accept"):
		accept_event()
		_play_accept_feedback()
		_activate()


func _activate() -> void:
	if player_setup == null:
		_request_feedback(&"invalid")
		return
	activated.emit(player_setup.slot_index)
	_request_feedback(&"confirm")


func _sync_content() -> void:
	if not is_node_ready():
		return
	if player_setup == null:
		title = "待设置"
		subtitle = ""
		artwork = null
		_slot_label.text = "P?"
		_control_badge.visible = false
		_control_label.text = ""
		_ready_label.text = "待设置"
		_ready_badge.visible = true
		_portrait.texture = null
		_name_label.text = "待设置"
		_profession_label.text = "未选择职业"
		_region_label.text = "未选择出生点"
		return

	var slot_number := player_setup.slot_index + 1
	var control_text := "AI" if player_setup.is_bot() else ""
	var profession_name := definition.profession_name if definition != null else "未选择职业"
	var region_name := "未选择出生点"
	if player_setup.has_valid_starting_region():
		region_name = String(MapSection.REGION.find_key(player_setup.starting_region))
	title = "P%d%s" % [slot_number, " · AI" if player_setup.is_bot() else ""]
	subtitle = "%s\n%s\n%s" % [player_setup.normalized_display_name(), profession_name, region_name]
	artwork = definition.selection_portrait if definition != null else null
	_slot_label.text = "P%d" % slot_number
	_control_label.text = control_text
	_control_badge.visible = player_setup.is_bot()
	_ready_label.text = "就绪" if player_setup.is_configured() else "待设置"
	_portrait.texture = artwork
	_name_label.text = player_setup.normalized_display_name()
	_profession_label.text = profession_name
	_region_label.text = region_name


func _refresh_visuals() -> void:
	if not is_node_ready():
		return
	add_theme_stylebox_override("panel", _make_card_style())
	_slot_badge.add_theme_stylebox_override(
		"panel",
		FrontendStyle.make_box(_accent, _accent.lightened(0.25), 2, 14, Vector4(16.0, 6.0, 16.0, 6.0))
	)
	_control_badge.add_theme_stylebox_override(
		"panel",
		FrontendStyle.make_box(
			Color("#6A4939"),
			Color("#F2C56D"),
			2,
			12,
			Vector4(12.0, 5.0, 12.0, 5.0)
		)
	)
	_portrait_frame.add_theme_stylebox_override(
		"panel",
		FrontendStyle.make_box(
			Color(_accent.lightened(0.60), 0.72),
			Color(_accent, 0.78),
			3,
			18,
			Vector4(10.0, 8.0, 10.0, 8.0)
		)
	)
	var configured := player_setup != null and player_setup.is_configured()
	_ready_badge.add_theme_stylebox_override(
		"panel",
		FrontendStyle.make_box(
			Color("#6F8E61") if configured else Color("#877767"),
			Color("#FFF0C5"),
			2,
			13,
			Vector4(13.0, 5.0, 13.0, 5.0)
		)
	)


func _make_card_style() -> StyleBoxFlat:
	var background := Color("#FFF0CB")
	var border := _accent
	var width := 4
	if _pressed:
		background = background.darkened(0.08)
	elif _focused:
		background = Color("#FFF7E2")
		border = FrontendStyle.FOCUS
		width = 7
	elif _hovered:
		background = Color("#FFF5D9")
		border = _accent.lightened(0.22)
		width = 6
	var style := FrontendStyle.make_box(
		background,
		border,
		width,
		22,
		Vector4(18.0, 16.0, 18.0, 14.0)
	)
	style.shadow_color = Color(FrontendStyle.BROWN_DARK, 0.25 if _focused or _hovered else 0.15)
	style.shadow_size = 11 if _focused else 7
	style.shadow_offset = Vector2(0.0, 5.0)
	if _focused:
		style.expand_margin_left = 4.0
		style.expand_margin_top = 4.0
		style.expand_margin_right = 4.0
		style.expand_margin_bottom = 4.0
	return style


func _on_mouse_entered() -> void:
	_hovered = true
	_refresh_visuals()
	_emit_preview()
	_tween_scale(Vector2(1.025, 1.025))


func _on_mouse_exited() -> void:
	_hovered = false
	_pressed = false
	_refresh_visuals()
	if not _focused:
		_tween_scale(Vector2.ONE)


func _on_focus_entered() -> void:
	_focused = true
	_refresh_visuals()
	_emit_preview()
	_tween_scale(Vector2(1.025, 1.025))


func _on_focus_exited() -> void:
	_focused = false
	_pressed = false
	_refresh_visuals()
	if not _hovered:
		_tween_scale(Vector2.ONE)


func _emit_preview() -> void:
	if player_setup != null:
		preview_requested.emit(player_setup.slot_index)


func _play_accept_feedback() -> void:
	_pressed = true
	_refresh_visuals()
	_tween_scale(Vector2(0.975, 0.975), 0.07)
	get_tree().create_timer(0.07, true, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		_pressed = false
		_refresh_visuals()
		_tween_scale(Vector2(1.025, 1.025) if _focused or _hovered else Vector2.ONE, 0.12)
	, CONNECT_ONE_SHOT)


func _tween_scale(target: Vector2, duration := 0.18) -> void:
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	var actual_duration := duration
	if _preferences != null:
		actual_duration = _preferences.transition_duration(duration)
	if is_zero_approx(actual_duration):
		scale = target
		_motion_tween = null
		return
	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(self, "scale", target, actual_duration)


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _on_reduce_motion_changed(enabled: bool) -> void:
	if not enabled:
		return
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	_motion_tween = null
	scale = Vector2.ONE


func _request_feedback(cue: StringName) -> void:
	if _preferences != null:
		_preferences.request_feedback(cue)
