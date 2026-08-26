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
@onready var _drawer_button: Button = %DrawerButton
@onready var _close_button: Button = %CloseButton
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

var _catalog: ManualCatalog
var _context: GuideOpenContext = null
var _view_mode: ViewMode = ViewMode.HOME
var _current_topic_id: StringName = &""
var _current_entry_kind: StringName = &""
var _current_entry_id: StringName = &""
var _compendium_kind: StringName = DiscoveryManager.KIND_FEIYI
var _compendium_page: int = 0
var _details_expanded: bool = false
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


func _ready() -> void:
	super._ready()
	_catalog = ManualCatalog.load_generated()
	if not _catalog.validate().is_empty():
		push_error("数字版游戏指南目录存在无效关联。")
	_ensure_input_action()
	_close_button.pressed.connect(close_guide)
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
	back_requested.connect(_handle_back)
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
		_context = context if context != null else GuideOpenContext.new()
		_continue_button.visible = not _last_read_topic_id.is_empty() and _catalog.has_topic(_last_read_topic_id)
		_context_button.visible = _context.source != GuideOpenContext.Source.MAIN_MENU
		_open_context_destination()
		var animate_reopen := animated and not _was_tree_paused and DisplayServer.get_name() != "headless"
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
	_continue_button.visible = not _last_read_topic_id.is_empty() and _catalog.has_topic(_last_read_topic_id)
	_context_button.visible = _context.source != GuideOpenContext.Source.MAIN_MENU
	_open_context_destination()
	var animate_open := animated and not _was_tree_paused and DisplayServer.get_name() != "headless"
	# 全屏遮罩出现前先暂停后台；FrontendScreen 的 Tween 使用 PROCESS 模式，
	# 因而仍能在暂停树中完成入场动画。
	_take_tree_pause()
	enter_screen(animate_open)
	guide_opened.emit(_context)
	return true


func close_guide(animated: bool = true) -> void:
	if not _opened or _closing:
		return
	_lifecycle_serial += 1
	var close_serial := _lifecycle_serial
	_closing = true
	var animate_close := animated and not _was_tree_paused and DisplayServer.get_name() != "headless"
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


func navigate_to(topic_id: StringName, entry_id: StringName = &"") -> bool:
	if not entry_id.is_empty() and _context != null and not _context.object_kind.is_empty():
		return _render_entry_detail(_context.object_kind, entry_id)
	if not _catalog.has_topic(topic_id):
		return false
	_render_topic(topic_id)
	return true


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("guide_toggle"):
		return
	if is_guide_open():
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


func _unhandled_input(event: InputEvent) -> void:
	if not is_guide_open():
		return
	if event.is_action_pressed("guide_toggle"):
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
	var closed_context := _context
	var owned_tree_pause := _owns_tree_pause
	_opened = false
	_closing = false
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
	if _context == null:
		_render_home()
		return
	if not _context.object_id.is_empty() and not _context.object_kind.is_empty():
		if _render_entry_detail(_context.object_kind, _context.object_id):
			return
	if _catalog.has_topic(_context.topic_id) and _context.topic_id != &"guide_home":
		_render_topic(_context.topic_id)
	else:
		_render_home()


func _render_home() -> void:
	_view_mode = ViewMode.HOME
	_update_sidebar_selection(&"home")
	_current_topic_id = &""
	_search.visible = false
	_breadcrumb.text = "首页"
	_set_footer_visible(false)
	_clear_article()
	_add_label(_article, "从这里出发", 54, FrontendStyle.BROWN_DARK)
	_add_label(_article, "先看懂一回合，再按主题查规则；玩过的内容会逐步翻开探索图鉴。", 32, FrontendStyle.BROWN_MUTED)
	var cards := GridContainer.new()
	cards.columns = 1 if _narrow_layout else 3
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("h_separation", 18)
	cards.add_theme_constant_override("v_separation", 18)
	_article.add_child(cards)
	_add_home_card(cards, "3分钟上手", "六步了解核心玩法", "res://arts/地图/地图完整版.png", func() -> void: _open_topic_by_index(&"quick", 0))
	_add_home_card(cards, "规则图鉴", "按主题查找正式裁定", "res://arts/事件卡/事件牌（牌背）.png", _render_rules_index)
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
	_grab_article_focus()


