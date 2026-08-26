extends Control
class_name GameResultOverlay

## 正式胜利结算层。
##
## 通过 Variant 接收结果快照，既兼容未来的 GameResult 对象，也兼容 Dictionary。
## 本节点只负责展示和发出导航请求，不直接依赖 TurnManager、GameManager 或 ResourceManager。

signal return_to_main_menu_requested
signal quit_requested
signal presentation_step_changed(step_name: StringName)
signal presentation_finished
signal presentation_cue(cue: StringName)

enum PresentationState {
	HIDDEN,
	INTRO,
	SCORE_REVEAL,
	RANK_REORDER,
	WINNER_REVEAL,
	COMPLETE,
}

const SCORE_KEYS: Array[StringName] = [
	&"base_score",
	&"category_combo_score",
	&"category_completion_score",
	&"regional_combo_score",
	&"achievement_score",
]
const SCORE_LABELS := {
	&"base_score": "基础",
	&"category_combo_score": "类别组合",
	&"category_completion_score": "类别集齐",
	&"regional_combo_score": "地域组合",
	&"achievement_score": "成就",
}
const PROFESSION_NAMES: Array[String] = [
	"美食博主", "魔术博主", "探险博主", "商业博主", "旅行博主", "生活博主",
]
const PORTRAIT_PATHS := {
	"美食博主": "res://arts/素材合集/sprite及立绘/水墨风格立绘/美食博主.png",
	"魔术博主": "res://arts/素材合集/sprite及立绘/水墨风格立绘/魔术博主.png",
	"探险博主": "res://arts/素材合集/sprite及立绘/水墨风格立绘/探险博主.png",
	"商业博主": "res://arts/素材合集/sprite及立绘/水墨风格立绘/商业博主.png",
	"旅行博主": "res://arts/素材合集/sprite及立绘/水墨风格立绘/旅行博主.png",
	"生活博主": "res://arts/素材合集/sprite及立绘/水墨风格立绘/生活博主.png",
}

const COLOR_INK := Color("4b291b")
const COLOR_INK_SOFT := Color("74503b")
const COLOR_CREAM := Color("fff3d6")
const COLOR_GOLD := Color("f4c36f")
const COLOR_GOLD_LIGHT := Color("ffe6a3")
const COLOR_BROWN := Color("6d3926")
const COLOR_MUTED := Color("a39078")
const COLOR_ELIMINATED := Color("ad6651")
const COLOR_NONWINNER := Color(0.9, 0.88, 0.84, 0.96)

@onready var _dimmer: ColorRect = %Dimmer
@onready var _frame: NinePatchRect = %Frame
@onready var _title_label: Label = %TitleLabel
@onready var _reason_label: Label = %ReasonLabel
@onready var _stage_label: Label = %StageLabel
@onready var _summary_page: Control = %SummaryPage
@onready var _player_grid: GridContainer = %PlayerGrid
@onready var _winner_showcase: CenterContainer = %WinnerShowcase
@onready var _winner_list: HBoxContainer = %WinnerList
@onready var _details_page: Control = %DetailsPage
@onready var _detail_list: VBoxContainer = %DetailList
@onready var _action_bar: HBoxContainer = %ActionBar
@onready var _details_button: Button = %DetailsButton
@onready var _return_button: Button = %ReturnButton
@onready var _quit_button: Button = %QuitButton
@onready var _skip_button: Button = %SkipButton
@onready var _sparkles: CPUParticles2D = %Sparkles
@onready var _fixed_animation_player: AnimationPlayer = %FixedAnimationPlayer

var current_state: int = PresentationState.HIDDEN
var _entries: Array[Dictionary] = []
var _player_cards: Array[Dictionary] = []
var _active_tweens: Array[Tween] = []
var _state_elapsed := 0.0
var _state_duration := 0.0
var _score_step := 0
var _saved_tree_paused := false
var _has_saved_pause := false
var _finish_emitted := false
var _showing_details := false
var _rank_old_positions: Dictionary = {}
var _presentation_generation := 0
var _is_solo_defeat := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	set_process_input(true)
	_setup_fixed_animations()
	_details_button.pressed.connect(_toggle_details_page)
	_return_button.pressed.connect(func(): return_to_main_menu_requested.emit())
	_quit_button.pressed.connect(func(): quit_requested.emit())
	_skip_button.pressed.connect(skip_all)
	hide()
	_apply_responsive_layout()


func _process(delta: float) -> void:
	if not visible or current_state in [PresentationState.HIDDEN, PresentationState.COMPLETE]:
		return
	_state_elapsed += delta
	if _state_elapsed >= _state_duration:
		_complete_current_step()


func _input(event: InputEvent) -> void:
	if not visible or current_state in [PresentationState.HIDDEN, PresentationState.COMPLETE]:
		return
	var guide_overlay := get_tree().get_first_node_in_group(&"digital_game_guide") as CanvasItem
	if guide_overlay != null and guide_overlay.visible:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			fast_forward_current_step()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT and not _pointer_is_over_button():
			fast_forward_current_step()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_apply_responsive_layout()


