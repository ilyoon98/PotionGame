extends RefCounted
## One catalog for reward rolls and the public range preview.
const POOLS := {
	"forest_edge": {"main": "dewgrass", "min": 1, "max": 3, "extra": ["starleaf", "herb", "moon_mushroom"]},
	"abandoned_greenhouse": {"main": "silver_moss", "min": 1, "max": 3, "extra": ["dewgrass", "starleaf", "moon_mushroom"]},
	"mist_valley": {"main": "blue_reed", "min": 2, "max": 4, "extra": ["silver_moss", "dewgrass", "starleaf"]},
	"crystal_mine": {"main": "crystal_herb", "min": 2, "max": 4, "extra": ["blue_reed", "silver_moss", "starleaf"]},
	"fog_marsh": {"main": "mist_mushroom", "min": 3, "max": 5, "extra": ["crystal_herb", "blue_reed", "silver_moss"]},
	"forgotten_tower": {"main": "ash_sage", "min": 3, "max": 5, "extra": ["mist_mushroom", "crystal_herb", "silver_moss"]},
	"moon_ruins": {"main": "moonflower", "min": 4, "max": 6, "extra": ["ash_sage", "mist_mushroom", "starleaf"]},
	"star_garden": {"main": "star_seed", "min": 5, "max": 7, "extra": ["moonflower", "ash_sage", "crystal_herb"]},
}
const RARE := {
	"forest_edge": {"id": "rare_forest_breath", "name": "숲숨결 물약"},
	"mist_valley": {"id": "rare_mist_veil", "name": "물안개 물약"},
	"moon_ruins": {"id": "rare_lunar_seal", "name": "월광봉인 물약"},
	"star_garden": {"id": "rare_nebula_distillate", "name": "성운 증류액"},
}

static func preview(id: String) -> Array:
	var pool: Dictionary = POOLS[id]
	var items: Array = [{"id": pool.main, "kind": "material", "min": pool.min, "max": pool.max, "guaranteed": true}]
	for material in pool.extra: items.append({"id": material, "kind": "material", "min": 0, "max": 2, "guaranteed": false})
	return items

static func integer(p: RefCounted, low: int, high: int) -> int:
	return low + mini(high - low, int(p.random_value() * (high - low + 1)))

static func roll(id: String, p: RefCounted) -> Dictionary:
	var pool: Dictionary = POOLS[id]
	var result := {pool.main: integer(p, pool.min, pool.max)}
	var candidates: Array = pool.extra.duplicate()
	var weights: Array = [60, 30, 10]
	var quantity := 2 if p.random_value() < 0.25 else 1
	for i in quantity:
		var total := 0
		for weight in weights: total += int(weight)
		var choice: float = p.random_value() * total
		var selected := weights.size() - 1
		for index in weights.size():
			choice -= int(weights[index])
			if choice < 0:
				selected = index
				break
		result[candidates[selected]] = integer(p, 1, 2)
		candidates.remove_at(selected)
		weights.remove_at(selected)
	return result
