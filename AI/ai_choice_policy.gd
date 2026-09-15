class_name AIChoicePolicy
extends RefCounted

## Every event ID has an explicit intent, including cards with no selectable effect.
const EVENT_INTENTS: Dictionary = {
	"zuo_shou_yu_li": "work", "bai_ge_zheng_liu": "team", "pou_duo_yi_gua": "balance_money",
	"gu_zhu_yi_zhi": "skill_block", "ba_geng_xie_ye": "work_block", "yi_chuang_zeng_shou": "income",
	"wen_hua_xin_feng": "reward", "jiao_huan_ren_sheng": "profession_swap", "mei_mei_yu_gong": "heal",
	"yang_jing_xu_rui": "rest", "cun_bu_nan_xing": "attack", "jing_pi_li_jin": "energy_loss",
	"bi_men_xie_ke": "scenery_block", "juan_yi_xiu_zheng": "optional_rest", "chen_jin_ti_yan": "scenery",
	"yi_wai_zhi_xi": "draw_food", "xin_huo_xiang_chuan": "give", "you_shi_tong_xiang": "reward",
	"chuan_yi_hu_jian": "steal", "yi_cang_hu_huan": "exchange", "tai_jiu_huan_xin": "discard",
	"wen_hua_gong_xiang": "attack", "tong_tai_jing_ji": "duel", "yi_shi_hui_you": "food_swap",
	"gu_di_chong_you": "return", "dou_zhuan_xing_yi": "position_swap", "ri_xing_qian_li": "teleport",
	"yi_jing_xun_zong": "move_collect", "tong_xing_feng_cai": "position_swap", "guo_bao_hu_hang": "free_move",
	"jin_ji_bi_xian": "discard", "jian_wang_zhi_lai": "market", "fu_di_chou_xin": "attack",
	"zhan_yi_gong_yan": "discard", "shi_ji_tao_zhen": "market", "jin_chan_tuo_qiao": "cancel",
	"yi_hua_jie_mu": "redirect", "miao_shou_hui_chun": "revive", "you_mu_cheng_huai": "scenery",
	"chang_xing_wu_zu": "free_move"
}

