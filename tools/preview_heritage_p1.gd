extends SceneTree

## User-operated P1 preview. Uses the real practice Host and controllers;
## no forced result, physics edits, score injection or discovery writes.
const HOST := preload("res://InheritanceTasks/UI/heritage_task_host.tscn")
const FONT := preload("res://InheritanceTasks/Art/Pixel/v2/fonts/fusion-pixel-12px-proportional-zh_hans.ttf")
var menu: Control
var host: HeritageTaskHost
var selected_avatar: StringName = HeritageAvatarCatalog.DEFAULT_AVATAR_ID

func _initialize() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	root.title = "楚物志 · 第二轮样板：炼丹与神农"
	call_deferred("_open")

func _open() -> void:
	menu = Control.new()
	root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color("2a2633")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",20)
	center.add_child(box)
	var label := Label.new()
	label.text = "第二轮可玩样板"
	label.add_theme_font_override("font",FONT)
	label.add_theme_font_size_override("font_size",36)
	label.add_theme_color_override("font_color",Color("f4dfad"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var avatars := OptionButton.new()
	avatars.custom_minimum_size = Vector2(480,56)
	avatars.add_theme_font_override("font",FONT)
	avatars.add_theme_font_size_override("font_size",24)
	HeritageTelevisionStyle.pixel_button(avatars,12,2)
	avatars.get_popup().add_theme_font_override("font",FONT)
	avatars.get_popup().add_theme_font_size_override("font_size",24)
	for id: StringName in HeritageAvatarCatalog.IDS: avatars.add_item(HeritageAvatarCatalog.display_name(id))
	selected_avatar = HeritageMinigamePreferences.practice_avatar_id()
	avatars.select(HeritageAvatarCatalog.IDS.find(selected_avatar))
	avatars.item_selected.connect(func(index: int) -> void:
		selected_avatar = HeritageAvatarCatalog.IDS[index]
		HeritageMinigamePreferences.save_practice_avatar(selected_avatar))
	box.add_child(avatars)
	for spec: Array in [["夏氏炼丹术 · 守炉候火","xia_lian_dan_shu"],["炎帝神农 · 登山采药","yandi_shennong_chuanshuo"]]:
		var button := Button.new()
		button.text = spec[0]
		button.custom_minimum_size = Vector2(480,64)
		button.add_theme_font_override("font",FONT)
		button.add_theme_font_size_override("font_size",24)
		HeritageTelevisionStyle.pixel_button(button,12,2)
		button.pressed.connect(_start.bind(String(spec[1])))
		box.add_child(button)
	_start("xia_lian_dan_shu")

func _start(id: String) -> void:
	if is_instance_valid(host): host.queue_free()
	menu.hide()
	var definition := load("res://InheritanceTasks/Definitions/%s.tres" % id) as HeritageTaskDefinition
	var context := HeritageTaskRunContext.new(definition.task_id,null,null,0,0,20260913,true)
	context.avatar_id = selected_avatar
	host = HOST.instantiate() as HeritageTaskHost
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.return_requested.connect(_return)
	host.configure(definition,context)
	host.begin()
	print("P1_PREVIEW_READY ",id)

func _return() -> void:
	if is_instance_valid(host): host.queue_free()
	menu.show()
	for button in menu.find_children("*","Button",true,false):
		button.grab_focus()
		break