## 主入口。result_snapshot 可为 GameResult、Dictionary，或任何提供 entries/players 属性的对象。
func present(result_snapshot: Variant, autoplay: bool = true) -> void:
	_presentation_generation += 1
	_kill_active_tweens()
	var previous_focus := get_viewport().gui_get_focus_owner()
	if previous_focus != null:
		previous_focus.release_focus()
	_entries = _normalize_result(result_snapshot)
	if _entries.is_empty():
		push_warning("GameResultOverlay 收到的结果中没有玩家。")
		return
	var end_reason: Variant = _read_value(result_snapshot, [&"end_reason", &"reason"], &"")
	_is_solo_defeat = _is_solo_defeat_reason(end_reason)
	_compute_competition_ranks()
	_build_player_cards()
	_build_detail_rows()
	_reason_label.text = _reason_text(
		end_reason,
		int(_read_value(result_snapshot, [&"target_score"], SessionSetup.DEFAULT_TARGET_SCORE))
	)
	_title_label.text = "游戏结束"
	_showing_details = false
	_summary_page.show()
	_winner_showcase.hide()
	_clear_container(_winner_list)
	_details_page.hide()
	_details_button.text = "计分详情"
	_action_bar.hide()
	_skip_button.show()
	_sparkles.emitting = false
	_dimmer.color.a = 0.0
	_frame.modulate.a = 0.0
	_frame.scale = Vector2(0.975, 0.975)
	_frame.pivot_offset = _frame.size * 0.5
	_finish_emitted = false
	if not _has_saved_pause:
		_saved_tree_paused = get_tree().paused
		_has_saved_pause = true
	show()
	get_tree().paused = true
	if autoplay:
		_enter_state(PresentationState.INTRO)
	else:
		_enter_state(PresentationState.COMPLETE)


## 便于主流程按语义调用。
func show_result(result_snapshot: Variant, autoplay: bool = true) -> void:
	present(result_snapshot, autoplay)


## 清理结算层。场景切换前可调用；默认恢复打开结算层前的暂停状态。
func reset_overlay(restore_pause: bool = true) -> void:
	_presentation_generation += 1
	_kill_active_tweens()
	_fixed_animation_player.stop()
	_sparkles.emitting = false
	_clear_container(_player_grid)
	_clear_container(_detail_list)
	_clear_container(_winner_list)
	_player_cards.clear()
	_entries.clear()
	_is_solo_defeat = false
	current_state = PresentationState.HIDDEN
	_showing_details = false
	hide()
	if restore_pause and _has_saved_pause and is_inside_tree():
		get_tree().paused = _saved_tree_paused
	_has_saved_pause = false


func fast_forward_current_step() -> void:
	if current_state in [PresentationState.HIDDEN, PresentationState.COMPLETE]:
		return
	_complete_current_step()


func skip_all() -> void:
	if current_state in [PresentationState.HIDDEN, PresentationState.COMPLETE]:
		return
	_presentation_generation += 1
	_kill_active_tweens()
	_enter_state(PresentationState.COMPLETE)


func get_state_name() -> StringName:
	match current_state:
		PresentationState.INTRO:
			return &"INTRO"
		PresentationState.SCORE_REVEAL:
			return &"SCORE_REVEAL"
		PresentationState.RANK_REORDER:
			return &"RANK_REORDER"
		PresentationState.WINNER_REVEAL:
			return &"WINNER_REVEAL"
		PresentationState.COMPLETE:
			return &"COMPLETE"
	return &"HIDDEN"


func get_normalized_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


func is_showing_details() -> bool:
	return _showing_details


func _enter_state(next_state: int) -> void:
	_kill_active_tweens()
	_fixed_animation_player.stop()
	current_state = next_state
	_state_elapsed = 0.0
	match current_state:
		PresentationState.INTRO:
			_state_duration = 0.85
			_start_intro()
		PresentationState.SCORE_REVEAL:
			_state_duration = 0.58
			_start_score_reveal_step()
		PresentationState.RANK_REORDER:
			_state_duration = 0.9
			_start_rank_reorder()
		PresentationState.WINNER_REVEAL:
			_state_duration = 1.15
			_start_winner_reveal()
		PresentationState.COMPLETE:
			_state_duration = 0.0
			_start_complete()
	presentation_step_changed.emit(get_state_name())
	presentation_cue.emit(get_state_name().to_lower())


func _complete_current_step() -> void:
	match current_state:
		PresentationState.INTRO:
			_finalize_intro()
			_score_step = 0
			_enter_state(PresentationState.SCORE_REVEAL)
		PresentationState.SCORE_REVEAL:
			_finalize_score_step()
			_score_step += 1
			if _score_step < SCORE_KEYS.size():
				_enter_state(PresentationState.SCORE_REVEAL)
			else:
				_enter_state(PresentationState.RANK_REORDER)
		PresentationState.RANK_REORDER:
			_finalize_rank_reorder()
			_enter_state(PresentationState.WINNER_REVEAL)
		PresentationState.WINNER_REVEAL:
			_finalize_winner_reveal()
			_enter_state(PresentationState.COMPLETE)