static func value(option: Dictionary, request: Dictionary, observation: AIObservation, policy: AIPolicy) -> float:
	var own: Dictionary = observation.state.self
	var source_id := String(request.get("source_id", ""))
	var purpose := String(request.get("purpose", "choose"))
	var context: Dictionary = request.get("context", {})
	var intent := String(EVENT_INTENTS.get(source_id, "food"))
	if option.type == "player":
		var other: Dictionary = option.player
		if purpose == "choose_team": return float(context.get("rolls", {}).get(other.id, 0))
		if intent == "profession_swap": return profession_value(other, own) - profession_value(own, own)
		if intent == "give" or source_id == "zhang_guan_he_zha": return 100.0 - float(other.score) - float(other.energy)
		if intent == "food_swap": return int(other.food_count) - int(own.food_count)
		if intent == "position_swap":
			var hypothetical := own.duplicate(true)
			hypothetical.position = other.position
			return policy.navigation_value(hypothetical, observation) - policy.navigation_value(own, observation)
		if intent == "exchange" or source_id in ["san_he_tang", "zhu_shan_lan_dou_fu"]:
			return policy.exchange_value(other, observation)
		var threat: float = float(other.score) * 10.0 + other.heritage.size() * 4.0
		if policy.profile.difficulty >= 1:
			var cards: Array = other.heritage.duplicate(true)
			var before := policy.collection_score(cards, observation)
			var largest_loss := 0.0
			for card: Dictionary in other.heritage:
				if not bool(card.effective) or int(card.category) == 6: continue
				var remaining := cards.duplicate(true)
				for index: int in remaining.size():
					if remaining[index].id == card.id:
						remaining.remove_at(index)
						break
				largest_loss = maxf(largest_loss, before - policy.collection_score(remaining, observation))
			threat += largest_loss * 12.0
			if int(other.score) >= int(observation.state.target_score) - 3: threat += 120.0
		return threat + (20.0 if int(other.energy) < 3 else 0.0) - (10000.0 if int(other.id) == int(own.id) else 0.0)
	if option.type == "section":
		var tile: Dictionary = option.section
		var value := policy.section_value(tile, own)
		# Ordinary event teleports don't receive normal-arrival scenery healing.
		if intent == "scenery": value += mini(5 if source_id == "you_mu_cheng_huai" else 6, 12 - int(own.energy)) * 18.0
		if policy.profile.difficulty >= 1:
			var next := own.duplicate(true)
			next.position = tile.position
			value += policy.navigation_value(next, observation) - policy.navigation_value(own, observation)
		if intent == "move_collect":
			var distance := Vector3(own.position).distance_to(Vector3(tile.position)) / sqrt(2.0)
			value -= distance * 24.0
		return value
	if option.type in ["heritage", "food", "event"]:
		var value := policy.card_value(option, observation)
		if purpose == "reaction":
			var harm := effect_harm(request, observation, policy)
			return harm - value if harm > 0.0 else -1.0
		if intent == "duel": return float(option.get("score", 0)) * 100.0
		if intent == "optional_rest": return (minf(2.0, 12 - int(own.energy)) * 18.0) - value
		return -value if bool(option.get("owned", false)) else value
	if option.type == "bool":
		if not bool(option.value): return 0.0
		if purpose == "revive":
			if int(context.get("target", -1)) == int(own.id):
				var highest_other := -1
				var dead_others := 0
				for other: Dictionary in observation.state.players:
					if int(other.id) == int(own.id): continue
					highest_other = maxi(highest_other, int(other.score))
					if not bool(other.alive): dead_others += 1
				return -1.0 if dead_others >= 1 and int(own.score) >= highest_other else 1000.0
			var living := 0
			var highest := -1
			for other: Dictionary in observation.state.players:
				if bool(other.alive): living += 1
				highest = maxi(highest, int(other.score))
			return 50.0 if living <= observation.state.players.size() - 1 and int(own.score) < highest else -1.0
		if purpose == "exchange_accept":
			for other: Dictionary in observation.state.players:
				if int(other.id) == int(context.get("source", -1)):
					return policy.exchange_value(other, observation) + (18.0 if int(own.energy) < 12 else 0.0) - 0.1
			return -1.0
		if intent == "optional_rest": return 60.0 if int(own.energy) < 5 else -1.0
		return 1.0
	if option.type == "number": return float(option.value)
	if option.type == "text": return 2.0 if String(option.value) == "redirect" else 1.0
	return 0.0

static func profession_value(profession: Dictionary, own: Dictionary) -> float:
	if not bool(profession.skill_enabled): return 0.0
	match int(profession.profession):
		0: return 40.0 + own.foods.size() * 10.0
		1: return 70.0
		2: return 95.0 if int(own.energy) < 4 else 65.0
		3: return 40.0 + mini(1000, int(own.money)) * 0.05
		4: return 45.0
		5: return 55.0
	return 0.0

static func effect_harm(request: Dictionary, observation: AIObservation, policy: AIPolicy = null) -> float:
	var context: Dictionary = request.get("context", {})
	var own: Dictionary = observation.state.self
	if context.has("amount"):
		var amount := float(context.amount)
		if amount >= 0: return -1.0
		return -amount * (0.08 if context.get("effect_method") == "_apply_money" else 35.0)
	match String(EVENT_INTENTS.get(String(request.source_id), "food")):
		"reward", "heal", "give", "income": return -1.0
		"attack", "steal":
			var total := 0.0
			for card: Dictionary in own.heritage:
				if int(card.category) != 6: total += policy.card_value(card, observation) if policy != null else int(card.score) * 100.0 + 40.0
			return total / maxf(1.0, own.heritage.size())
		"food_swap": return own.foods.size() * 15.0
		"profession_swap": return 35.0
		"food":
			if String(request.source_id) in ["zhang_guan_he_zha", "mao_zui_lu_ji", "sui_zhou_mi_zao"]: return -1.0
			return 40.0 if String(request.source_id) == "zao_yang_suan_jiang_mian" else 15.0
	return 25.0
