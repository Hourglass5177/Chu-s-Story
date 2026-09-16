extends "res://main_map.gd"

# Initial capture fixture only; all subsequent movement uses the real map.
func _apply_legacy_player_setup(player: PlayerClass, config: Dictionary, index: int) -> void:
	var valid := config.duplicate()
	valid.location = "孝感" if index == 0 else "随州"
	super._apply_legacy_player_setup(player,valid,index)
	if index == 0:
		for section: Node in get_tree().get_nodes_in_group("MAP")[0].grid_map.values():
			if section is MapSection and section.section_name == "武汉0":
				player.start_coord = section.location_index
				break
