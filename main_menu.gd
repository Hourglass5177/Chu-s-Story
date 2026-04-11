extends Control

# --- 节点引用 ---
@onready var main_buttons = $MainButtons
@onready var settings_panel = $SettingsPanel
@onready var slots_container = $SettingsPanel/ScrollContainer/SlotsContainer
@onready var count_slider = $SettingsPanel/PlayerCountSlider
@onready var lbl_count = $SettingsPanel/LblCountDisplay

# 弹窗
@onready var rules_panel = $RulesPanel
@onready var credits_panel = $CreditsPanel
var default_font:FontFile = preload("res://arts/像素字体.ttf")
# --- 模拟数据 (请替换为你实际的数据和图片) ---
var jobs_data = PlayerClass.PlayerCharacter
var locations_data = [MapSection.REGION.十堰, MapSection.REGION.随州, MapSection.REGION.孝感, MapSection.REGION.黄冈, MapSection.REGION.荆州,MapSection.REGION.恩施]
# 模拟立绘路径或资源，可以用 preload 加载真实图片
var job_portraits = {
	"商业博主": preload("res://arts/素材合集/sprite及立绘/Sprite/角色/商业博主.png"), # 替换为真实图片
	"美食博主": preload("res://arts/素材合集/sprite及立绘/Sprite/角色/美食博主.png"),
	"旅行博主": preload("res://arts/素材合集/sprite及立绘/Sprite/角色/旅行博主.png"),
	"生活博主": preload("res://arts/素材合集/sprite及立绘/Sprite/角色/生活博主.png"),
	"魔术博主": preload("res://arts/素材合集/sprite及立绘/Sprite/角色/魔术博主.png"),
	"探险博主": preload("res://arts/素材合集/sprite及立绘/Sprite/角色/探险博主.png"),
}

func _ready():
	# 1. 绑定主菜单按钮
	$MainButtons/TextureStart/BtnStart.pressed.connect(_on_btn_start_pressed)
	$MainButtons/BtnRules.pressed.connect(func(): rules_panel.show())
	$MainButtons/BtnCredits.pressed.connect(func(): credits_panel.show())
	$MainButtons/BtnExit.pressed.connect(func(): get_tree().quit())
	
	# 2. 绑定弹窗关闭按钮
	$RulesPanel/BtnCloseRules.pressed.connect(func(): rules_panel.hide())
	$CreditsPanel/BtnCloseCredits.pressed.connect(func(): credits_panel.hide())
	
	# 3. 绑定设置面板按钮与滑块
	count_slider.value_changed.connect(_on_slider_changed)
	$SettingsPanel/BtnCancelStart.pressed.connect(_on_cancel_start)
	$SettingsPanel/BtnConfirmStart.pressed.connect(_on_confirm_start)
	var btn_close = $MainButtons/BtnExit
	if btn_close.texture_normal:
		var bitmap = BitMap.new()
		# 读取原图的透明通道数据
		bitmap.create_from_image_alpha(btn_close.texture_normal.get_image())
		# 将其设为按钮的点击遮罩
		btn_close.texture_click_mask = bitmap
		var mask = $MainButtons/BtnExit/mask
		btn_close.mouse_entered.connect(func(): mask.show())
		btn_close.mouse_exited.connect(func(): mask.hide())
		btn_close.button_down.connect(func(): mask.modulate = Color(0, 0, 0, 0.7)) # 按下更黑
		btn_close.button_up.connect(func(): mask.modulate = Color(0, 0, 0, 0.4)) 
	btn_close = $CreditsPanel/BtnCloseCredits
	if btn_close.texture_normal:
		var bitmap = BitMap.new()
		# 读取原图的透明通道数据
		bitmap.create_from_image_alpha(btn_close.texture_normal.get_image())
		# 将其设为按钮的点击遮罩
		btn_close.texture_click_mask = bitmap
		var mask = $CreditsPanel/BtnCloseCredits/mask
		btn_close.mouse_entered.connect(func(): mask.show())
		btn_close.mouse_exited.connect(func(): mask.hide())
		btn_close.button_down.connect(func(): mask.modulate = Color(0, 0, 0, 0.7)) # 按下更黑
		btn_close.button_up.connect(func(): mask.modulate = Color(0, 0, 0, 0.4)) 
	
	btn_close = $SettingsPanel/BtnCancelStart
	if btn_close.texture_normal:
		var bitmap = BitMap.new()
		# 读取原图的透明通道数据
		bitmap.create_from_image_alpha(btn_close.texture_normal.get_image())
		# 将其设为按钮的点击遮罩
		btn_close.texture_click_mask = bitmap
		var mask = $SettingsPanel/BtnCancelStart/mask
		btn_close.mouse_entered.connect(func(): mask.show())
		btn_close.mouse_exited.connect(func(): mask.hide())
		btn_close.button_down.connect(func(): mask.modulate = Color(0, 0, 0, 0.7)) # 按下更黑
		btn_close.button_up.connect(func(): mask.modulate = Color(0, 0, 0, 0.4)) 
		
	btn_close = $RulesPanel/BtnCloseRules
	if btn_close.texture_normal:
		var bitmap = BitMap.new()
		# 读取原图的透明通道数据
		bitmap.create_from_image_alpha(btn_close.texture_normal.get_image())
		# 将其设为按钮的点击遮罩
		btn_close.texture_click_mask = bitmap
		var mask = $RulesPanel/BtnCloseRules/mask
		btn_close.mouse_entered.connect(func(): mask.show())
		btn_close.mouse_exited.connect(func(): mask.hide())
		btn_close.button_down.connect(func(): mask.modulate = Color(0, 0, 0, 0.7)) # 按下更黑
		btn_close.button_up.connect(func(): mask.modulate = Color(0, 0, 0, 0.4))
	
