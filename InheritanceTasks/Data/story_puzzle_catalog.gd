extends RefCounted

## Independently abridged local legends; articles and illustrations are not redistributed.
const STORIES: Array[Dictionary] = [
	{"id":"water_cow", "title":"水牛洞", "source":"https://news.hubeidaily.net/pc/c_2714369.html", "scenes":[
		{"title":"调牛助耕", "text":"相传士兵开荒时缺少耕牛，刘备调来水牛，帮他们犁田。"},
		{"title":"牧牛入洞", "text":"牧牛人发现一座干爽的大洞，夜里把牛群赶进去歇息。"},
		{"title":"逃牛留名", "text":"战后，几头牛从洞尾逃走。人们把关过牛的岩洞叫作水牛洞。"}]},
	{"id":"tribute_rice", "title":"秀水贡米", "source":"https://news.hubeidaily.net/mobile/c_2999822.html", "scenes":[
		{"title":"故乡尝米", "text":"相传赵勉回乡探亲，尝到了甘甜可口的秀水米饭。"},
		{"title":"携米入宫", "text":"他把秀水大米带进皇宫，让皇帝也尝尝家乡的滋味。"},
		{"title":"米香获赞", "text":"皇帝尝后称赞，把秀水大米封为贡米，乡间传下这段佳话。"}]},
	{"id":"dragon_temple", "title":"蛟龙寺", "source":"https://news.hubeidaily.net/pc/c_3216991.html", "scenes":[
		{"title":"鸟问寺中人", "text":"传说百灵鸟日日问和尚是否满百人，长老一日随口答有了。"},
		{"title":"双蛟洪水", "text":"鸟飞走后，双蛟随暴雨洪水出山，高梁寺和僧人被洪水吞没。"},
		{"title":"建寺追念", "text":"后来人们修起小寺，追念遇难的僧人，叫它蛟龙寺。"}]},
]
const ART_ROOT := "res://InheritanceTasks/Art/Pixel/v3/runtime/story-detail-v4/"
const BANK_PATH := "res://InheritanceTasks/Data/story-puzzle-bank-v1.json"
static var _bank: Dictionary = {}

static func candidate(rng: RandomNumberGenerator, scene: int) -> Dictionary:
	if _bank.is_empty():
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(BANK_PATH))
		if value is Dictionary: _bank = value
	var depth := rng.randi_range(10 + scene * 2, 12 + scene * 2)
	var entries: Array = _bank.get("by_depth", {}).get(str(depth), [])
	if entries.is_empty(): return {}
	var entry: Dictionary = entries[rng.randi_range(0, entries.size() - 1)].duplicate(true)
	entry["depth"] = depth
	return entry

static func image_path(story: int, scene: int) -> String:
	return ART_ROOT + str(STORIES[story].id) + "-%d.png" % (scene + 1)
