extends Node

static var reveal_stamp_msec: int = -999999

func pulse_reveal() -> void:
	reveal_stamp_msec = Time.get_ticks_msec()
