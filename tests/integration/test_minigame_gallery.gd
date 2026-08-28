extends GutTest

const GUIDE_SCENE := preload("res://UI/GameGuide/digital_game_guide.tscn")
const TEST_DISCOVERY_PATH := "user://minigame-gallery-test.cfg"

var _guide: DigitalGameGuide
var _storage_backup: String
var _discovered_backup: Dictionary
var _known_ids_backup: Dictionary
var _paused_backup: bool


func before_each() -> void:
	_paused_backup = get_tree().paused
	get_tree().paused = false
	_storage_backup = DiscoveryManager._storage_path
	_discovered_backup = DiscoveryManager._discovered.duplicate(true)
	_known_ids_backup = DiscoveryManager._known_ids.duplicate(true)
	_remove_test_file()
	DiscoveryManager.clear_runtime_cache()
	DiscoveryManager.configure_storage_path(TEST_DISCOVERY_PATH)
	_guide = GUIDE_SCENE.instantiate() as DigitalGameGuide
	add_child_autofree(_guide)
	await get_tree().process_frame
	assert_true(_guide.open_guide(GuideOpenContext.new(GuideOpenContext.Source.MAIN_MENU), false))
	await get_tree().process_frame
	_set_developer_view(false)


func after_each() -> void:
	if _guide != null and is_instance_valid(_guide):
		_set_developer_view(false)
		if _guide.is_guide_open():
			_guide.close_guide(false)
	_remove_test_file()
	DiscoveryManager._storage_path = _storage_backup
	DiscoveryManager._test_storage_enabled = false
	DiscoveryManager._discovered = _discovered_backup.duplicate(true)
	DiscoveryManager._known_ids = _known_ids_backup.duplicate(true)
	get_tree().paused = _paused_backup


func test_minigame_gallery_exists_only_in_main_menu_context() -> void:
	var sidebar_button := _guide.get_node("%MinigameButton") as Button
	assert_not_null(sidebar_button)
	assert_true(sidebar_button.is_visible_in_tree(), "主菜单指南必须在固定导航中直接显示小游戏图鉴")
	assert_true("小游戏图鉴" in _visible_and_accessible_text(_guide))
	if sidebar_button != null:
		sidebar_button.pressed.emit()
	assert_eq(int(_guide.get("_view_mode")), DigitalGameGuide.ViewMode.MINIGAME_GALLERY)
	assert_true(sidebar_button.button_pressed, "进入小游戏图鉴后固定导航必须显示选中态")
	_guide.close_guide(false)
	assert_true(_guide.open_guide(GuideOpenContext.new(GuideOpenContext.Source.HUD), false))
	assert_false(sidebar_button.visible, "局内指南不得显示小游戏图鉴固定入口")
	assert_false("小游戏图鉴" in _visible_and_accessible_text(_guide))
	assert_false(_guide.open_minigame_gallery(), "局内实例即使被脚本直接调用也不得进入小游戏图鉴")
	assert_ne(int(_guide.get("_view_mode")), DigitalGameGuide.ViewMode.MINIGAME_GALLERY)


func test_locked_cards_do_not_carry_task_names_descriptions_ids_or_accessibility_text() -> void:
	var task_ids := DiscoveryManager.get_known_ids(DiscoveryManager.KIND_MINIGAME)
	assert_eq(task_ids.size(), 15)
	assert_true(_guide.open_minigame_gallery())
	var rendered := _visible_and_accessible_text(_guide)
	assert_true("未发现" in rendered)
	var gallery := _find_named_gallery(_guide)
	assert_not_null(gallery)
	if gallery != null:
		for entry: Dictionary in gallery.get("_entries"):
			assert_eq(entry.size(), 1, "锁定展示模型只能携带统一锁定状态")
			assert_true(entry.has("unlocked"))
			assert_false(bool(entry.unlocked))
	for task_id: StringName in task_ids:
		var definition := _guide.call(&"_find_card_resource", DiscoveryManager.KIND_MINIGAME, task_id) as HeritageTaskDefinition
		assert_not_null(definition)
		if definition == null:
			continue
		for secret: String in [
			String(task_id),
			definition.display_name,
			definition.heritage_name,
			definition.hook,
			definition.control_hint,
			definition.prototype_asset_note,
			definition.future_asset_slot,
		]:
			if not secret.strip_edges().is_empty():
				assert_false(secret in rendered, "锁定小游戏不得泄露：%s" % secret)
	var locked_panel := _first_node_named_with_prefix(_guide, "LockedTask") as Control
	assert_not_null(locked_panel)
	var locked_texture := _first_texture_rect(locked_panel)
	assert_not_null(locked_texture)
	if locked_texture != null:
		assert_eq(locked_texture.texture.resource_path, "res://arts/任务卡/任务卡（牌背）.png")


