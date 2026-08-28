extends Control
class_name CardHandAnimator

signal animation_started(kind: int, player: PlayerClass, card: 卡牌基类)
signal animation_finished(kind: int, player: PlayerClass, card: 卡牌基类)
signal queue_finished

const DISSOLVE_SHADER := preload("res://HUDs/card_dissolve.gdshader")
const CARD_SIZE := Vector2(216.0, 282.0)
const GAIN_DURATION := 0.52
const TRANSFER_DURATION := 0.46
const LOSS_DURATION := 0.38

var hud: HUD = null
var _queue: Array[Dictionary] = []
var _playing: bool = false
var _hidden_gain_cards: Array[卡牌基类] = []
var _active_tween: Tween = null
var _generation: int = 0
var _modal_lease: int = -1
var _modal_session_generation: int = -1
var _modal_turn_epoch: int = -1
var _waiting_for_detail: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 120


func setup(target_hud: HUD) -> void:
	hud = target_hud


func enqueue(
	kind: int,
	player: PlayerClass,
	card: 卡牌基类,
	other_player: PlayerClass = null,
	reveal_detail: bool = false,
	block_gameplay: bool = true
) -> void:
	if hud == null or player == null or card == null:
		return
	# 模拟模式只跳过表现层；手牌和成就状态在调用本动画前已经提交。
	# 直接刷新可避免跨局时仍有协程等待 Tween.finished，并让规则结果与正常模式一致。
	if GameManager.is_headless_simulation():
		hud.refresh_hand_after_animation(player)
		if kind == ResourceManager.CardHandVisualKind.转移 and other_player != null:
			hud.refresh_hand_after_animation(other_player)
		return
	var start_position := hud.get_player_card_anchor(player)
	if kind == ResourceManager.CardHandVisualKind.失去:
		start_position = hud.get_card_thumbnail_anchor(card)
	var end_position := hud.get_hand_area_anchor(card)
	if kind == ResourceManager.CardHandVisualKind.转移 and other_player != null:
		end_position = hud.get_player_card_anchor(other_player)
	_queue.append({
		"kind": kind,
		"player": player,
		"card": card,
		"other_player": other_player,
		"reveal_detail": reveal_detail,
		"start": start_position,
		"end": end_position,
		"generation": _generation,
	})
	if kind in [ResourceManager.CardHandVisualKind.获得, ResourceManager.CardHandVisualKind.转移] and not _hidden_gain_cards.has(card):
		_hidden_gain_cards.append(card)
	# 动画可能由事件/食物等已有模态内部触发；它仍必须持有自己的嵌套租约，
	# 否则外层先结束时会在卡牌动画尚未完成前恢复阶段计时。
	if block_gameplay and _modal_lease < 0 and TurnManager.GameOn:
		_modal_session_generation = TurnManager.get_session_generation()
		_modal_turn_epoch = TurnManager.get_turn_epoch()
		_modal_lease = TurnManager.acquire_modal(
			&"card_hand_animation",
			TurnManager.ModalResumePolicy.RESUME_REMAINING
		)
	if not _playing:
		_play_queue.call_deferred()


func _exit_tree() -> void:
	clear_queue()
	hud = null


func clear_queue() -> void:
	var was_busy := is_busy()
	_generation += 1
	_queue.clear()
	_hidden_gain_cards.clear()
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.custom_step(10.0)
	_active_tween = null
	if _waiting_for_detail and hud != null and hud.detail_panel != null:
		hud.detail_panel.close_detail()
	_waiting_for_detail = false
	_release_owned_modal()
	for child: Node in get_children():
		child.free()
	_playing = false
	if was_busy:
		queue_finished.emit()


func is_busy() -> bool:
	return _playing or not _queue.is_empty()


func should_hide_card(card: 卡牌基类) -> bool:
	return _hidden_gain_cards.has(card)


func _play_queue() -> void:
	if _playing or _queue.is_empty():
		return
	_playing = true
	while not _queue.is_empty():
		var request: Dictionary = _queue.pop_front()
		var player := request["player"] as PlayerClass
		var card := request["card"] as 卡牌基类
		if not is_instance_valid(player) or card == null:
			continue
		var kind := int(request["kind"])
		animation_started.emit(kind, player, card)
		match kind:
			ResourceManager.CardHandVisualKind.获得:
				await _play_gain(request)
			ResourceManager.CardHandVisualKind.失去:
				await _play_loss(request)
			ResourceManager.CardHandVisualKind.转移:
				await _play_transfer(request)
		if int(request["generation"]) != _generation:
			return
		animation_finished.emit(kind, player, card)
	_playing = false
	_release_owned_modal()
	queue_finished.emit()


