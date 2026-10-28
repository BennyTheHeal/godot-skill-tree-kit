class_name TKTreeView
extends PanelContainer
## A ready-to-use skill tree screen: one tab per tree, skills on their grid with lines
## from each requirement, ranks, a details panel (current and next rank, what is
## missing), Learn / Unlearn and Reset. Works with the mouse, the keyboard and a gamepad:
## focus moves between skills, Enter / A on the selected skill learns a rank, Q / E or
## LB / RB switch trees. Styled by an Inventory Kit [IKSkin] and your Theme.
## Skills placed freely ([member TKSkill.use_free_position]) are drawn where they are, with
## curved links; exclusive choices are joined by a dashed line and the locked side greys out.

signal learned(skill: TKSkill, rank: int)
signal refused(result: TKResult, text: String)
signal close_requested

const TAB_PREVIOUS := &"tk_previous_tab"
const TAB_NEXT := &"tk_next_tab"

## How links are drawn. AUTO: right-angled on grid trees, curves when the tree has free placements.
enum LineStyle { AUTO, ELBOW, CURVE, STRAIGHT }

@export var skills: TKSkills:
	set(value):
		if skills != null and skills.changed.is_connected(_queue_refresh):
			skills.changed.disconnect(_queue_refresh)
		skills = value
		if skills != null:
			skills.changed.connect(_queue_refresh)
		_queue_refresh()
@export var skin: IKSkin:
	set(value):
		skin = value
		_queue_refresh()
## Paid by Reset when [member TKSkills.reset_cost] is set.
var bag: IKContainer
@export var cell_size := Vector2(64, 64)
@export var gap := Vector2(34, 30)
## Line colors: requirement met / not met.
@export var line_on := Color(1.0, 0.82, 0.35)
@export var line_off := Color(1, 1, 1, 0.22)
@export var line_style: LineStyle = LineStyle.AUTO
## Dashed line between the skills of an exclusive group.
@export var exclusive_color := Color(1.0, 0.5, 0.4, 0.55)

var current_tree: int = 0
var _tabs := HBoxContainer.new()
var _points := Label.new()
var _reset := Button.new()
var _canvas := Control.new()
var _icon := TextureRect.new()
var _title := Label.new()
var _rank := Label.new()
var _text := RichTextLabel.new()
var _learn := Button.new()
var _unlearn := Button.new()
var _status := Label.new()
var _buttons: Dictionary = {}  # skill id -> Button
var _selected: StringName
var _fallback_skin: IKSkin
var _refresh_queued := false


func _init() -> void:
	_build()


func _ready() -> void:
	_ensure_actions()
	refresh()


func get_current_tree() -> TKSkillTree:
	if skills == null or skills.trees.is_empty():
		return null
	return skills.trees[clampi(current_tree, 0, skills.trees.size() - 1)]


func show_tree(index: int) -> void:
	if skills == null or skills.trees.is_empty():
		return
	current_tree = posmod(index, skills.trees.size())
	_selected = &""
	refresh()
	_focus_selected.call_deferred()


