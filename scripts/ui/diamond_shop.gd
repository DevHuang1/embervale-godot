extends CanvasLayer
class_name DiamondShop

## === The Glintmonger's Case — Diamond Cosmetics ===
## Diamonds buy looks and voice ONLY. Every item here is a sidegrade:
## prettier SFX, trail colors, body auras. No stat lines exist on this shelf.
## Catalog lives in DiamondCatalog (pure data) so store safety audits can
## compile it headlessly; the shop reads the same single source of truth.

const ITEMS := preload("res://scripts/systems/diamond_catalog.gd").ITEMS
var _store: Node = null
## True while a native purchase sheet is open: the pack buttons stay disabled so
## one sheet can never be stacked on another.
var _buying := false

@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager
@onready var diamonds_label: Label = $Root/Panel/VBox/Header/DiamondsLabel
@onready var items_vbox: VBoxContainer = $Root/Panel/VBox/Scroll/ItemsVBox
@onready var message_label: Label = $Root/Panel/VBox/Message
@onready var close_button: Button = $Root/Panel/VBox/Footer/Close
@onready var unequip_button: Button = $Root/Panel/VBox/Footer/UnequipAll

## The panel was a fixed 660 px wide inside a CenterContainer, but the pack row
## asked for three side-by-side buttons and blew the minimum width past the
## phone frame, cutting the title and the footer off both edges. The frame keeps
## the surface on-screen; the pack row below now stacks instead of stretching.
func _apply_responsive_frame() -> void:
	UiKit.apply_menu_frame(get_node_or_null("Root/Panel") as Control,
		get_viewport().get_visible_rect().size, 40.0, 60.0)

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS  # stay interactive while the world is frozen
	# The Glintmonger's case reads as a warm display sheet over the dim.
	UiKit.apply_parchment($Root/Panel)
	UiKit.style_secondary_button(close_button)
	UiKit.style_secondary_button(unequip_button)
	close_button.pressed.connect(close)
	unequip_button.pressed.connect(_on_unequip_all)
	game_state.diamonds_changed.connect(func(_t): _refresh())
	_connect_store()

## The web-store row is optional furniture: without the autoload (or without a
## configured provider) the case still opens and every local path still works.
func _connect_store() -> void:
	_store = get_node_or_null("/root/StoreManager")
	if _store == null:
		return
	_store.availability_changed.connect(_on_store_availability_changed)
	_store.refresh_finished.connect(_on_store_refresh_finished)
	_store.purchase_claimed.connect(_on_store_purchase_claimed)

func open() -> void:
	visible = true
	_refresh()
	audio.play_ui_blip()

var _freeze_was_visible := false
var _freeze_held := false

## Freeze/resume the world whenever this interface toggles, whichever
## code path opened or closed it.
func _poll_world_freeze() -> void:
	if visible == _freeze_was_visible:
		return
	_freeze_was_visible = visible
	if visible:
		game_state.push_world_freeze()
		_freeze_held = true
	else:
		_release_world_freeze()

func _process(_delta: float) -> void:
	_poll_world_freeze()

func close() -> void:
	visible = false
	audio.play_ui_cancel()

func _refresh() -> void:
	_apply_responsive_frame()
	if not get_viewport().size_changed.is_connected(_apply_responsive_frame):
		get_viewport().size_changed.connect(_apply_responsive_frame)
	diamonds_label.text = "DIAMONDS  %d" % game_state.diamonds
	for child in items_vbox.get_children():
		child.queue_free()
	items_vbox.add_child(_build_web_store_row())
	for item in ITEMS:
		items_vbox.add_child(_build_row(item))