func _render_rules_index(query: String = "", focus_results: bool = true) -> void:
	_view_mode = ViewMode.RULES_INDEX
	_update_sidebar_selection(&"rules")
	_current_topic_id = &""
	_search.visible = true
	_breadcrumb.text = "规则图鉴"
	_set_footer_visible(false)
	_clear_article()
	_add_label(_article, "规则图鉴", 50, FrontendStyle.BROWN_DARK)
	_add_label(_article, "按主题浏览，或搜索公开规则与已经发现的条目。", 29, FrontendStyle.BROWN_MUTED)
	var results := _catalog.search(query, &"rules")
	for topic: ManualTopic in results:
		_add_result_button(_article, topic.title, topic.summary, func() -> void: _render_topic(topic.topic_id))
	if not query.strip_edges().is_empty():
		_render_discovered_search_results(query)
	if results.is_empty() and _article.get_child_count() <= 2:
		_add_label(_article, "没有找到相关规则", 30, FrontendStyle.BROWN_MUTED)
	if focus_results:
		_grab_article_focus()


func _render_topic(topic_id: StringName) -> void:
	var topic := _catalog.get_topic(topic_id)
	if topic == null:
		_render_home()
		return
	_view_mode = ViewMode.TOPIC
	_update_sidebar_selection(&"quick" if topic.category == &"quick" else &"rules")
	_current_topic_id = topic_id
	_details_expanded = false
	_search.visible = false
	_breadcrumb.text = ("3分钟上手 / " if topic.category == &"quick" else "规则图鉴 / ") + topic.title
	_clear_article()
	_add_label(_article, topic.title, 52, FrontendStyle.BROWN_DARK)
	_add_label(_article, topic.summary, 32, FrontendStyle.ORANGE)
	var has_details := false
	for section: ManualSection in topic.sections:
		if section.kind == ManualSection.Kind.DETAIL:
			has_details = true
			continue
		_add_manual_section(section)
	if has_details:
		var detail_button := _add_button(_article, "详细规则", Vector2(260, 68))
		detail_button.pressed.connect(func() -> void:
			_details_expanded = not _details_expanded
			_render_topic_with_detail(topic_id)
		)
	_add_related_topics(topic)
	_last_read_topic_id = topic_id
	if not _reading_history.has(topic_id):
		_reading_history.append(topic_id)
	_continue_button.visible = true
	_update_topic_footer(topic)
	topic_opened.emit(topic_id)
	_grab_article_focus()


func _render_topic_with_detail(topic_id: StringName) -> void:
	var expanded := _details_expanded
	var topic := _catalog.get_topic(topic_id)
	if topic == null:
		return
	_view_mode = ViewMode.TOPIC
	_update_sidebar_selection(&"quick" if topic.category == &"quick" else &"rules")
	_search.visible = false
	_clear_article()
	_add_label(_article, topic.title, 52, FrontendStyle.BROWN_DARK)
	_add_label(_article, topic.summary, 32, FrontendStyle.ORANGE)
	for section: ManualSection in topic.sections:
		if section.kind != ManualSection.Kind.DETAIL or expanded:
			_add_manual_section(section)
	var detail_button := _add_button(_article, "收起详细规则" if expanded else "详细规则", Vector2(300, 68))
	detail_button.pressed.connect(func() -> void:
		_details_expanded = not expanded
		_render_topic_with_detail(topic_id)
	)
	_add_related_topics(topic)
	_update_topic_footer(topic)
	_grab_article_focus()


