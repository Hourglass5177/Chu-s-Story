class_name FrontendSessionLauncher
extends RefCounted

## Narrow boundary between front-end flow and the running game session. Keeping the
## boundary injectable lets loading/error behavior be verified without replacing
## the active GUT scene tree.


func prepare_local_session(setup: SessionSetup) -> Error:
	return GameManager.begin_local_session(setup)


func change_to_game_scene(tree: SceneTree, scene_path: String) -> Error:
	if tree == null:
		return ERR_UNCONFIGURED
	return tree.change_scene_to_file(scene_path)


func rollback_session() -> void:
	GameManager.reset_session()
