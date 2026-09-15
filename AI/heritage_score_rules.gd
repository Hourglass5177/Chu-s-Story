class_name HeritageScoreRules
extends RefCounted

## Shared, side-effect-free scoring for the live game and hypothetical collections.
static func calculate(cards: Array, category_totals: Dictionary, region_totals: Dictionary) -> Dictionary:
	var categories: Dictionary = {}
	var regions: Dictionary = {}
	var base: int = 0
	for card: Dictionary in cards:
		if not card.get("effective", true):
			continue
		base += int(card.score)
		categories[card.category] = int(categories.get(card.category, 0)) + 1
		regions[card.region] = int(regions.get(card.region, 0)) + 1
	var category_combo: int = 0
	var category_complete: int = 0
	for category: int in categories:
		var count: int = categories[category]
		category_combo = maxi(category_combo, 5 if count >= 10 else (3 if count >= 5 else (2 if count >= 3 else 0)))
		if int(category_totals.get(category, 0)) > 0 and count >= int(category_totals[category]):
			category_complete += 5
	if categories.size() >= 5:
		category_combo += 5
	var regional: int = 0
	var annotations: Dictionary = {}
	for region: int in regions:
		var notes: Array[String] = []
		if int(regions[region]) >= 5:
			regional += 5
			notes.append("触发同城5张得分+5")
		if int(region_totals.get(region, 0)) > 0 and int(regions[region]) >= int(region_totals[region]):
			regional += 2
			notes.append("触发集齐全市得分+2")
		if not notes.is_empty():
			annotations[region] = notes
	if regions.has(6) and regions.has(10) and regions.has(12):
		regional += 2
		for region: int in [6, 10, 12]:
			if not annotations.has(region):
				annotations[region] = []
			annotations[region].append("触发江汉三市得分+2（合计）")
	return {"base_score": base, "category_combo_score": category_combo, "category_completion_score": category_complete, "regional_combo_score": regional, "total_score": base + category_combo + category_complete + regional, "region_annotations": annotations}
