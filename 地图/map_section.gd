extends AnimatedSprite2D
class_name MapSection
signal section_clicked(target_section: MapSection)
var is_reachable: bool = false:
	set(value):
		is_reachable = value
		_apply_visual_state()
var is_reached: bool = false
var is_occupied: bool = false
enum SectionType{
	一般,
	非遗,
	事件,
	打工,
	商店,
	风景,
	研究所,
	起点,
	其他
}

enum LandForm{
	平原,
	山地,
	湖泊,
	其他
}

enum REGION{
	鄂州,
	恩施,
	黄冈,
	黄石,
	荆门,
	荆州,
	潜江,
	神农架,
	十堰,
	随州,
	天门,
	武汉,
	仙桃,
	咸宁,
	襄阳,
	孝感,
	宜昌,
	其他,
	未知
}

const LANDFORMCOST = {
	LandForm.平原:1,
	LandForm.山地:2,
	LandForm.湖泊:2,
	LandForm.其他:0
}

const REGIONNUM = {
	REGION.鄂州:0,
	REGION.恩施:0,
	REGION.黄冈:0,
	REGION.黄石:0,
	REGION.荆门:0,
	REGION.荆州:0,
	REGION.潜江:0,
	REGION.神农架:0,
	REGION.十堰:0,
	REGION.随州:0,
	REGION.天门:0,
	REGION.武汉:0,
	REGION.仙桃:0,
	REGION.咸宁:0,
	REGION.襄阳:0,
	REGION.孝感:0,
	REGION.宜昌:0,
	REGION.其他:0,
	REGION.未知:0,
}

const 出生点坐标 = {
	REGION.十堰: Vector3i(0,0,0),
	REGION.随州: Vector3i(13, -9, -4),
	REGION.孝感: Vector3i(15, -12, -3), 
	REGION.黄冈: Vector3i(20, -17, -3), 
	REGION.荆州: Vector3i(11, -17, 6), 
	REGION.恩施: Vector3i(-1, -12, 13), 
}

@export var section_name: String = ""
@export var scenery_name: String = ""
@export var location_index: Vector3i = Vector3i(0, 0, 0)
@export var region: REGION = REGION.鄂州
@export var logical_index: int = 0
@export var type: SectionType = SectionType.一般
@export var landform: LandForm = LandForm.平原
@export var cost: int = 1
@export var icon: Image = null
var player_index: int = -1
var grid_visit_history: Dictionary[PlayerClass, int] = {}
@onready var click_area = $click_area
@onready var normal_hover_highlight: Sprite2D = $NormalHoverHighlight
var _hud: HUD = null
var _hovered := false
var _visual_tween: Tween = null
var _base_scale := Vector2.ONE
const ORIGINAL_MOVE_MODULATE := Color(1, 1, 1, 0.84705883)
const ORIGINAL_MOVE_SELF_MODULATE := Color(1, 1, 1, 0.5882353)
const ORIGINAL_MOVE_HOVER_MODULATE := Color(1.347, 0.589, 0.611, 1.0)

static func get_type_brief(section_type: SectionType) -> String:
	match section_type:
		SectionType.非遗:
			return "消耗1精力收集非遗"
		SectionType.事件:
			return "到达后抽取事件牌"
		SectionType.打工:
			return "连续工作获得积分点"
		SectionType.商店:
			return "购买食物牌"
		SectionType.风景:
			return "首次到达后获得3点精力"
		SectionType.研究所:
			return "买卖非遗牌"
		SectionType.起点:
			return "玩家出发点"
		_:
			return ""

func get_tooltip_text() -> String:
	var region_name := String(MapSection.REGION.find_key(region))
	var landform_name := String(MapSection.LandForm.find_key(landform))
	var type_name := String(MapSection.SectionType.find_key(type))
	if type == SectionType.风景 and not scenery_name.is_empty():
		type_name += "（%s）" % scenery_name
	var lines: Array[String] = [
		"%s%d · %s · %s" % [region_name, logical_index, landform_name, type_name],
		"精力消耗：%d" % cost,
	]
	var description := get_type_brief(type)
	if not description.is_empty():
		lines.append(description)
	return "\n".join(lines)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_base_scale = scale
	_hud = get_tree().get_first_node_in_group("HUD") as HUD
	normal_hover_highlight.global_position = global_position
	normal_hover_highlight.global_rotation = global_rotation
	normal_hover_highlight.global_scale = global_scale
	visible = true
	_apply_visual_state()
	if click_area and not click_area.input_event.is_connected(_on_input_event):
		click_area.input_event.connect(_on_input_event)
	if not click_area.mouse_entered.is_connected(_on_mouse_entered):
		click_area.mouse_entered.connect(_on_mouse_entered)
	if not click_area.mouse_exited.is_connected(_on_mouse_exited):
		click_area.mouse_exited.connect(_on_mouse_exited)

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_play_click_feedback()
		elif is_reachable and (_hud == null or not _hud.should_suppress_map_section_click()):
			section_clicked.emit(self)

func _on_mouse_entered() -> void:
	_hovered = true
	if not is_reachable:
		normal_hover_highlight.global_position = global_position
		normal_hover_highlight.global_rotation = global_rotation
		normal_hover_highlight.global_scale = global_scale * 1.04
	_apply_visual_state()
	if _hud != null:
		_hud.request_map_section_tooltip(self)

func _on_mouse_exited() -> void:
	_hovered = false
	_apply_visual_state()
	if _hud != null:
		_hud.cancel_map_section_tooltip(self)

func _apply_visual_state() -> void:
	if not is_inside_tree():
		return
	if is_reachable:
		normal_hover_highlight.hide()
		# 从 Git 历史原样恢复：移动格悬浮时使用原项目的明显亮蓝乘色。
		self_modulate = ORIGINAL_MOVE_SELF_MODULATE
		modulate = ORIGINAL_MOVE_HOVER_MODULATE if _hovered else ORIGINAL_MOVE_MODULATE
	else:
		# 只隐藏主移动高亮贴图，不隐藏 Area2D 和独立的常规悬浮图层。
		self_modulate = Color(1, 1, 1, 0)
		modulate = Color.WHITE
		normal_hover_highlight.visible = _hovered

func _play_click_feedback() -> void:
	if is_reachable:
		return
	var hover_scale := _base_scale * 1.04
	_animate_scale(hover_scale * 0.97, 0.06)
	if _visual_tween != null:
		_visual_tween.tween_property(self, "scale", hover_scale if _hovered else _base_scale, 0.08)

func _animate_scale(target_scale: Vector2, duration: float) -> void:
	if _visual_tween != null and _visual_tween.is_valid():
		_visual_tween.kill()
	_visual_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_visual_tween.tween_property(self, "scale", target_scale, duration)

func _clear_is_reached() -> void:
	is_reached = false