func _release_owned_modal() -> void:
	if _modal_lease < 0:
		return
	var same_context: bool = (
		_modal_session_generation == TurnManager.get_session_generation()
		and _modal_turn_epoch == TurnManager.get_turn_epoch()
	)
	if same_context:
		TurnManager.release_modal(_modal_lease)
	_modal_lease = -1
	_modal_session_generation = -1
	_modal_turn_epoch = -1


func _play_gain(request: Dictionary) -> void:
	var card := request["card"] as 卡牌基类
	var player := request["player"] as PlayerClass
	var visual := _create_card_visual(_back_texture(card), request["start"] as Vector2)
	visual.scale = Vector2(0.78, 0.78)
	visual.modulate.a = 0.0
	if hud != null:
		hud.set_card_thumbnail_hidden(card, true)
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_active_tween = tween
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, "modulate:a", 1.0, 0.08)
	tween.parallel().tween_property(visual, "scale", Vector2(1.05, 1.05), 0.12)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(visual, "position", _top_left(request["end"] as Vector2), GAIN_DURATION)
	tween.parallel().tween_property(visual, "scale", Vector2(0.9, 0.9), GAIN_DURATION)
	tween.tween_property(visual, "modulate:a", 0.0, 0.08)
	await tween.finished
	_active_tween = null
	if int(request["generation"]) != _generation:
		_free_visual(visual)
		return
	_free_visual(visual)
	if hud != null:
		if bool(request["reveal_detail"]) and card is 非遗牌:
			_waiting_for_detail = true
			await hud.show_collected_feiyi_detail_and_wait(player, card as 非遗牌)
			_waiting_for_detail = false
			if int(request["generation"]) != _generation:
				return
	_hidden_gain_cards.erase(card)
	if hud != null:
		hud.refresh_hand_after_animation(player)


func _play_transfer(request: Dictionary) -> void:
	var card := request["card"] as 卡牌基类
	var visual := _create_card_visual(_back_texture(card), request["start"] as Vector2)
	visual.scale = Vector2(0.86, 0.86)
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_active_tween = tween
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, "scale", Vector2(1.05, 1.05), 0.1)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(visual, "position", _top_left(request["end"] as Vector2), TRANSFER_DURATION)
	tween.parallel().tween_property(visual, "scale", Vector2(0.9, 0.9), TRANSFER_DURATION)
	tween.tween_property(visual, "modulate:a", 0.0, 0.08)
	await tween.finished
	_active_tween = null
	if int(request["generation"]) != _generation:
		_free_visual(visual)
		return
	_free_visual(visual)
	_hidden_gain_cards.erase(card)
	if hud != null:
		hud.refresh_hand_after_animation(request["player"] as PlayerClass)
		var target := request["other_player"] as PlayerClass
		if target != null:
			hud.refresh_hand_after_animation(target)


func _play_loss(request: Dictionary) -> void:
	var card := request["card"] as 卡牌基类
	var visual := _create_card_visual(_front_texture(card), request["start"] as Vector2)
	visual.scale = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = DISSOLVE_SHADER
	material.set_shader_parameter("progress", 0.0)
	visual.material = material
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_active_tween = tween
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_method(func(value: float) -> void: material.set_shader_parameter("progress", value), 0.0, 1.08, LOSS_DURATION)
	tween.parallel().tween_property(visual, "position:y", visual.position.y - 34.0, LOSS_DURATION)
	await tween.finished
	_active_tween = null
	if int(request["generation"]) != _generation:
		_free_visual(visual)
		return
	_free_visual(visual)
	if hud != null:
		hud.refresh_hand_after_animation(request["player"] as PlayerClass)


func _create_card_visual(texture: Texture2D, center: Vector2) -> TextureRect:
	var visual := TextureRect.new()
	visual.custom_minimum_size = CARD_SIZE
	visual.size = CARD_SIZE
	visual.position = _top_left(center)
	visual.pivot_offset = CARD_SIZE * 0.5
	visual.texture = texture
	visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	visual.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(visual)
	return visual


func _back_texture(card: 卡牌基类) -> Texture2D:
	return card.image_of_back if card.image_of_back != null else card.image_of_front

func _front_texture(card: 卡牌基类) -> Texture2D:
	return card.image_of_front

func _free_visual(visual: TextureRect) -> void:
	if is_instance_valid(visual):
		visual.queue_free()


func _top_left(center: Vector2) -> Vector2:
	return center - CARD_SIZE * 0.5