func _add_manual_section(section: ManualSection) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", FrontendStyle.make_box(Color("#FFF4D8"), Color(FrontendStyle.GOLD, 0.72), 2, 16, Vector4(24, 20, 24, 20)))
	_article.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	if not section.title.is_empty():
		_add_label(content, section.title, 37, FrontendStyle.BROWN_DARK)
	if section.kind == ManualSection.Kind.FLOW:
		var flow_demo := GuideFlowDemo.new()
		flow_demo.custom_minimum_size = Vector2(0, 90)
		flow_demo.setup(section.title, _preferences != null and _preferences.reduce_motion)
		content.add_child(flow_demo)
	if not section.media_path.is_empty() and ResourceLoader.exists(section.media_path):
		var media := TextureRect.new()
		media.texture = load(section.media_path) as Texture2D
		media.custom_minimum_size = Vector2(0, 310 if not _narrow_layout else 220)
		media.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		media.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		media.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(media)
	if not section.body.is_empty():
		_add_wrapped_label(content, section.body, 29, FrontendStyle.BROWN)
	for item: String in section.items:
		_add_wrapped_label(content, "• %s" % item, 27, FrontendStyle.BROWN_MUTED)


func _add_related_topics(topic: ManualTopic) -> void:
	if topic.related_topic_ids.is_empty():
		return
	_add_label(_article, "相关规则", 30, FrontendStyle.BROWN_MUTED)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 12)
	_article.add_child(row)
	for topic_id: StringName in topic.related_topic_ids:
		var related := _catalog.get_topic(topic_id)
		if related == null:
			continue
		var button := _add_button(row, related.title, Vector2(240, 62))
		button.pressed.connect(func() -> void: _render_topic(topic_id))


func _render_compendium(kind: StringName, page: int) -> void:
	if not COMPENDIUM_KINDS.has(kind):
		kind = DiscoveryManager.KIND_FEIYI
	_view_mode = ViewMode.COMPENDIUM
	_update_sidebar_selection(&"compendium")
	_current_topic_id = &""
	_current_entry_kind = &""
	_current_entry_id = &""
	_compendium_kind = kind
	var ids := DiscoveryManager.get_known_ids(kind)
	var page_count := maxi(ceili(float(ids.size()) / PAGE_SIZE), 1)
	_compendium_page = clampi(page, 0, page_count - 1)
	_search.visible = false
	_breadcrumb.text = "探索图鉴 / %s" % KIND_LABELS[kind]
	_clear_article()
	_add_label(_article, "探索图鉴", 50, FrontendStyle.BROWN_DARK)
	var progress := DiscoveryManager.get_discovery_progress(kind)
	_add_label(_article, "%s · 已发现 %d / %d" % [KIND_LABELS[kind], progress.discovered, progress.total], 30, FrontendStyle.ORANGE)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 10)
	tabs.add_theme_constant_override("v_separation", 10)
	_article.add_child(tabs)
	for candidate_kind: StringName in COMPENDIUM_KINDS:
		var tab := _add_button(tabs, String(KIND_LABELS[candidate_kind]), Vector2(150, 58))
		tab.disabled = candidate_kind == kind
		tab.pressed.connect(func() -> void: _render_compendium(candidate_kind, 0))
	var grid := GridContainer.new()
	grid.columns = 2 if _narrow_layout else 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	_article.add_child(grid)
	var start := _compendium_page * PAGE_SIZE
	var finish := mini(start + PAGE_SIZE, ids.size())
	for index: int in range(start, finish):
		_add_compendium_card(grid, kind, ids[index], index - start)
	if ids.is_empty():
		_add_label(_article, "暂无条目", 30, FrontendStyle.BROWN_MUTED)
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
	_grab_article_focus()


func _add_compendium_card(parent: Control, kind: StringName, entry_id: StringName, local_index: int) -> void:
	var discovered := DiscoveryManager.is_discovered(kind, entry_id)
	var panel := PanelContainer.new()
	panel.name = "Entry%d" % local_index if discovered else "LockedEntry%d" % local_index
	panel.custom_minimum_size = Vector2(235, 330)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", FrontendStyle.make_box(Color("#F6E4BB"), FrontendStyle.GOLD if discovered else FrontendStyle.DISABLED, 3, 15, Vector4(12, 12, 12, 12)))
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	panel.add_child(content)
	var image := TextureRect.new()
	image.custom_minimum_size = Vector2(180, 235)
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
	var button := _add_button(content, title, Vector2(0, 62))
	button.disabled = not discovered
	button.tooltip_text = "" if not discovered else title
	if discovered:
		button.pressed.connect(func() -> void: _render_entry_detail(kind, entry_id))


