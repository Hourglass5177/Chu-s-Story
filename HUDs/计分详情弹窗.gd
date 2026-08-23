extends Control
class_name ScoreDetailPanel

@onready var title_label: Label = $Panel/标题
@onready var details_container: VBoxContainer = $Panel/详情
@onready var rules_label: Label = $Panel/规则内容
@onready var rules_button: Button = $Panel/计分规则
@onready var close_button: TextureButton = $Panel/BtnClose
@onready var close_mask: TextureRect = $Panel/BtnClose/mask

var _player: PlayerClass = null
var _showing_rules := false
var _was_tree_paused := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rules_button.pressed.connect(_toggle_rules)
	close_button.pressed.connect(close_panel)
	_setup_close_button_feedback()
	hide()

func _setup_close_button_feedback() -> void:
	if close_button.texture_normal == null:
		return
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(close_button.texture_normal.get_image())
	close_button.texture_click_mask = bitmap
	close_button.mouse_entered.connect(func(): close_mask.show())
	close_button.mouse_exited.connect(func(): close_mask.hide())
	close_button.button_down.connect(func(): close_mask.modulate = Color(0, 0, 0, 0.7))
	close_button.button_up.connect(func(): close_mask.modulate = Color(0, 0, 0, 0.4))

func open_for_player(player: PlayerClass) -> void:
	if player == null:
		return
	_player = player
	_showing_rules = false
	_was_tree_paused = get_tree().paused
	_refresh_content()
	show()
	get_tree().paused = true

func close_panel() -> void:
	hide()
	get_tree().paused = _was_tree_paused

func _toggle_rules() -> void:
	_showing_rules = not _showing_rules
	_refresh_content()

func _refresh_content() -> void:
	if _showing_rules:
		title_label.text = "计分规则"
		rules_button.text = "返回"
		details_container.hide()
		rules_label.show()
		rules_label.text = _get_rules_text()
		return
	var breakdown := ResourceManager.get_score_breakdown(_player)
	title_label.text = "计分详情"
	rules_button.text = "计分规则"
	rules_label.hide()
	details_container.show()
	$Panel/详情/基础分/数值.text = str(int(breakdown.get("base_score", 0)))
	$Panel/详情/类别组合分/数值.text = "+" + str(int(breakdown.get("category_combo_score", 0)))
	$Panel/详情/类别集齐分/数值.text = "+" + str(int(breakdown.get("category_completion_score", 0)))
	$Panel/详情/地域组合分/数值.text = "+" + str(int(breakdown.get("regional_combo_score", 0)))
	$Panel/详情/成就分/数值.text = "+" + str(int(breakdown.get("achievement_score", 0)))
	var achievement_names: Array[String] = []
	for value: Variant in breakdown.get("achievements", []):
		if value is 成就牌:
			var achievement := value as 成就牌
			achievement_names.append("%s +%d" % [achievement.card_name, achievement.score_value])
	$Panel/详情/成就明细.visible = not achievement_names.is_empty()
	$Panel/详情/成就明细.text = " · ".join(achievement_names)
	$Panel/详情/总分/数值.text = str(int(breakdown.get("total_score", 0)))

func _get_rules_text() -> String:
	return "基础分：手牌上所有非遗牌的基础分之和。\n\n" \
		+ "类别组合：同类3/5/10张得2/3/5分，只取最高一档；集齐5种类别再得5分。\n\n" \
		+ "类别集齐：每集齐一个类别的全部实际牌得5分。\n\n" \
		+ "地域组合：同城5张得5分（只计一次）；每集齐一市全部实际牌得2分；同时持有潜江、天门、仙桃非遗牌再得2分。\n\n" \
		+ "成就分：本局获得的成就牌分数之和。成就全局唯一，先达成者获得。"
