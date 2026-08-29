extends VBoxContainer
class_name ElementalHud

const ELEMENTS := ["fire", "frost", "shock", "nature"]
const LABELS := {"fire": "FIRE", "frost": "FROST", "shock": "SHOCK", "nature": "NATURE"}
const ICONS := {"fire": "✦", "frost": "❄", "shock": "ϟ", "nature": "✿"}
const COLORS := {
    "fire": Color(1.0, 0.30, 0.10),
    "frost": Color(0.38, 0.84, 1.0),
    "shock": Color(0.76, 0.52, 1.0),
    "nature": Color(0.34, 1.0, 0.46),
}
const MAX_STACKS := {"fire": 3, "frost": 1, "shock": 2, "nature": 2}

var _weapon_label: Label
var _target_label: Label
var _meters: Dictionary = {}
var _target: Node3D = null
var _hero: Node3D = null
var _poll := 0.0

func _ready() -> void:
    name = "ElementalHud"
    add_theme_constant_override("separation", 3)
    _build()

func _process(delta: float) -> void:
    _poll -= delta
    if _poll > 0.0:
        return
    _poll = 0.12
    if _hero == null or not is_instance_valid(_hero):
        var scene := get_tree().current_scene
        _hero = scene.get_node_or_null("Hero") if scene != null else null
    _target = GameState.enemy_target if is_instance_valid(GameState.enemy_target) else null
    _refresh_weapon()
    _refresh_target()

func set_target(target: Node3D) -> void:
    _target = target
    _refresh_target()

func _build() -> void:
    _weapon_label = Label.new()
    _weapon_label.name = "WeaponElement"
    _weapon_label.text = "ELEMENT  ·  FIRE"
    _weapon_label.add_theme_font_size_override("font_size", 15)
    _weapon_label.add_theme_color_override("font_color", Color(1.0, 0.76, 0.34))
    add_child(_weapon_label)

    _target_label = Label.new()
    _target_label.name = "TargetBuildup"
    _target_label.text = "ELEMENTAL BUILDUP"
    _target_label.add_theme_font_size_override("font_size", 11)
    _target_label.add_theme_color_override("font_color", Color(0.62, 0.72, 0.64))
    add_child(_target_label)

    var grid := GridContainer.new()
    grid.name = "BuildupMeters"
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 8)
    grid.add_theme_constant_override("v_separation", 2)
    add_child(grid)
    for element in ELEMENTS:
        var row := HBoxContainer.new()
        row.custom_minimum_size = Vector2(118, 17)
        var label := Label.new()
        label.custom_minimum_size = Vector2(52, 17)
        label.text = "%s %s" % [ICONS[element], LABELS[element]]
        label.add_theme_font_size_override("font_size", 10)
        label.add_theme_color_override("font_color", COLORS[element].lightened(0.18))
        row.add_child(label)
        var meter := ProgressBar.new()
        meter.name = "%sBuildup" % element.capitalize()
        meter.custom_minimum_size = Vector2(48, 12)
        meter.max_value = int(MAX_STACKS[element])
        meter.value = 0
        meter.show_percentage = false
        meter.add_theme_stylebox_override("background", _bar_style(Color(0.04, 0.04, 0.05, 0.82), Color(0.18, 0.18, 0.18, 0.8)))
        meter.add_theme_stylebox_override("fill", _bar_style(Color(COLORS[element].r, COLORS[element].g, COLORS[element].b, 0.9), COLORS[element]))
        row.add_child(meter)
        var value := Label.new()
        value.custom_minimum_size = Vector2(22, 17)
        value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        value.add_theme_font_size_override("font_size", 10)
        value.add_theme_color_override("font_color", Color(0.82, 0.84, 0.78))
        row.add_child(value)
        grid.add_child(row)
        _meters[element] = {"meter": meter, "value": value}

func _bar_style(fill: Color, border: Color) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = border
    style.set_border_width_all(1)
    style.corner_radius_top_left = 3
    style.corner_radius_top_right = 3
    style.corner_radius_bottom_left = 3
    style.corner_radius_bottom_right = 3
    return style

func _refresh_weapon() -> void:
    var element := "fire"
    if _hero != null and is_instance_valid(_hero) and _hero.has_method("_equipped_element"):
        element = str(_hero.call("_equipped_element"))
    elif GameState.equipped_weapon is Dictionary:
        element = str(GameState.equipped_weapon.get("element", "fire"))
    if not LABELS.has(element):
        element = "fire"
    _weapon_label.text = "%s  %s ELEMENT" % [ICONS[element], LABELS[element]]
    _weapon_label.add_theme_color_override("font_color", COLORS[element].lightened(0.12))

func _refresh_target() -> void:
    var snapshot: Dictionary = {}
    var target_name := "NO TARGET"
    if _target != null and is_instance_valid(_target):
        target_name = String(_target.name).split("@", false)[0].rstrip("0123456789").capitalize()
        if _target.has_method("get_elemental_status_snapshot"):
            snapshot = _target.get_elemental_status_snapshot()
    var immunity_text := ""
    if _target != null and _target.has_method("get_elemental_immunities"):
        var immunities: Array = _target.get_elemental_immunities()
        if not immunities.is_empty():
            immunity_text = "  ·  IMMUNE " + ",".join(immunities).to_upper()
    _target_label.text = "%s  ·  BUILDUP%s" % [target_name, immunity_text]
    for element in ELEMENTS:
        var stack_count := int(snapshot.get(element, 0))
        var entry: Dictionary = _meters[element]
        var meter: ProgressBar = entry["meter"]
        var value: Label = entry["value"]
        meter.value = stack_count
        value.text = "%d/%d" % [stack_count, int(MAX_STACKS[element])]
