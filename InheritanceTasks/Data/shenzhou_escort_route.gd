extends RefCounted

const LENGTH: float = 7200.0
const MIN_SPEED: float = 100.0
const MAX_SPEED: float = 320.0
const LANE_SECONDS: float = .32
const ACCELERATION: float = 180.0
const DECELERATION: float = 360.0
const COLLISION_HALF_LENGTH: float = 120.0
const COLLISION_HALF_WIDTH: float = .44
## Readable slalom: successive mandatory openings move only one lane.
## 550-unit spacing leaves 310 units after hull clearance: even at 320 speed
## that permits a 0.45s reaction, a 0.32s lane change and ~0.2s extra margin.
## Close decorative rows share the current safe lane; never demand 2→0 jumps.
const ROWS: Array[Dictionary] = [
	{"distance":700.0,"lanes":[1],"kind":"boat"},
	{"distance":1250.0,"lanes":[0,2],"kind":"boat"},
	{"distance":1800.0,"lanes":[0,1],"kind":"boat"},
	{"distance":2150.0,"lanes":[0],"kind":"driftwood"},
	{"distance":2700.0,"lanes":[0,2],"kind":"boat"},
	{"distance":3250.0,"lanes":[1,2],"kind":"boat"},
	{"distance":3650.0,"lanes":[2],"kind":"driftwood"},
	{"distance":4200.0,"lanes":[0,2],"kind":"boat"},
	{"distance":4750.0,"lanes":[0,1],"kind":"boat"},
	{"distance":5100.0,"lanes":[0],"kind":"driftwood"},
	{"distance":5650.0,"lanes":[0,2],"kind":"boat"},
	{"distance":6200.0,"lanes":[1,2],"kind":"boat"},
	{"distance":6600.0,"lanes":[2],"kind":"driftwood"},
	{"distance":7000.0,"lanes":[2],"kind":"boat"},
]

static func approaching_turn(distance: float) -> bool:
	for row: Dictionary in ROWS:
		if row.lanes.size() == 2 and row.distance-distance > 0.0 and row.distance-distance < 550.0:
			return true
	return false

static func obstacles() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for i: int in ROWS.size():
		for lane: int in ROWS[i].lanes:
			list.append({"id":"row_%d_lane_%d" % [i,lane],"distance":float(ROWS[i].distance),"lane":lane,"kind":ROWS[i].kind})
	return list

static func swept_hit(from: Vector2, to: Vector2, obstacle: Dictionary) -> bool:
	# Liang-Barsky segment/AABB intersection in lane and route coordinates.
	var low := Vector2(float(obstacle.lane)-COLLISION_HALF_WIDTH,float(obstacle.distance)-COLLISION_HALF_LENGTH)
	var high := Vector2(float(obstacle.lane)+COLLISION_HALF_WIDTH,float(obstacle.distance)+COLLISION_HALF_LENGTH)
	var t0 := 0.0
	var t1 := 1.0
	var change := to-from
	for axis: int in 2:
		if absf(change[axis]) < .000001:
			if from[axis] < low[axis] or from[axis] > high[axis]: return false
		else:
			var a := (low[axis]-from[axis])/change[axis]
			var b := (high[axis]-from[axis])/change[axis]
			t0 = maxf(t0,minf(a,b))
			t1 = minf(t1,maxf(a,b))
			if t0 > t1: return false
	return true