# ================= 主菜单逻辑 =================

func _on_btn_start_pressed():
	main_buttons.hide()
	settings_panel.show()
	# 强制触发一次滑块更新，生成默认的 1 个栏位
	_on_slider_changed(count_slider.value)

func _on_cancel_start():
	# 遗忘所有设置（滑块归位，清空容器）
	count_slider.value = 1
	for child in slots_container.get_children():
		child.queue_free()
	settings_panel.hide()
	main_buttons.show()

# ================= 动态栏位生成逻辑 =================

func _on_slider_changed(value: float):
	var target_count = int(value)
	lbl_count.text = str(target_count) + " 人"
	
	# 获取当前已有的栏位数量
	var current_count = slots_container.get_child_count()
	
	# 如果拉大滑块，增加缺少的栏位
	if target_count > current_count:
		for i in range(target_count - current_count):
			_create_player_slot(current_count + i + 1)
	
	# 如果拉小滑块，删除多余的栏位
	elif target_count < current_count:
		var children = slots_container.get_children()
		for i in range(current_count - target_count):
			children[current_count - 1 - i].queue_free()
			
	# 延迟一帧刷新选项排他逻辑（等节点生成/销毁完毕）
	call_deferred("_update_unique_options")

func _create_player_slot(player_index: int):
	var slot = HBoxContainer.new()
	slot.name = "Slot_" + str(player_index)
	slot.add_theme_constant_override("separation", 20)
	slot.alignment = BoxContainer.ALIGNMENT_CENTER
	# 1. 玩家编号
	var lbl_num = Label.new()
	lbl_num.name = "PlayerLabel"
	lbl_num.text = "P" + str(player_index)
	lbl_num.add_theme_font_override("font", default_font)
	lbl_num.add_theme_font_size_override("font_size", 64)
	lbl_num.add_theme_color_override("font_color", Color.BLACK)
	slot.add_child(lbl_num)
	
	# 2. 立绘展示框
	var portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(300, 300)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	slot.add_child(portrait)
	
	# 3. 名字输入框
	var name_input = LineEdit.new()
	name_input.name = "NameInput"
	name_input.placeholder_text = "输入名字"
	name_input.custom_minimum_size = Vector2(160, 50) 
	name_input.add_theme_font_size_override("font_size", 28)
	slot.add_child(name_input)
	
	# 4. 出生点选择 (OptionButton)
	var loc_btn = OptionButton.new()
	loc_btn.name = "LocButton"
	for loc in locations_data:
		var loc_name = MapSection.REGION.find_key(loc)
		loc_btn.add_item(loc_name)
	loc_btn.custom_minimum_size = Vector2(140, 50)
	loc_btn.add_theme_font_size_override("font_size", 28)
	loc_btn.get_popup().add_theme_font_size_override("font_size", 28)
	loc_btn.select(_get_first_available_index(loc_btn, "LocButton"))
	loc_btn.item_selected.connect(func(idx): _update_unique_options())
	slot.add_child(loc_btn)
	
	# 5. 职业选择 (OptionButton)
	var job_btn = OptionButton.new()
	job_btn.name = "JobButton"
	for job in jobs_data.values():
		var job_name = PlayerClass.PlayerCharacter.find_key(job)
		job_btn.add_item(job_name)
	job_btn.select(_get_first_available_index(job_btn, "JobButton"))
	job_btn.custom_minimum_size = Vector2(180, 50)
	job_btn.add_theme_font_size_override("font_size", 28)
	job_btn.get_popup().add_theme_font_size_override("font_size", 28)
	# 职业选择变化时：不仅要更新排他逻辑，还要切换立绘！
	job_btn.item_selected.connect(func(idx): 
		_update_unique_options()
		_update_portrait(slot)
	)
	slot.add_child(job_btn)
	
	slots_container.add_child(slot)
	
	# 初始化默认立绘
	_update_portrait(slot)

