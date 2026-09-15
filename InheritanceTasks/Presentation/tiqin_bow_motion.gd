extends RefCounted

## Art-only two-segment arm. Source musical progress is supplied by the task.
## The bow translates at fixed length; the torso and supporting hand never move.
static func sample(progress: float, direction: int, shoulder: Vector2, string_contact: Vector2, closing: float = 0.0) -> Dictionary:
	var p := clampf(progress, 0.0, 1.0)
	var eased := p * p * (3.0 - 2.0 * p)
	var start_x := shoulder.x + 9.0 if direction < 0 else shoulder.x - 18.0
	var end_x := shoulder.x - 18.0 if direction < 0 else shoulder.x + 9.0
	var wrist := Vector2(lerpf(start_x, end_x, eased), string_contact.y - 3.0 - clampf(closing, 0.0, 1.0) * 2.0)
	var reach := wrist - shoulder
	var distance := maxf(0.001, reach.length())
	const UPPER_LENGTH := 18.0
	const FOREARM_LENGTH := 26.0
	var along := (UPPER_LENGTH * UPPER_LENGTH - FOREARM_LENGTH * FOREARM_LENGTH + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, UPPER_LENGTH * UPPER_LENGTH - along * along))
	var axis := reach / distance
	var elbow := shoulder + axis * along + Vector2(-axis.y, axis.x) * height
	var bow_rect := Rect2(wrist - Vector2(11.0, 3.0), Vector2(108.0, 8.0))
	return {"progress": p, "direction": direction, "shoulder": shoulder, "elbow": elbow, "wrist": wrist,
		"bow_rect": bow_rect, "string_contact": string_contact, "bow_grip": wrist, "closing": closing}