func _render_entry_detail(kind: StringName, entry_id: StringName) -> bool:
	if not DiscoveryManager.is_discovered(kind, entry_id):
		return false
	var data := _get_entry_data(kind, entry_id)
	if data.is_empty():
		return false
	_view_mode = ViewMode.ENTRY
	_update_sidebar_selection(&"compendium")
	_current_entry_kind = kind
	_current_entry_id = entry_id
	_search.visible = false
	_breadcrumb.text = "探索图鉴 / %s / %s" % [KIND_LABELS.get(kind, "条目"), data.title]
	_clear_article()
	_add_label(_article, String(data.title), 50, FrontendStyle.BROWN_DARK)
	var texture := data.get("texture") as Texture2D
	if texture != null:
		var image := TextureRect.new()
		image.texture = texture
		image.custom_minimum_size = Vector2(0, 460 if not _narrow_layout else 300)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_article.add_child(image)
	var description := String(data.get("description", ""))
	if not description.is_empty():
		_add_wrapped_label(_article, description, 30, FrontendStyle.BROWN)
	var back := _add_button(_article, "返回%s图鉴" % KIND_LABELS.get(kind, "探索"), Vector2(300, 68))
	back.pressed.connect(func() -> void: _render_compendium(kind, _page_for_entry(kind, entry_id)))
	_set_footer_visible(false)
	_grab_article_focus()
	return true


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
				String(data.get("description", "")).left(60),
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
			data = {"title": card.card_name, "texture": card.image_of_front, "description": card.description}
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
			if resource is 食物牌:
				var food := resource as 食物牌
				description = food.effect_description
				if not food.ruling_note.is_empty():
					description += "\n\n裁定：%s" % food.ruling_note
			data = {"title": card.card_name, "texture": card.image_of_front, "description": description}
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
			}
	for child: Node in node.get_children():
		_collect_scenery_data(child)


func _get_card_back(kind: StringName) -> Texture2D:
	var path := String(KIND_BACKS.get(kind, ""))
	return load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else null


func _update_topic_footer(topic: ManualTopic) -> void:
	var topics := _catalog.get_topics(topic.category)
	var index := topics.find(topic)
	_set_footer_visible(topics.size() > 1)
	_previous_button.text = "上一步" if topic.category == &"quick" else "上一条"
	_next_button.text = "下一步" if topic.category == &"quick" else "下一条"
	_previous_button.disabled = index <= 0
	_next_button.disabled = index < 0 or index >= topics.size() - 1
	_progress_label.text = "%d / %d" % [index + 1, topics.size()]
	_disconnect_button(_previous_button)
	_disconnect_button(_next_button)
	_previous_button.pressed.connect(func() -> void: _open_topic_by_index(topic.category, index - 1))
	_next_button.pressed.connect(func() -> void: _open_topic_by_index(topic.category, index + 1))


func _move_topic(direction: int) -> void:
	if _view_mode != ViewMode.TOPIC or _current_topic_id.is_empty():
		return
	var topic := _catalog.get_topic(_current_topic_id)
	if topic == null:
		return
	var topics := _catalog.get_topics(topic.category)
	_open_topic_by_index(topic.category, topics.find(topic) + direction)


func _open_topic_by_index(category: StringName, index: int) -> void:
	var topics := _catalog.get_topics(category)
	if index >= 0 and index < topics.size():
		_render_topic(topics[index].topic_id)


func _continue_reading() -> void:
	if not _last_read_topic_id.is_empty() and _catalog.has_topic(_last_read_topic_id):
		_render_topic(_last_read_topic_id)
	else:
		_render_home()


func _open_context_topic() -> void:
	if _context == null:
		_render_home()
		return
	var mapped := _context.topic_id
	if not _catalog.has_topic(mapped):
		mapped = _topic_for_kind(_context.object_kind)
	if _catalog.has_topic(mapped):
		_render_topic(mapped)
	else:
		_render_home()


