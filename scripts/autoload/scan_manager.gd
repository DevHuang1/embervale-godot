extends Node

signal relic_forged(relic: RelicData)

static var reveal_stamp_msec: int = -999999

var last_relic: RelicData = null

func pulse_reveal() -> void:
	reveal_stamp_msec = Time.get_ticks_msec()
