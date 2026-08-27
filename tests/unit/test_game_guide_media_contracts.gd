extends GutTest

## Semantic media contracts for the player-facing guide.
##
## These tests intentionally inspect the authored manifest rather than rendered
## pixels.  They protect the exact editorial decisions confirmed by the user:
## use the unannotated gameplay capture for movement examples, crop setup
## dialogs instead of showing the whole menu background, explain every major
## HUD region, and pair the map chapter with the real tile-hover readout.

const MEDIA_MANIFEST_PATH := "res://docs/游戏指南结构与配图（数字版）.json"
const QUICK_GOAL_PATH := "res://arts/游戏指南/实机截图/v4/地图格悬浮信息.png"
const QUICK_MOVE_PATH := "res://arts/游戏指南/实机截图/v4/移动阶段-用户原图.png"
const EXPECTED_SESSION_PATHS: Array[String] = [
	"res://arts/游戏指南/实机截图/v4/模式选择弹窗.png",
	"res://arts/游戏指南/实机截图/v4/人数设置弹窗.png",
]

const EXPECTED_INTERFACE_PATHS: Array[String] = [
	"res://arts/游戏指南/实机截图/v4/界面-左侧玩家.png",
	"res://arts/游戏指南/实机截图/v4/界面-中央地图.png",
	"res://arts/游戏指南/实机截图/v4/界面-下方信息与操作.png",
	"res://arts/游戏指南/实机截图/v4/界面-右侧手牌与分数.png",
]
const EXPECTED_INTERFACE_IDS: Array[StringName] = [
	&"interface_current_player",
	&"interface_map",
	&"interface_info_actions",
	&"interface_hand_score",
]

var _manifest: Dictionary


func before_all() -> void:
	_manifest = _load_manifest()


func test_quick_goal_targets_feiyi_without_calling_wulonghe_a_feiyi_tile() -> void:
	var media := _media_by_id(&"quick_goal_route")
	assert_false(media.is_empty(), "快速上手的旅程图必须存在")
	if media.is_empty():
		return
	var semantic_copy := _semantic_copy(media)
	assert_true("非遗" in semantic_copy, "旅程图必须明确指向非遗点")
	assert_false("五龙河" in semantic_copy, "五龙河是风景，不能标成非遗点")
	assert_false("风景" in semantic_copy, "此图解释前往非遗点，不能把风景当作目标")
	var paths := _string_array(media.get("paths", []))
	assert_eq(paths, [QUICK_GOAL_PATH], "快速上手应直接使用明确显示非遗格信息的用户截图")
	if paths.size() == 1:
		_assert_existing_image(paths[0])


func test_quick_move_uses_the_unannotated_gameplay_capture() -> void:
	var quick_move := _media_by_id(&"quick_move_route")
	assert_false(quick_move.is_empty())
	if quick_move.is_empty():
		return
	var move_paths := _string_array(quick_move.get("paths", []))
	assert_eq(move_paths.size(), 1, "移动例子只需要一张真实截图")
	if move_paths.size() != 1:
		return
	assert_eq(move_paths[0], QUICK_MOVE_PATH, "移动例子必须直接使用用户提供的原始移动截图")
	var normalized := move_paths[0].to_lower()
	for forbidden: String in ["标注", "起点至", "路线图", "合成"]:
		assert_false(forbidden in normalized, "不得再使用自绘起终点或路线的合成图：%s" % forbidden)
	assert_true("用户原图" in normalized, "正式路径应明确标识为未经自绘标注的用户原图")
	_assert_existing_image(move_paths[0])


func test_session_mode_and_player_count_media_are_dialog_only_crops() -> void:
	var media := _media_by_id(&"session_modes")
	assert_false(media.is_empty(), "开始一局必须配模式选择与人数设置")
	if media.is_empty():
		return
	var paths := _string_array(media.get("paths", []))
	assert_eq(paths, EXPECTED_SESSION_PATHS, "模式选择与人数设置必须各使用一张仅含弹窗的裁图")
	for path: String in paths:
		assert_true("弹窗" in path, "开始界面配图必须是弹窗裁图，不能带整张背景：%s" % path)
		var image := _load_image(path)
		assert_not_null(image, "弹窗裁图必须能读取：%s" % path)
		if image == null:
			continue
		assert_lt(image.get_width(), 2000, "弹窗裁图仍然过宽，疑似保留了整张开始界面背景：%s" % path)
		assert_lt(image.get_height(), 1500, "弹窗裁图仍然过高，疑似保留了整张开始界面背景：%s" % path)