func test_unlocked_card_shows_thumbnail_heritage_goal_and_operation() -> void:
	var task_ids := DiscoveryManager.get_known_ids(DiscoveryManager.KIND_MINIGAME)
	assert_false(task_ids.is_empty())
	if task_ids.is_empty():
		return
	var task_id := task_ids[0]
	var definition := _guide.call(&"_find_card_resource", DiscoveryManager.KIND_MINIGAME, task_id) as HeritageTaskDefinition
	assert_not_null(definition)
	assert_true(DiscoveryManager.record_discovery(DiscoveryManager.KIND_MINIGAME, task_id))
	assert_true(_guide.open_minigame_gallery())
	var gallery := _find_named_gallery(_guide)
	assert_not_null(gallery)
	if gallery == null or definition == null:
		return
	var unlocked_entry: Dictionary = {}
	for entry: Dictionary in gallery.get("_entries"):
		if bool(entry.get("unlocked", false)):
			unlocked_entry = entry
			break
	assert_false(unlocked_entry.is_empty())
	assert_same(unlocked_entry.get("thumbnail"), definition.gallery_thumbnail)
	assert_eq(unlocked_entry.get("heritage_name"), definition.heritage_name)
	assert_eq(unlocked_entry.get("task_name"), definition.display_name)
	assert_eq(unlocked_entry.get("goal"), definition.hook)
	assert_false(String(unlocked_entry.get("operation", "")).strip_edges().is_empty())
	var rendered := _visible_and_accessible_text(_guide)
	for expected: String in [definition.heritage_name, definition.display_name, definition.hook]:
		assert_true(expected in rendered, "已解锁卡应显示：%s" % expected)
	var unlocked_panel := _first_node_named_with_prefix(_guide, "UnlockedTask") as Control
	assert_not_null(unlocked_panel)
	var thumbnail := _first_texture_rect(unlocked_panel)
	assert_not_null(thumbnail)
	if thumbnail != null:
		assert_same(thumbnail.texture, definition.gallery_thumbnail)


func test_gallery_switches_between_three_column_and_single_column_layouts() -> void:
	var gallery := preload("res://UI/GameGuide/components/minigame_gallery.tscn").instantiate() as GuideMinigameGallery
	add_child_autofree(gallery)
	var entries: Array[Dictionary] = []
	for index: int in 6:
		entries.append({"unlocked": false})
	gallery.configure(entries, false)
	var grid := gallery.get_node("GalleryGrid") as GridContainer
	assert_eq(grid.columns, 3)
	gallery.configure(entries, true)
	await get_tree().process_frame
	grid = gallery.get_node("GalleryGrid") as GridContainer
	assert_eq(grid.columns, 1)


func test_unlocked_card_emits_stable_task_id_for_practice_replay() -> void:
	var task_ids := DiscoveryManager.get_known_ids(DiscoveryManager.KIND_MINIGAME)
	assert_false(task_ids.is_empty())
	if task_ids.is_empty():
		return
	var task_id := task_ids[0]
	assert_true(DiscoveryManager.record_discovery(DiscoveryManager.KIND_MINIGAME, task_id))
	assert_true(_guide.open_minigame_gallery())
	var replay := _first_replay_button(_guide)
	assert_not_null(replay)
	watch_signals(_guide)
	if replay != null:
		replay.pressed.emit()
		assert_signal_emitted_with_parameters(_guide, "replay_requested", [task_id])