## Ember marks bought on the web, delivered to this device by provider
## confirmation. No price is duplicated here: the hosted checkout owns pricing.
func _build_web_store_row() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_constant_override("panel_inset", 10)
	panel.add_theme_stylebox_override("panel", UiKit.parchment_stylebox(UiKit.RADIUS_BUTTON))
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "EMBER MARKS · ONLINE STORE"
	UiKit.style_label(header, &"MenuTitle", 32)
	vbox.add_child(header)

	var status := Label.new()
	status.text = _store_status_text()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(status, &"Caption", 18)
	vbox.add_child(status)

	var row := HBoxContainer.new()
	vbox.add_child(row)
	var state := _store_state()

	# The browser row only exists when the build actually has a hosted funnel:
	# an SDK-only build sells through the native pack row below, and a button
	# that could only report failure would be a dead control.
	var has_funnel := _store != null and _store.has_method("has_hosted_checkout") \
		and bool(_store.has_hosted_checkout())
	if has_funnel:
		var buy := Button.new()
		buy.name = "BuyOnline"
		buy.custom_minimum_size = Vector2(160, 0)
		buy.text = "BUY ONLINE"
		buy.tooltip_text = "Opens the hosted checkout in your browser."
		buy.disabled = state not in ["ready", "pending"]
		UiKit.style_primary_button(buy)
		buy.pressed.connect(_on_buy_online)
		row.add_child(buy)

	var restore := Button.new()
	restore.custom_minimum_size = Vector2(120, 0)
	restore.text = "RESTORE"
	restore.tooltip_text = "Rechecks provider ownership. A claimed pack is never granted twice."
	restore.disabled = state == "unavailable"
	UiKit.style_secondary_button(restore)
	restore.pressed.connect(_on_restore_purchases)
	row.add_child(restore)

	var packs := _build_native_pack_row()
	if packs != null:
		vbox.add_child(packs)
	return panel

