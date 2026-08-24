class_name AudioCueConfig
extends Resource

## === Audio Cue Config ===
## Maps synthesized cue names to playback rules: volume, pitch randomization
## range, bus routing and how many pre-rendered variants to cycle through.
## Designers tune feel here without touching AudioManager logic.
##
## Keys per cue:
##   volume_db : float   playback level (combat cues sit above ambient beds)
##   pitch_min/pitch_max : float  random pitch window per play
##   bus       : String  "SFX" for combat/UI, "Music" only for beds
##   variants  : int     number of distinct renders cycled randomly

@export var cues: Dictionary = {
	# --- Hero movement ---
	"footstep_grass": {"volume_db": -10.0, "pitch_min": 0.92, "pitch_max": 1.1, "bus": "SFX", "variants": 3},
	"footstep_mud": {"volume_db": -9.0, "pitch_min": 0.88, "pitch_max": 1.08, "bus": "SFX", "variants": 3},
	"footstep_stone": {"volume_db": -11.0, "pitch_min": 0.9, "pitch_max": 1.12, "bus": "SFX", "variants": 3},
	"dodge_roll": {"volume_db": -7.0, "pitch_min": 0.95, "pitch_max": 1.05, "bus": "SFX", "variants": 2},

	# --- Hero combat ---
	"swing_open": {"volume_db": -7.5, "pitch_min": 0.94, "pitch_max": 1.08, "bus": "SFX", "variants": 2},
	"swing_reverse": {"volume_db": -7.0, "pitch_min": 0.94, "pitch_max": 1.08, "bus": "SFX", "variants": 2},
	"swing_finisher": {"volume_db": -5.5, "pitch_min": 0.96, "pitch_max": 1.05, "bus": "SFX", "variants": 2},
	"magic_cast": {"volume_db": -7.0, "pitch_min": 0.97, "pitch_max": 1.03, "bus": "SFX", "variants": 2},
	"slash_impact": {"volume_db": -6.5, "pitch_min": 0.93, "pitch_max": 1.09, "bus": "SFX", "variants": 2},

	# --- Lantern ---
	"lantern_hum": {"volume_db": -16.0, "pitch_min": 0.98, "pitch_max": 1.02, "bus": "SFX", "variants": 3},
	"lantern_creak": {"volume_db": -13.0, "pitch_min": 0.94, "pitch_max": 1.06, "bus": "SFX", "variants": 2},

	# --- Hushling ---
	"hushling_telegraph": {"volume_db": -9.0, "pitch_min": 0.9, "pitch_max": 1.12, "bus": "SFX", "variants": 2},
	"hushling_lunge": {"volume_db": -8.0, "pitch_min": 0.92, "pitch_max": 1.1, "bus": "SFX", "variants": 2},
	"spore_burst": {"volume_db": -6.5, "pitch_min": 0.9, "pitch_max": 1.12, "bus": "SFX", "variants": 2},
	"hushling_death": {"volume_db": -8.0, "pitch_min": 0.95, "pitch_max": 1.05, "bus": "SFX", "variants": 2},

	# --- Boss ---
	"boss_stomp": {"volume_db": -4.5, "pitch_min": 0.94, "pitch_max": 1.06, "bus": "SFX", "variants": 2},
	"boss_death": {"volume_db": -4.0, "pitch_min": 0.97, "pitch_max": 1.03, "bus": "SFX", "variants": 2},

	# --- UI / forge ---
	"ui_confirm": {"volume_db": -8.0, "pitch_min": 0.99, "pitch_max": 1.01, "bus": "SFX", "variants": 1},
	"ui_cancel": {"volume_db": -9.0, "pitch_min": 0.99, "pitch_max": 1.01, "bus": "SFX", "variants": 1},
	"forge_success": {"volume_db": -5.0, "pitch_min": 1.0, "pitch_max": 1.0, "bus": "SFX", "variants": 1},
}
