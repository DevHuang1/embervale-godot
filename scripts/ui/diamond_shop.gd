extends CanvasLayer
class_name DiamondShop

## === The Glintmonger's Case — Diamond Cosmetics ===
## Diamonds buy looks and voice ONLY. Every item here is a sidegrade:
## prettier SFX, trail colors, body auras. No stat lines exist on this shelf.
## Catalog lives in DiamondCatalog (pure data) so store safety audits can
## compile it headlessly; the shop reads the same single source of truth.

const ITEMS := preload("res://scripts/systems/diamond_catalog.gd").ITEMS
const PURCHASE_STATES: Array[String] = ["unavailable", "pending", "failed",
	"cancelled", "offline", "restoring", "confirmed"]
var scan_purchase_state: String = "unavailable"

@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager
@onready var diamonds_label: Label = $Root/Center/Panel/VBox/Header/DiamondsLabel
@onready var items_vbox: VBoxContainer = $Root/Center/Panel/VBox/Scroll/ItemsVBox
@onready var message_label: Label = $Root/Center/Panel/VBox/Message
@onready var close_button: Button = $Root/Center/Panel/VBox/Footer/Close
@onready var unequip_button: Button = $Root/Center/Panel/VBox/Footer/UnequipAll

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS  # stay interactive while the world is frozen
	_freeze_was_visible = visible
	# The Glintmonger's case reads as a warm display sheet over the dim.
	UiKit.apply_parchment($Root/Center/Panel)
	UiKit.style_secondary_button(close_button)
	UiKit.style_secondary_button(unequip_button)
	close_button.pressed.connect(close)
	unequip_button.pressed.connect(_on_unequip_all)
	game_state.diamonds_changed.connect(func(_t): _refresh())

func open() -> void:
	visible = true
	_refresh()
	audio.play_ui_blip()

func set_scan_purchase_state(state: String) -> bool:
	var normalized := state.strip_edges().to_lower()
	if normalized not in PURCHASE_STATES:
		return false
	scan_purchase_state = normalized
	if visible:
		_refresh()
	return true

var _freeze_was_visible := false

## Freeze/resume the world whenever this interface toggles, whichever
## code path opened or closed it.
func _poll_world_freeze() -> void:
	if visible == _freeze_was_visible:
		return
	_freeze_was_visible = visible
	if visible:
		game_state.push_world_freeze()
	else:
		game_state.pop_world_freeze()

func _process(_delta: float) -> void:
	_poll_world_freeze()

func close() -> void:
	visible = false
	audio.play_ui_cancel()

func _refresh() -> void:
	diamonds_label.text = "DIAMONDS  %d" % game_state.diamonds
	for child in items_vbox.get_children():
		child.queue_free()
	for item in ITEMS:
		items_vbox.add_child(_build_row(item))

func _build_row(item: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_constant_override("panel_inset", 10)
	panel.add_theme_stylebox_override("panel", UiKit.parchment_stylebox(UiKit.RADIUS_BUTTON))
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)

	var glyph := Label.new()
	match str(item.kind):
		"scan_pack":
			glyph.text = "SCAN"
		"sfx":
			glyph.text = "SFX"
		"trail":
			glyph.text = "TRAIL"
		_:
			glyph.text = "AURA"
	UiKit.style_label(glyph, "", 22)
	hbox.add_child(glyph)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)
	var name_l := Label.new()
	name_l.text = "%s%s" % [str(item.name),
		"" if str(item.kind) != "sfx" else "  (SFX)"]
	UiKit.style_label(name_l, &"MenuTitle", 13)
	info.add_child(name_l)
	var desc := Label.new()
	desc.text = str(item.desc)
	if str(item.kind) == "scan_pack":
		desc.text += "\n5 SCANS · $%.2f · BALANCE %d/%d · %s · %s" % [
			float(item.price), game_state.scans_remaining, game_state.MAX_SCANS,
			str(item.get("duplicate_behavior", "")), str(item.get("restore_path", ""))]
	UiKit.style_label(desc, &"Caption", 11)
	info.add_child(desc)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(160, 0)
	if str(item.kind) == "scan_pack":
		var purchase_copy := {
			"unavailable": ["UNAVAILABLE", "Purchase integration is not connected"],
			"pending": ["PROCESSING", "Waiting for store confirmation; no scans granted yet."],
			"failed": ["RETRY", "Purchase failed; no charge or scans were applied."],
			"cancelled": ["TRY AGAIN", "Purchase cancelled; no scans were granted."],
			"offline": ["OFFLINE", "Reconnect before starting a purchase."],
			"restoring": ["RESTORING", "Checking provider ownership; no duplicate grant."],
			"confirmed": ["CONFIRMED", "Provider confirmed; grant through the entitlement handler."]
		}
		var copy: Array = purchase_copy.get(scan_purchase_state, purchase_copy["unavailable"])
		btn.text = str(copy[0])
		btn.disabled = scan_purchase_state not in ["failed", "cancelled"]
		btn.tooltip_text = str(copy[1])
		UiKit.style_secondary_button(btn)
	elif game_state.active_cosmetic_id_for(str(item.kind)) == str(item.id):
		var worn := UiKit.action_state("equipped", "Cosmetic is currently active")
		btn.text = str(worn.get("label", "EQUIPPED"))
		btn.disabled = true
		btn.tooltip_text = str(worn.get("detail", "Cosmetic is currently active"))
		UiKit.style_secondary_button(btn)
	elif game_state.owns_cosmetic(str(item.id)):
		var owned := UiKit.action_state("owned", "Apply this cosmetic")
		btn.text = str(owned.get("label", "OWNED / EQUIP"))
		btn.tooltip_text = str(owned.get("detail", "Apply this cosmetic"))
		UiKit.style_button(btn)
		btn.pressed.connect(_on_equip.bind(item))
	else:
		var available := UiKit.action_state("available", "Cosmetic only · %d diamonds" % int(item.price))
		btn.text = "BUY  ·  %d DIAMONDS" % int(item.price)
		btn.tooltip_text = "%s · %s" % [str(available.get("label", "AVAILABLE")), str(available.get("detail", ""))]
		UiKit.style_primary_button(btn)
		btn.pressed.connect(_on_buy.bind(item))
	hbox.add_child(btn)
	return panel

func _on_buy(item: Dictionary) -> void:
	if game_state.purchase_cosmetic(str(item.id), int(item.price),
			str(item.kind), str(item.value)):
		message_label.text = "%s is yours — purely beautiful." % str(item.name)
		audio.play_forge_success()
	else:
		message_label.text = "Not enough diamonds — they favor the patient."
		audio.play_ui_cancel()
	_refresh()

func _on_equip(item: Dictionary) -> void:
	game_state.equip_cosmetic(str(item.kind), str(item.value), str(item.id))
	audio.play_ui_blip()
	_refresh()

func _on_unequip_all() -> void:
	game_state.equip_cosmetic("sfx", "", "")
	game_state.equip_cosmetic("trail", "", "")
	game_state.equip_cosmetic("aura", "", "")
	audio.play_ui_back()
	_refresh()