func _start_intro() -> void:
	_stage_label.text = "结算开始"
	_fixed_animation_player.play(&"intro")
	for index in _player_cards.size():
		var panel := _player_cards[index]["panel"] as PanelContainer
		panel.modulate.a = 0.0
		panel.scale = Vector2(0.98, 0.98)
		panel.pivot_offset = panel.size * 0.5
		var tween := _new_tween().set_parallel(true)
		tween.tween_property(panel, "modulate:a", 1.0, 0.28).set_delay(0.05 * index)
		tween.tween_property(panel, "scale", Vector2.ONE, 0.32).set_delay(0.05 * index).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _finalize_intro() -> void:
	_kill_active_tweens()
	_dimmer.color.a = 0.82
	_frame.modulate.a = 1.0
	_frame.scale = Vector2.ONE
	for card_state in _player_cards:
		var panel := card_state["panel"] as PanelContainer
		panel.modulate.a = 1.0
		panel.scale = Vector2.ONE


func _start_score_reveal_step() -> void:
	var key: StringName = SCORE_KEYS[_score_step]
	_stage_label.text = "%s分" % SCORE_LABELS[key]
	for card_state in _player_cards:
		var entry: Dictionary = card_state["entry"]
		var value_label := card_state["score_labels"][key] as Label
		value_label.text = _signed_score(int(entry[key]), key == &"base_score")
		value_label.modulate.a = 0.0
		value_label.scale = Vector2(1.12, 1.12)
		value_label.pivot_offset = value_label.size * 0.5
		var reveal_tween := _new_tween().set_parallel(true)
		reveal_tween.tween_property(value_label, "modulate:a", 1.0, 0.22)
		reveal_tween.tween_property(value_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var from_total := int(card_state["display_total"])
		var to_total := from_total + int(entry[key])
		card_state["display_total"] = to_total
		var total_tween := _new_tween()
		total_tween.tween_method(_set_card_total.bind(card_state), float(from_total), float(to_total), 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if key == &"achievement_score":
			var achievement_row := card_state["achievement_row"] as HBoxContainer
			achievement_row.show()
			achievement_row.modulate.a = 0.0
			var achievement_tween := _new_tween()
			achievement_tween.tween_property(achievement_row, "modulate:a", 1.0, 0.3)
			for thumbnail_node: Node in achievement_row.get_children():
				if thumbnail_node is Control:
					var thumbnail := thumbnail_node as Control
					thumbnail.scale = Vector2(0.86, 0.86)
					thumbnail.pivot_offset = thumbnail.size * 0.5
					var pop_tween := _new_tween()
					pop_tween.tween_property(thumbnail, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _finalize_score_step() -> void:
	_kill_active_tweens()
	var key: StringName = SCORE_KEYS[_score_step]
	for card_state in _player_cards:
		var entry: Dictionary = card_state["entry"]
		var label := card_state["score_labels"][key] as Label
		label.text = _signed_score(int(entry[key]), key == &"base_score")
		label.modulate.a = 1.0
		label.scale = Vector2.ONE
		var revealed_total := 0
		for index in range(_score_step + 1):
			revealed_total += int(entry[SCORE_KEYS[index]])
		card_state["display_total"] = revealed_total
		_set_card_total(float(revealed_total), card_state)
		if key == &"achievement_score":
			var achievement_row := card_state["achievement_row"] as HBoxContainer
			achievement_row.show()
			achievement_row.modulate.a = 1.0
			for thumbnail_node: Node in achievement_row.get_children():
				if thumbnail_node is Control:
					(thumbnail_node as Control).scale = Vector2.ONE


func _start_rank_reorder() -> void:
	_stage_label.text = "最终排名"
	_rank_old_positions.clear()
	for card_state in _player_cards:
		var panel := card_state["panel"] as PanelContainer
		_rank_old_positions[panel] = panel.global_position
	var sorted_cards := _player_cards.duplicate()
	sorted_cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_entry: Dictionary = a["entry"]
		var b_entry: Dictionary = b["entry"]
		if int(a_entry["rank"]) == int(b_entry["rank"]):
			return int(a_entry["player_index"]) < int(b_entry["player_index"])
		return int(a_entry["rank"]) < int(b_entry["rank"])
	)
	for index in sorted_cards.size():
		_player_grid.move_child(sorted_cards[index]["panel"] as Control, index)
	_player_cards = sorted_cards
	_player_grid.queue_sort()
	var generation := _presentation_generation
	_animate_rank_after_layout(generation)


func _animate_rank_after_layout(generation: int) -> void:
	await get_tree().process_frame
	if generation != _presentation_generation or current_state != PresentationState.RANK_REORDER:
		return
	for card_state in _player_cards:
		var panel := card_state["panel"] as PanelContainer
		var final_position := panel.position
		var old_global: Vector2 = _rank_old_positions.get(panel, panel.global_position)
		panel.position += old_global - panel.global_position
		var tween := _new_tween()
		tween.tween_property(panel, "position", final_position, 0.68).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		var entry: Dictionary = card_state["entry"]
		var rank_label := card_state["rank_label"] as Label
		rank_label.text = "第%d名" % int(entry["rank"])
		rank_label.modulate.a = 0.0
		var rank_tween := _new_tween()
		rank_tween.tween_property(rank_label, "modulate:a", 1.0, 0.28).set_delay(0.28)


func _finalize_rank_reorder() -> void:
	_kill_active_tweens()
	for card_state in _player_cards:
		var entry: Dictionary = card_state["entry"]
		var rank_label := card_state["rank_label"] as Label
		rank_label.text = "第%d名" % int(entry["rank"])
		rank_label.modulate.a = 1.0
		(card_state["panel"] as PanelContainer).scale = Vector2.ONE


func _start_winner_reveal() -> void:
	if _is_solo_defeat:
		_stage_label.text = "挑战失败"
		_fixed_animation_player.play(&"winner_reveal")
		_winner_showcase.hide()
		_summary_page.show()
		_sparkles.emitting = false
		for card_state in _player_cards:
			var panel := card_state["panel"] as PanelContainer
			panel.modulate = Color.WHITE
			panel.add_theme_stylebox_override("panel", _normal_card_style())
		return
	var winner_names := _winner_names()
	_stage_label.text = "冠军 · %s" % "、".join(winner_names)
	_fixed_animation_player.play(&"winner_reveal")
	_build_winner_showcase()
	_summary_page.hide()
	_winner_showcase.show()
	for index: int in _winner_list.get_child_count():
		var winner_panel := _winner_list.get_child(index) as Control
		winner_panel.modulate.a = 0.0
		winner_panel.scale = Vector2(0.9, 0.9)
		winner_panel.pivot_offset = winner_panel.size * 0.5
		var winner_tween := _new_tween().set_parallel(true)
		winner_tween.tween_property(winner_panel, "modulate:a", 1.0, 0.28).set_delay(0.06 * index)
		winner_tween.tween_property(winner_panel, "scale", Vector2.ONE, 0.46).set_delay(0.06 * index).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sparkles.restart()
	_sparkles.emitting = true
	for card_state in _player_cards:
		var entry: Dictionary = card_state["entry"]
		var panel := card_state["panel"] as PanelContainer
		if bool(entry["is_winner"]):
			panel.add_theme_stylebox_override("panel", _winner_card_style())
			panel.pivot_offset = panel.size * 0.5
			panel.scale = Vector2(0.94, 0.94)
			var tween := _new_tween()
			tween.tween_property(panel, "scale", Vector2.ONE, 0.46).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			var tween := _new_tween()
			tween.tween_property(panel, "modulate", COLOR_NONWINNER, 0.32)


func _finalize_winner_reveal() -> void:
	_kill_active_tweens()
	if _is_solo_defeat:
		_winner_showcase.hide()
		_summary_page.show()
		_sparkles.emitting = false
		for card_state in _player_cards:
			var panel := card_state["panel"] as PanelContainer
			panel.modulate = Color.WHITE
			panel.scale = Vector2.ONE
			panel.add_theme_stylebox_override("panel", _normal_card_style())
		return
	for child: Node in _winner_list.get_children():
		if child is Control:
			(child as Control).modulate.a = 1.0
			(child as Control).scale = Vector2.ONE
	for card_state in _player_cards:
		var entry: Dictionary = card_state["entry"]
		var panel := card_state["panel"] as PanelContainer
		panel.scale = Vector2.ONE
		if bool(entry["is_winner"]):
			panel.modulate = Color.WHITE
			panel.add_theme_stylebox_override("panel", _winner_card_style())
		else:
			panel.modulate = COLOR_NONWINNER


func _start_complete() -> void:
	_winner_showcase.hide()
	_summary_page.show()
	_apply_complete_visuals()
	_skip_button.hide()
	_action_bar.show()
	_details_button.grab_focus()
	if not _finish_emitted:
		_finish_emitted = true
		presentation_finished.emit()


func _apply_complete_visuals() -> void:
	_kill_active_tweens()
	_fixed_animation_player.stop()
	_dimmer.color.a = 0.82
	_frame.modulate = Color.WHITE
	_frame.scale = Vector2.ONE
	_stage_label.modulate = Color.WHITE
	_score_step = SCORE_KEYS.size()
	_sort_cards_immediately()
	var winner_names := _winner_names()
	_stage_label.text = "挑战失败" if _is_solo_defeat else "冠军 · %s" % "、".join(winner_names)
	for card_state in _player_cards:
		var entry: Dictionary = card_state["entry"]
		var panel := card_state["panel"] as PanelContainer
		panel.scale = Vector2.ONE
		panel.modulate = Color.WHITE if _is_solo_defeat or bool(entry["is_winner"]) else COLOR_NONWINNER
		panel.add_theme_stylebox_override("panel", _winner_card_style() if bool(entry["is_winner"]) else _normal_card_style())
		(card_state["rank_label"] as Label).text = "第%d名" % int(entry["rank"])
		for key in SCORE_KEYS:
			var label := card_state["score_labels"][key] as Label
			label.text = _signed_score(int(entry[key]), key == &"base_score")
			label.modulate.a = 1.0
			label.scale = Vector2.ONE
		card_state["display_total"] = int(entry["total_score"])
		_set_card_total(float(entry["total_score"]), card_state)
		var achievement_row := card_state["achievement_row"] as HBoxContainer
		achievement_row.visible = not (entry["achievements"] as Array).is_empty()
		achievement_row.modulate.a = 1.0
	if _is_solo_defeat:
		_sparkles.emitting = false
	else:
		_sparkles.restart()
		_sparkles.emitting = true


func _sort_cards_immediately() -> void:
	_player_cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_entry: Dictionary = a["entry"]
		var b_entry: Dictionary = b["entry"]
		if int(a_entry["rank"]) == int(b_entry["rank"]):
			return int(a_entry["player_index"]) < int(b_entry["player_index"])
		return int(a_entry["rank"]) < int(b_entry["rank"])
	)
	for index in _player_cards.size():
		_player_grid.move_child(_player_cards[index]["panel"] as Control, index)


func _toggle_details_page() -> void:
	if current_state != PresentationState.COMPLETE:
		return
	_kill_active_tweens()
	_showing_details = not _showing_details
	_summary_page.visible = not _showing_details
	_details_page.visible = _showing_details
	_details_button.text = "返回排名" if _showing_details else "计分详情"
	var page := _details_page if _showing_details else _summary_page
	page.modulate.a = 0.0
	var tween := _new_tween()
	tween.tween_property(page, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_details_button.grab_focus()


func _build_player_cards() -> void:
	_clear_container(_player_grid)
	_player_cards.clear()
	_configure_grid_for_player_count(_entries.size())
	var compact := _entries.size() >= 5
	for entry in _entries:
		var panel := PanelContainer.new()
		panel.name = "PlayerCard%d" % int(entry["player_index"])
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", _normal_card_style())
		panel.custom_minimum_size.y = 350.0 if compact else 420.0

		var margin := MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_theme_constant_override("margin_left", 24 if compact else 34)
		margin.add_theme_constant_override("margin_top", 18 if compact else 26)
		margin.add_theme_constant_override("margin_right", 24 if compact else 34)
		margin.add_theme_constant_override("margin_bottom", 18 if compact else 26)
		panel.add_child(margin)

		var root_box := VBoxContainer.new()
		root_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root_box.add_theme_constant_override("separation", 12 if compact else 17)
		margin.add_child(root_box)

		var header := HBoxContainer.new()
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_theme_constant_override("separation", 16)
		root_box.add_child(header)
		var rank_label := _make_label("待揭晓", 27 if compact else 32, COLOR_BROWN)
		rank_label.custom_minimum_size.x = 118 if compact else 140
		header.add_child(rank_label)
		var name_label := _make_label(str(entry["player_name"]), 34 if compact else 40, COLOR_INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		header.add_child(name_label)
		var total_label := _make_label("总分 —", 34 if compact else 42, COLOR_BROWN)
		total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		header.add_child(total_label)

		var separator := HSeparator.new()
		separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root_box.add_child(separator)

		var body := HBoxContainer.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 20 if compact else 30)
		root_box.add_child(body)

		var portrait_shell := PanelContainer.new()
		portrait_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait_shell.custom_minimum_size = Vector2(116, 166) if compact else Vector2(150, 220)
		portrait_shell.add_theme_stylebox_override("panel", _portrait_style())
		body.add_child(portrait_shell)
		var portrait := TextureRect.new()
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.texture = entry["portrait"] as Texture2D
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait_shell.add_child(portrait)

		var info_box := VBoxContainer.new()
		info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_box.add_theme_constant_override("separation", 7 if compact else 10)
		body.add_child(info_box)
		var meta_row := HBoxContainer.new()
		meta_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info_box.add_child(meta_row)
		var profession_label := _make_label(str(entry["profession"]), 22 if compact else 26, COLOR_INK_SOFT)
		profession_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meta_row.add_child(profession_label)
		var status_text := "在场" if bool(entry["alive"]) else "已淘汰"
		var status_color := COLOR_MUTED if bool(entry["alive"]) else COLOR_ELIMINATED
		var status_label := _make_label(status_text, 21 if compact else 25, status_color)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		meta_row.add_child(status_label)

		var score_grid := GridContainer.new()
		score_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		score_grid.columns = 2
		score_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
		score_grid.add_theme_constant_override("h_separation", 18)
		score_grid.add_theme_constant_override("v_separation", 4 if compact else 7)
		info_box.add_child(score_grid)
		var score_labels: Dictionary = {}
		for key in SCORE_KEYS:
			var key_label := _make_label(str(SCORE_LABELS[key]), 20 if compact else 24, COLOR_INK_SOFT)
			key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			score_grid.add_child(key_label)
			var value_label := _make_label("—", 22 if compact else 27, COLOR_BROWN)
			value_label.custom_minimum_size.x = 72
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			score_grid.add_child(value_label)
			score_labels[key] = value_label

		var achievement_row := HBoxContainer.new()
		achievement_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		achievement_row.add_theme_constant_override("separation", 7)
		achievement_row.visible = false
		info_box.add_child(achievement_row)
		for achievement in entry["achievements"] as Array:
			var texture := achievement.get("texture") as Texture2D
			if texture == null:
				continue
			var thumbnail := TextureRect.new()
			thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
			thumbnail.custom_minimum_size = Vector2(38, 53) if compact else Vector2(46, 64)
			thumbnail.texture = texture
			thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			achievement_row.add_child(thumbnail)

		_player_grid.add_child(panel)
		_player_cards.append({
			"entry": entry,
			"panel": panel,
			"rank_label": rank_label,
			"total_label": total_label,
			"score_labels": score_labels,
			"achievement_row": achievement_row,
			"display_total": 0,
		})
	_apply_responsive_layout()


func _build_winner_showcase() -> void:
	_clear_container(_winner_list)
	var winner_count := 0
	for entry: Dictionary in _entries:
		if bool(entry["is_winner"]):
			winner_count += 1
	var compact := winner_count >= 4
	for entry: Dictionary in _entries:
		if not bool(entry["is_winner"]):
			continue
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.custom_minimum_size = Vector2(270, 390) if compact else Vector2(350, 480)
		panel.add_theme_stylebox_override("panel", _winner_card_style())
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 24)
		margin.add_theme_constant_override("margin_top", 22)
		margin.add_theme_constant_override("margin_right", 24)
		margin.add_theme_constant_override("margin_bottom", 22)
		panel.add_child(margin)
		var content := VBoxContainer.new()
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 12)
		margin.add_child(content)
		var crown_label := _make_label("冠军", 30 if compact else 38, COLOR_BROWN, HORIZONTAL_ALIGNMENT_CENTER)
		content.add_child(crown_label)
		var portrait := TextureRect.new()
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.custom_minimum_size = Vector2(150, 210) if compact else Vector2(190, 270)
		portrait.texture = entry["portrait"] as Texture2D
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		content.add_child(portrait)
		content.add_child(_make_label(str(entry["player_name"]), 34 if compact else 44, COLOR_INK, HORIZONTAL_ALIGNMENT_CENTER))
		content.add_child(_make_label("总分 %d" % int(entry["total_score"]), 34 if compact else 46, COLOR_BROWN, HORIZONTAL_ALIGNMENT_CENTER))
		_winner_list.add_child(panel)


