extends RefCounted
class_name BalanceHarness

## Deterministic, presentation-free combat evaluator for balance reviews.
## It intentionally models only the shared auto-strike contract; encounter
## scripts remain responsible for movement, telegraphs, and special attacks.

static func evaluate_weapon(weapon: Dictionary, target_hp: int,
		target_armor: int = 0, attack_speed: float = 1.0,
		crit_chance: float = 0.0, crit_damage: float = 1.5) -> Dictionary:
	var hp := maxi(target_hp, 1)
	var armor := maxi(target_armor, 0)
	var speed := maxf(attack_speed, 0.01)
	var raw := maxi(int(weapon.get("atk", 1)), 1)
	var per_hit := maxi(raw - armor, 1)
	var crit := clampf(crit_chance, 0.0, 1.0)
	var multiplier := 1.0 + crit * maxf(crit_damage - 1.0, 0.0)
	var expected_hit := per_hit * multiplier
	var swing_time := maxf(float(weapon.get("swing_time", 0.36)) / speed, 0.05)
	var hits := int(ceil(float(hp) / maxf(expected_hit, 0.01)))
	return {
		"weapon_id": str(weapon.get("id", "unknown")),
		"hits_to_kill": hits,
		"seconds_to_kill": float(hits) * swing_time,
		"damage_per_second": expected_hit / swing_time,
		"effective_hit": expected_hit,
	}

static func compare_weapons(weapons: Array[Dictionary], target_hp: int,
		target_armor: int = 0) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for weapon in weapons:
		results.append(evaluate_weapon(weapon, target_hp, target_armor))
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("seconds_to_kill", INF)) < float(b.get("seconds_to_kill", INF)))
	return results

static func evaluate_survivability(player_hp: int, enemy_damage: int,
		enemy_armor: int = 0, attack_interval: float = 1.5) -> Dictionary:
	var hp := maxi(player_hp, 1)
	var incoming := maxi(enemy_damage - maxi(enemy_armor, 0), 1)
	var hits := int(ceil(float(hp) / float(incoming)))
	var interval := maxf(attack_interval, 0.05)
	return {
		"player_hp": hp,
		"incoming_hit": incoming,
		"hits_to_defeat": hits,
		"seconds_to_defeat": float(hits) * interval,
	}
