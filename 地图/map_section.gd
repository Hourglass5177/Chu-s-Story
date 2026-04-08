extends AnimatedSprite2D
class_name MapSection
signal section_clicked(target_section: MapSection)
var is_reachable: bool = false
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

@export var section_name: String = ""
@export var location_index: Vector3i = Vector3i(0, 0, 0)
@export var region: REGION = REGION.鄂州
@export var logical_index: int = 0
@export var type: SectionType = SectionType.一般
@export var landform: LandForm = LandForm.平原
@export var cost: int = 1
@export var icon: Image = null
var player_index: int = -1
var grid_visit_history: Dictionary = {}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if(!is_reachable):
		hide()
	else:
		show()

func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_reachable:
			section_clicked.emit(self)
