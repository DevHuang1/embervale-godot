extends Control
class_name AssetIntakeReview

const CATALOG := preload("res://scripts/systems/asset_intake_catalog.gd")

var _rows: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_surface()

func _build_surface() -> void:
	var panel := PanelContainer.new()
	panel.name = "AssetIntakePanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(720, 520)
	panel.add_theme_stylebox_override("panel", UiKit.glass_stylebox(true))
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	var title := Label.new()
	title.text = "ASSET INTAKE REVIEW"
	UiKit.style_label(title, &"MenuTitle", 24)
	outer.add_child(title)
	var summary := Label.new()
	summary.name = "AssetIntakeSummary"
	var errors: Array[String] = CATALOG.validate_entries()
	summary.text = "%d PACKS  ·  %s" % [CATALOG.ENTRIES.size(),
		"READY FOR REVIEW" if errors.is_empty() else "ACTION REQUIRED"]
	UiKit.style_label(summary, &"Caption", 14)
	outer.add_child(summary)
	var readiness := Label.new()
	readiness.name = "AssetReadinessSummary"
	readiness.text = _readiness_text(errors)
	readiness.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(readiness, &"Caption", 13)
	readiness.add_theme_color_override("font_color", UiKit.SAGE_BRIGHT)
	outer.add_child(readiness)
	var scroll := ScrollContainer.new()
	scroll.name = "PackList"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.name = "PackRows"
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)
	for entry in CATALOG.ENTRIES:
		_rows.add_child(_build_row(entry))

func _readiness_text(errors: Array[String]) -> String:
	var categories: Dictionary = {}
	var realms: Dictionary = {}
	for entry in CATALOG.ENTRIES:
		var category := str(entry.get("category", "unknown")).to_upper()
		var realm := str(entry.get("realm", "all")).to_upper()
		categories[category] = int(categories.get(category, 0)) + 1
		realms[realm] = int(realms.get(realm, 0)) + 1
	var category_parts: Array[String] = []
	for category in categories.keys():
		category_parts.append("%s %d" % [category, int(categories[category])])
	var realm_parts: Array[String] = []
	for realm in realms.keys():
		realm_parts.append("%s %d" % [realm, int(realms[realm])])
	var total_score := 0
	var ship_ready := 0
	for entry in CATALOG.ENTRIES:
		var score := CATALOG.quality_score(entry)
		total_score += score
		if CATALOG.quality_band(entry) == "SHIP-READY":
			ship_ready += 1
	var average := int(round(float(total_score) / maxf(1.0, float(CATALOG.ENTRIES.size()))))
	return "READY %d/%d  ·  %s\nQUALITY  ·  %d/100 AVG  ·  SHIP-READY %d/%d\nREALMS  ·  %s" % [
		CATALOG.reviewed_entries().size() if errors.is_empty() else 0,
		CATALOG.ENTRIES.size(), "  ·  ".join(category_parts), average, ship_ready,
		CATALOG.ENTRIES.size(), "  ·  ".join(realm_parts)]

func _build_row(entry: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.name = str(entry.get("id", "Asset")).to_pascal_case()
	row.custom_minimum_size = Vector2(0, 72)
	row.add_theme_stylebox_override("panel", UiKit.item_card_stylebox(UiKit.SAGE))
	var label := Label.new()
	label.text = "%s\n%s  ·  %s  ·  %s\nLICENSE  ·  %s  ·  QUALITY %d/100  ·  %s" % [
		str(entry.get("pack", "Unknown")),
		str(entry.get("category", "unknown")).to_upper(),
		str(entry.get("realm", "all")).to_upper(),
		str(entry.get("mobile_status", "unreviewed")).to_upper(),
		str(entry.get("license", "UNKNOWN")),
		CATALOG.quality_score(entry), CATALOG.quality_band(entry)]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(label, &"Body", 13)
	row.add_child(label)
	return row