func _topic_for_kind(kind: StringName) -> StringName:
	match kind:
		DiscoveryManager.KIND_FEIYI:
			return &"feiyi_cards"
		DiscoveryManager.KIND_FOOD:
			return &"food_system"
		DiscoveryManager.KIND_EVENT:
			return &"event_response"
		DiscoveryManager.KIND_ACHIEVEMENT:
			return &"achievements"
		DiscoveryManager.KIND_PROFESSION:
			return &"professions"
		DiscoveryManager.KIND_SCENERY, &"map_section":
			return &"map_movement"
		&"market":
			return &"market_economy"
		&"score":
			return &"scoring_victory"
		&"phase":
			return &"turn_phases"
		_:
			return &"digital_rulings"


func _context_summary() -> String:
	if _context == null:
		return "当前规则"
	var topic_id := _context.topic_id if _catalog.has_topic(_context.topic_id) else _topic_for_kind(_context.object_kind)
	var topic := _catalog.get_topic(topic_id)
	return topic.title if topic != null else "当前规则"


func _handle_back() -> void:
	if _narrow_layout and _drawer_open:
		_toggle_drawer()
		return
	match _view_mode:
		ViewMode.HOME:
			close_guide()
		ViewMode.ENTRY:
			_render_compendium(_current_entry_kind, _page_for_entry(_current_entry_kind, _current_entry_id))
		_:
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
		_grab_first_sidebar_focus()
	else:
		_grab_article_focus()


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
		&"quick": "3分钟上手",
		&"rules": "规则图鉴",
		&"compendium": "探索图鉴",
	}
	for key: StringName in buttons:
		var button := buttons[key] as Button
		button.disabled = key == selected
		button.text = ("◆ " if key == selected else "") + String(labels[key])


func _update_responsive_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size := size
	_narrow_layout = viewport_size.x < 1500.0 or viewport_size.x / maxf(viewport_size.y, 1.0) < 1.35
	_drawer_button.visible = _narrow_layout
	if _narrow_layout:
		_safe_area.add_theme_constant_override("margin_left", 20)
		_safe_area.add_theme_constant_override("margin_top", 18)
		_safe_area.add_theme_constant_override("margin_right", 20)
		_safe_area.add_theme_constant_override("margin_bottom", 18)
		_frame.custom_minimum_size = Vector2(720, 560)
		_sidebar.visible = _drawer_open
		_content_panel.visible = not _drawer_open
	else:
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
	if is_guide_open():
		match _view_mode:
			ViewMode.HOME:
				_render_home()
			ViewMode.COMPENDIUM:
				_render_compendium(_compendium_kind, _compendium_page)
			_:
				pass


func _add_home_card(parent: Control, title: String, subtitle: String, media_path: String, callback: Callable) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 390)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", FrontendStyle.make_box(Color("#F3DCAC"), Color(FrontendStyle.GOLD, 0.78), 3, 18, Vector4(14, 14, 14, 14)))
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	if ResourceLoader.exists(media_path):
		var media := TextureRect.new()
		media.texture = load(media_path) as Texture2D
		media.custom_minimum_size = Vector2(0, 235)
		media.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		media.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		media.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(media)
	var button := _add_button(content, "%s\n%s" % [title, subtitle], Vector2(0, 120))
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(callback)


func _add_result_button(parent: Control, title: String, subtitle: String, callback: Callable) -> void:
	var button := _add_button(parent, "%s\n%s" % [title, subtitle], Vector2(0, 104))
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
	call_deferred(&"_grab_first_article_focus")


func _grab_first_article_focus() -> void:
	if not is_guide_open() or screen_state != FrontendScreen.ScreenState.ACTIVE or not is_interaction_enabled() or (_narrow_layout and _drawer_open):
		return
	var focusable := _find_focusable(_article)
	if focusable != null:
		focusable.grab_focus()
	else:
		_close_button.grab_focus()


func _find_focusable(node: Node) -> Control:
	for child: Node in node.get_children():
		if child is Control:
			var control := child as Control
			var can_focus := control.focus_mode != Control.FOCUS_NONE and control.is_visible_in_tree()
			if control is BaseButton and (control as BaseButton).disabled:
				can_focus = false
			if can_focus:
				return control
		var nested := _find_focusable(child)
		if nested != null:
			return nested
	return null


func _page_for_entry(kind: StringName, entry_id: StringName) -> int:
	var index := DiscoveryManager.get_known_ids(kind).find(entry_id)
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
