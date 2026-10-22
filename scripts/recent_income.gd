extends RefCounted
## Session-only gross sales in the trailing 60 seconds; upgrades do not reduce it.
var elapsed := 0.0
var sales: Array[Vector2] = []
var gold := 0


func advance(delta: float, earned: int = 0) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	elapsed += delta
	if earned > 0:
		sales.append(Vector2(elapsed, earned))
		gold += earned
	while not sales.is_empty() and sales[0].x <= elapsed - 60.0:
		gold -= int(sales.pop_front().y)
