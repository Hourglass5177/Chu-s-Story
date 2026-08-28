extends Control
class_name EventOverlay

const EVENT_CARD_BACK := preload("res://arts/事件卡/事件牌（牌背）.png")

@onready var _card_image: TextureRect = %CardImage
@onready var _title_label: Label = %TitleLabel
@onready var _context_label: Label = %ContextLabel
@onready var _prompt_label: Label = %PromptLabel
@onready var _countdown_label: Label = %CountdownLabel
@onready var _timer_panel: PanelContainer = $PopupFrame/Header/TimerPanel
@onready var _guide_button: Button = %GuideButton
@onready var _instruction_label: Label = %InstructionLabel
@onready var _step_label: Label = %StepLabel
@onready var _options_box: VBoxContainer = %OptionsBox
@onready var _timeout_bar: ProgressBar = %TimeoutBar
@onready var _timeout_hint: Label = %TimeoutHint
var _active_request: EventChoiceRequest = null
var _deadline_msec: int = 0
var _timeout_seconds: float = 15.0
var _current_card_name: String = ""
var _current_event_id: StringName = &""
var _showing_retained_preview: bool = false
var _retained_preview_modal_lease: int = -1
var _retained_preview_session_generation: int = -1
var _retained_preview_turn_epoch: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	hide()
	EventManager.event_revealed.connect(_on_event_revealed)
	EventManager.choice_requested.connect(_on_choice_requested)
	EventManager.reaction_requested.connect(_on_reaction_requested)
	EventManager.choice_resolved.connect(_on_choice_resolved)
	EventManager.interaction_finished.connect(_on_interaction_finished)
	_guide_button.pressed.connect(_open_event_guide)

func _process(_delta: float) -> void:
	if not visible or _active_request == null:
		return
	var remaining := EventManager.get_choice_time_left(_active_request.request_id)
	if remaining <= 0.0:
		remaining = maxf(float(_deadline_msec - Time.get_ticks_msec()) / 1000.0, 0.0)
	_countdown_label.text = "剩余 %02d 秒" % int(ceil(remaining))
	_timeout_bar.value = remaining / maxf(_timeout_seconds, 0.001) * 100.0

func _on_event_revealed(player: PlayerClass, card: 事件牌) -> void:
	_showing_retained_preview = false
	_current_card_name = card.card_name
	_current_event_id = card.event_id
	_guide_button.visible = true
	_context_label.text = "%s · 事件牌" % player.player_name
	_title_label.text = "【%s】" % card.card_name
	_prompt_label.text = card.description
	_card_image.texture = card.image_of_front
	_instruction_label.text = "事件效果"
	_step_label.text = "公开"
	_countdown_label.text = "15 秒"
	_timer_panel.show()
	_timeout_bar.value = 100.0
	_timeout_hint.text = "超时自动结算"
	_clear_options()
	show()

func _on_choice_requested(request: EventChoiceRequest) -> void:
	if request.presentation != EventChoiceRequest.Presentation.默认 \
			or request.kind in [EventChoiceRequest.ChoiceKind.格子, EventChoiceRequest.ChoiceKind.玩家]:
		_active_request = null
		_clear_options()
		hide()
		return
	_show_request(request, false)

func _on_reaction_requested(request: EventChoiceRequest) -> void:
	_show_request(request, true)

func _show_request(request: EventChoiceRequest, is_reaction: bool) -> void:
	_active_request = request
	_timeout_seconds = request.timeout_seconds
	_timer_panel.show()
	_deadline_msec = Time.get_ticks_msec() + int(request.timeout_seconds * 1000.0)
	var requester_name := request.requester.player_name if is_instance_valid(request.requester) else "当前玩家"
	var is_reveal_confirmation := request.kind == EventChoiceRequest.ChoiceKind.确认 and not _current_card_name.is_empty()
	_context_label.text = "%s · %s" % [requester_name, "响应牌" if is_reaction else ("事件牌" if is_reveal_confirmation else "选择")]
	if is_reaction:
		_show_response_card_preview(request.options[0] if not request.options.is_empty() else null)
	else:
		_title_label.text = "【%s】" % _current_card_name if not _current_card_name.is_empty() else request.title
		if _current_card_name.is_empty():
			_card_image.texture = EVENT_CARD_BACK
	if not is_reveal_confirmation:
		_prompt_label.text = request.prompt
	_instruction_label.text = "是否响应" if is_reaction else ("确认" if is_reveal_confirmation else "请选择")
	_step_label.text = "%d 秒" % int(request.timeout_seconds)
	_timeout_hint.text = "超时放弃" if request.optional else "超时默认选择"
	_timeout_bar.value = 100.0
	_clear_options()
	for index in request.options.size():
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 76)
		button.focus_mode = Control.FOCUS_ALL
		button.text = request.option_labels[index] if index < request.option_labels.size() else str(request.options[index])
		button.pressed.connect(_on_option_pressed.bind(request.options[index]))
		if is_reaction and request.options[index] is 卡牌基类:
			button.mouse_entered.connect(_show_response_card_preview.bind(request.options[index]))
			button.focus_entered.connect(_show_response_card_preview.bind(request.options[index]))
		_options_box.add_child(button)
	if request.optional:
		var pass_button := Button.new()
		pass_button.custom_minimum_size = Vector2(0, 76)
		pass_button.focus_mode = Control.FOCUS_ALL
		pass_button.text = "不使用" if is_reaction else "放弃"
		pass_button.pressed.connect(_on_option_pressed.bind(null))
		_options_box.add_child(pass_button)
	if _options_box.get_child_count() > 0:
		(_options_box.get_child(0) as Control).grab_focus()
	show()