func _build_detail_rows() -> void:
	_clear_container(_detail_list)
	var ordered := _entries.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["rank"]) == int(b["rank"]):
			return int(a["player_index"]) < int(b["player_index"])
		return int(a["rank"]) < int(b["rank"])
	)
	for entry in ordered:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.custom_minimum_size.y = 145
		panel.add_theme_stylebox_override("panel", _winner_card_style() if bool(entry["is_winner"]) else _detail_row_style())
		var margin := MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
			margin.add_theme_constant_override(side, 18)
		panel.add_child(margin)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 24)
		margin.add_child(row)
		var rank := _make_label("第%d名" % int(entry["rank"]), 30, COLOR_BROWN)
		rank.custom_minimum_size.x = 120
		row.add_child(rank)
		var identity := VBoxContainer.new()
		identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
		identity.custom_minimum_size.x = 285
		row.add_child(identity)
		identity.add_child(_make_label(str(entry["player_name"]), 34, COLOR_INK))
		identity.add_child(_make_label("%s · %s" % [entry["profession"], "在场" if bool(entry["alive"]) else "已淘汰"], 22, COLOR_INK_SOFT))

		var scores := GridContainer.new()
		scores.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scores.columns = 5
		scores.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scores.add_theme_constant_override("h_separation", 18)
		row.add_child(scores)
		for key in SCORE_KEYS:
			var score_box := VBoxContainer.new()
			score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			score_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			score_box.add_child(_make_label(str(SCORE_LABELS[key]), 20, COLOR_INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
			score_box.add_child(_make_label(_signed_score(int(entry[key]), key == &"base_score"), 27, COLOR_BROWN, HORIZONTAL_ALIGNMENT_CENTER))
			scores.add_child(score_box)
		var total := _make_label("%d分" % int(entry["total_score"]), 40, COLOR_BROWN, HORIZONTAL_ALIGNMENT_RIGHT)
		total.custom_minimum_size.x = 145
		row.add_child(total)

		var achievement_names: Array[String] = []
		for achievement in entry["achievements"] as Array:
			achievement_names.append(str(achievement.get("name", "成就")))
		var achievement_label := _make_label("成就  %s" % ("、".join(achievement_names) if not achievement_names.is_empty() else "无"), 21, COLOR_INK_SOFT)
		achievement_label.custom_minimum_size.x = 330
		achievement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(achievement_label)
		_detail_list.add_child(panel)


func _normalize_result(snapshot: Variant) -> Array[Dictionary]:
	var raw_entries: Variant = _read_value(snapshot, [&"entries", &"players", &"results"], [])
	if not raw_entries is Array:
		return []
	var normalized: Array[Dictionary] = []
	var ordinal := 0
	for raw_entry in raw_entries as Array:
		var player_source: Variant = _read_value(raw_entry, [&"player", &"player_ref"], null)
		var index_value: Variant = _read_with_fallback(raw_entry, player_source, [&"player_index", &"index"], ordinal)
		var player_name := str(_read_with_fallback(raw_entry, player_source, [&"player_name", &"name", &"display_name"], "P%d" % (ordinal + 1)))
		var profession_value: Variant = _read_with_fallback(raw_entry, player_source, [&"profession", &"profession_name", &"player_type_name", &"player_character", &"player_types"], "")
		var profession := _profession_text(profession_value)
		var alive_value: Variant = _read_with_fallback(raw_entry, player_source, [&"alive", &"is_alive"], null)
		if alive_value == null:
			alive_value = not bool(_read_with_fallback(raw_entry, player_source, [&"eliminated", &"is_eliminated"], false))
		var breakdown: Variant = _read_value(raw_entry, [&"breakdown", &"score_breakdown", &"scores"], raw_entry)
		var entry := {
			"player_index": int(index_value),
			"player_name": player_name,
			"profession": profession,
			"portrait": _extract_portrait(raw_entry, player_source, profession),
			"alive": bool(alive_value),
			"base_score": int(_read_value(breakdown, [&"base_score"], 0)),
			"category_combo_score": int(_read_value(breakdown, [&"category_combo_score"], 0)),
			"category_completion_score": int(_read_value(breakdown, [&"category_completion_score"], 0)),
			"regional_combo_score": int(_read_value(breakdown, [&"regional_combo_score", &"region_combo_score"], 0)),
			"achievement_score": int(_read_value(breakdown, [&"achievement_score"], 0)),
			"achievements": _normalize_achievements(_read_with_fallback(raw_entry, player_source, [&"achievements", &"achievement_cards", &"成就牌手牌"], [])),
		}
		var direct_total: Variant = _read_value(raw_entry, [&"total_score", &"score"], null)
		if direct_total == null:
			direct_total = _read_value(breakdown, [&"total_score", &"score"], null)
		if direct_total == null:
			direct_total = _sum_entry_scores(entry)
		entry["total_score"] = int(direct_total)
		entry["rank"] = 0
		entry["is_winner"] = false
		normalized.append(entry)
		ordinal += 1
	return normalized


func _compute_competition_ranks() -> void:
	var indices: Array[int] = []
	for index in _entries.size():
		indices.append(index)
	indices.sort_custom(func(a: int, b: int) -> bool:
		var a_entry := _entries[a]
		var b_entry := _entries[b]
		if int(a_entry["total_score"]) == int(b_entry["total_score"]):
			return int(a_entry["player_index"]) < int(b_entry["player_index"])
		return int(a_entry["total_score"]) > int(b_entry["total_score"])
	)
	var previous_score := 0
	var current_rank := 0
	for ordered_index in indices.size():
		var entry_index := indices[ordered_index]
		var entry := _entries[entry_index]
		var score := int(entry["total_score"])
		if ordered_index == 0 or score != previous_score:
			current_rank = ordered_index + 1
		entry["rank"] = current_rank
		entry["is_winner"] = not _is_solo_defeat and current_rank == 1
		_entries[entry_index] = entry
		previous_score = score


func _normalize_achievements(raw_achievements: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_achievements is Array:
		return result
	for raw in raw_achievements as Array:
		result.append({
			"name": str(_read_value(raw, [&"card_name", &"achievement_name", &"name"], "成就")),
			"score": int(_read_value(raw, [&"achievement_score", &"score_value", &"score", &"base_score"], 0)),
			"texture": _texture_from_value(_read_value(raw, [&"image_of_front", &"texture", &"image"], null)),
		})
	return result


func _extract_portrait(entry: Variant, player_source: Variant, profession: String) -> Texture2D:
	var raw: Variant = _read_with_fallback(entry, player_source, [&"portrait", &"portrait_texture", &"character_image", &"avatar", &"立绘精二", &"立绘精一"], null)
	var texture := _texture_from_value(raw)
	if texture != null:
		return texture
	var fallback_path := str(PORTRAIT_PATHS.get(profession, ""))
	return load(fallback_path) as Texture2D if not fallback_path.is_empty() else null


func _texture_from_value(value: Variant) -> Texture2D:
	if value is Texture2D:
		return value as Texture2D
	if value is String or value is StringName:
		var path := str(value)
		if not path.is_empty() and ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


func _read_with_fallback(primary: Variant, fallback: Variant, names: Array[StringName], default_value: Variant) -> Variant:
	var probe := _try_read_value(primary, names)
	if bool(probe["found"]):
		return probe["value"]
	return _read_value(fallback, names, default_value)


func _read_value(source: Variant, names: Array[StringName], default_value: Variant) -> Variant:
	var probe := _try_read_value(source, names)
	return probe["value"] if bool(probe["found"]) else default_value


func _try_read_value(source: Variant, names: Array[StringName]) -> Dictionary:
	if source == null:
		return {"found": false, "value": null}
	if source is Dictionary:
		var dictionary := source as Dictionary
		for name in names:
			if dictionary.has(name):
				return {"found": true, "value": dictionary[name]}
			var string_name := str(name)
			if dictionary.has(string_name):
				return {"found": true, "value": dictionary[string_name]}
		return {"found": false, "value": null}
	if typeof(source) == TYPE_OBJECT and is_instance_valid(source):
		var property_names: Dictionary = {}
		for property in (source as Object).get_property_list():
			property_names[StringName(property.get("name", ""))] = true
		for name in names:
			if property_names.has(name):
				return {"found": true, "value": (source as Object).get(name)}
	return {"found": false, "value": null}


func _profession_text(value: Variant) -> String:
	if value is int and int(value) >= 0 and int(value) < PROFESSION_NAMES.size():
		return PROFESSION_NAMES[int(value)]
	var text := str(value)
	return text if not text.is_empty() else "玩家"


func _reason_text(reason: Variant, target_score: int = SessionSetup.DEFAULT_TARGET_SCORE) -> String:
	if reason is int:
		match int(reason):
			0:
				return "达到%d分" % target_score
			1:
				return "累计淘汰2人"
			2:
				return "胜利条件达成"
			3:
				return "精力耗尽"
	var text := str(reason).to_lower()
	if "both" in text or "同时" in text or "全部" in text:
		return "胜利条件达成"
	if "elimination" in text or "淘汰" in text:
		return "累计淘汰2人"
	if "defeat" in text or "失败" in text or "耗尽" in text:
		return "精力耗尽"
	if "score" in text or "20" in text or "分数" in text:
		return "达到%d分" % target_score
	return "胜利条件达成"


func _is_solo_defeat_reason(reason: Variant) -> bool:
	if reason is int:
		return int(reason) == GameResult.EndReason.SOLO_DEFEAT
	var text := str(reason).to_lower()
	return "solo_defeat" in text or "defeat" in text or "失败" in text or "耗尽" in text


func _sum_entry_scores(entry: Dictionary) -> int:
	var total := 0
	for key in SCORE_KEYS:
		total += int(entry.get(key, 0))
	return total


func _winner_names() -> Array[String]:
	var names: Array[String] = []
	for entry in _entries:
		if bool(entry["is_winner"]):
			names.append(str(entry["player_name"]))
	return names


func _set_card_total(value: float, card_state: Dictionary) -> void:
	var total_label := card_state["total_label"] as Label
	if is_instance_valid(total_label):
		total_label.text = "总分 %d" % int(round(value))


func _signed_score(value: int, plain: bool = false) -> String:
	if plain:
		return str(value)
	return "+%d" % value if value >= 0 else str(value)


func _configure_grid_for_player_count(player_count: int) -> void:
	_player_grid.columns = 1 if player_count <= 1 else (2 if player_count in [2, 4] else 3)


func _apply_responsive_layout() -> void:
	if not is_node_ready():
		return
	_frame.pivot_offset = _frame.size * 0.5
	_sparkles.position = size * 0.5
	if _player_cards.is_empty():
		return
	var columns: int = maxi(_player_grid.columns, 1)
	var available_width: float = maxf(_frame.size.x - 300.0, 1000.0)
	var separation: float = 28.0
	var card_width: float = floorf((available_width - separation * float(columns - 1)) / float(columns))
	card_width = maxf(card_width, 420.0)
	for card_state in _player_cards:
		(card_state["panel"] as PanelContainer).custom_minimum_size.x = card_width


func _pointer_is_over_button() -> bool:
	var control := get_viewport().gui_get_hovered_control()
	while control != null:
		if control is BaseButton:
			return true
		control = control.get_parent() as Control
	return false


func _setup_fixed_animations() -> void:
	if _fixed_animation_player.has_animation_library(&""):
		return
	var library := AnimationLibrary.new()
	var intro := Animation.new()
	intro.length = 0.45
	_add_value_track(intro, NodePath("Dimmer:color"), Color(0.071, 0.039, 0.022, 0.0), Color(0.071, 0.039, 0.022, 0.82))
	_add_value_track(intro, NodePath("Frame:modulate"), Color(1, 1, 1, 0), Color.WHITE)
	_add_value_track(intro, NodePath("Frame:scale"), Vector2(0.975, 0.975), Vector2.ONE)
	library.add_animation(&"intro", intro)
	var winner_reveal := Animation.new()
	winner_reveal.length = 0.42
	_add_value_track(winner_reveal, NodePath("Frame/StagePanel/StageLabel:modulate"), Color(1, 1, 1, 0), Color.WHITE)
	library.add_animation(&"winner_reveal", winner_reveal)
	_fixed_animation_player.add_animation_library(&"", library)


func _add_value_track(animation: Animation, property_path: NodePath, from_value: Variant, to_value: Variant) -> void:
	var track_index := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track_index, property_path)
	animation.track_insert_key(track_index, 0.0, from_value)
	animation.track_insert_key(track_index, animation.length, to_value)


func _new_tween() -> Tween:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_ignore_time_scale(true)
	_active_tweens.append(tween)
	return tween


func _kill_active_tweens() -> void:
	for tween in _active_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_active_tweens.clear()


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.free()


func _make_label(text_value: String, font_size: int, color: Color, alignment: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text_value
	label.horizontal_alignment = alignment as HorizontalAlignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _normal_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.986, 0.925, 0.79, 0.97)
	style.border_color = Color(0.51, 0.278, 0.165, 0.94)
	style.set_border_width_all(4)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0.18, 0.08, 0.035, 0.28)
	style.shadow_size = 9
	return style


func _winner_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.944, 0.745, 0.99)
	style.border_color = Color(0.965, 0.655, 0.235, 1.0)
	style.set_border_width_all(7)
	style.set_corner_radius_all(20)
	style.shadow_color = Color(0.925, 0.548, 0.145, 0.38)
	style.shadow_size = 16
	return style


func _detail_row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.986, 0.93, 0.81, 0.95)
	style.border_color = Color(0.647, 0.408, 0.255, 0.78)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	return style


func _portrait_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.82, 0.665, 0.43, 0.2)
	style.border_color = Color(0.73, 0.43, 0.23, 0.8)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	return style
