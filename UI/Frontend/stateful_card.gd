class_name FrontendStatefulCard
extends PanelContainer

## Focusable card used for professions, modes, birthplaces, and roster entries.
## Occupied cards remain inspectable but emit activation_blocked instead of activated.

signal activated
signal activation_blocked(reason: String)
signal presentation_state_changed(state: FrontendStyle.CardState)

@export var title := "选项":
	set(value):
		title = value
		_sync_content()

@export_multiline var subtitle := "":
	set(value):
		subtitle = value
		_sync_content()

@export var artwork: Texture2D:
	set(value):
		artwork = value
		_sync_content()

@export var presentation_state := FrontendStyle.CardState.NORMAL:
	set(value):
		var next_state: FrontendStyle.CardState = clampi(
			value,
			FrontendStyle.CardState.NORMAL,
			FrontendStyle.CardState.CONFIRMED
		) as FrontendStyle.CardState
		if presentation_state == next_state:
			return
		presentation_state = next_state
		_refresh_visuals()
		presentation_state_changed.emit(presentation_state)

@export var occupied_by := "":
	set(value):
		occupied_by = value
		_refresh_visuals()

@export var interactable := true:
	set(value):
		interactable = value
		_refresh_visuals()

@export var blocked_reason := "不可选择"

@onready var _artwork_rect: TextureRect = %Artwork
@onready var _title_label: Label = %Title
@onready var _subtitle_label: Label = %Subtitle
@onready var _badge_label: Label = %Badge

var _hovered := false
var _focused := false
var _pressed := false
var _motion_tween: Tween
var _preferences: FrontendUIPreferences


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
	_sync_content()
	_refresh_visuals()


func set_ui_preferences(preferences: FrontendUIPreferences) -> void:
	if _preferences != null and _preferences.reduce_motion_changed.is_connected(_on_reduce_motion_changed):
		_preferences.reduce_motion_changed.disconnect(_on_reduce_motion_changed)
	_preferences = preferences
	if _preferences != null and not _preferences.reduce_motion_changed.is_connected(_on_reduce_motion_changed):
		_preferences.reduce_motion_changed.connect(_on_reduce_motion_changed)


func set_selected(selected: bool) -> void:
	presentation_state = (
		FrontendStyle.CardState.SELECTED if selected else FrontendStyle.CardState.NORMAL
	)


func set_occupied(owner_label: String) -> void:
	occupied_by = owner_label
	presentation_state = FrontendStyle.CardState.OCCUPIED


func set_confirmed(confirmed: bool) -> void:
	presentation_state = (
		FrontendStyle.CardState.CONFIRMED if confirmed else FrontendStyle.CardState.NORMAL
	)


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
	if not interactable:
		activation_blocked.emit(blocked_reason)
		_request_feedback(&"invalid")
		return
	if presentation_state == FrontendStyle.CardState.OCCUPIED:
		activation_blocked.emit(
			blocked_reason if not blocked_reason.is_empty() else "已被选择"
		)
		_request_feedback(&"invalid")
		return
	activated.emit()
	_request_feedback(&"confirm")


func _sync_content() -> void:
	if not is_node_ready():
		return
	_title_label.text = title
	_subtitle_label.text = subtitle
	_subtitle_label.visible = not subtitle.is_empty()
	_artwork_rect.texture = artwork
	_artwork_rect.visible = artwork != null


func _refresh_visuals() -> void:
	if not is_node_ready():
		return
	add_theme_stylebox_override(
		"panel",
		FrontendStyle.card_style(
			presentation_state,
			_hovered,
			_focused,
			_pressed,
			interactable
		)
	)
	_title_label.add_theme_color_override(
		"font_color",
		FrontendStyle.card_title_color(presentation_state, interactable)
	)
	var badge_text := FrontendStyle.card_badge(presentation_state, occupied_by)
	if not interactable:
		badge_text = "不可用"
	_badge_label.text = badge_text
	_badge_label.visible = not badge_text.is_empty()
	modulate.a = 1.0 if interactable or presentation_state == FrontendStyle.CardState.OCCUPIED else 0.78


func _on_mouse_entered() -> void:
	_hovered = true
	_refresh_visuals()
	_tween_scale(Vector2(1.012, 1.012))


func _on_mouse_exited() -> void:
	_hovered = false
	_pressed = false
	_refresh_visuals()
	_tween_scale(Vector2.ONE)


func _on_focus_entered() -> void:
	_focused = true
	_refresh_visuals()
	_tween_scale(Vector2(1.012, 1.012))


func _on_focus_exited() -> void:
	_focused = false
	_pressed = false
	_refresh_visuals()
	if not _hovered:
		_tween_scale(Vector2.ONE)


func _play_accept_feedback() -> void:
	_pressed = true
	_refresh_visuals()
	_tween_scale(Vector2(0.982, 0.982), 0.07)
	get_tree().create_timer(0.07, true, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		_pressed = false
		_refresh_visuals()
		_tween_scale(Vector2(1.012, 1.012) if _focused or _hovered else Vector2.ONE, 0.12)
	, CONNECT_ONE_SHOT)


func _tween_scale(target: Vector2, duration := 0.20) -> void:
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
	_motion_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(self, "scale", target, actual_duration)


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _on_reduce_motion_changed(enabled: bool) -> void:
	if enabled:
		if _motion_tween != null and _motion_tween.is_valid():
			_motion_tween.kill()
		_motion_tween = null
		scale = Vector2.ONE


func _request_feedback(cue: StringName) -> void:
	if _preferences != null:
		_preferences.request_feedback(cue)