func _on_option_pressed(option) -> void:
	if _active_request == null:
		return
	EventManager.submit_choice(_active_request.request_id, option)

func _on_choice_resolved(request_id: int, _timed_out: bool) -> void:
	if _active_request == null or _active_request.request_id != request_id:
		return
	var close_overlay := _active_request.close_overlay_on_resolve
	_active_request = null
	_clear_options()
	if close_overlay:
		_reset_and_hide()
		return
	_instruction_label.text = "结算中"
	_step_label.text = ""
	_countdown_label.text = ""
	_timer_panel.hide()
	_timeout_bar.value = 0.0


func _show_response_card_preview(card) -> void:
	if not card is 卡牌基类:
		_title_label.text = "选择响应牌"
		_card_image.texture = EVENT_CARD_BACK
		return
	var response_card := card as 卡牌基类
	_title_label.text = "【%s】" % response_card.card_name
	_card_image.texture = response_card.image_of_front if response_card.image_of_front != null else EVENT_CARD_BACK

func _on_interaction_finished(_player: PlayerClass) -> void:
	_release_retained_preview_pause()
	_reset_and_hide()


func _reset_and_hide() -> void:
	_active_request = null
	_current_card_name = ""
	_current_event_id = &""
	_guide_button.visible = false
	_showing_retained_preview = false
	_card_image.texture = null
	_timer_panel.show()
	_timeout_bar.show()
	_timeout_bar.value = 0.0
	_timeout_hint.text = ""
	_countdown_label.text = ""
	_instruction_label.text = ""
	_step_label.text = ""
	_clear_options()
	hide()


func show_retained_card_detail(player: PlayerClass, card: 事件牌) -> void:
	if player == null or card == null or _showing_retained_preview:
		return
	_showing_retained_preview = true
	_active_request = null
	_current_card_name = card.card_name
	_current_event_id = card.event_id
	_guide_button.visible = true
	_context_label.text = "%s · 私密" % player.player_name
	_title_label.text = "【%s】" % card.card_name
	_prompt_label.text = "%s\n\n时机：%s" % [card.description, EventManager.get_retained_event_usage_hint(card, player)]
	_card_image.texture = card.image_of_front
	_instruction_label.text = "事件牌"
	_step_label.text = "仅自己可见"
	_countdown_label.text = ""
	_timer_panel.hide()
	_timeout_bar.hide()
	_timeout_hint.text = ""
	_clear_options()
	if EventManager.can_play_retained_event_now(card, player):
		var use_button := Button.new()
		use_button.custom_minimum_size = Vector2(0, 76)
		use_button.text = "使用"
		use_button.pressed.connect(_on_retained_use_pressed.bind(player, card))
		_options_box.add_child(use_button)
	var close_button := Button.new()
	close_button.custom_minimum_size = Vector2(0, 76)
	close_button.text = "关闭"
	close_button.pressed.connect(close_retained_card_detail)
	_options_box.add_child(close_button)
	_begin_retained_preview_modal()
	show()
	close_button.grab_focus()


func close_retained_card_detail() -> void:
	if not _showing_retained_preview:
		return
	_release_retained_preview_pause()
	_reset_and_hide()


func _release_retained_preview_pause() -> void:
	var same_context: bool = (
		_retained_preview_session_generation == TurnManager.get_session_generation()
		and _retained_preview_turn_epoch == TurnManager.get_turn_epoch()
	)
	if _retained_preview_modal_lease >= 0 and same_context:
		TurnManager.release_modal(_retained_preview_modal_lease)
	_retained_preview_modal_lease = -1
	_retained_preview_session_generation = -1
	_retained_preview_turn_epoch = -1


func _begin_retained_preview_modal() -> void:
	_retained_preview_session_generation = TurnManager.get_session_generation()
	_retained_preview_turn_epoch = TurnManager.get_turn_epoch()
	_retained_preview_modal_lease = TurnManager.acquire_modal(
		&"retained_event_detail",
		TurnManager.ModalResumePolicy.RESUME_REMAINING,
		true
	)


func _on_retained_use_pressed(player: PlayerClass, card: 事件牌) -> void:
	close_retained_card_detail()
	EventManager.request_play_retained_event(player, card)


func _open_event_guide() -> void:
	var hud := get_tree().get_first_node_in_group("HUD") as HUD
	if hud == null:
		return
	hud.open_game_guide(GuideOpenContext.new(
		GuideOpenContext.Source.CARD,
		&"event_response",
		DiscoveryManager.KIND_EVENT,
		_current_event_id,
		_guide_button,
		&"draw_discard"
	))

func _clear_options() -> void:
	if _options_box == null:
		return
	for child in _options_box.get_children():
		child.queue_free()
