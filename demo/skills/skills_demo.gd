extends IKInventoryUI
## Skill Tree Kit demo: a Warrior tree on a grid and a Survivor tree placed freely with
## curved links (ranks, requirements, row gates), active abilities, exclusive choices
## ("choose one style"), level-ups that give points, the character's stats built from the
## learned skills, a reset that costs gold from the bag, save / load and the art styles.

const ART := "res://addons/inventory_kit/art/"
const DIRECTIONS := {"painted": "Hand-painted", "realistic": "Realistic", "cartoon": "Cartoon", "flat": "Flat"}
const SAVE_DIR := "user://skills_demo/"
const SITE := "https://banc-essai.site-testeurs.workers.dev/?src=skills-demo"
const BASE_STATS := {&"damage": 10.0, &"armor": 5.0, &"health": 100.0, &"ranged": 6.0, &"healing": 0.0, &"gathering": 0.0, &"scouting": 0.0, &"stamina": 100.0}

var bag: IKInventory
var skills: TKSkills
var view: TKTreeView
var level := 1
var art_direction := ""
var _picker: OptionButton
var _stats: RichTextLabel
var _level: Label
var _status: Label
var _save := IKSaveFile.new(SAVE_DIR + "inventory.json")


static func available_directions() -> Array[String]:
	var result: Array[String] = []
	for da in DIRECTIONS:
		if ResourceLoader.exists(ART + "%s/%s_items.tres" % [da, da]):
			result.append(da)
	return result


static func make_trees() -> Array[TKSkillTree]:
	var warrior := TKSkillTree.new()
	warrior.id = &"warrior"
	warrior.title = "Warrior"
	warrior.points_per_row = 3
	_skill(warrior, &"blade", "Blade Training", "+%d damage.", Vector2i(0, 0), 3, {&"damage": 2.0}, {}, &"sword")
	_skill(warrior, &"shield_wall", "Shield Wall", "+%d armor.", Vector2i(1, 0), 3, {&"armor": 3.0}, {}, &"shield")
	_skill(warrior, &"toughness", "Toughness", "+%d health.", Vector2i(2, 0), 3, {&"health": 10.0}, {}, &"iron_helmet")
	var cleave := _skill(warrior, &"cleave", "Cleave", "+%d damage: your swings hit two enemies.", Vector2i(0, 1), 1, {&"damage": 5.0}, {&"blade": 2}, &"axe")
	cleave.ability = &"cleave"
	_skill(warrior, &"heavy_armor", "Heavy Armor", "+%d armor.", Vector2i(1, 1), 2, {&"armor": 6.0}, {&"shield_wall": 1}, &"iron_chest")
	var second_wind := _skill(warrior, &"second_wind", "Second Wind", "+%d health, once per fight.", Vector2i(2, 1), 1, {&"health": 25.0}, {&"toughness": 2}, &"roast_meat")
	second_wind.ability = &"second_wind"
	_skill(warrior, &"crushing", "Crushing Blows", "+%d damage.", Vector2i(0, 2), 2, {&"damage": 4.0}, {&"cleave": 1}, &"mace")
	_skill(warrior, &"juggernaut", "Juggernaut", "+%d armor.", Vector2i(1, 2), 1, {&"armor": 15.0}, {&"heavy_armor": 2}, &"steel_chest")
	var warlord := _skill(warrior, &"warlord", "Warlord", "+%d damage.", Vector2i(1, 3), 1, {&"damage": 12.0}, {&"crushing": 1, &"juggernaut": 1}, &"spear")
	warlord.cost = 2
	# A fighting style: Whirlwind or Bulwark, not both (a reset frees the choice).
	var whirlwind := _skill(warrior, &"whirlwind", "Whirlwind", "Active: spin and hit every enemy around you. +%d damage.", Vector2i(0, 3), 1, {&"damage": 6.0}, {&"crushing": 1}, &"dagger")
	whirlwind.ability = &"whirlwind"
	whirlwind.exclusive_group = &"warrior_style"
	var bulwark := _skill(warrior, &"bulwark", "Bulwark", "Active: draw every enemy to you. +%d armor.", Vector2i(2, 3), 1, {&"armor": 10.0}, {&"juggernaut": 1}, &"mithril_chest")
	bulwark.ability = &"bulwark"
	bulwark.exclusive_group = &"warrior_style"
	var survivor := TKSkillTree.new()
	survivor.id = &"survivor"
	survivor.title = "Survivor"
	survivor.points_per_row = 2
	# Placed freely (grid units): the view draws curved links. Rows still open with points.
	_skill(survivor, &"lumberjack", "Lumberjack", "+%d%% wood when chopping.", Vector2i(0, 0), 3, {&"gathering": 10.0}, {}, &"oak_log").place(Vector2(0.0, 0.0))
	_skill(survivor, &"herbalist", "Herbalist", "+%d healing from herbs.", Vector2i(1, 0), 3, {&"healing": 5.0}, {}, &"herb").place(Vector2(1.6, 0.0))
	_skill(survivor, &"archery", "Archery", "+%d ranged damage.", Vector2i(2, 0), 3, {&"ranged": 2.0}, {}, &"bow").place(Vector2(3.2, 0.0))
	_skill(survivor, &"night_eyes", "Night Eyes", "+%d scouting range.", Vector2i(0, 1), 2, {&"scouting": 1.0}, {}, &"torch").place(Vector2(0.4, 1.2))
	_skill(survivor, &"alchemy", "Alchemy", "+%d healing from potions.", Vector2i(1, 1), 2, {&"healing": 10.0}, {&"herbalist": 2}, &"health_potion").place(Vector2(1.6, 1.35))
	var quick_draw := _skill(survivor, &"quick_draw", "Quick Draw", "+%d ranged damage. Active: a quick shot.", Vector2i(2, 1), 2, {&"ranged": 3.0}, {&"archery": 2}, &"arrows").place(Vector2(2.9, 1.2))
	quick_draw.ability = &"quick_shot"
	var pathfinder := _skill(survivor, &"pathfinder", "Pathfinder", "+%d scouting range. Active: reveal the map around you.", Vector2i(0, 2), 1, {&"scouting": 3.0}, {&"night_eyes": 1}, &"map").place(Vector2(0.0, 2.5))
	pathfinder.ability = &"reveal_map"
	pathfinder.exclusive_group = &"survivor_calling"
	_skill(survivor, &"endurance", "Endurance", "+%d stamina.", Vector2i(1, 2), 3, {&"stamina": 15.0}, {&"alchemy": 1}, &"stamina_potion").place(Vector2(1.6, 2.6))
	var mark := _skill(survivor, &"hunters_mark", "Hunter's Mark", "+%d ranged damage. Active: mark a prey.", Vector2i(2, 2), 1, {&"ranged": 5.0}, {&"quick_draw": 1}, &"scroll").place(Vector2(3.2, 2.5))
	mark.ability = &"hunters_mark"
	mark.exclusive_group = &"survivor_calling"
	return [warrior, survivor]