## A native SDK purchase (the Test Store sheet today, the store's own sheet with
## a real key) opens in-app and delivers through the same claim path as a web
## purchase. The row exists only when the native authority is live, so no dead
## control is ever shown, and no price is duplicated here: the sheet owns pricing.
func _build_native_pack_row() -> Control:
	if _store == null or not _store.has_method("authority_name") \
			or not _store.has_method("buy"):
		return null
	if str(_store.authority_name()) != "native" or _store_state() == "unavailable":
		return null
	# Packs stack full-width: three side-by-side buttons each demanded more
	# width than the phone frame has, and the sheet owns pricing anyway.
	var box := VBoxContainer.new()
	box.name = "NativePacks"
	box.add_theme_constant_override("separation", 8)
	box.add_child(UiKit.section_header("Diamond Packs", UiKit.EMBER))
	for tier in WebStoreCatalog.all():
		var product_id := WebStoreCatalog.product_id_for(tier)
		if product_id.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var label := Label.new()
		label.text = "%s · %d" % [str(tier.get("name", product_id)),
			int(tier.get("diamonds", 0))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiKit.style_label(label, &"RowLabel", 22)
		row.add_child(label)
		var btn := Button.new()
		btn.name = "Buy_%s" % product_id
		btn.custom_minimum_size = Vector2(140, 56)
		btn.text = "BUY"
		btn.tooltip_text = str(tier.get("blurb", ""))
		btn.disabled = _buying
		UiKit.style_primary_button(btn)
		btn.pressed.connect(_on_buy_pack.bind(product_id))
		row.add_child(btn)
	return box

## Runs one in-app purchase and reports its outcome. Delivery is never taken
## from the purchase result itself: StoreManager re-reads provider state and
## claims exactly once, so this only narrates what the claim reported.
func _on_buy_pack(product_id: String) -> void:
	if _buying or _store == null or not _store.has_method("buy"):
		return
	_buying = true
	message_label.text = "Opening the store · the sheet appears over the game."
	audio.play_ui_blip()
	_refresh()
	var result: Dictionary = await _store.buy(product_id)
	_buying = false
	if bool(result.get("purchased", false)):
		var marks := int(result.get("diamonds", 0))
		if marks > 0:
			message_label.text = "Pack delivered · +%d ember marks." % marks
			audio.play_forge_success()
		else:
			message_label.text = "Purchase confirmed · tap RESTORE to deliver it."
		_refresh()
		return
	match str(result.get("status", "")):
		"cancelled":
			message_label.text = "Purchase cancelled · nothing was charged."
		"offline", "timeout":
			message_label.text = "Offline · reconnect before buying."
		"unconfigured", "unavailable", "unsupported":
			message_label.text = "In-app purchases are not configured in this build."
		_:
			message_label.text = "The purchase could not be completed."
			audio.play_ui_cancel()
	_refresh()

func _store_state() -> String:
	if _store == null or not _store.has_method("availability_state"):
		return "unavailable"
	return str(_store.availability_state())

func _store_status_text() -> String:
	var state := _store_state()
	if state == "unavailable":
		return "Online packs are not configured in this build. All local play is unaffected."
	if state == "pending":
		return "Checking provider ownership · no duplicate grant will be made."
	var last: Dictionary = {}
	if _store != null and _store.has_method("last_result"):
		last = _store.last_result()
	match str(last.get("status", "")):
		"offline", "timeout":
			return "Offline · reconnect, then restore to recheck ownership."
		"rate_limited":
			return "Just checked · wait a moment before restoring again."
		"unauthorized", "not_found":
			return "The provider rejected this build's lookup · check the store configuration."
		_:
			return "Provider connected · packs are delivered to this device after checkout."

func _on_buy_online() -> void:
	if _store == null or not _store.has_method("open_web_store"):
		message_label.text = "Online packs are not configured in this build."
		audio.play_ui_cancel()
		return
	if bool(_store.open_web_store()):
		message_label.text = "Finish checkout in your browser, then return and tap RESTORE."
		audio.play_ui_blip()
	else:
		message_label.text = "The online store could not be opened."
		audio.play_ui_cancel()
	_refresh()

func _on_restore_purchases() -> void:
	if _store == null or not _store.has_method("request_refresh"):
		message_label.text = "Online packs are not configured in this build."
		audio.play_ui_cancel()
		return
	message_label.text = "Checking provider ownership · no duplicate grant will be made."
	audio.play_ui_blip()
	_store.request_refresh()
	_refresh()

func _on_store_availability_changed(_available: bool) -> void:
	if visible:
		_refresh()

func _on_store_refresh_finished(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		match str(result.get("status", "")):
			"rate_limited":
				message_label.text = "Just checked · wait a moment before restoring again."
			"unavailable", "unconfigured":
				message_label.text = "Online packs are not configured in this build."
			"unauthorized", "not_found":
				message_label.text = "The provider rejected this build's lookup · check the store configuration."
			_:
				message_label.text = "Could not reach the store · reconnect and restore again."
	elif int(result.get("granted", 0)) <= 0:
		message_label.text = "No new ownership found · nothing was double-granted."
	if visible:
		_refresh()

func _on_store_purchase_claimed(grants: int, diamonds: int) -> void:
	var noun := "pack" if grants == 1 else "packs"
	message_label.text = "%d %s delivered · +%d ember marks." % [grants, noun, diamonds]
	audio.play_forge_success()
	_refresh()

func _build_row(item: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_constant_override("panel_inset", 10)
	panel.add_theme_stylebox_override("panel", UiKit.parchment_stylebox(UiKit.RADIUS_BUTTON))
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)

	var kind_icons := {"sfx": "sigil_wave",
		"trail": "fire", "aura": "sigil_moon"}
	hbox.add_child(UiKit.icon_well(str(kind_icons.get(str(item.kind), "relic")),
		UiKit.MOON if str(item.kind) == "aura" else UiKit.EMBER, 56.0))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)
	var name_l := Label.new()
	name_l.text = "%s%s" % [str(item.name),
		"" if str(item.kind) != "sfx" else "  (SFX)"]
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(name_l, &"RowLabel", 24)
	info.add_child(name_l)
	var desc := Label.new()
	desc.text = str(item.desc)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(desc, &"Caption", 18)
	info.add_child(desc)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(160, 0)
	if game_state.active_cosmetic_id_for(str(item.kind)) == str(item.id):
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

## A menu freed while it still holds the world must not leave it paused behind
## it. Every freeze-holding surface shares this guarantee, matching the altar's
## teardown behaviour.
func _exit_tree() -> void:
	_release_world_freeze()

func _release_world_freeze() -> void:
	if not _freeze_held:
		return
	_freeze_held = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("pop_world_freeze"):
		gs.call("pop_world_freeze")