func test_debug_shortcut_reveals_without_persisting_and_alt_variant_does_not_toggle() -> void:
	assert_eq(DiscoveryManager.get_discovery_progress(DiscoveryManager.KIND_MINIGAME).discovered, 0)
	assert_true(_guide.open_minigame_gallery())
	_send_developer_shortcut(false)
	assert_true(_guide.is_developer_view_enabled())
	var progress := DiscoveryManager.get_discovery_progress(DiscoveryManager.KIND_MINIGAME)
	assert_eq(progress.discovered, 0, "开发者视图不能改写玩家进度")
	assert_eq(_nodes_named_with_prefix(_guide, "UnlockedTask").size(), 6, "第一页应全部以已解锁形态展示")
	assert_eq(DiscoveryManager.save_progress(), OK)
	var config := ConfigFile.new()
	assert_eq(config.load(TEST_DISCOVERY_PATH), OK)
	assert_true(Array(config.get_value("discoveries", "minigame", [])).is_empty())

	_send_developer_shortcut(true)
	assert_true(_guide.is_developer_view_enabled(), "额外按住 Alt 的组合键不得误触开发者视图")
	_send_developer_shortcut(false)
	assert_false(_guide.is_developer_view_enabled())


func test_developer_view_reveals_every_hidden_compendium_without_unlocking_it() -> void:
	_send_developer_shortcut(false)
	assert_true(_guide.is_developer_view_enabled())
	for kind: StringName in [
		DiscoveryManager.KIND_FOOD,
		DiscoveryManager.KIND_EVENT,
		DiscoveryManager.KIND_ACHIEVEMENT,
	]:
		assert_eq(DiscoveryManager.get_discovery_progress(kind).discovered, 0)
		_guide.call(&"_render_compendium", kind, 0)
		assert_gt(_nodes_named_with_prefix(_guide, "Entry").size(), 0, "%s 应显示正面条目" % kind)
		assert_eq(_nodes_named_with_prefix(_guide, "LockedEntry").size(), 0, "%s 不应保留锁定卡" % kind)
		assert_eq(DiscoveryManager.get_discovery_progress(kind).discovered, 0, "开发覆盖不得写入 %s 图鉴" % kind)


func test_developer_view_uses_an_honest_generated_front_when_achievement_art_is_missing() -> void:
	var achievement_id := AchievementManager.ID_YOU_SHAN_WAN_SHUI
	var card := _guide.call(&"_find_card_resource", DiscoveryManager.KIND_ACHIEVEMENT, achievement_id) as 成就牌
	assert_not_null(card)
	if card == null:
		return
	assert_same(card.image_of_front, card.image_of_back, "测试前提：游山玩水目前确实没有正式正面美术")
	_send_developer_shortcut(false)
	_guide.call(&"_render_compendium", DiscoveryManager.KIND_ACHIEVEMENT, 0)
	var generated := _first_node_named_with_prefix(_guide, "GeneratedAchievementFront") as Control
	assert_not_null(generated, "开发者视图不能把统一牌背继续当作已经解锁的正面")
	if generated != null:
		assert_eq(StringName(generated.get_meta(&"achievement_id", &"")), achievement_id)
		assert_true(bool(generated.get_meta(&"guide_generated_front", false)))
		assert_true("游山玩水" in _visible_and_accessible_text(generated))
		assert_true("+5分" in _visible_and_accessible_text(generated))
	assert_eq(DiscoveryManager.get_discovery_progress(DiscoveryManager.KIND_ACHIEVEMENT).discovered, 0, "信息正面不能写入真实图鉴")

	assert_true(bool(_guide.call(&"_render_entry_detail", DiscoveryManager.KIND_ACHIEVEMENT, achievement_id)))
	await get_tree().process_frame
	generated = _first_node_named_with_prefix(_guide, "GeneratedAchievementFront") as Control
	assert_not_null(generated, "详情页也不能退回显示统一牌背")


