extends GutTest

class CameraToggleProbe extends HUD:
	var camera_update_count: int = 0

	func update_camera_view(_duration: float = 0.4):
		camera_update_count += 1

	func _update_view_mode_hint() -> void:
		pass

func test_score_panel_shows_breakdown_and_rules_page() -> void:
	var was_paused := get_tree().paused
	get_tree().paused = false
	var panel := preload("res://HUDs/计分详情弹窗.tscn").instantiate() as ScoreDetailPanel
	add_child_autofree(panel)
	await get_tree().process_frame
	var player := PlayerClass.new()
	var card := 非遗牌.new()
	card.card_name = "计分弹窗测试"
	card.base_score = 3
	player.非遗牌手牌.append(card)
	panel.open_for_player(player)
	assert_true(panel.visible)
	assert_true(get_tree().paused)
	var close_mask := panel.get_node("Panel/BtnClose/mask") as TextureRect
	assert_false(close_mask.visible)
	panel.close_button.mouse_entered.emit()
	assert_true(close_mask.visible, "关闭按钮悬浮时应显示与其他弹窗一致的遮罩反馈")
	panel.close_button.button_down.emit()
	assert_almost_eq(close_mask.modulate.a, 0.7, 0.001)
	panel.close_button.button_up.emit()
	assert_almost_eq(close_mask.modulate.a, 0.4, 0.001)
	panel.close_button.mouse_exited.emit()
	assert_false(close_mask.visible)
	assert_eq(panel.get_node("Panel/详情/基础分/数值").text, "3")
	assert_eq(panel.get_node("Panel/详情/总分/数值").text, "3")
	panel._toggle_rules()
	assert_true(panel.get_node("Panel/规则内容").visible)
	assert_eq(panel.get_node("Panel/计分规则").text, "返回")
	panel.close_panel()
	assert_false(panel.visible)
	assert_false(get_tree().paused)
	player.free()
	get_tree().paused = was_paused

func test_map_zoom_limits_and_tooltip_copy_are_fixed() -> void:
	assert_eq(HUD.clamp_map_zoom_factor(0.25), 1.0)
	assert_eq(HUD.clamp_map_zoom_factor(2.0), 2.0)
	assert_eq(HUD.clamp_map_zoom_factor(9.0), 3.0)
	assert_eq(HUD.get_focus_entry_zoom_factor(1.0), 2.0, "默认全图进入追踪应相对默认放大一倍")
	assert_eq(HUD.get_focus_entry_zoom_factor(1.5), 2.0, "追踪入口缩放不得依赖当前全局倍率")
	assert_eq(HUD.get_focus_entry_zoom_factor(3.0), 2.0, "追踪入口不得把当前倍率再次翻倍")
	assert_eq(HUD.get_view_mode_hint_text(false), "【ALT】切换视角：全局\n【滚轮】视角缩放")
	assert_eq(HUD.get_view_mode_hint_text(true), "【ALT】切换视角：追踪\n【滚轮】视角缩放")
	var hud_scene := preload("res://HUDs/HUD.tscn").instantiate()
	var view_hint := hud_scene.get_node("地图/缩放提示信息") as Label
	assert_eq(view_hint.get_theme_constant("outline_size"), 2, "视角状态需要轻微白边以提高辨识度")
	assert_eq(view_hint.get_theme_color("font_outline_color"), Color(1.0, 1.0, 1.0, 0.9))
	hud_scene.free()
	assert_eq(HUD.MAP_TOOLTIP_DELAY, 0.6)
	assert_eq(MapSection.get_type_brief(MapSection.SectionType.研究所), "买卖非遗牌")
	assert_eq(MapSection.get_type_brief(MapSection.SectionType.一般), "")
	var scenery := MapSection.new()
	scenery.region = MapSection.REGION.十堰
	scenery.logical_index = 16
	scenery.landform = MapSection.LandForm.山地
	scenery.type = MapSection.SectionType.风景
	scenery.scenery_name = "武当山"
	scenery.cost = 2
	assert_eq(scenery.get_tooltip_text(), "十堰16 · 山地 · 风景（武当山）\n精力消耗：2\n首次到达后获得3点精力")
	scenery.free()

