class_name TutorialDefinition
extends RefCounted

const VERSION := 1
const START := Vector3i(10, -13, 3)
const DESTINATION := Vector3i(11, -13, 2)
const CARD := preload("res://Cards/非遗牌/天门/天门糖塑.tres")
const FOOD := preload("res://Cards/食物牌/云梦鱼面.tres")
const TITLES := ["准备出发", "走到非遗点", "收集非遗", "补充精力", "认识传承", "看看分数", "结束回合", "入门完成"]
const PROMPTS := ["一起收集第一张非遗吧。", "点亮起的非遗点。", "收集一次，消耗1点精力。", "吃一份鱼面，恢复精力。", "打开收藏中的天门糖塑。", "点总分，看看刚获得的5分。", "准备好了，就结束回合。", "移动 → 收集 → 补给 → 结束"]
const HINTS := ["这是一段练习，不影响正式对局。", "点数是最多可走步数，不必走满。", "右下方的“收集非遗”可以拿到一张牌。", "打开“食物”，再点鱼面下的“享用”。", "打开天门糖塑，再点“传承任务”。", "积分点用来购买，总分决定胜负。", "先关闭弹窗，再点右下方“结束回合”。", "详细规则可以随时在游戏说明中查看。"]

static func make_setup() -> SessionSetup:
	var setup := SessionSetup.new(SessionSetup.GameMode.TUTORIAL, 1, 0)
	setup.players[0].display_name = "初行旅人"
	setup.players[0].profession_type = PlayerClass.PlayerCharacter.生活博主
	setup.players[0].starting_region = MapSection.REGION.荆州
	return setup