func test_debug_shortcut_does_nothing_while_guide_is_closed() -> void:
	_guide.close_guide(false)
	_send_developer_shortcut(false)
	assert_false(_guide.is_developer_view_enabled())


func test_developer_shortcut_requires_the_exact_pressed_non_echo_modifier_chord() -> void:
	var invalid_events: Array[InputEventKey] = []
	for modifiers: Dictionary in [
		{"ctrl": false, "shift": true, "alt": false, "meta": false, "pressed": true, "echo": false},
		{"ctrl": true, "shift": false, "alt": false, "meta": false, "pressed": true, "echo": false},
		{"ctrl": true, "shift": true, "alt": true, "meta": false, "pressed": true, "echo": false},
		{"ctrl": true, "shift": true, "alt": false, "meta": true, "pressed": true, "echo": false},
		{"ctrl": true, "shift": true, "alt": false, "meta": false, "pressed": false, "echo": false},
		{"ctrl": true, "shift": true, "alt": false, "meta": false, "pressed": true, "echo": true},
	]:
		var event := InputEventKey.new()
		event.keycode = KEY_D
		event.pressed = bool(modifiers.pressed)
		event.echo = bool(modifiers.echo)
		event.ctrl_pressed = bool(modifiers.ctrl)
		event.shift_pressed = bool(modifiers.shift)
		event.alt_pressed = bool(modifiers.alt)
		event.meta_pressed = bool(modifiers.meta)
		invalid_events.append(event)
	for event: InputEventKey in invalid_events:
		_guide.call(&"_input", event)
		assert_false(_guide.is_developer_view_enabled())


func _set_developer_view(enabled: bool) -> void:
	if _guide != null and _guide.is_guide_open() and _guide.is_developer_view_enabled() != enabled:
		_send_developer_shortcut(false)


func _send_developer_shortcut(with_alt: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_D
	event.physical_keycode = KEY_D
	event.pressed = true
	event.ctrl_pressed = true
	event.shift_pressed = true
	event.alt_pressed = with_alt
	_guide.call(&"_input", event)


func _first_replay_button(root: Node) -> Button:
	for node: Node in _descendants(root):
		if node is Button and node.name.begins_with("ReplayButton"):
			return node as Button
	return null


func _find_named_gallery(root: Node) -> GuideMinigameGallery:
	for node: Node in _descendants(root):
		if node is GuideMinigameGallery:
			return node as GuideMinigameGallery
	return null


func _visible_and_accessible_text(root: Node) -> String:
	var parts := PackedStringArray()
	for node: Node in [root] + _descendants(root):
		if node is Control and not (node as Control).is_visible_in_tree():
			continue
		if node is Label:
			parts.append((node as Label).text)
		elif node is BaseButton:
			parts.append((node as BaseButton).text)
		if node is Control:
			var control := node as Control
			parts.append(control.tooltip_text)
			parts.append(control.accessibility_name)
			parts.append(control.accessibility_description)
	return "\n".join(parts)


func _nodes_named_with_prefix(root: Node, prefix: String) -> Array[Node]:
	var result: Array[Node] = []
	for node: Node in _descendants(root):
		if String(node.name).begins_with(prefix):
			result.append(node)
	return result


func _first_node_named_with_prefix(root: Node, prefix: String) -> Node:
	var nodes := _nodes_named_with_prefix(root, prefix)
	return nodes[0] if not nodes.is_empty() else null


func _first_texture_rect(root: Node) -> TextureRect:
	for node: Node in [root] + _descendants(root):
		if node is TextureRect:
			return node as TextureRect
	return null


func _descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in root.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


func _remove_test_file() -> void:
	if FileAccess.file_exists(TEST_DISCOVERY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_DISCOVERY_PATH))
