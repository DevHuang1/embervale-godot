extends RefCounted
class_name BossLessonCatalog

const LESSON: Array[Dictionary] = [
	{"stage": "introduce", "rule": "read the thorn lash arc", "proof": "phase_1_safe_zone"},
	{"stage": "test", "rule": "leave the root-denied center", "proof": "phase_2_safe_zone"},
	{"stage": "combine", "rule": "circle storm and watch crown", "proof": "phase_3_vulnerability"},
	{"stage": "mastery_payoff", "rule": "break crown and punish recovery", "proof": "matriarch_relic_reward"},
]

static func validate() -> Array[String]:
	var errors: Array[String] = []
	for entry in LESSON:
		for field in ["stage", "rule", "proof"]:
			if str(entry.get(field, "")).is_empty():
				errors.append("Boss lesson entry missing %s" % field)
	return errors