static func _skill(tree: TKSkillTree, id: StringName, title: String, description: String, position: Vector2i,
		max_rank: int, effects: Dictionary, requires: Dictionary, icon_item: StringName) -> TKSkill:
	var skill := TKSkill.make(id, title, position, max_rank, effects, requires, icon_item)
	skill.description = description
	return tree.add(skill)


func _ready() -> void:
	var directions := available_directions()
	var database: IKItemDatabase = load(ART + "%s/%s_items.tres" % [directions[0], directions[0]])
	bag = IKInventory.new()
	bag.name = "Bag"
	bag.container_id = &"bag"
	bag.size = 6
	bag.database = database
	bag.initial_items.assign({&"gold_coins": 120})
	add_child(bag)
	skills = TKSkills.new()
	skills.name = "Skills"
	skills.trees = make_trees()
	skills.database = database
	skills.points = 5
	skills.reset_cost = {&"gold_coins": 50}
	add_child(skills)
	_build_layout(directions)
	super._ready()
	view.skills = skills
	view.bag = bag.container
	skills.changed.connect(_refresh_stats)
	view.learned.connect(func(skill: TKSkill, rank: int) -> void: _set_status("%s rank %d learned." % [skill.get_title(), rank]))
	view.refused.connect(func(_r: TKResult, text: String) -> void: _set_status(text, true))
	skills.ability_unlocked.connect(func(ability: StringName, _skill: TKSkill) -> void: _set_status("New ability: %s!" % String(ability).capitalize()))
	interaction_failed.connect(func(result: IKResult) -> void: _set_status(IKText.result_message(result), true))
	apply_art_direction(directions[0])
	_refresh_stats()


func apply_art_direction(da: String) -> void:
	art_direction = da
	var database: IKItemDatabase = load(ART + "%s/%s_items.tres" % [da, da])
	bag.container.database = database
	cursor.container.database = database
	skills.database = database
	theme = load(ART + "%s/%s_theme.tres" % [da, da])
	skin = load(ART + "%s/%s_skin.tres" % [da, da])
	view.skin = skin
	var index := available_directions().find(da)
	if _picker != null and index >= 0 and _picker.selected != index:
		_picker.select(index)