func test_leaving_focus_keeps_the_current_camera_center() -> void:
	var hud := CameraToggleProbe.new()
	var camera := Camera2D.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1299, 826)
	hud.map_camera = camera
	hud.map_viewport = viewport
	hud.global_zoom = Vector2.ONE
	hud.map_zoom_factor = 2.0
	hud.global_pos = Vector2(1280.0, 800.0)
	hud._global_camera_position = hud.global_pos
	hud.is_focus_mode = true
	var displayed_center := Vector2(900.0, 600.0)
	camera.position = displayed_center
	camera.zoom = Vector2(2.0, 2.0)

	hud._on_view_toggle_pressed()

	assert_false(hud.is_focus_mode)
	assert_eq(hud._global_camera_position, displayed_center, "退出追踪后应从当前画面继续全局浏览，不回地图正中")
	assert_eq(hud.camera_update_count, 1)
	camera.free()
	viewport.free()
	hud.free()

func test_every_scenery_section_has_a_display_name() -> void:
	var map_scene := preload("res://地图/map.tscn").instantiate()
	var scenery_count := 0
	var sections_by_location: Dictionary[Vector3i, MapSection] = {}
	for city in map_scene.get_node("MapSprite").get_children():
		for section in city.get_children():
			if section is MapSection:
				sections_by_location[section.location_index] = section
				if section.type == MapSection.SectionType.风景:
					scenery_count += 1
					assert_false(section.scenery_name.is_empty(), section.section_name)
	assert_eq(scenery_count, 21)
	var heritage_section := sections_by_location[Vector3i(15, -18, 3)]
	assert_eq(heritage_section.type, MapSection.SectionType.非遗, "咸宁2是非遗点，不得错误发放风景奖励")
	assert_true(heritage_section.scenery_name.is_empty())
	var jiugong_section := sections_by_location[Vector3i(17, -20, 3)]
	assert_eq(jiugong_section.type, MapSection.SectionType.风景, "九宫山风景属性必须落在地图图标对应格")
	assert_eq(jiugong_section.scenery_name, "九宫山")
	var sample_section := preload("res://地图/map_section.tscn").instantiate() as MapSection
	var highlight_material := sample_section.get_node("NormalHoverHighlight").material as ShaderMaterial
	assert_not_null(highlight_material)
	var hover_color: Color = highlight_material.get_shader_parameter("fill_color")
	assert_gt(hover_color.r, hover_color.b, "悬浮反馈应为暖黄色")
	assert_almost_eq(sample_section.get_node("NormalHoverHighlight").modulate.a, 0.3, 0.001, "常规格悬浮暖黄层应保持柔和透明")
	assert_null(sample_section.material, "主移动高亮不得附加 Shader，必须保留 Git 历史中的原贴图表现")
	sample_section.free()
	map_scene.free()

func test_reachable_hover_stays_blue_and_only_normal_hover_turns_yellow() -> void:
	var section := preload("res://地图/map_section.tscn").instantiate() as MapSection
	add_child_autofree(section)
	await get_tree().process_frame
	section.is_reachable = true
	section._on_mouse_entered()
	assert_eq(section.modulate, MapSection.ORIGINAL_MOVE_HOVER_MODULATE, "可移动格悬浮必须使用 Git 历史中的原始亮蓝乘色")
	assert_false(section.normal_hover_highlight.visible)
	section._on_mouse_exited()
	assert_eq(section.modulate, MapSection.ORIGINAL_MOVE_MODULATE)
	assert_eq(section.self_modulate, MapSection.ORIGINAL_MOVE_SELF_MODULATE)
	section.is_reachable = false
	section._on_mouse_entered()
	assert_true(section.normal_hover_highlight.visible, "非可移动格悬浮时应显示独立暖黄图层")
