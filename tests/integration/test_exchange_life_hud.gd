extends GutTest

class HudRefreshProbe extends HUD:
	var refreshed_player: PlayerClass = null
	var refreshed_hand_player: PlayerClass = null
	var camera_refresh_count: int = 0

	func _ready() -> void:
		pass

	func _update_player_stats(player: PlayerClass) -> void:
		refreshed_player = player

	func _update_button_states(_phase: TurnManager.TurnPhase) -> void:
		pass

	func refresh_feiyi_list(player: PlayerClass) -> void:
		refreshed_hand_player = player

	func update_camera_view(_duration: float = 0.4) -> void:
		camera_refresh_count += 1

	func _refresh_current_event_list() -> void:
		pass

var _hud: HudRefreshProbe
var _source: PlayerClass
var _target: PlayerClass

func before_each() -> void:
	_hud = HudRefreshProbe.new()
	_source = _make_player(PlayerClass.PlayerCharacter.美食博主)
	_target = _make_player(PlayerClass.PlayerCharacter.商业博主)
	TurnManager.players.assign([_source, _target])
	TurnManager.player_num = 2
	TurnManager.now_player_index = 0
	TurnManager.now_phase = TurnManager.TurnPhase.ACTION
	TurnManager.GameOn = true
	TurnManager.modal_resolution_depth = 0
	EventManager.reset_for_new_game()
	EventManager.bind_runtime(_hud, null)
	EventManager.auto_resolve_choices = true
	EventManager.event_finished.connect(_hud._on_event_modal_closed)

func after_each() -> void:
	TurnManager.turn_timer.stop()
	TurnManager.GameOn = false
	TurnManager.modal_resolution_depth = 0
	TurnManager.players.clear()
	EventManager.reset_for_new_game()
	EventManager.bind_runtime(null, null)
	if EventManager.event_finished.is_connected(_hud._on_event_modal_closed):
		EventManager.event_finished.disconnect(_hud._on_event_modal_closed)
	_hud.free()
	_source.free()
	_target.free()

func test_exchange_life_refreshes_current_player_profile_immediately() -> void:
	var card := load("res://Cards/事件牌/交换人生.tres") as 事件牌

	await EventManager.resolve_event(_source, card)

	assert_eq(_source.player_types, PlayerClass.PlayerCharacter.商业博主)
	assert_eq(_target.player_types, PlayerClass.PlayerCharacter.美食博主)
	assert_eq(_hud.refreshed_player, _source, "事件关闭时应立即刷新当前玩家左侧档案")
	assert_eq(_hud.refreshed_hand_player, _source, "事件结束必须把右侧手牌恢复为当前玩家")

func test_position_swap_refreshes_alt_focus_camera_target() -> void:
	var map := MAP.new()
	var source_section := MapSection.new()
	var target_section := MapSection.new()
	source_section.location_index = Vector3i.ZERO
	target_section.location_index = Vector3i(1, -1, 0)
	source_section.position = Vector2(100.0, 100.0)
	target_section.position = Vector2(500.0, 300.0)
	map.add_child(source_section)
	map.add_child(target_section)
	map.grid_map[source_section.location_index] = source_section
	map.grid_map[target_section.location_index] = target_section
	_source.map = map
	_target.map = map
	_source.now_pos = source_section.location_index
	_target.now_pos = target_section.location_index
	source_section.is_occupied = true
	target_section.is_occupied = true
	var card := load("res://Cards/事件牌/斗转星移.tres") as 事件牌

	await EventManager.resolve_event(_source, card)

	assert_eq(_source.now_pos, target_section.location_index)
	assert_eq(_target.now_pos, source_section.location_index)
	assert_eq(_hud.camera_refresh_count, 1, "换位后应立即重算 ALT 聚焦相机目标")
	_source.map = null
	_target.map = null
	map.free()

func _make_player(character: PlayerClass.PlayerCharacter) -> PlayerClass:
	var player := PlayerClass.new()
	player.player_types = character
	player.sprite_frames = SpriteFrames.new()
	for key: PlayerClass.PlayerCharacter in PlayerClass.PlayerCharacter.values():
		var animation_name := StringName(PlayerClass.PlayerCharacter.find_key(key))
		if not player.sprite_frames.has_animation(animation_name):
			player.sprite_frames.add_animation(animation_name)
		player.立绘精一图组[key] = null
		player.立绘精二图组[key] = null
	return player
