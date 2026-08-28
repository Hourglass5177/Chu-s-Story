extends Panel
class_name 非遗详情弹窗

signal detail_closed

const TASK_HOST_SCENE := preload("res://InheritanceTasks/UI/heritage_task_host.tscn")
const VOCAL_SCORER_PATH := "res://InheritanceTasks/Common/onnx_crepe_vocal_scorer.gd"

@onready var card_image = $TextureRect as TextureRect
@onready var title_label = $标题 as Label
@onready var lbl_name = $VBoxContainer/LblName as Label
@onready var lbl_score = $VBoxContainer/LblScore as Label
@onready var lbl_desc = $VBoxContainer/LblDesc as Label
@onready var lbl_cate = $VBoxContainer/LblCate as Label
@onready var lbl_effect = $VBoxContainer/LblEffect as Label
@onready var guide_button := $BtnGuide as Button
@onready var task_panel := $VBoxContainer/TaskPanel as Control
@onready var task_status := $VBoxContainer/TaskPanel/Content/Status as Label
@onready var task_cost := $VBoxContainer/TaskPanel/Content/Cost as Label
@onready var task_button := $VBoxContainer/TaskPanel/Content/TaskButton as Button

var current_card: 非遗牌 = null
var current_player: PlayerClass = null
var _hud: HUD = null
var _modal_lease: int = -1
var _modal_session_generation: int = -1
var _modal_turn_epoch: int = -1
var _active_attempt: HeritageTaskAttempt = null
var _task_host: HeritageTaskHost = null
var _vocal_scorer: VocalScorer = null

func _ready() -> void:
	#btn_use.pressed.connect(_on_use_pressed)
	_hud = get_tree().get_first_node_in_group("HUD") as HUD
	guide_button.pressed.connect(_open_guide)
	task_button.pressed.connect(_on_task_pressed)
	$BtnClose.pressed.connect(_on_close_pressed)
	hide()
	if $BtnClose.texture_normal:
		var bitmap = BitMap.new()
		# 读取原图的透明通道数据
		bitmap.create_from_image_alpha($BtnClose.texture_normal.get_image())
		# 将其设为按钮的点击遮罩
		$BtnClose.texture_click_mask = bitmap
		var mask = $BtnClose/mask
		$BtnClose.mouse_entered.connect(func(): mask.show())
		$BtnClose.mouse_exited.connect(func(): mask.hide())
		$BtnClose.button_down.connect(func(): mask.modulate = Color(0, 0, 0, 0.7)) # 按下更黑
		$BtnClose.button_up.connect(func(): mask.modulate = Color(0, 0, 0, 0.4))   # 松开恢复

# 打开面板并填充数据
func show_detail(card_data: 非遗牌, player: PlayerClass) -> void:
	if card_data == null or _active_attempt != null or _task_host != null:
		return
	current_card = card_data
	current_player = player
	_render_current_card()
	if not visible:
		_begin_modal()
	show()


func _render_current_card() -> void:
	if current_card == null:
		return
	var content := FeiyiDetailContent.build(current_card, true)
	title_label.text = String(content.get("heading", ""))
	card_image.texture = content.get("texture") as Texture2D
	lbl_name.text = String(content.get("name", ""))
	lbl_cate.text = String(content.get("category", ""))
	lbl_score.text = String(content.get("score", ""))
	lbl_desc.text = String(content.get("description", ""))
	lbl_effect.text = String(content.get("effect", ""))
	_refresh_task_panel()


func _refresh_task_panel() -> void:
	var is_national := current_card != null \
			and current_card.category == 非遗牌.CardCategory.国家级非遗
	task_panel.visible = is_national
	if not is_national:
		return
	if HeritageTaskManager.is_inherited(current_card):
		task_status.text = "已传承"
		task_cost.text = ""
		task_button.text = "已传承"
		task_button.disabled = true
		return
	var check := HeritageTaskManager.get_attempt_check(current_player, current_card)
	task_button.text = "传承任务"
	task_button.disabled = check == null or not check.allowed or _active_attempt != null
	task_cost.text = "消耗1精力" if check != null and check.allowed else ""
	task_status.text = "未传承" if check != null and check.allowed else (check.message if check != null else "当前不可挑战")