func test_interface_overview_has_a_distinct_image_for_all_four_screen_regions() -> void:
	var topic_media: Array[Dictionary] = []
	for media_value: Variant in _manifest.get("media", []):
		if media_value is Dictionary:
			var media := media_value as Dictionary
			if StringName(media.get("topic_id", &"")) == &"interface_overview":
				topic_media.append(media)
	assert_eq(topic_media.size(), 4, "“先看懂你的桌面”的左、中、下、右四节都必须各有一张图")
	for index: int in EXPECTED_INTERFACE_IDS.size():
		var media := _media_by_id(EXPECTED_INTERFACE_IDS[index])
		assert_false(media.is_empty(), "缺少桌面区域配图：%s" % EXPECTED_INTERFACE_IDS[index])
		if media.is_empty():
			continue
		var paths := _string_array(media.get("paths", []))
		assert_eq(paths, [EXPECTED_INTERFACE_PATHS[index]], "桌面区域配图与正文位置不一致：%s" % EXPECTED_INTERFACE_IDS[index])
		if paths.size() == 1:
			_assert_existing_image(paths[0])


func test_map_movement_chapter_includes_the_real_tile_hover_readout() -> void:
	var matching: Array[Dictionary] = []
	for media_value: Variant in _manifest.get("media", []):
		if not media_value is Dictionary:
			continue
		var media := media_value as Dictionary
		if StringName(media.get("topic_id", &"")) != &"map_movement":
			continue
		for path: String in _string_array(media.get("paths", [])):
			if path == QUICK_GOAL_PATH:
				matching.append(media)
				break
	assert_eq(matching.size(), 1, "地图章节必须且只能配置一份真实的格子悬浮信息截图")
	if matching.size() != 1:
		return
	var hover_media := matching[0]
	assert_eq(StringName(hover_media.get("group_id", &"")), &"hex_regions", "悬浮信息图应紧跟六角格与地域说明")
	var paths := _string_array(hover_media.get("paths", []))
	assert_eq(paths.size(), 1)
	if paths.size() == 1:
		_assert_existing_image(paths[0])
	var semantic_copy := _semantic_copy(hover_media)
	for expected: String in ["地域", "地形", "精力", "非遗"]:
		assert_true(expected in semantic_copy, "格子悬浮信息图的说明缺少关键内容：%s" % expected)


func _load_manifest() -> Dictionary:
	assert_true(FileAccess.file_exists(MEDIA_MANIFEST_PATH), "配图清单不存在")
	if not FileAccess.file_exists(MEDIA_MANIFEST_PATH):
		return {}
	var file := FileAccess.open(MEDIA_MANIFEST_PATH, FileAccess.READ)
	assert_not_null(file)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_true(parsed is Dictionary, "配图清单不是合法 JSON 对象")
	return parsed as Dictionary if parsed is Dictionary else {}


func _media_by_id(media_id: StringName) -> Dictionary:
	for media_value: Variant in _manifest.get("media", []):
		if media_value is Dictionary:
			var media := media_value as Dictionary
			if StringName(media.get("id", &"")) == media_id:
				return media
	return {}


func _semantic_copy(media: Dictionary) -> String:
	var parts: Array[String] = [
		String(media.get("match", "")),
		String(media.get("alt", "")),
	]
	parts.append_array(_string_array(media.get("captions", [])))
	return " ".join(parts)


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item: Variant in value:
			result.append(String(item))
	return result


func _assert_existing_image(path: String) -> void:
	assert_true(path.begins_with("res://"), "正式配图必须位于项目资源目录：%s" % path)
	assert_true(FileAccess.file_exists(path), "正式配图不存在：%s" % path)
	assert_not_null(_load_image(path), "正式配图无法解码：%s" % path)


func _load_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(path))
	return image if error == OK else null
