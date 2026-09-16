extends "res://tools/promotion-video/demo_map.gd"
var capture_mode:String
func _apply_legacy_player_setup(player:PlayerClass,config:Dictionary,index:int)->void:
	super._apply_legacy_player_setup(player,config,index)
	if index!=0 or capture_mode not in ["market","event"]: return
	var grid=get_tree().get_nodes_in_group("MAP")[0].grid_map
	var kind=MapSection.SectionType.研究所 if capture_mode=="market" else MapSection.SectionType.事件
	for target in grid.values():
		if target.type!=kind:continue
		for section in grid.values():
			var delta:Vector3i=section.location_index-target.location_index
			if maxi(absi(delta.x),maxi(absi(delta.y),absi(delta.z)))==1:
				player.start_coord=section.location_index;return