func refresh() -> void:
	_refresh_queued = false
	_rebuild_tabs()
	var tree := get_current_tree()
	_points.text = "%s %d" % [TKText.t("Skill points:"), skills.points if skills != null else 0]
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focused_id: StringName = focused.get_meta(&"skill_id", &"") if focused != null and _canvas.is_ancestor_of(focused) else &""
	for child in _canvas.get_children():
		_canvas.remove_child(child)
		child.queue_free()
	_buttons.clear()
	if tree == null:
		return
	var grid := tree.get_extent()
	_canvas.custom_minimum_size = Vector2(grid.x * cell_size.x + maxf(0.0, grid.x - 1.0) * gap.x, grid.y * cell_size.y + maxf(0.0, grid.y - 1.0) * gap.y) + Vector2(16, 16)
	for skill in tree.skills:
		if skill == null:
			continue
		var button := Button.new()
		button.set_meta(&"skill_id", skill.id)
		button.icon = skill.get_icon(skills.database)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.custom_minimum_size = cell_size
		button.size = cell_size
		button.position = _place_position(skill.get_layout_position())
		button.focus_mode = FOCUS_ALL
		button.tooltip_text = skill.get_title()
		var rank := skills.get_rank(skill.id)
		var available := skills.can_learn(skill.id).ok
		var excluded := rank == 0 and skills.is_excluded(skill.id)
		var style_skin := _skin()
		button.add_theme_stylebox_override(&"normal", style_skin.get_slot_style(IKSlotView.State.MARKED if skill.id == _selected else IKSlotView.State.NORMAL))
		button.add_theme_stylebox_override(&"hover", style_skin.get_slot_style(IKSlotView.State.HOVER))
		button.add_theme_stylebox_override(&"pressed", style_skin.get_slot_style(IKSlotView.State.MARKED))
		button.add_theme_stylebox_override(&"focus", style_skin.get_slot_style(IKSlotView.State.FOCUS))
		button.add_theme_constant_override(&"icon_max_width", int(cell_size.x - style_skin.icon_margin * 2))
		var tint := Color.WHITE if rank > 0 else (Color(1, 1, 1, 0.85) if available else Color(0.45, 0.45, 0.45, 0.8))
		if excluded:
			tint = Color(0.55, 0.32, 0.3, 0.7)
		for state in [&"icon_normal_color", &"icon_hover_color", &"icon_focus_color", &"icon_pressed_color"]:
			button.add_theme_color_override(state, tint)
		var label := Label.new()
		label.text = "%d/%d" % [rank, skill.max_rank]
		label.mouse_filter = MOUSE_FILTER_IGNORE
		style_skin.apply_amount_label(label)
		if rank >= skill.max_rank:
			label.add_theme_color_override(&"font_color", line_on)
		button.add_child(label)
		label.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
		label.grow_horizontal = GROW_DIRECTION_BEGIN
		label.grow_vertical = GROW_DIRECTION_BEGIN
		label.offset_right = -4
		var skill_id := skill.id
		button.pressed.connect(func() -> void: _on_pressed(skill_id))
		button.focus_entered.connect(func() -> void: _select(skill_id, false))
		_canvas.add_child(button)
		_buttons[skill.id] = button
	if not _buttons.has(_selected):
		_selected = tree.skills[0].id if not tree.skills.is_empty() else &""
	_canvas.queue_redraw()
	_refresh_details()
	if focused_id != &"" and _buttons.has(focused_id):
		_buttons[focused_id].grab_focus.call_deferred()


# --- Building ----------------------------------------------------------------

func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	column.add_child(header)
	_tabs.add_theme_constant_override(&"separation", 6)
	header.add_child(_tabs)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(spacer)
	_points.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.35))
	_points.add_theme_font_size_override(&"font_size", 18)
	header.add_child(_points)
	_reset.text = TKText.t("Reset tree")
	_reset.focus_mode = FOCUS_NONE
	_reset.pressed.connect(_on_reset)
	header.add_child(_reset)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 16)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	center.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.add_child(center)
	_canvas.draw.connect(_draw_lines)
	center.add_child(_canvas)

	var details := VBoxContainer.new()
	details.custom_minimum_size = Vector2(270, 0)
	details.add_theme_constant_override(&"separation", 6)
	body.add_child(details)
	var name_row := HBoxContainer.new()
	details.add_child(name_row)
	_icon.custom_minimum_size = Vector2(48, 48)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	name_row.add_child(_icon)
	var names := VBoxContainer.new()
	name_row.add_child(names)
	_title.add_theme_font_size_override(&"font_size", 19)
	names.add_child(_title)
	_rank.modulate = Color(1, 1, 1, 0.7)
	names.add_child(_rank)
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.size_flags_vertical = SIZE_EXPAND_FILL
	details.add_child(_text)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	details.add_child(buttons)
	_learn.text = TKText.t("Learn")
	_learn.custom_minimum_size = Vector2(110, 40)
	_learn.pressed.connect(func() -> void: _act(skills.learn(_selected)))
	buttons.add_child(_learn)
	_unlearn.text = TKText.t("Unlearn")
	_unlearn.custom_minimum_size = Vector2(0, 40)
	_unlearn.pressed.connect(func() -> void: _act(skills.unlearn(_selected)))
	buttons.add_child(_unlearn)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_status)


func _rebuild_tabs() -> void:
	var count := skills.trees.size() if skills != null else 0
	if _tabs.get_child_count() != count:
		for child in _tabs.get_children():
			_tabs.remove_child(child)
			child.queue_free()
		var group := ButtonGroup.new()
		for i in count:
			var tab := Button.new()
			tab.toggle_mode = true
			tab.button_group = group
			tab.focus_mode = FOCUS_NONE
			var index := i
			tab.pressed.connect(func() -> void: show_tree(index))
			_tabs.add_child(tab)
	for i in count:
		var tab: Button = _tabs.get_child(i)
		tab.text = skills.trees[i].get_title()
		tab.button_pressed = i == current_tree
		tab.modulate = Color.WHITE if i == current_tree else Color(1, 1, 1, 0.55)
	_tabs.visible = count > 1