func level_up() -> void:
	level += 1
	skills.points += 1
	_refresh_stats()
	_set_status("Level %d: +1 skill point." % level)


func _refresh_stats() -> void:
	if _stats == null:
		return
	var lines := PackedStringArray()
	for stat: StringName in BASE_STATS:
		var bonus := skills.get_bonus(stat)
		var total: float = BASE_STATS[stat] + bonus
		lines.append("%s  [b]%d[/b]%s" % [String(stat).capitalize(), roundi(total), "  [color=#7ee08a]+%d[/color]" % roundi(bonus) if bonus > 0 else ""])
	var abilities := PackedStringArray()
	for ability in skills.get_abilities():
		abilities.append(String(ability).capitalize())
	lines.append("Abilities  [color=#8fd3ff]%s[/color]" % (", ".join(abilities) if not abilities.is_empty() else "none yet"))
	_stats.text = "\n".join(lines)
	_level.text = "Level %d" % level


func _build_layout(directions: Array[String]) -> void:
	var background := ColorRect.new()
	background.color = Color(0.07, 0.08, 0.10)
	background.mouse_filter = MOUSE_FILTER_IGNORE
	background.set_anchors_preset(PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	column.add_child(header)
	var title := Label.new()
	title.text = "Skill Tree Kit — demo"
	title.add_theme_font_size_override(&"font_size", 22)
	header.add_child(title)
	_picker = OptionButton.new()
	for da in directions:
		_picker.add_item(DIRECTIONS[da])
	_picker.item_selected.connect(func(index: int) -> void: apply_art_direction(directions[index]))
	_picker.focus_mode = FOCUS_NONE
	header.add_child(_picker)
	_button(header, "Save", _on_save)
	_button(header, "Load", _on_load)
	var site := LinkButton.new()
	site.text = "More kits & our games »"
	site.uri = SITE
	site.size_flags_vertical = SIZE_SHRINK_CENTER
	header.add_child(site)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 14)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 8)
	left.custom_minimum_size = Vector2(300, 0)
	body.add_child(left)
	var hero := PanelContainer.new()
	left.add_child(hero)
	var hero_box := VBoxContainer.new()
	hero.add_child(hero_box)
	_level = Label.new()
	_level.add_theme_font_size_override(&"font_size", 20)
	hero_box.add_child(_level)
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.fit_content = true
	_stats.scroll_active = false
	_stats.custom_minimum_size = Vector2(260, 0)
	hero_box.add_child(_stats)
	_button(left, "Level up (+1 skill point)", level_up)
	var bag_frame := PanelContainer.new()
	left.add_child(bag_frame)
	var bag_box := VBoxContainer.new()
	bag_frame.add_child(bag_box)
	var bag_label := Label.new()
	bag_label.text = "Your bag (a reset costs 50 gold)"
	bag_box.add_child(bag_label)
	var bag_view := IKContainerView.new()
	bag_view.name = "BagView"
	bag_view.columns = 6
	bag_view.inventory = bag
	bag_box.add_child(bag_view)
	_status = Label.new()
	_status.text = "Click a skill, then click it again (or Learn) to spend a point. Dashed lines: choose one."
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(300, 0)
	left.add_child(_status)

	view = TKTreeView.new()
	view.name = "TreeView"
	view.size_flags_horizontal = SIZE_EXPAND_FILL
	view.size_flags_vertical = SIZE_EXPAND_FILL
	view.close_requested.connect(func() -> void: _set_status("Cancel in the tree: a game would close it here."))
	body.add_child(view)


func _button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)


func _on_save() -> void:
	return_held()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var error := _save.save([bag.container])
	var file := FileAccess.open(SAVE_DIR + "skills.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"skills": skills.to_data(), "level": level}, "\t"))
	_set_status("Saved: bag, level and skills." if error == OK and file != null else "Save failed.", error != OK or file == null)


func _on_load() -> void:
	return_held()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_DIR + "skills.json"))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("skills")) != TYPE_DICTIONARY:
		_set_status("Nothing to load yet: press Save first.", true)
		return
	var report := _save.load_into([bag.container])
	if not report.ok:
		_set_status(report.error, true)
		return
	skills.load_data(parsed.skills)
	level = int(parsed.get("level", 1))
	_refresh_stats()
	_set_status("Loaded.")


func _set_status(text: String, warning: bool = false) -> void:
	_status.text = text
	_status.modulate = Color(1, 0.6, 0.5) if warning else Color(0.7, 1, 0.7)