func _on_task_pressed() -> void:
	if _active_attempt != null or current_card == null or current_player == null:
		return
	var attempt := HeritageTaskManager.begin_attempt(current_player, current_card)
	if attempt == null:
		_refresh_task_panel()
		return
	_active_attempt = attempt
	_refresh_task_panel()
	var definition := HeritageTaskManager.get_definition(current_card)
	if definition == null:
		HeritageTaskManager.finish_attempt(attempt, HeritageTaskResult.technical_error(
			attempt.task_id, &"missing_definition", "任务资源未就绪"
		))
		_active_attempt = null
		_render_current_card()
		return
	var context := HeritageTaskRunContext.new(
		definition.task_id,
		current_player,
		current_card,
		attempt.session_generation,
		attempt.turn_epoch,
		_derive_task_seed(definition.task_id, attempt.attempt_id),
		false
	)
	if definition.microphone_required:
		var scorer_script := load(VOCAL_SCORER_PATH) as Script
		if scorer_script != null:
			_vocal_scorer = scorer_script.new() as VocalScorer
			context.services[&"vocal_scorer"] = _vocal_scorer
	_task_host = TASK_HOST_SCENE.instantiate() as HeritageTaskHost
	_task_host.z_index = 100
	get_parent().add_child(_task_host)
	_task_host.task_entered.connect(_on_task_entered, CONNECT_ONE_SHOT)
	_task_host.task_finished.connect(_on_task_finished, CONNECT_ONE_SHOT)
	_task_host.return_requested.connect(_on_task_return_requested, CONNECT_ONE_SHOT)
	_task_host.configure(definition, context)
	_task_host.begin()


func _derive_task_seed(task_id: StringName, attempt_id: int) -> int:
	var value: int = GameManager.get_session_seed() ^ 0x5F3759DF
	for byte: int in String(task_id).to_utf8_buffer():
		value = int((value ^ byte) * 16777619) & 0x7fffffff
	return maxi(1, value ^ (attempt_id * 104729))


func _on_task_entered(task_id: StringName) -> void:
	DiscoveryManager.record_discovery(DiscoveryManager.KIND_MINIGAME, task_id)


func _on_task_finished(result: HeritageTaskResult) -> void:
	var attempt := _active_attempt
	_active_attempt = null
	if attempt != null:
		HeritageTaskManager.finish_attempt(attempt, result)
	_render_current_card()


func _on_task_return_requested() -> void:
	if _task_host != null and is_instance_valid(_task_host):
		_task_host.queue_free()
	_task_host = null
	if _vocal_scorer != null:
		_vocal_scorer.cancel_capture()
	_vocal_scorer = null
	_render_current_card()
	if task_button.visible and not task_button.disabled:
		task_button.grab_focus()
	else:
		$BtnClose.grab_focus()


func _open_guide() -> void:
	if current_card == null:
		return
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group("HUD") as HUD
	if _hud == null:
		return
	_hud.open_game_guide(GuideOpenContext.new(
		GuideOpenContext.Source.CARD,
		&"feiyi_cards",
		DiscoveryManager.KIND_FEIYI,
		StringName(current_card.resource_path),
		guide_button,
		&"active_use"
	))

func _on_close_pressed() -> void:
	close_detail()

func close_detail() -> void:
	if not visible or _task_host != null:
		return
	hide()
	_release_modal()
	detail_closed.emit()


func _exit_tree() -> void:
	if _task_host != null and is_instance_valid(_task_host):
		_task_host.cancel(&"scene_changed")
		_task_host.queue_free()
	_task_host = null
	if _active_attempt != null:
		HeritageTaskManager.abort_attempt(_active_attempt, &"scene_changed")
		_active_attempt = null
	if _vocal_scorer != null:
		_vocal_scorer.cancel_capture()
	_release_modal()


func _begin_modal() -> void:
	_modal_session_generation = TurnManager.get_session_generation()
	_modal_turn_epoch = TurnManager.get_turn_epoch()
	_modal_lease = TurnManager.acquire_modal(
		&"feiyi_detail",
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
