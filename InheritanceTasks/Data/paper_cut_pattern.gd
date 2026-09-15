extends RefCounted

## Four closed negative-space contours in one double-bird/floral composition.
## Geometry is the source of truth for cuts, holes and detached scraps. This
## original game pattern remains subject to craft-reference/art review.
const NAMES: Array[String] = ["左鸟翅羽", "花心花瓣", "右鸟翅羽", "锯齿叶心"]
const PAPER_RECT := Rect2(160,112,680,420)
const SOURCE := "res://InheritanceTasks/Data/paper-cut-geometry-v4.json"

static func contours(source: String = SOURCE) -> Array[PackedVector2Array]:
	if not FileAccess.file_exists(source): return []
	return decode_contours(JSON.parse_string(FileAccess.get_file_as_string(source)))

static func decode_contours(parsed: Variant) -> Array[PackedVector2Array]:
	var output: Array[PackedVector2Array] = []
	# Missing or malformed geometry cannot silently fall back to an unrelated
	# design: the displayed motif, scoring path and cut holes must stay identical.
	if not parsed is Dictionary or int(parsed.get("version",0))!=4: return output
	var raw_paths: Variant = parsed.get("contours",[])
	if not raw_paths is Array or raw_paths.size()!=4: return output
	for raw: Variant in raw_paths:
		if not raw is Array or raw.size()<4: return []
		var exact := PackedVector2Array()
		for point: Variant in raw:
			if not point is Array or point.size()!=2: return []
			if not typeof(point[0]) in [TYPE_INT,TYPE_FLOAT] or not typeof(point[1]) in [TYPE_INT,TYPE_FLOAT]: return []
			var at := Vector2(point[0],point[1])
			if not at.is_finite() or not PAPER_RECT.has_point(at): return []
			exact.append(at)
		if not exact[0].is_equal_approx(exact[-1]) or length(exact)<30.0: return []
		output.append(exact)
	return output

static func length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i: int in path.size()-1: total += path[i].distance_to(path[i+1])
	return total

static func prefix(path: PackedVector2Array, distance: float) -> PackedVector2Array:
	var result := PackedVector2Array([path[0]])
	for i: int in path.size()-1:
		var part := path[i].distance_to(path[i+1])
		if distance <= part:
			result.append(path[i].lerp(path[i+1],distance/maxf(.001,part)))
			break
		result.append(path[i+1])
		distance -= part
	return result