func _cell_position(cell: Vector2i) -> Vector2:
	return _place_position(Vector2(cell))


## Top-left corner of a skill at [param place] (grid units, free placements included).
func _place_position(place: Vector2) -> Vector2:
	return Vector2(8, 8) + place * (cell_size + gap)


## The style used for [param tree] (AUTO resolved).
func get_line_style(tree: TKSkillTree) -> LineStyle:
	if line_style != LineStyle.AUTO or tree == null:
		return line_style
	for skill in tree.skills:
		if skill != null and skill.use_free_position:
			return LineStyle.CURVE
	return LineStyle.ELBOW


## Points of a link from [param from] (bottom of the required skill) to [param to] (top of the skill).
func _link_points(from: Vector2, to: Vector2, style: LineStyle) -> PackedVector2Array:
	match style:
		LineStyle.STRAIGHT:
			return PackedVector2Array([from, to])
		LineStyle.CURVE:
			var bend := maxf(absf(to.y - from.y) * 0.5, 24.0)
			var c1 := from + Vector2(0, bend)
			var c2 := to - Vector2(0, bend)
			var points := PackedVector2Array()
			for i in 25:
				var t := i / 24.0
				var u := 1.0 - t
				points.append(from * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + to * t * t * t)
			return points
	var middle := (from.y + to.y) / 2
	return PackedVector2Array([from, Vector2(from.x, middle), Vector2(to.x, middle), to])


func _draw_lines() -> void:
	var tree := get_current_tree()
	if tree == null:
		return
	var style := get_line_style(tree)
	var drawn := {}
	for skill in tree.skills:
		if skill == null or skill.exclusive_group.is_empty():
			continue
		for other in tree.skills:
			if other == null or other == skill or other.exclusive_group != skill.exclusive_group or drawn.has(other):
				continue
			var a := _place_position(skill.get_layout_position()) + cell_size / 2
			var b := _place_position(other.get_layout_position()) + cell_size / 2
			_canvas.draw_dashed_line(a, b, exclusive_color, 2.0, 7.0)
		drawn[skill] = true
	for skill in tree.skills:
		if skill == null:
			continue
		for required in skill.requires:
			var other := tree.get_skill(required)
			if other == null:
				continue
			var from := _place_position(other.get_layout_position()) + Vector2(cell_size.x / 2, cell_size.y)
			var to := _place_position(skill.get_layout_position()) + Vector2(cell_size.x / 2, 0)
			var met := skills.get_rank(required) >= skill.requires[required]
			var color := line_on if met else line_off
			_canvas.draw_polyline(_link_points(from, to, style), color, 3.0, true)


# --- Details and actions ----------------------------------------------------------

func _on_pressed(skill_id: StringName) -> void:
	if skill_id == _selected:
		_act(skills.learn(skill_id))  # a second press (or Enter / A on the selection) learns
	else:
		_select(skill_id)


func _select(skill_id: StringName, grab: bool = true) -> void:
	_selected = skill_id
	for id: StringName in _buttons:
		var button: Button = _buttons[id]
		button.add_theme_stylebox_override(&"normal", _skin().get_slot_style(IKSlotView.State.MARKED if id == skill_id else IKSlotView.State.NORMAL))
	if grab and _buttons.has(skill_id) and not _buttons[skill_id].has_focus():
		_buttons[skill_id].grab_focus()
	_refresh_details()


