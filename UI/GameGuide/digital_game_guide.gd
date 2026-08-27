extends FrontendScreen
class_name DigitalGameGuide

signal guide_opened(context: GuideOpenContext)
signal guide_closed(context: GuideOpenContext)
signal topic_opened(topic_id: StringName)
signal ui_feedback_requested(cue: StringName)

enum ViewMode { HOME, TOPIC, RULES_INDEX, COMPENDIUM, ENTRY }

const PAGE_SIZE: int = 12
const COMPENDIUM_KINDS: Array[StringName] = [
	DiscoveryManager.KIND_FEIYI,
	DiscoveryManager.KIND_FOOD,
	DiscoveryManager.KIND_EVENT,
	DiscoveryManager.KIND_ACHIEVEMENT,
	DiscoveryManager.KIND_PROFESSION,
	DiscoveryManager.KIND_SCENERY,
]
const KIND_LABELS: Dictionary = {
	DiscoveryManager.KIND_FEIYI: "非遗",
	DiscoveryManager.KIND_FOOD: "食物",
	DiscoveryManager.KIND_EVENT: "事件",
	DiscoveryManager.KIND_ACHIEVEMENT: "成就",
	DiscoveryManager.KIND_PROFESSION: "职业",
	DiscoveryManager.KIND_SCENERY: "风景",
}
const KIND_BACKS: Dictionary = {
	DiscoveryManager.KIND_FEIYI: "res://arts/非遗牌/非遗牌（牌背）.png",
	DiscoveryManager.KIND_FOOD: "res://arts/食物牌/食物牌（牌背）.jpg",
	DiscoveryManager.KIND_EVENT: "res://arts/事件卡/事件牌（牌背）.png",
	DiscoveryManager.KIND_ACHIEVEMENT: "res://arts/成就卡/成就卡（牌背）.png",
}
const GUIDE_FEIYI_DETAIL_SCRIPT := preload("res://UI/GameGuide/components/guide_feiyi_detail.gd")
const FEIYI_DETAIL_CONTENT_SOURCE := preload("res://UI/Shared/feiyi_detail_content.gd")

static var _last_read_topic_id: StringName = &""
static var _reading_history: Array[StringName] = []

@onready var _safe_area: MarginContainer = %SafeArea
@onready var _frame: PanelContainer = %Frame
@onready var _body: HBoxContainer = %Body
@onready var _sidebar: PanelContainer = %Sidebar
@onready var _content_panel: PanelContainer = %ContentPanel
@onready var _article_scroll: ScrollContainer = %ArticleScroll
@onready var _article: VBoxContainer = %Article
@onready var _breadcrumb: Label = %Breadcrumb
@onready var _search: LineEdit = %Search
@onready var _back_button: Button = %BackButton
@onready var _drawer_button: Button = %DrawerButton
@onready var _close_button: Button = %CloseButton
@onready var _brand: Label = %Brand
@onready var _group_navigation: HFlowContainer = %GroupNavigation
@onready var _home_button: Button = %HomeButton
@onready var _quick_button: Button = %QuickButton
@onready var _rules_button: Button = %RulesButton
@onready var _compendium_button: Button = %CompendiumButton
@onready var _continue_button: Button = %ContinueButton
@onready var _context_button: Button = %ContextButton
@onready var _footer_line: HSeparator = %FooterLine
@onready var _footer: HBoxContainer = %Footer
@onready var _previous_button: Button = %PreviousButton
@onready var _next_button: Button = %NextButton
@onready var _progress_label: Label = %Progress
@onready var _media_preview: Control = %MediaPreview
@onready var _media_preview_safe_area: MarginContainer = %MediaPreviewSafeArea
@onready var _media_preview_image: TextureRect = %MediaPreviewImage
@onready var _media_preview_caption: Label = %MediaPreviewCaption
@onready var _media_preview_close: Button = %MediaPreviewClose

var _catalog: ManualCatalog
var _context: GuideOpenContext = null
var _view_mode: ViewMode = ViewMode.HOME
var _current_topic_id: StringName = &""
var _current_section_id: StringName = &""
var _current_group_id: StringName = &""
var _current_entry_kind: StringName = &""
var _current_entry_id: StringName = &""
var _compendium_kind: StringName = DiscoveryManager.KIND_FEIYI
var _compendium_page: int = 0
var _shortcut_enabled: bool = false
var _opened: bool = false
var _closing: bool = false
var _narrow_layout: bool = false
var _drawer_open: bool = false
var _was_tree_paused: bool = false
var _owns_tree_pause: bool = false
var _open_session_generation: int = -1
var _open_turn_epoch: int = -1
var _turn_modal_lease: int = -1
var _interaction_suspend_lease: int = -1
var _resource_index: Dictionary = {}
var _scenery_index: Dictionary = {}
var _article_tween: Tween = null
var _article_transition_serial: int = 0
var _lifecycle_serial: int = 0
var _resource_path_index: Dictionary = {}
var _last_rules_query: String = ""
var _force_animations_for_test: bool = false
var _catalog_injected_for_test: bool = false
var _focus_after_enter: bool = false
var _direction_navigation_engaged: bool = false
var _left_pointer_button_held: bool = false
var _responsive_rebuild_pending: bool = false
var _background_focus_controls: Array[WeakRef] = []
var _background_focus_modes: Array[int] = []
var _media_preview_focus_return: WeakRef = null
var _home_primary_button: Button = null
var _active_group_button: Button = null
var _compendium_filters: Dictionary = {
	&"feiyi_region": {},
	&"feiyi_category": {},
	&"food_level": {},
	&"scenery_region": {},
}


func _ready() -> void:
	super._ready()
	if not _catalog_injected_for_test:
		_catalog = ManualCatalog.load_generated()
	if _catalog != null and not _catalog.validate().is_empty():
		push_error("数字版游戏指南目录存在无效关联。")
	_ensure_input_action()
	_close_button.pressed.connect(close_guide)
	_back_button.pressed.connect(_handle_back)
	_home_button.pressed.connect(_render_home)
	_quick_button.pressed.connect(func() -> void: _open_topic_by_index(&"quick", 0))
	_rules_button.pressed.connect(_render_rules_index)
	_compendium_button.pressed.connect(func() -> void: _render_compendium(_compendium_kind, 0))
	_continue_button.pressed.connect(_continue_reading)
	_context_button.pressed.connect(_open_context_topic)
	_drawer_button.pressed.connect(_toggle_drawer)
	_previous_button.pressed.connect(func() -> void: _move_topic(-1))
	_next_button.pressed.connect(func() -> void: _move_topic(1))
	_search.text_changed.connect(_on_search_changed)
	_media_preview_close.pressed.connect(_close_media_preview)
	_media_preview.gui_input.connect(_on_media_preview_root_input)
	back_requested.connect(_handle_back)
	transition_finished.connect(_on_screen_transition_finished)
	resized.connect(_update_responsive_layout)
	_update_responsive_layout()


func open_guide(context: GuideOpenContext = null, animated: bool = true) -> bool:
	if _opened and not _closing:
		if context != null:
			_context = context
			_open_context_destination()
		return true
	_lifecycle_serial += 1
	if _closing:
		# 取消退场并继续使用原有暂停/模态租约；不要先发 guide_closed，
		# 否则主菜单会在新指南入场前短暂重新启用后台页面。
		cancel_transition(false)
		_closing = false
		_direction_navigation_engaged = false
		_left_pointer_button_held = false
		_context = context if context != null else GuideOpenContext.new()
		_continue_button.visible = not _last_read_topic_id.is_empty() and _catalog.has_topic(_last_read_topic_id)
		_context_button.visible = _context.source != GuideOpenContext.Source.MAIN_MENU
		_open_context_destination()
		_focus_after_enter = true
		var animate_reopen := _should_animate(animated)
		enter_screen(animate_reopen)
		guide_opened.emit(_context)
		return true
	_context = context if context != null else GuideOpenContext.new()
	_was_tree_paused = get_tree().paused
	_open_session_generation = TurnManager.get_session_generation()
	_open_turn_epoch = TurnManager.get_turn_epoch()
	_turn_modal_lease = TurnManager.acquire_modal(&"digital_game_guide", TurnManager.ModalResumePolicy.RESUME_REMAINING) if TurnManager.GameOn else -1
	_interaction_suspend_lease = InteractionCoordinator.suspend_active(&"digital_game_guide")
	_opened = true
	_closing = false
	_direction_navigation_engaged = false
	_left_pointer_button_held = false
	_disable_background_focus()
	_continue_button.visible = not _last_read_topic_id.is_empty() and _catalog.has_topic(_last_read_topic_id)
	_context_button.visible = _context.source != GuideOpenContext.Source.MAIN_MENU
	_open_context_destination()
	_focus_after_enter = true
	var animate_open := _should_animate(animated)
	# 全屏遮罩出现前先暂停后台；FrontendScreen 的 Tween 使用 PROCESS 模式，
	# 因而仍能在暂停树中完成入场动画。
	_take_tree_pause()
	enter_screen(animate_open)
	guide_opened.emit(_context)
	return true


func close_guide(animated: bool = true) -> void:
	if not _opened or _closing:
		return
	_close_media_preview(false)
	_lifecycle_serial += 1
	var close_serial := _lifecycle_serial
	_closing = true
	var animate_close := _should_animate(animated)
	# 退出 Tween 使用 PROCESS 模式，可在暂停树中正常播放。直到遮罩完全退场前都
	# 保持场景树暂停，避免关闭动画期间后台地图、HUD 或旧弹窗提前恢复一帧。
	exit_screen(animate_close)
	if animate_close:
		await transition_finished
		# 关闭动画可能被一次新的 open_guide() 取消；新入场的完成信号不能
		# 唤醒旧关闭协程并误释放刚取得的租约。
		if close_serial != _lifecycle_serial or not _closing:
			return
	_finalize_close(true)


func is_guide_open() -> bool:
	return _opened and visible


func set_shortcut_enabled(enabled: bool) -> void:
	_shortcut_enabled = enabled


func set_force_animations_for_test(enabled: bool) -> void:
	_force_animations_for_test = enabled