func _update_portrait(slot: HBoxContainer):
	var job_btn = slot.get_node("JobButton") as OptionButton
	var portrait = slot.get_node("Portrait") as TextureRect
	var job_name = job_btn.get_item_text(job_btn.get_selected_id())
	# 从字典里取图，找不到就用默认的
	portrait.texture = job_portraits.get(job_name, preload("res://icon.svg"))

# ================= 核心：排他锁定逻辑 =================

func _update_unique_options():
	var active_slots = slots_container.get_children()
	var selected_jobs = []
	var selected_locs = []
	
	# 第一轮：收集所有插槽【当前选中】的文本
	for slot in active_slots:
		if slot.is_queued_for_deletion(): continue
		var job_btn = slot.get_node("JobButton") as OptionButton
		var loc_btn = slot.get_node("LocButton") as OptionButton
		
		selected_jobs.append(job_btn.get_item_text(job_btn.get_selected_id()))
		selected_locs.append(loc_btn.get_item_text(loc_btn.get_selected_id()))
		
	# 第二轮：将已经被别人选走的东西，在自己的菜单里灰掉（禁用）
	for slot in active_slots:
		if slot.is_queued_for_deletion(): continue
		var job_btn = slot.get_node("JobButton") as OptionButton
		var loc_btn = slot.get_node("LocButton") as OptionButton
		
		var my_job = job_btn.get_item_text(job_btn.get_selected_id())
		var my_loc = loc_btn.get_item_text(loc_btn.get_selected_id())
		
		# 处理职业锁定
		for i in range(job_btn.get_item_count()):
			var item_text = job_btn.get_item_text(i)
			# 如果这个职业在“被选名单”里，且【不是我自己当前选的】，就禁用它
			var is_taken = selected_jobs.has(item_text) and item_text != my_job
			job_btn.set_item_disabled(i, is_taken)
			
		# 处理出生点锁定
		for i in range(loc_btn.get_item_count()):
			var item_text = loc_btn.get_item_text(i)
			var is_taken = selected_locs.has(item_text) and item_text != my_loc
			loc_btn.set_item_disabled(i, is_taken)

# ================= 确认开始游戏 =================

func _on_confirm_start():
	var final_players_data = []
	
	# 收集所有数据交给游戏主场景
	for slot in slots_container.get_children():
		var p_name = slot.get_node("NameInput").text
		var p_loc = slot.get_node("LocButton").text
		var p_job = slot.get_node("JobButton").text
		
		# 可以在这里做判空验证
		if p_name.strip_edges() == "":
			p_name = slot.get_node("PlayerLabel").text
			
		final_players_data.append({
			"name": p_name,
			"location": p_loc,
			"job": p_job
		})
		
	print("准备创建游戏，玩家数据：", final_players_data)
	GameManager.player_data = final_players_data
	get_tree().change_scene_to_file("res://main_map.tscn")

# ================= 辅助函数：寻找未被占用的选项索引 =================
func _get_first_available_index(target_btn: OptionButton, btn_name: String) -> int:
	var used_items = []
	
	# 1. 扫描当前已经生成的所有玩家栏位
	for slot in slots_container.get_children():
		if slot.is_queued_for_deletion(): continue
		var btn = slot.get_node_or_null(btn_name) as OptionButton
		# 确保按钮存在，并且里面已经有选项了
		if btn and btn.get_item_count() > 0:
			used_items.append(btn.get_item_text(btn.get_selected_id()))
			
	# 2. 对比目标按钮里的所有选项文字，找出第一个没被占用的
	for i in range(target_btn.get_item_count()):
		var item_text = target_btn.get_item_text(i)
		if not used_items.has(item_text):
			return i # 找到了！返回它的索引
			
	# 3. 极限情况防崩
	return 0