func _refresh_details() -> void:
	var skill := skills.get_skill(_selected) if skills != null and _selected != &"" else null
	_reset.visible = skills != null and get_current_tree() != null and skills.get_spent(get_current_tree()) > 0
	if skill == null:
		_icon.texture = null
		_title.text = ""
		_rank.text = ""
		_text.text = ""
		_learn.disabled = true
		_unlearn.disabled = true
		return
	var rank := skills.get_rank(skill.id)
	_icon.texture = skill.get_icon(skills.database)
	_title.text = skill.get_title()
	_rank.text = "%s %d / %d · %s %d" % [TKText.t("Rank"), rank, skill.max_rank, TKText.t("cost"), skill.cost]
	var lines := PackedStringArray()
	if rank > 0:
		lines.append("[color=#ffd25a]%s[/color] %s" % [TKText.t("Now:"), skill.get_description(rank)])
	if rank < skill.max_rank:
		lines.append("[color=#aab1bf]%s[/color] %s" % [TKText.t("Next rank:") if rank > 0 else TKText.t("Rank 1:"), skill.get_description(rank + 1)])
	if not skill.ability.is_empty():
		var unlocked := skill.gives_ability(rank)
		var ability_line := "%s %s" % [TKText.t("Unlocks:"), TKText.t(String(skill.ability).capitalize())]
		if skill.ability_rank > 1:
			ability_line += " (%s %d)" % [TKText.t("rank"), skill.ability_rank]
		lines.append("[color=%s]%s[/color]" % ["#ffd25a" if unlocked else "#8fd3ff", ability_line])
	var rivals := skills.get_exclusive_rivals(skill.id)
	if not rivals.is_empty():
		var names := PackedStringArray()
		for rival in rivals:
			names.append(rival.get_title())
		var taken := skills.get_exclusive_choice(skill.exclusive_group)
		if taken != null and taken != skill:
			lines.append("[color=#ff7a6b]%s %s[/color]" % [TKText.t("Locked: you chose"), taken.get_title()])
		else:
			lines.append("[color=#ffb38a]%s %s[/color]" % [TKText.t("Choose one, locks:"), ", ".join(names)])
	var check := skills.can_learn(skill.id)
	for required in skill.requires:
		var other := skills.get_skill(required)
		var met := skills.get_rank(required) >= skill.requires[required]
		lines.append("[color=%s]%s %s %d[/color]" % ["#7ee08a" if met else "#ff7a6b", TKText.t("Requires"), other.get_title() if other != null else String(required), skill.requires[required]])
	var tree := skills.get_tree_of(skill.id)
	if tree.points_per_row > 0 and skill.position.y > 0:
		var need := skill.position.y * tree.points_per_row
		var have := skills.get_spent(tree, skill.position.y)
		lines.append("[color=%s]%s %d / %d[/color]" % ["#7ee08a" if have >= need else "#ff7a6b", TKText.t("Points spent above:"), have, need])
	_text.text = "\n".join(lines)
	_learn.disabled = not check.ok
	_learn.tooltip_text = TKText.result_message(check)
	_unlearn.disabled = not skills.can_unlearn(skill.id).ok


func _act(result: TKResult) -> void:
	if result.ok:
		var skill := skills.get_skill(result.skill_id)
		if skill != null:
			_status.text = "%s: %s %d" % [skill.get_title(), TKText.t("rank"), skills.get_rank(skill.id)]
			learned.emit(skill, skills.get_rank(skill.id))
		_status.modulate = Color(0.6, 1, 0.65)
	else:
		var text := TKText.result_message(result)
		_status.text = text
		_status.modulate = Color(1, 0.62, 0.52)
		refused.emit(result, text)
	_queue_refresh()


func _on_reset() -> void:
	var tree := get_current_tree()
	if tree != null:
		var result := skills.reset_tree(tree.id, bag)
		if result.ok:
			_status.text = TKText.t("Points refunded.")
			_status.modulate = Color(0.6, 1, 0.65)
		else:
			_act(result)


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(TAB_PREVIOUS):
		show_tree(current_tree - 1)
		accept_event()
	elif event.is_action_pressed(TAB_NEXT):
		show_tree(current_tree + 1)
		accept_event()
	elif event.is_action_pressed(&"ui_cancel"):
		close_requested.emit()
		accept_event()


func _focus_selected() -> void:
	if is_inside_tree() and _buttons.has(_selected):
		_buttons[_selected].grab_focus()


func _ensure_actions() -> void:
	var defaults := {
		TAB_PREVIOUS: [_key(KEY_Q), _joy(JOY_BUTTON_LEFT_SHOULDER)],
		TAB_NEXT: [_key(KEY_E), _joy(JOY_BUTTON_RIGHT_SHOULDER)],
	}
	for action: StringName in defaults:
		if InputMap.has_action(action):
			continue  # the game's own bindings win
		InputMap.add_action(action)
		for event: InputEvent in defaults[action]:
			InputMap.action_add_event(action, event)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


func _joy(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


func _skin() -> IKSkin:
	if skin != null:
		return skin
	if _fallback_skin == null:
		_fallback_skin = IKSkin.create_default()
	return _fallback_skin


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	refresh.call_deferred()