func set_catalog_for_test(catalog: ManualCatalog) -> void:
	_catalog = catalog if catalog != null else ManualCatalog.new()
	_catalog_injected_for_test = true


func get_current_section_id() -> StringName:
	return _current_section_id


func navigate_to(topic_id: StringName, section_id: StringName = &"") -> bool:
	if _catalog == null or not _catalog.has_topic(topic_id):
		return false
	_render_topic(topic_id, section_id)
	return true


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("guide_toggle"):
		if is_guide_open():
			if _media_preview.visible:
				_close_media_preview()
			else:
				close_guide()
		elif _shortcut_enabled:
			var hud := get_tree().get_first_node_in_group("HUD") as HUD
			if hud != null:
				hud.open_game_guide()
			else:
				var focus := get_viewport().gui_get_focus_owner()
				open_guide(GuideOpenContext.new(GuideOpenContext.Source.HUD, &"turn_phases", &"", &"", focus))
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if not is_guide_open():
		return
	if _is_directional_navigation_event(event):
		if not _direction_navigation_engaged:
			_direction_navigation_engaged = true
			_focus_current_view()
		# 不消费第一次方向输入：Godot 会从刚建立的默认焦点继续完成本次导航。
		return
	if _is_pointer_navigation_event(event):
		_direction_navigation_engaged = false
		if event is InputEventMouseButton:
			var mouse_button := event as InputEventMouseButton
			if mouse_button.button_index == MOUSE_BUTTON_LEFT:
				_left_pointer_button_held = mouse_button.pressed
				if not mouse_button.pressed:
					call_deferred(&"_release_guide_navigation_focus")
		elif event is InputEventMouseMotion:
			var motion := event as InputEventMouseMotion
			_left_pointer_button_held = (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
			if not _left_pointer_button_held:
				# MouseMotion 本身不会启动按钮按压，必须在这里同步清焦点。
				# 若延迟到帧末，随后同帧到达的 mouse-down 会被这次旧请求取消。
				_release_guide_navigation_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not is_guide_open():
		return
	if event.is_action_pressed("guide_toggle"):
		if _media_preview.visible:
			_close_media_preview()
		else:
			close_guide()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_handle_back()
		get_viewport().set_input_as_handled()
		return
	# 指南是最高层模态；未被其控件消费的键盘/手柄输入不得到达后台。
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_lifecycle_serial += 1
	if _article_tween != null and _article_tween.is_valid():
		_article_tween.kill()
	if _opened:
		_finalize_close(false)


func _finalize_close(restore_focus: bool) -> void:
	_close_media_preview(false)
	var closed_context := _context
	var owned_tree_pause := _owns_tree_pause
	_opened = false
	_closing = false
	_focus_after_enter = false
	_direction_navigation_engaged = false
	_left_pointer_button_held = false
	_drawer_open = false
	_owns_tree_pause = false
	if _turn_modal_lease >= 0:
		TurnManager.release_modal(_turn_modal_lease)
	_turn_modal_lease = -1
	var tree := get_tree()
	var same_runtime_context: bool = (
		_open_session_generation == TurnManager.get_session_generation()
		and _open_turn_epoch == TurnManager.get_turn_epoch()
	)
	var terminal_pause: bool = not TurnManager.GameOn and TurnManager.get_game_result() != null
	# 只撤销指南自己建立、且仍属于同一局同一回合的暂停。终局或会话切换
	# 已经接管暂停所有权时，旧指南绝不能把新状态重新放行。
	if tree != null and owned_tree_pause and same_runtime_context and not terminal_pause:
		tree.paused = _was_tree_paused
	if _interaction_suspend_lease >= 0:
		InteractionCoordinator.resume_active(_interaction_suspend_lease)
	_interaction_suspend_lease = -1
	_restore_background_focus()
	_open_session_generation = -1
	_open_turn_epoch = -1
	if restore_focus and closed_context != null:
		closed_context.restore_scroll_state()
		var focus := closed_context.get_return_focus()
		if focus != null and is_instance_valid(focus) and focus.is_visible_in_tree() and focus.focus_mode != Control.FOCUS_NONE:
			focus.call_deferred(&"grab_focus")
	_context = null
	if closed_context != null:
		guide_closed.emit(closed_context)


func _take_tree_pause() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = true
	_owns_tree_pause = not _was_tree_paused


func _open_context_destination() -> void:
	if _catalog == null or not _catalog.load_error.is_empty() or _catalog.get_topics().is_empty():
		_render_catalog_error()
		return
	if _context == null:
		_render_home()
		return
	if not _context.object_id.is_empty() and not _context.object_kind.is_empty():
		if _render_entry_detail(_context.object_kind, _context.object_id):
			return
	if _catalog.has_topic(_context.topic_id) and _context.topic_id != &"guide_home":
		_render_topic(_context.topic_id, _context.section_id)
	elif not _context.object_kind.is_empty():
		_open_context_topic()
	else:
		_render_home()


func _render_home() -> void:
	_close_drawer_for_destination()
	_set_primary_navigation_enabled(true)
	_view_mode = ViewMode.HOME
	_update_sidebar_selection(&"home")
	_current_topic_id = &""
	_current_section_id = &""
	_current_group_id = &""
	_group_navigation.visible = false
	_search.visible = false
	_breadcrumb.text = "首页"
	_update_back_button()
	_set_footer_visible(false)
	_clear_article()
	_render_home_intro()
	var cards := GridContainer.new()
	cards.columns = 1 if _narrow_layout else 3
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("h_separation", 18)
	cards.add_theme_constant_override("v_separation", 18)
	_article.add_child(cards)
	_home_primary_button = _add_home_card(cards, "快速上手", "六步了解核心玩法", "res://arts/地图/地图完整版.png", func() -> void: _open_topic_by_index(&"quick", 0))
	_add_home_card(cards, "规则介绍", "按主题查找正式裁定", "res://arts/事件卡/事件牌（牌背）.png", _render_rules_index)
	_add_home_card(cards, "探索图鉴", "翻开旅途中见过的内容", "res://arts/成就卡/成就卡（牌背）.png", func() -> void: _render_compendium(_compendium_kind, 0))
	var quick_actions := HFlowContainer.new()
	quick_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quick_actions.add_theme_constant_override("h_separation", 14)
	quick_actions.add_theme_constant_override("v_separation", 14)
	_article.add_child(quick_actions)
	if not _last_read_topic_id.is_empty() and _catalog.has_topic(_last_read_topic_id):
		var continue_topic := _catalog.get_topic(_last_read_topic_id) as ManualTopic
		var continue_card := _add_button(quick_actions, "继续阅读 · %s" % continue_topic.title, Vector2(340, 68))
		continue_card.pressed.connect(_continue_reading)
	if _context != null and _context.source != GuideOpenContext.Source.MAIN_MENU:
		var context_card := _add_button(quick_actions, "本局相关 · %s" % _context_summary(), Vector2(340, 68))
		context_card.pressed.connect(_open_context_topic)
	_request_current_view_focus()


func _render_home_intro() -> void:
	var data := _catalog.home_data if _catalog != null else {}
	var title := String(data.get("title", "从这里出发"))
	var summary := String(data.get("summary", ""))
	if not title.is_empty() and not _is_production_directive(title):
		_add_rich_text(_article, title, 56, FrontendStyle.BROWN_DARK)
	if not summary.is_empty() and not _is_production_directive(summary):
		_add_rich_text(_article, summary, 33, FrontendStyle.BROWN_MUTED)
	var raw_sections: Variant = data.get("sections", data.get("blocks", []))
	if raw_sections is Array:
		for raw_section: Variant in raw_sections:
			if raw_section is Dictionary:
				_add_manual_section(ManualSection.from_dictionary(raw_section))
	var raw_paragraphs: Variant = data.get("paragraphs", [])
	if raw_paragraphs is Array:
		for raw_paragraph: Variant in raw_paragraphs:
			var paragraph := String(raw_paragraph)
			if not paragraph.is_empty() and not _is_production_directive(paragraph):
				_add_rich_text(_article, paragraph, 31, FrontendStyle.BROWN)


func _render_rules_index(query: String = "", focus_results: bool = true) -> void:
	_close_drawer_for_destination()
	_set_primary_navigation_enabled(true)
	_view_mode = ViewMode.RULES_INDEX
	_update_sidebar_selection(&"rules")
	_current_topic_id = &""
	_current_section_id = &""
	_current_group_id = &""
	_group_navigation.visible = false
	_search.visible = true
	_search.set_block_signals(true)
	_search.text = query
	_search.set_block_signals(false)
	_last_rules_query = query
	_breadcrumb.text = "规则介绍"
	_update_back_button()
	_set_footer_visible(false)
	_clear_article()
	_add_label(_article, "规则介绍", 54, FrontendStyle.BROWN_DARK)
	_add_label(_article, "按主题浏览，或搜索公开规则与已经发现的条目。", 31, FrontendStyle.BROWN_MUTED)
	var result_grid := GridContainer.new()
	result_grid.columns = 1 if _narrow_layout else 2
	result_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_grid.add_theme_constant_override("h_separation", 16)
	result_grid.add_theme_constant_override("v_separation", 16)
	_article.add_child(result_grid)
	var results := _catalog.search(query, &"rules", _requirements_met)
	for topic: ManualTopic in results:
		var target_group := _first_matching_group(topic, query)
		_add_result_button(result_grid, topic.title, func() -> void: _render_topic(topic.topic_id, target_group))
	if not query.strip_edges().is_empty():
		_render_discovered_search_results(query)
	if results.is_empty():
		_add_label(_article, "没有找到相关规则", 30, FrontendStyle.BROWN_MUTED)
	if focus_results:
		_request_current_view_focus()


func _render_topic(topic_id: StringName, section_id: StringName = &"") -> void:
	_close_drawer_for_destination()
	_set_primary_navigation_enabled(true)
	var topic := _catalog.get_topic(topic_id) as ManualTopic
	if topic == null:
		_render_catalog_error("请求的规则条目不存在")
		return
	_view_mode = ViewMode.TOPIC
	_update_sidebar_selection(&"quick" if topic.category == &"quick" else &"rules")
	_current_topic_id = topic.topic_id
	_search.visible = false
	var selected_group := _resolve_visible_group(topic, section_id)
	_current_group_id = selected_group
	_current_section_id = selected_group
	_breadcrumb.text = ("快速上手 / " if topic.category == &"quick" else "规则介绍 / ") + topic.title
	_update_back_button()
	_build_group_navigation(topic, selected_group)
	_clear_article()
	_add_label(_article, topic.title, 56, FrontendStyle.BROWN_DARK)
	# The builder promotes the authored opening paragraph into the topic summary
	# so it can also serve the index and search results. It is still player-facing
	# prose and must appear exactly once on the topic page.
	var visible_summary := topic.get_visible_summary(_requirements_met)
	if not visible_summary.is_empty():
		_add_rich_text(_article, visible_summary, 33, FrontendStyle.BROWN)
	var sections := topic.sections if topic.category == &"quick" else topic.get_sections_for_group(selected_group)
	for section: ManualSection in sections:
		_add_manual_section(section)
	_last_read_topic_id = topic.topic_id
	if not _reading_history.has(topic.topic_id):
		_reading_history.append(topic.topic_id)
	_continue_button.visible = true
	_update_topic_footer(topic)
	topic_opened.emit(topic.topic_id)
	_request_current_view_focus()


func _render_topic_with_detail(topic_id: StringName) -> void:
	# Schema v3 no longer hides prose behind a DETAIL accordion.  Keep this
	# compatibility entry point for older callers and render the selected group.
	_render_topic(topic_id, _current_section_id)


func _add_manual_section(section: ManualSection) -> void:
	if not _requirements_met(section.requirements):
		return
	match section.section_type:
		ManualSection.Type.HEADING:
			var heading := section.text if not section.text.is_empty() else section.title
			if not heading.is_empty() and not _is_production_directive(heading):
				var heading_size := clampi(49 - section.level * 3, 32, 45)
				_add_rich_text(_article, heading, heading_size, FrontendStyle.BROWN_DARK)
		ManualSection.Type.PARAGRAPH:
			_add_prose_section(section)
		ManualSection.Type.BULLETS, ManualSection.Type.NUMBERED:
			_add_list_section(section)
		ManualSection.Type.TABLE:
			_add_table_section(section)
		ManualSection.Type.QUOTE:
			_add_quote_section(section)
		ManualSection.Type.MEDIA:
			_add_media_section(section)
		ManualSection.Type.DIVIDER:
			_article.add_child(HSeparator.new())


func _add_prose_section(section: ManualSection) -> void:
	var prose := section.text if not section.text.is_empty() else section.body
	if not section.title.is_empty() and not _is_production_directive(section.title):
		_add_rich_text(_article, section.title, 39, FrontendStyle.BROWN_DARK)
	if section.legacy_flow:
		var flow_demo := GuideFlowDemo.new()
		flow_demo.custom_minimum_size = Vector2(0, 90)
		flow_demo.setup(section.title, _reduce_motion_enabled())
		_article.add_child(flow_demo)
	if not prose.is_empty() and not _is_production_directive(prose):
		_add_rich_text(_article, prose, 32, FrontendStyle.BROWN)
	if not section.media_entries.is_empty():
		_add_media_entries(section.media_entries)
	if not section.items.is_empty():
		_add_list_section(section)


func _add_list_section(section: ManualSection) -> void:
	if not section.title.is_empty() and not _is_production_directive(section.title):
		_add_rich_text(_article, section.title, 38, FrontendStyle.BROWN_DARK)
	var visible_index := 0
	for item: Dictionary in section.items:
		if not _requirements_met(item.get("requirements", [])):
			continue
		var item_text := String(item.get("text", "")).strip_edges()
		if item_text.is_empty() or _is_production_directive(item_text):
			continue
		visible_index += 1
		var prefix := "%d.  " % visible_index if section.section_type == ManualSection.Type.NUMBERED else "•  "
		_add_rich_text(_article, prefix + item_text, 31, FrontendStyle.BROWN)


func _add_table_section(section: ManualSection) -> void:
	var visible_rows: Array[Dictionary] = []
	for row: Dictionary in section.table_rows:
		if _requirements_met(row.get("requirements", [])):
			visible_rows.append(row)
	if section.table_headers.is_empty() and visible_rows.is_empty():
		return
	if not section.title.is_empty() and not _is_production_directive(section.title):
		_add_rich_text(_article, section.title, 38, FrontendStyle.BROWN_DARK)
	var column_count := section.table_headers.size()
	for row: Dictionary in visible_rows:
		column_count = maxi(column_count, (row.get("cells", PackedStringArray()) as PackedStringArray).size())
	column_count = maxi(column_count, 1)
	# Wide layouts preserve the comparison structure. Narrow layouts render each
	# row as a compact card so Chinese prose never requires horizontal scrolling.
	if not _narrow_layout and column_count <= 5:
		var grid := GridContainer.new()
		grid.columns = column_count
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		_article.add_child(grid)
		for header_index: int in range(column_count):
			var header := section.table_headers[header_index] if header_index < section.table_headers.size() else ""
			_add_table_cell(grid, header, true)
		for row: Dictionary in visible_rows:
			var cells := row.get("cells", PackedStringArray()) as PackedStringArray
			for cell_index: int in range(column_count):
				_add_table_cell(grid, cells[cell_index] if cell_index < cells.size() else "", false)
	else:
		for row: Dictionary in visible_rows:
			var card := PanelContainer.new()
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.add_theme_stylebox_override("panel", FrontendStyle.make_box(Color("#FFF4D8"), Color(FrontendStyle.GOLD, 0.58), 2, 12, Vector4(18, 14, 18, 14)))
			_article.add_child(card)
			var content := VBoxContainer.new()
			content.add_theme_constant_override("separation", 8)
			card.add_child(content)
			var cells := row.get("cells", PackedStringArray()) as PackedStringArray
			for cell_index: int in range(cells.size()):
				var header := section.table_headers[cell_index] if cell_index < section.table_headers.size() else ""
				var line := "%s：%s" % [header, cells[cell_index]] if not header.is_empty() else cells[cell_index]
				_add_rich_text(content, line, 29, FrontendStyle.BROWN)


func _add_table_cell(parent: GridContainer, value: String, header: bool) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var background := Color("#EFD49A") if header else Color("#FFF4D8")
	panel.add_theme_stylebox_override("panel", FrontendStyle.make_box(background, Color(FrontendStyle.GOLD, 0.52), 1, 8, Vector4(12, 10, 12, 10)))
	parent.add_child(panel)
	_add_rich_text(panel, value, 29 if header else 28, FrontendStyle.BROWN_DARK if header else FrontendStyle.BROWN)


func _add_quote_section(section: ManualSection) -> void:
	var quote_text := section.text if not section.text.is_empty() else section.body
	if quote_text.is_empty() or _is_production_directive(quote_text):
		return
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", FrontendStyle.make_box(Color("#F4DFC0"), FrontendStyle.ORANGE, 3, 14, Vector4(22, 18, 22, 18)))
	_article.add_child(panel)
	_add_rich_text(panel, quote_text, 32, FrontendStyle.BROWN_DARK)


func _add_media_section(section: ManualSection) -> void:
	if not section.title.is_empty() and not _is_production_directive(section.title):
		_add_rich_text(_article, section.title, 38, FrontendStyle.BROWN_DARK)
	_add_media_entries(section.media_entries)


func _add_media_entries(entries: Array[Dictionary]) -> void:
	for entry: Dictionary in entries:
		if not _requirements_met(entry.get("requirements", [])):
			continue
		var provider := String(entry.get("provider", "static")).to_lower()
		var dynamic_kind := StringName(str(entry.get("dynamic_kind", "")))
		# The round overview is intentionally a flow presentation. Other authored
		# guide captures are rendered as the actual, audited screenshots declared
		# in the media manifest. Never turn an unrelated map or card back into a
		# pseudo-demonstration merely to fill empty space.
		if provider == "dynamic" and dynamic_kind == &"guide_capture" and StringName(str(entry.get("dynamic_id", ""))) == &"quick_turn_flow":
			var demo := GuideVisualDemo.new()
			_article.add_child(demo)
			demo.media_preview_requested.connect(_open_media_preview)
			demo.setup(
				StringName(str(entry.get("dynamic_id", entry.get("id", "")))),
				String(entry.get("layout", "full")),
				String(entry.get("alt", "")),
				_narrow_layout,
				StringName(str(entry.get("id", ""))),
				entry.get("paths", []) as Array,
				entry.get("captions", []) as Array
			)
			continue
		var records := _resolve_media_records([entry])
		if records.is_empty():
			continue
		var block := ManualMediaBlock.new()
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_article.add_child(block)
		block.media_preview_requested.connect(_open_media_preview)
		block.setup(records, _narrow_layout)


func _resolve_media_records(entries: Array[Dictionary]) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if not _requirements_met(entry.get("requirements", [])):
			continue
		var record := {
			"id": StringName(str(entry.get("id", ""))),
			"layout": String(entry.get("layout", "full")),
			"fit": String(entry.get("fit", "contain")),
			"min_item_width": float(entry.get("min_item_width", 0.0)),
			"target_width_ratio": float(entry.get("target_width_ratio", 1.0)),
			"max_columns": int(entry.get("max_columns", 0)),
			"alt": String(entry.get("alt", "")),
			"items": [],
		}
		var provider := String(entry.get("provider", "static")).to_lower()
		if provider == "dynamic":
			record["items"] = _resolve_dynamic_media(entry)
			if (record["items"] as Array).is_empty():
				record["items"] = _resolve_static_media_items(entry)
		else:
			record["items"] = _resolve_static_media_items(entry)
		if not (record["items"] as Array).is_empty():
			records.append(record)
	return records


func _resolve_static_media_items(entry: Dictionary) -> Array[Dictionary]:
	var paths: Array[String] = []
	var single_path := String(entry.get("path", ""))
	if not single_path.is_empty():
		paths.append(single_path)
	for raw_path: Variant in entry.get("paths", []):
		var path := String(raw_path)
		if not path.is_empty() and not paths.has(path):
			paths.append(path)
	var result: Array[Dictionary] = []
	var captions := entry.get("captions", []) as Array
	var alt_texts := entry.get("alts", []) as Array
	for path_index: int in range(paths.size()):
		var path := paths[path_index]
		if not ResourceLoader.exists(path):
			continue
		var texture := load(path) as Texture2D
		if texture != null:
			result.append({
				"texture": texture,
				"path": path,
				"kind": StringName(str(entry.get("dynamic_kind", ""))),
				"id": StringName(str(entry.get("id", ""))),
				"alt": String(alt_texts[path_index]) if path_index < alt_texts.size() else String(entry.get("alt", "")),
				"caption": String(captions[path_index]) if path_index < captions.size() else "",
			})
	return result


func _resolve_dynamic_media(entry: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dynamic_kind := StringName(str(entry.get("dynamic_kind", "")))
	var dynamic_id := StringName(str(entry.get("dynamic_id", entry.get("id", ""))))
	var declared_id := StringName(str(entry.get("id", "")))
	var kinds_and_ids: Array[Dictionary] = []
	match dynamic_kind:
		&"retained_events":
			for event_id: StringName in DiscoveryManager.get_known_ids(DiscoveryManager.KIND_EVENT):
				var resource := _find_card_resource(DiscoveryManager.KIND_EVENT, event_id)
				if resource is 事件牌 and (resource as 事件牌).retainable:
					kinds_and_ids.append({"kind": DiscoveryManager.KIND_EVENT, "id": event_id})
		&"achievements":
			for achievement_id: StringName in DiscoveryManager.get_known_ids(DiscoveryManager.KIND_ACHIEVEMENT):
				kinds_and_ids.append({"kind": DiscoveryManager.KIND_ACHIEVEMENT, "id": achievement_id})
		&"compendium_preview":
			for kind: StringName in [DiscoveryManager.KIND_FOOD, DiscoveryManager.KIND_EVENT, DiscoveryManager.KIND_ACHIEVEMENT]:
				var ids := DiscoveryManager.get_known_ids(kind)
				if not ids.is_empty():
					kinds_and_ids.append({"kind": kind, "id": ids[0]})
		&"food_levels":
			return _resolve_food_level_media(entry)
		&"guide_capture":
			for raw_path: Variant in entry.get("paths", []):
				var path := String(raw_path)
				if ResourceLoader.exists(path):
					var texture := load(path) as Texture2D
					if texture != null:
						result.append({"texture": texture, "path": path, "kind": dynamic_kind, "id": declared_id, "alt": String(entry.get("alt", ""))})
			return result
		_:
			return result
	for pair: Dictionary in kinds_and_ids:
		var kind := StringName(pair.get("kind", &""))
		var entry_id := StringName(pair.get("id", &""))
		var discovered := DiscoveryManager.is_discovered(kind, entry_id)
		var texture: Texture2D = null
		var caption := "未发现"
		if discovered:
			var data := _get_entry_data(kind, entry_id)
			texture = data.get("texture") as Texture2D
			caption = String(data.get("title", ""))
		else:
			texture = _get_card_back(kind)
		if texture != null:
			result.append({
				"texture": texture,
				"path": "",
				"kind": dynamic_kind,
				"id": declared_id,
				"alt": caption if discovered else "未发现",
				"caption": caption,
			})
	return result


func _resolve_food_level_media(entry: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var declared_id := StringName(str(entry.get("id", "food_levels")))
	var food_ids := DiscoveryManager.get_known_ids(DiscoveryManager.KIND_FOOD)
	for food_type: int in [食物牌.FoodType.市级, 食物牌.FoodType.省级, 食物牌.FoodType.国家级]:
		var selected_id: StringName = &""
		var selected_card: 食物牌 = null
		for food_id: StringName in food_ids:
			var resource := _find_card_resource(DiscoveryManager.KIND_FOOD, food_id)
			if resource is 食物牌 and (resource as 食物牌).food_type == food_type:
				selected_id = food_id
				selected_card = resource as 食物牌
				if DiscoveryManager.is_discovered(DiscoveryManager.KIND_FOOD, food_id):
					break
		var level_name: String = String(食物牌.FoodType.find_key(food_type))
		var discovered := selected_card != null and DiscoveryManager.is_discovered(DiscoveryManager.KIND_FOOD, selected_id)
		var texture := selected_card.image_of_front if discovered else _get_card_back(DiscoveryManager.KIND_FOOD)
		if texture == null:
			continue
		var caption := "%s · %s" % [level_name, selected_card.card_name] if discovered else "%s · 未发现" % level_name
		result.append({
			"texture": texture,
			"path": texture.resource_path if discovered else String(KIND_BACKS[DiscoveryManager.KIND_FOOD]),
			"kind": &"food_levels",
			"id": declared_id,
			"alt": caption,
			"caption": caption,
		})
	return result


func _requirements_met(requirements: Variant) -> bool:
	if requirements == null:
		return true
	var values: Array = []
	if requirements is Dictionary:
		values = [requirements]
	elif requirements is Array:
		values = requirements as Array
	else:
		return false
	for raw_requirement: Variant in values:
		if not raw_requirement is Dictionary:
			return false
		var requirement := raw_requirement as Dictionary
		var kind := StringName(str(requirement.get("kind", "")))
		var entry_id := StringName(str(requirement.get("id", "")))
		if not [DiscoveryManager.KIND_FOOD, DiscoveryManager.KIND_EVENT, DiscoveryManager.KIND_ACHIEVEMENT].has(kind):
			return false
		if entry_id.is_empty() or not DiscoveryManager.is_discovered(kind, entry_id):
			return false
	return true


func _is_production_directive(value: String) -> bool:
	var normalized := value.strip_edges()
	return normalized.begins_with("【配图") or normalized.begins_with("【卷首") or normalized.begins_with("【演示")


func _add_rich_text(parent: Control, value: String, font_size: int, color: Color) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 0
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_font_size_override("bold_font_size", font_size)
	label.add_theme_font_size_override("mono_font_size", font_size)
	label.add_theme_color_override("default_color", color)
	label.add_theme_constant_override("line_separation", 7)
	label.text = _restricted_markdown_to_bbcode(value)
	parent.add_child(label)
	return label


func _restricted_markdown_to_bbcode(value: String) -> String:
	# The authored guide only needs inline emphasis and code-like terms. Literal
	# BBCode is neutralised first, so content can never inject layout tags.
	var safe := value.replace("[", "［").replace("]", "］")
	var bold_pattern := RegEx.new()
	bold_pattern.compile("\\*\\*([^*\\n]+)\\*\\*")
	safe = bold_pattern.sub(safe, "[b]$1[/b]", true)
	var code_pattern := RegEx.new()
	code_pattern.compile("`([^`\\n]+)`")
	safe = code_pattern.sub(safe, "[color=#C46B2B]$1[/color]", true)
	return safe.replace("**", "").replace("`", "")


func _build_group_navigation(topic: ManualTopic, selected_group: StringName) -> void:
	_active_group_button = null
	for child: Node in _group_navigation.get_children():
		_group_navigation.remove_child(child)
		child.queue_free()
	_group_navigation.visible = topic.category == &"rules" and _visible_groups(topic).size() > 1
	if not _group_navigation.visible:
		return
	for group: Dictionary in _visible_groups(topic):
		var group_id := StringName(group.get("id", &""))
		var button := _add_button(_group_navigation, String(group.get("title", "规则")), Vector2(210, 64))
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.toggle_mode = true
		button.button_pressed = group_id == selected_group
		if group_id == selected_group:
			_active_group_button = button
		button.pressed.connect(func() -> void: _render_topic(topic.topic_id, group_id))


func _visible_groups(topic: ManualTopic) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for group: Dictionary in topic.groups:
		if not _requirements_met(group.get("requirements", [])):
			continue
		var has_visible_content := false
		for section: ManualSection in topic.get_sections_for_group(StringName(group.get("id", &""))):
			if _requirements_met(section.requirements):
				has_visible_content = true
				break
		if has_visible_content:
			result.append(group)
	return result


func _resolve_visible_group(topic: ManualTopic, requested_id: StringName) -> StringName:
	var requested_group := requested_id
	if topic.has_section(requested_id):
		requested_group = topic.get_group_id_for_section(requested_id)
	for group: Dictionary in _visible_groups(topic):
		if StringName(group.get("id", &"")) == requested_group:
			return requested_group
	var groups := _visible_groups(topic)
	return StringName(groups[0].get("id", &"")) if not groups.is_empty() else &""


func _first_matching_group(topic: ManualTopic, query: String) -> StringName:
	var normalized := query.strip_edges().to_lower()
	var groups := _visible_groups(topic)
	if normalized.is_empty():
		return StringName(groups[0].get("id", &"")) if not groups.is_empty() else &""
	for group: Dictionary in groups:
		var group_id := StringName(group.get("id", &""))
		var searchable := String(group.get("title", ""))
		for section: ManualSection in topic.get_sections_for_group(group_id):
			if not _requirements_met(section.requirements):
				continue
			searchable += "\n%s\n%s\n%s" % [section.title, section.text, " ".join(section.table_headers)]
			for item: Dictionary in section.items:
				if _requirements_met(item.get("requirements", [])):
					searchable += "\n%s" % String(item.get("text", ""))
			for row: Dictionary in section.table_rows:
				if _requirements_met(row.get("requirements", [])):
					searchable += "\n%s" % " ".join(PackedStringArray(row.get("cells", [])))
		if normalized in searchable.to_lower():
			return group_id
	return StringName(groups[0].get("id", &"")) if not groups.is_empty() else &""


func _render_compendium(kind: StringName, page: int) -> void:
	_close_drawer_for_destination()
	_set_primary_navigation_enabled(true)
	if not COMPENDIUM_KINDS.has(kind):
		kind = DiscoveryManager.KIND_FEIYI
	_view_mode = ViewMode.COMPENDIUM
	_update_sidebar_selection(&"compendium")
	_current_topic_id = &""
	_current_section_id = &""
	_current_group_id = &""
	_group_navigation.visible = false
	_current_entry_kind = &""
	_current_entry_id = &""
	_compendium_kind = kind
	var ids := _get_filtered_compendium_ids(kind)
	var page_count := maxi(ceili(float(ids.size()) / PAGE_SIZE), 1)
	_compendium_page = clampi(page, 0, page_count - 1)
	_search.visible = false
	_breadcrumb.text = "探索图鉴 / %s" % KIND_LABELS[kind]
	_update_back_button()
	_clear_article()
	_add_label(_article, "探索图鉴", 50, FrontendStyle.BROWN_DARK)
	var progress := DiscoveryManager.get_discovery_progress(kind)
	var progress_text := "%s · 已发现 %d / %d" % [KIND_LABELS[kind], progress.discovered, progress.total]
	if _has_active_compendium_filters(kind):
		progress_text += " · 当前 %d 张" % ids.size()
	_add_label(_article, progress_text, 31, FrontendStyle.ORANGE)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 10)
	tabs.add_theme_constant_override("v_separation", 10)
	_article.add_child(tabs)
	for candidate_kind: StringName in COMPENDIUM_KINDS:
		var tab := _add_button(tabs, String(KIND_LABELS[candidate_kind]), Vector2(150, 58))
		tab.toggle_mode = true
		tab.button_pressed = candidate_kind == kind
		tab.pressed.connect(func() -> void: _render_compendium(candidate_kind, 0))
	_add_compendium_filters(kind)
	var grid := GridContainer.new()
	grid.columns = _compendium_column_count()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	_article.add_child(grid)
	var start := _compendium_page * PAGE_SIZE
	var finish := mini(start + PAGE_SIZE, ids.size())
	for index: int in range(start, finish):
		_add_compendium_card(grid, kind, ids[index], index - start)
	if ids.is_empty():
		_add_label(_article, "没有符合筛选的条目" if _has_active_compendium_filters(kind) else "暂无条目", 31, FrontendStyle.BROWN_MUTED)
	_set_footer_visible(true)
	_previous_button.text = "上一页"
	_next_button.text = "下一页"
	_previous_button.disabled = _compendium_page <= 0
	_next_button.disabled = _compendium_page >= page_count - 1
	_progress_label.text = "%d / %d" % [_compendium_page + 1, page_count]
	_disconnect_button(_previous_button)
	_disconnect_button(_next_button)
	_previous_button.pressed.connect(func() -> void: _render_compendium(kind, _compendium_page - 1))
	_next_button.pressed.connect(func() -> void: _render_compendium(kind, _compendium_page + 1))
	_request_current_view_focus()


func _add_compendium_filters(kind: StringName) -> void:
	var facet_specs: Array[Dictionary] = []
	match kind:
		DiscoveryManager.KIND_FEIYI:
			facet_specs = [
				{"title": "地区", "state": &"feiyi_region", "field": &"region_value"},
				{"title": "类别", "state": &"feiyi_category", "field": &"category_value"},
			]
		DiscoveryManager.KIND_FOOD:
			facet_specs = [{"title": "级别", "state": &"food_level", "field": &"level_value"}]
		DiscoveryManager.KIND_SCENERY:
			facet_specs = [{"title": "地区", "state": &"scenery_region", "field": &"region_value"}]
		_:
			return
	var panel := PanelContainer.new()
	panel.name = "CompendiumFilters"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", FrontendStyle.make_box(Color("#F8E7C1"), Color(FrontendStyle.GOLD, 0.55), 2, 13, Vector4(18, 14, 18, 14)))
	_article.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	for spec: Dictionary in facet_specs:
		_add_compendium_filter_facet(
			content,
			String(spec.get("title", "筛选")),
			StringName(spec.get("state", &"")),
			StringName(spec.get("field", &"")),
			kind
		)
	if _has_active_compendium_filters(kind):
		var clear_button := _add_button(content, "清除筛选", Vector2(176, 58))
		clear_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		clear_button.pressed.connect(func() -> void: _clear_compendium_filters(kind))


func _add_compendium_filter_facet(
	parent: Control,
	title: String,
	state_key: StringName,
	field: StringName,
	kind: StringName
) -> void:
	var options := _get_compendium_filter_options(kind, field)
	if options.is_empty():
		return
	var row := HBoxContainer.new()
	row.name = "Filter%s" % String(state_key).to_pascal_case()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var title_label := _add_label(row, title, 27, FrontendStyle.BROWN_DARK)
	title_label.custom_minimum_size = Vector2(82, 56)
	title_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var choices := HFlowContainer.new()
	choices.name = "Choices"
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("h_separation", 8)
	choices.add_theme_constant_override("v_separation", 8)
	row.add_child(choices)
	var selected := _compendium_filters.get(state_key, {}) as Dictionary
	for option: Dictionary in options:
		var option_key := StringName(str(option.get("key", "")))
		var button := _add_button(choices, String(option.get("label", "")), Vector2(104, 56))
		button.name = "Filter%s%s" % [String(state_key).to_pascal_case(), String(option_key)]
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.toggle_mode = true
		button.button_pressed = selected.has(option_key)
		button.toggled.connect(func(pressed: bool) -> void:
			_toggle_compendium_filter(state_key, option_key, pressed, kind)
		)


func _get_compendium_filter_options(kind: StringName, field: StringName) -> Array[Dictionary]:
	var unique: Dictionary = {}
	for entry_id: StringName in DiscoveryManager.get_known_ids(kind):
		var data := _get_entry_data(kind, entry_id)
		var value := int(data.get(field, -1))
		if value < 0 or unique.has(value):
			continue
		var label_field := StringName("%s_label" % String(field).trim_suffix("_value"))
		unique[value] = {
			"key": StringName(str(value)),
			"label": String(data.get(label_field, str(value))),
			"sort": value,
		}
	var options: Array[Dictionary] = []
	for value: Variant in unique.values():
		options.append((value as Dictionary).duplicate())
	options.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return int(first.get("sort", 0)) < int(second.get("sort", 0))
	)
	return options


func _toggle_compendium_filter(state_key: StringName, option_key: StringName, pressed: bool, kind: StringName) -> void:
	var selected := _compendium_filters.get(state_key, {}) as Dictionary
	if pressed:
		selected[option_key] = true
	else:
		selected.erase(option_key)
	_compendium_filters[state_key] = selected
	_render_compendium(kind, 0)


func _clear_compendium_filters(kind: StringName) -> void:
	for state_key: StringName in _filter_state_keys_for_kind(kind):
		_compendium_filters[state_key] = {}
	_render_compendium(kind, 0)


func _filter_state_keys_for_kind(kind: StringName) -> Array[StringName]:
	match kind:
		DiscoveryManager.KIND_FEIYI:
			return [&"feiyi_region", &"feiyi_category"]
		DiscoveryManager.KIND_FOOD:
			return [&"food_level"]
		DiscoveryManager.KIND_SCENERY:
			return [&"scenery_region"]
		_:
			return []


func _has_active_compendium_filters(kind: StringName) -> bool:
	for state_key: StringName in _filter_state_keys_for_kind(kind):
		if not (_compendium_filters.get(state_key, {}) as Dictionary).is_empty():
			return true
	return false


func _get_filtered_compendium_ids(kind: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for entry_id: StringName in DiscoveryManager.get_known_ids(kind):
		if _compendium_entry_matches_filters(kind, entry_id):
			result.append(entry_id)
	return result


func _compendium_entry_matches_filters(kind: StringName, entry_id: StringName) -> bool:
	if not _has_active_compendium_filters(kind):
		return true
	var data := _get_entry_data(kind, entry_id)
	var checks: Array[Dictionary] = []
	match kind:
		DiscoveryManager.KIND_FEIYI:
			checks = [
				{"state": &"feiyi_region", "field": &"region_value"},
				{"state": &"feiyi_category", "field": &"category_value"},
			]
		DiscoveryManager.KIND_FOOD:
			checks = [{"state": &"food_level", "field": &"level_value"}]
		DiscoveryManager.KIND_SCENERY:
			checks = [{"state": &"scenery_region", "field": &"region_value"}]
	for check: Dictionary in checks:
		var selected := _compendium_filters.get(StringName(check.get("state", &"")), {}) as Dictionary
		if selected.is_empty():
			continue
		var value_key := StringName(str(int(data.get(StringName(check.get("field", &"")), -1))))
		if not selected.has(value_key):
			return false
	return true


func _compendium_column_count() -> int:
	if _narrow_layout:
		return 2
	# The first render can happen while the content panel still carries its
	# previous or pre-layout width. The viewport-derived value is a stable lower
	# bound for the actual wide-screen article area.
	var available_width := maxf(
		_content_panel.size.x - 96.0,
		get_viewport_rect().size.x - 610.0
	)
	available_width = maxf(available_width, 640.0)
	if available_width < 1050.0:
		return 2
	if available_width < 1700.0:
		return 3
	return 4


func _add_compendium_card(parent: Control, kind: StringName, entry_id: StringName, local_index: int) -> void:
	var discovered := DiscoveryManager.is_discovered(kind, entry_id)
	var panel := PanelContainer.new()
	panel.name = "Entry%d" % local_index if discovered else "LockedEntry%d" % local_index
	panel.custom_minimum_size = Vector2(280, 470)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", FrontendStyle.make_box(Color("#F6E4BB"), FrontendStyle.GOLD if discovered else FrontendStyle.DISABLED, 3, 15, Vector4(12, 12, 12, 12)))
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	panel.add_child(content)
	var image := TextureRect.new()
	image.custom_minimum_size = Vector2(260, 360)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(image)
	var title := "未发现"
	if discovered:
		var data := _get_entry_data(kind, entry_id)
		title = String(data.get("title", "未命名"))
		image.texture = data.get("texture") as Texture2D
	else:
		image.texture = _get_card_back(kind)
	var title_label := _add_label(content, title, 30, FrontendStyle.BROWN_DARK if discovered else FrontendStyle.BROWN_MUTED)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.custom_minimum_size.y = 64
	if discovered:
		var button := Button.new()
		button.name = "CompendiumCardButton"
		button.flat = true
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.accessibility_name = title
		button.accessibility_description = "打开%s详情" % title
		button.add_theme_stylebox_override("normal", _card_overlay_style(Color.TRANSPARENT, Color.TRANSPARENT, 0))
		button.add_theme_stylebox_override("hover", _card_overlay_style(Color(FrontendStyle.GOLD, 0.06), Color(FrontendStyle.GOLD, 0.86), 3))
		button.add_theme_stylebox_override("focus", _card_overlay_style(Color(FrontendStyle.GOLD, 0.05), Color("#FFF1C7"), 5))
		button.add_theme_stylebox_override("pressed", _card_overlay_style(Color(FrontendStyle.ORANGE, 0.10), FrontendStyle.GOLD, 4))
		panel.add_child(button)
		button.pressed.connect(func() -> void: _render_entry_detail(kind, entry_id))


func _card_overlay_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(15)
	return style


func _render_entry_detail(kind: StringName, entry_id: StringName) -> bool:
	if not DiscoveryManager.is_discovered(kind, entry_id):
		return false
	var data := _get_entry_data(kind, entry_id)
	if data.is_empty():
		return false
	_view_mode = ViewMode.ENTRY
	_close_drawer_for_destination()
	_set_primary_navigation_enabled(true)
	_update_sidebar_selection(&"compendium")
	_current_topic_id = &""
	_current_section_id = &""
	_current_group_id = &""
	_group_navigation.visible = false
	_current_entry_kind = kind
	_current_entry_id = entry_id
	_search.visible = false
	_breadcrumb.text = "探索图鉴 / %s / %s" % [KIND_LABELS.get(kind, "条目"), data.title]
	_update_back_button()
	_clear_article()
	if kind == DiscoveryManager.KIND_FEIYI:
		_render_feiyi_entry_content(entry_id)
	else:
		_render_generic_entry_content(kind, entry_id, data)
	var back := _add_button(_article, "返回%s图鉴" % KIND_LABELS.get(kind, "探索"), Vector2(300, 68))
	back.pressed.connect(func() -> void: _render_compendium(kind, _page_for_entry(kind, entry_id)))
	_set_footer_visible(false)
	_request_current_view_focus()
	return true


func _render_feiyi_entry_content(entry_id: StringName) -> void:
	var card := load(String(entry_id)) as 非遗牌
	if card == null:
		return
	var content: Dictionary = FEIYI_DETAIL_CONTENT_SOURCE.build(card)
	var detail := GUIDE_FEIYI_DETAIL_SCRIPT.new() as GuideFeiyiDetail
	detail.media_preview_requested.connect(_open_media_preview)
	_article.add_child(detail)
	detail.setup(content, _narrow_layout)


func _render_generic_entry_content(kind: StringName, entry_id: StringName, data: Dictionary) -> void:
	_add_label(_article, String(data.get("title", "")), 50, FrontendStyle.BROWN_DARK)
	var texture := data.get("texture") as Texture2D
	if texture != null:
		var media := ManualMediaBlock.new()
		_article.add_child(media)
		media.media_preview_requested.connect(_open_media_preview)
		media.setup([{
			"id": entry_id,
			"layout": "portrait",
			"fit": "contain",
			"min_item_width": 360.0,
			"target_width_ratio": 0.48,
			"items": [{"texture": texture, "path": "", "kind": kind, "id": entry_id, "alt": String(data.get("title", ""))}],
		}], _narrow_layout)
	var description := String(data.get("description", ""))
	if not description.is_empty():
		_add_wrapped_label(_article, description, 30, FrontendStyle.BROWN)


func _render_discovered_search_results(query: String) -> void:
	var normalized := query.strip_edges().to_lower()
	for kind: StringName in COMPENDIUM_KINDS:
		for entry_id: StringName in DiscoveryManager.get_known_ids(kind):
			if not DiscoveryManager.is_discovered(kind, entry_id):
				continue
			var data := _get_entry_data(kind, entry_id)
			var searchable := "%s\n%s" % [data.get("title", ""), data.get("description", "")]
			if normalized not in searchable.to_lower():
				continue
			_add_result_button(
				_article,
				"%s · %s" % [KIND_LABELS[kind], data.get("title", "")],
				func() -> void: _render_entry_detail(kind, entry_id)
			)


func _get_entry_data(kind: StringName, entry_id: StringName) -> Dictionary:
	var cache_key := "%s:%s" % [kind, entry_id]
	if _resource_index.has(cache_key):
		return (_resource_index[cache_key] as Dictionary).duplicate()
	var data: Dictionary = {}
	if kind == DiscoveryManager.KIND_FEIYI:
		var card := load(String(entry_id)) as 非遗牌
		if card != null:
			data = {
				"title": card.card_name,
				"texture": card.image_of_front,
				"description": card.description,
				"region_value": int(card.region),
				"region_label": String(非遗牌.REGION.find_key(card.region)),
				"category_value": int(card.category),
				"category_label": String(非遗牌.CardCategory.find_key(card.category)),
			}
	elif kind == DiscoveryManager.KIND_PROFESSION:
		var definition := ProfessionManager.get_definition_by_id(entry_id)
		if definition != null:
			data = {"title": definition.profession_name, "texture": definition.selection_portrait, "description": definition.description}
	elif kind == DiscoveryManager.KIND_SCENERY:
		_ensure_scenery_index()
		data = (_scenery_index.get(entry_id, {}) as Dictionary).duplicate()
	else:
		var resource := _find_card_resource(kind, entry_id)
		if resource is 卡牌基类:
			var card := resource as 卡牌基类
			var description := card.description
			data = {"title": card.card_name, "texture": card.image_of_front, "description": description}
			if resource is 食物牌:
				var food := resource as 食物牌
				description = food.effect_description
				if not food.ruling_note.is_empty():
					description += "\n\n裁定：%s" % food.ruling_note
				data["level_value"] = int(food.food_type)
				data["level_label"] = String(食物牌.FoodType.find_key(food.food_type))
			data["description"] = description
	_resource_index[cache_key] = data.duplicate()
	return data


func _find_card_resource(kind: StringName, entry_id: StringName) -> Resource:
	_ensure_resource_path_index(kind)
	var cache_key := "%s:%s" % [kind, entry_id]
	var resource_path := String(_resource_path_index.get(cache_key, ""))
	return load(resource_path) if not resource_path.is_empty() else null


func _ensure_resource_path_index(kind: StringName) -> void:
	if _resource_path_index.has(kind):
		return
	_resource_path_index[kind] = true
	var root := String(DiscoveryManager.RESOURCE_ROOTS.get(kind, ""))
	var paths: Array[String] = []
	_collect_paths(root, paths)
	for path: String in paths:
		var resource := load(path)
		var indexed_id: StringName = &""
		if kind == DiscoveryManager.KIND_FOOD and resource is 食物牌:
			indexed_id = (resource as 食物牌).food_id
		elif kind == DiscoveryManager.KIND_EVENT and resource is 事件牌:
			indexed_id = (resource as 事件牌).event_id
		elif kind == DiscoveryManager.KIND_ACHIEVEMENT and resource is 成就牌:
			indexed_id = (resource as 成就牌).achievement_id
		if not indexed_id.is_empty():
			_resource_path_index["%s:%s" % [kind, indexed_id]] = path


func _collect_paths(root: String, output: Array[String]) -> void:
	var directory := DirAccess.open(root)
	if directory == null:
		return
	for child_dir: String in directory.get_directories():
		_collect_paths(root.path_join(child_dir), output)
	for file_name: String in directory.get_files():
		if file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
			output.append(root.path_join(file_name.trim_suffix(".remap")))


func _ensure_scenery_index() -> void:
	if not _scenery_index.is_empty():
		return
	var packed := load("res://地图/map.tscn") as PackedScene
	if packed == null:
		return
	var root := packed.instantiate()
	_collect_scenery_data(root)
	root.free()


func _collect_scenery_data(node: Node) -> void:
	if node is MapSection:
		var section := node as MapSection
		if section.type == MapSection.SectionType.风景:
			var entry_id := StringName("%d,%d,%d" % [section.location_index.x, section.location_index.y, section.location_index.z])
			_scenery_index[entry_id] = {
				"title": section.scenery_name if not section.scenery_name.is_empty() else section.section_name,
				"texture": load("res://arts/地图/地图完整版.png") as Texture2D,
				"description": "%s · %s · 精力消耗%d" % [MapSection.REGION.find_key(section.region), MapSection.LandForm.find_key(section.landform), section.cost],
				"region_value": int(section.region),
				"region_label": String(MapSection.REGION.find_key(section.region)),
			}
	for child: Node in node.get_children():
		_collect_scenery_data(child)


func _get_card_back(kind: StringName) -> Texture2D:
	var path := String(KIND_BACKS.get(kind, ""))
	return load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else null


func _update_topic_footer(topic: ManualTopic) -> void:
	var destinations: Array[Dictionary] = []
	if topic.category == &"quick":
		for quick_topic: ManualTopic in _catalog.get_topics(&"quick"):
			destinations.append({"topic_id": quick_topic.topic_id, "section_id": &""})
	else:
		for rules_topic: ManualTopic in _catalog.get_topics(&"rules"):
			for group: Dictionary in _visible_groups(rules_topic):
				destinations.append({
					"topic_id": rules_topic.topic_id,
					"section_id": StringName(group.get("id", &"")),
				})
	var current_index := -1
	for index: int in range(destinations.size()):
		var destination := destinations[index]
		if StringName(destination.get("topic_id", &"")) == topic.topic_id and (
			topic.category == &"quick" or StringName(destination.get("section_id", &"")) == _current_section_id
		):
			current_index = index
			break
	_set_footer_visible(destinations.size() > 1)
	_previous_button.text = "上一步" if topic.category == &"quick" else "上一节"
	_next_button.text = "下一步" if topic.category == &"quick" else "下一节"
	_previous_button.disabled = current_index <= 0
	_next_button.disabled = current_index < 0 or current_index >= destinations.size() - 1
	_progress_label.text = "%d / %d" % [current_index + 1, destinations.size()]
	_disconnect_button(_previous_button)
	_disconnect_button(_next_button)
	_previous_button.pressed.connect(func() -> void: _open_destination_at(destinations, current_index - 1))
	_next_button.pressed.connect(func() -> void: _open_destination_at(destinations, current_index + 1))


func _open_destination_at(destinations: Array[Dictionary], index: int) -> void:
	if index < 0 or index >= destinations.size():
		return
	var destination := destinations[index]
	_render_topic(StringName(destination.get("topic_id", &"")), StringName(destination.get("section_id", &"")))


func _move_topic(direction: int) -> void:
	if _view_mode != ViewMode.TOPIC or _current_topic_id.is_empty():
		return
	var topic := _catalog.get_topic(_current_topic_id)
	if topic == null:
		return
	if direction < 0 and not _previous_button.disabled:
		_previous_button.pressed.emit()
	elif direction > 0 and not _next_button.disabled:
		_next_button.pressed.emit()


func _open_topic_by_index(category: StringName, index: int) -> void:
	var topics := _catalog.get_topics(category)
	if index >= 0 and index < topics.size():
		_render_topic(topics[index].topic_id)


func _continue_reading() -> void:
	if not _last_read_topic_id.is_empty() and _catalog.has_topic(_last_read_topic_id):
		_render_topic(_last_read_topic_id, _current_section_id if _current_topic_id == _last_read_topic_id else &"")
	else:
		_render_home()


func _open_context_topic() -> void:
	if _context == null:
		_render_home()
		return
	var target := _target_for_kind(_context.object_kind)
	var mapped := _context.topic_id
	var section_id := _context.section_id
	if not _catalog.has_topic(mapped):
		mapped = StringName(target.get("topic_id", &""))
	if section_id.is_empty():
		section_id = StringName(target.get("section_id", &""))
	if _catalog.has_topic(mapped):
		_render_topic(mapped, section_id)
	else:
		_render_home()


func _topic_for_kind(kind: StringName) -> StringName:
	return StringName(_target_for_kind(kind).get("topic_id", &"digital_rulings"))


func _target_for_kind(kind: StringName) -> Dictionary:
	match kind:
		DiscoveryManager.KIND_FEIYI:
			return {"topic_id": &"feiyi_cards", "section_id": &"categories"}
		DiscoveryManager.KIND_FOOD:
			return {"topic_id": &"food_system", "section_id": &"consume_timing"}
		DiscoveryManager.KIND_EVENT:
			return {"topic_id": &"event_response", "section_id": &"draw_discard"}
		DiscoveryManager.KIND_ACHIEVEMENT:
			return {"topic_id": &"achievements", "section_id": &"claiming"}
		DiscoveryManager.KIND_PROFESSION:
			return {"topic_id": &"professions", "section_id": &"food_blogger"}
		DiscoveryManager.KIND_SCENERY:
			return {"topic_id": &"functional_tiles", "section_id": &"scenery_tile"}
		&"map_section":
			return {"topic_id": &"map_movement", "section_id": &"hex_regions"}
		&"market":
			return {"topic_id": &"market_economy", "section_id": &"market_prices"}
		&"score":
			return {"topic_id": &"scoring_victory", "section_id": &"base_score"}
		&"phase":
			return {"topic_id": &"turn_phases", "section_id": &"action_phase"}
		_:
			return {"topic_id": &"digital_rulings", "section_id": &""}


func _context_summary() -> String:
	if _context == null:
		return "当前规则"
	var topic_id := _context.topic_id if _catalog.has_topic(_context.topic_id) else _topic_for_kind(_context.object_kind)
	var topic := _catalog.get_topic(topic_id)
	return topic.title if topic != null else "当前规则"


func _handle_back() -> void:
	if _media_preview.visible:
		_close_media_preview()
		return
	if _narrow_layout and _drawer_open:
		_toggle_drawer()
		return
	match _view_mode:
		ViewMode.HOME:
			close_guide()
		ViewMode.ENTRY:
			_render_compendium(_current_entry_kind, _page_for_entry(_current_entry_kind, _current_entry_id))
		ViewMode.TOPIC:
			var topic := _catalog.get_topic(_current_topic_id) as ManualTopic
			if topic != null and topic.category == &"rules":
				_render_rules_index(_last_rules_query)
			else:
				_render_home()
		ViewMode.RULES_INDEX, ViewMode.COMPENDIUM:
			_render_home()


func _on_search_changed(query: String) -> void:
	if _view_mode == ViewMode.RULES_INDEX:
		_render_rules_index(query, false)


func _toggle_drawer() -> void:
	if not _narrow_layout:
		return
	_drawer_open = not _drawer_open
	_sidebar.visible = _drawer_open
	_content_panel.visible = not _drawer_open
	_drawer_button.text = "返回内容" if _drawer_open else "目录"
	if _drawer_open:
		call_deferred(&"_grab_first_sidebar_focus")
	else:
		_request_current_view_focus()


func _grab_first_sidebar_focus() -> void:
	for button: Button in [_home_button, _quick_button, _rules_button, _compendium_button, _continue_button, _context_button]:
		if button.visible and not button.disabled and button.focus_mode != Control.FOCUS_NONE:
			button.grab_focus()
			return
	_drawer_button.grab_focus()


func _update_sidebar_selection(selected: StringName) -> void:
	var buttons: Dictionary = {
		&"home": _home_button,
		&"quick": _quick_button,
		&"rules": _rules_button,
		&"compendium": _compendium_button,
	}
	var labels: Dictionary = {
		&"home": "指南首页",
		&"quick": "快速上手",
		&"rules": "规则介绍",
		&"compendium": "探索图鉴",
	}
	for key: StringName in buttons:
		var button := buttons[key] as Button
		button.disabled = false
		button.toggle_mode = true
		button.button_pressed = key == selected
		button.text = ("◆ " if key == selected else "") + String(labels[key])


func _update_responsive_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size := size
	var was_narrow := _narrow_layout
	_narrow_layout = viewport_size.x < 1500.0 or viewport_size.x / maxf(viewport_size.y, 1.0) < 1.35
	_drawer_button.visible = _narrow_layout
	_brand.visible = not _narrow_layout
	_search.custom_minimum_size.x = 260.0 if _narrow_layout else 360.0
	if _narrow_layout:
		_media_preview_safe_area.add_theme_constant_override("margin_left", 24)
		_media_preview_safe_area.add_theme_constant_override("margin_top", 20)
		_media_preview_safe_area.add_theme_constant_override("margin_right", 24)
		_media_preview_safe_area.add_theme_constant_override("margin_bottom", 20)
		_safe_area.add_theme_constant_override("margin_left", 20)
		_safe_area.add_theme_constant_override("margin_top", 18)
		_safe_area.add_theme_constant_override("margin_right", 20)
		_safe_area.add_theme_constant_override("margin_bottom", 18)
		_frame.custom_minimum_size = Vector2.ZERO
		_sidebar.visible = _drawer_open
		_content_panel.visible = not _drawer_open
	else:
		_media_preview_safe_area.add_theme_constant_override("margin_left", 72)
		_media_preview_safe_area.add_theme_constant_override("margin_top", 56)
		_media_preview_safe_area.add_theme_constant_override("margin_right", 72)
		_media_preview_safe_area.add_theme_constant_override("margin_bottom", 56)
		# 超宽屏保持约 2560px 的安全内容区，避免规则卡片被横向拉得过散。
		var horizontal_safe_margin := maxi(56, roundi((viewport_size.x - 2560.0) * 0.5))
		_safe_area.add_theme_constant_override("margin_left", horizontal_safe_margin)
		_safe_area.add_theme_constant_override("margin_top", 44)
		_safe_area.add_theme_constant_override("margin_right", horizontal_safe_margin)
		_safe_area.add_theme_constant_override("margin_bottom", 44)
		_frame.custom_minimum_size = Vector2(960, 620)
		_sidebar.visible = true
		_content_panel.visible = true
		_drawer_open = false
		_drawer_button.text = "目录"
	if is_guide_open() and was_narrow != _narrow_layout and not _responsive_rebuild_pending:
		_responsive_rebuild_pending = true
		call_deferred(&"_rebuild_current_view_after_breakpoint")


func _rebuild_current_view_after_breakpoint() -> void:
	if not _responsive_rebuild_pending:
		return
	_responsive_rebuild_pending = false
	if not is_guide_open():
		return
	_drawer_open = false
	_sidebar.visible = not _narrow_layout
	_content_panel.visible = true
	_drawer_button.text = "目录"
	match _view_mode:
		ViewMode.HOME:
			_render_home()
		ViewMode.TOPIC:
			_render_topic(_current_topic_id, _current_section_id)
		ViewMode.RULES_INDEX:
			_render_rules_index(_last_rules_query, false)
		ViewMode.COMPENDIUM:
			_render_compendium(_compendium_kind, _compendium_page)
		ViewMode.ENTRY:
			_render_entry_detail(_current_entry_kind, _current_entry_id)


func _add_home_card(parent: Control, title: String, subtitle: String, media_path: String, callback: Callable) -> Button:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 450)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", FrontendStyle.make_box(Color("#F3DCAC"), Color(FrontendStyle.GOLD, 0.78), 3, 18, Vector4(14, 14, 14, 14)))
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	if ResourceLoader.exists(media_path):
		var media := TextureRect.new()
		media.texture = load(media_path) as Texture2D
		media.custom_minimum_size = Vector2(0, 285)
		media.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		media.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		media.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(media)
	var button := _add_button(content, "%s\n%s" % [title, subtitle], Vector2(0, 128))
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(callback)
	return button


func _add_result_button(parent: Control, title: String, callback: Callable) -> void:
	var button := _add_button(parent, title, Vector2(0, 82))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(callback)


func _add_button(parent: Control, text: String, minimum: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	return button


func _add_label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _add_wrapped_label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := _add_label(parent, text, font_size, color)
	label.custom_minimum_size.x = 0
	return label


func _clear_article() -> void:
	_home_primary_button = null
	_article_transition_serial += 1
	if _article_tween != null and _article_tween.is_valid():
		_article_tween.kill()
	_article_tween = null
	for child: Node in _article.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false
		child.queue_free()
	_article_scroll.scroll_vertical = 0
	_article.modulate.a = 1.0 if _reduce_motion_enabled() or DisplayServer.get_name() == "headless" else 0.0
	call_deferred(&"_play_article_transition", _article_transition_serial)


func _play_article_transition(serial: int) -> void:
	if serial != _article_transition_serial or not is_inside_tree():
		return
	if _reduce_motion_enabled() or DisplayServer.get_name() == "headless":
		_article.modulate.a = 1.0
		return
	_article_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_article_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_article_tween.tween_property(_article, "modulate:a", 1.0, 0.18)


func _reduce_motion_enabled() -> bool:
	return _preferences != null and _preferences.reduce_motion


func _set_footer_visible(shown: bool) -> void:
	_footer.visible = shown
	_footer_line.visible = shown


func _disconnect_button(button: Button) -> void:
	for connection: Dictionary in button.pressed.get_connections():
		var callable := connection.get("callable", Callable()) as Callable
		if callable.is_valid():
			button.pressed.disconnect(callable)


func _grab_article_focus() -> void:
	_request_current_view_focus()


func _grab_first_article_focus() -> void:
	_focus_current_view()


func grab_initial_focus() -> void:
	if _direction_navigation_engaged:
		_focus_current_view()
	else:
		_release_guide_navigation_focus()


func _find_focusable(node: Node) -> Control:
	for child: Node in node.get_children():
		if child is Control:
			var control := child as Control
			var can_focus := control.focus_mode == Control.FOCUS_ALL and control.is_visible_in_tree()
			if control is BaseButton and (control as BaseButton).disabled:
				can_focus = false
			if can_focus:
				return control
		var nested := _find_focusable(child)
		if nested != null:
			return nested
	return null


func _request_current_view_focus() -> void:
	if _direction_navigation_engaged:
		call_deferred(&"_focus_current_view")
	else:
		call_deferred(&"_release_guide_navigation_focus")


func _release_guide_navigation_focus() -> void:
	if not is_inside_tree():
		return
	# 任何较早排队的清焦点请求都不得跨过新的 mouse-down。
	# BaseButton 在按压期间失焦会取消 press_attempt，表现为偶发吞点击。
	if _left_pointer_button_held:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not is_ancestor_of(focused):
		return
	# 搜索框被鼠标明确点中后仍需保留文本输入焦点；普通按钮则不留下白色选框。
	if focused is LineEdit:
		return
	focused.release_focus()


func _is_directional_navigation_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_left") \
		or event.is_action_pressed("ui_right") \
		or event.is_action_pressed("ui_up") \
		or event.is_action_pressed("ui_down")


func _is_pointer_navigation_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return true
	if event is InputEventMouseMotion:
		return (event as InputEventMouseMotion).relative.length_squared() > 0.0
	return false


func _focus_current_view() -> void:
	if not is_guide_open() or screen_state != FrontendScreen.ScreenState.ACTIVE or not is_interaction_enabled() or (_narrow_layout and _drawer_open):
		return
	if _media_preview.visible:
		_media_preview_close.grab_focus()
		return
	var target: Control = null
	match _view_mode:
		ViewMode.HOME:
			target = _home_primary_button
		ViewMode.RULES_INDEX:
			target = _search
		ViewMode.TOPIC:
			target = _active_group_button if _active_group_button != null else (_next_button if _next_button.visible and not _next_button.disabled else _previous_button)
		ViewMode.ENTRY:
			target = _find_focusable(_article)
		_:
			target = _find_focusable(_article)
	if target == null or not target.is_visible_in_tree() or target.focus_mode != Control.FOCUS_ALL:
		target = _back_button if _back_button.visible and not _back_button.disabled else _close_button
	if target != null:
		target.grab_focus()


func _on_screen_transition_finished(state: FrontendScreen.ScreenState) -> void:
	if state == FrontendScreen.ScreenState.ACTIVE and _focus_after_enter:
		_focus_after_enter = false
		_request_current_view_focus()


func _should_animate(requested: bool) -> bool:
	if not requested or _reduce_motion_enabled():
		return false
	if _force_animations_for_test:
		return true
	return DisplayServer.get_name() != "headless"


func _disable_background_focus() -> void:
	_background_focus_controls.clear()
	_background_focus_modes.clear()
	var scene := get_tree().current_scene
	if scene == null:
		return
	_collect_background_focus(scene)
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and owner != self and not is_ancestor_of(owner):
		owner.release_focus()


func _collect_background_focus(node: Node) -> void:
	for child: Node in node.get_children():
		if child == self or is_ancestor_of(child):
			continue
		if child is Control:
			var control := child as Control
			if control.focus_mode != Control.FOCUS_NONE:
				_background_focus_controls.append(weakref(control))
				_background_focus_modes.append(control.focus_mode)
				control.focus_mode = Control.FOCUS_NONE
		_collect_background_focus(child)


func _restore_background_focus() -> void:
	var count := mini(_background_focus_controls.size(), _background_focus_modes.size())
	for index: int in range(count):
		var control := _background_focus_controls[index].get_ref() as Control
		if control != null and is_instance_valid(control):
			control.focus_mode = _background_focus_modes[index] as Control.FocusMode
	_background_focus_controls.clear()
	_background_focus_modes.clear()


func _close_drawer_for_destination() -> void:
	# An explicit destination render already performed the responsive rebuild;
	# cancel a stale deferred breakpoint refresh so it cannot reopen/close panels
	# after the player's next input.
	_responsive_rebuild_pending = false
	if not _narrow_layout:
		return
	_drawer_open = false
	_sidebar.visible = false
	_content_panel.visible = true
	_drawer_button.text = "目录"


func _update_back_button() -> void:
	# 首页已有右上角关闭按钮；再放一个“关闭”会形成两个同义入口。
	_back_button.visible = _view_mode != ViewMode.HOME
	_back_button.text = "返回"


func _open_media_preview(texture: Texture2D, alt_text: String) -> void:
	if texture == null or not is_guide_open():
		return
	var focused := get_viewport().gui_get_focus_owner()
	_media_preview_focus_return = weakref(focused) if focused != null and is_ancestor_of(focused) else null
	_media_preview_image.texture = texture
	var caption := alt_text.strip_edges()
	_media_preview_caption.text = caption if not caption.is_empty() else "规则配图"
	_frame.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	_media_preview.visible = true
	if _direction_navigation_engaged:
		_media_preview_close.call_deferred(&"grab_focus")
	else:
		call_deferred(&"_release_guide_navigation_focus")
	ui_feedback_requested.emit(&"guide_media_opened")


func _close_media_preview(restore_focus: bool = true) -> void:
	if not _media_preview.visible:
		return
	_media_preview.visible = false
	_media_preview_image.texture = null
	_frame.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	var return_focus: Control = null
	if restore_focus and _media_preview_focus_return != null:
		return_focus = _media_preview_focus_return.get_ref() as Control
	_media_preview_focus_return = null
	if _direction_navigation_engaged and return_focus != null and is_instance_valid(return_focus) and return_focus.is_visible_in_tree() and return_focus.focus_mode != Control.FOCUS_NONE:
		return_focus.call_deferred(&"grab_focus")
	elif _direction_navigation_engaged and restore_focus and is_guide_open():
		_request_current_view_focus()
	elif restore_focus:
		call_deferred(&"_release_guide_navigation_focus")
	ui_feedback_requested.emit(&"guide_media_closed")


func _on_media_preview_root_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (event as InputEventMouseButton).pressed:
		_close_media_preview()
		get_viewport().set_input_as_handled()


func _set_primary_navigation_enabled(enabled: bool) -> void:
	for button: Button in [_home_button, _quick_button, _rules_button, _compendium_button, _continue_button, _context_button]:
		button.disabled = not enabled


func _render_catalog_error(detail: String = "") -> void:
	_close_drawer_for_destination()
	_view_mode = ViewMode.HOME
	_current_topic_id = &""
	_current_section_id = &""
	_current_group_id = &""
	_current_entry_kind = &""
	_current_entry_id = &""
	_group_navigation.visible = false
	_search.visible = false
	_breadcrumb.text = "游戏指南"
	_set_footer_visible(false)
	_set_primary_navigation_enabled(false)
	_update_back_button()
	_clear_article()
	_add_label(_article, "指南内容读取失败", 48, FrontendStyle.BROWN_DARK)
	var message := detail
	if message.is_empty() and _catalog != null:
		message = _catalog.load_error
	if not message.is_empty():
		_add_wrapped_label(_article, message, 28, FrontendStyle.BROWN_MUTED)
	_add_wrapped_label(_article, "可以先关闭指南，稍后再试。", 26, FrontendStyle.BROWN_MUTED)
	_request_current_view_focus()


func _page_for_entry(kind: StringName, entry_id: StringName) -> int:
	var index := _get_filtered_compendium_ids(kind).find(entry_id)
	return int(maxi(index, 0) / PAGE_SIZE)


func _ensure_input_action() -> void:
	if not InputMap.has_action("guide_toggle"):
		InputMap.add_action("guide_toggle")
	var has_f1 := false
	for event: InputEvent in InputMap.action_get_events("guide_toggle"):
		if event is InputEventKey and (event as InputEventKey).keycode == KEY_F1:
			has_f1 = true
	if not has_f1:
		var key := InputEventKey.new()
		key.keycode = KEY_F1
		InputMap.action_add_event("guide_toggle", key)
	var has_gamepad_back := false
	for event: InputEvent in InputMap.action_get_events("guide_toggle"):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_BACK:
			has_gamepad_back = true
	if not has_gamepad_back:
		var gamepad_back := InputEventJoypadButton.new()
		gamepad_back.button_index = JOY_BUTTON_BACK
		InputMap.action_add_event("guide_toggle", gamepad_back)
