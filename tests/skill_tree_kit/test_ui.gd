extends "res://tests/skill_tree_kit/tk_test_case.gd"
## The tree view and the demo scene.


func _view() -> Dictionary:
	var skills := make_skills(5)
	var view := TKTreeView.new()
	view.skills = skills
	add_to_tree(view)
	return {"view": view, "skills": skills}


func test_view_builds_the_tree() -> void:
	var w := _view()
	await wait_frames(2)
	var view: TKTreeView = w.view
	assert_eq(view._buttons.size(), 4)
	var berserk: Button = view._buttons[&"berserk"]
	assert_eq(berserk.position, view._cell_position(Vector2i(0, 2)))


func test_select_then_press_again_learns() -> void:
	var w := _view()
	await wait_frames(2)
	var view: TKTreeView = w.view
	var learned := []
	view.learned.connect(func(skill: TKSkill, rank: int) -> void: learned.append([skill.id, rank]))
	view._on_pressed(&"strength")
	assert_eq(w.skills.get_rank(&"strength"), 1, "strength was already selected (first skill): a press learns")
	view._on_pressed(&"toughness")
	assert_eq(w.skills.get_rank(&"toughness"), 0, "first press selects")
	view._on_pressed(&"toughness")
	assert_eq(w.skills.get_rank(&"toughness"), 1)
	assert_eq(learned, [[&"strength", 1], [&"toughness", 1]])


func test_refusal_and_buttons() -> void:
	var w := _view()
	await wait_frames(2)
	var view: TKTreeView = w.view
	var texts := []
	view.refused.connect(func(_r: TKResult, text: String) -> void: texts.append(text))
	view._select(&"cleave")
	assert_true(view._learn.disabled)
	view._on_pressed(&"cleave")
	assert_eq(texts, ["Learn the skills above it first."])


func test_reset_button() -> void:
	var w := _view()
	await wait_frames(2)
	var view: TKTreeView = w.view
	w.skills.learn(&"strength")
	view._on_reset()
	assert_eq(w.skills.points, 5)


func test_demo_runs_in_every_art_direction() -> void:
	var demo: Node = add_to_tree(load("res://demo/skills/skills_demo.tscn").instantiate())
	await wait_frames(3)
	for tree in demo.skills.trees:
		assert_eq(tree.validate(), PackedStringArray(), tree.id)
	for da in demo.available_directions():
		demo.apply_art_direction(da)
		for i in demo.skills.trees.size():
			demo.view.show_tree(i)
			await wait_frames(1)
			assert_true(demo.view._buttons.size() > 0)
	assert_true(demo.skills.learn(&"blade").ok)
	demo.level_up()
	assert_eq(demo.skills.points, 5)
	var bag: IKContainer = demo.bag.container
	assert_true(demo.skills.reset_all(bag).ok)
	assert_eq(bag.count(&"gold_coins"), 70, "the reset cost 50 gold")
	demo.skills.learn(&"archery")
	demo._on_save()
	demo.skills.learn(&"archery")
	demo._on_load()
	assert_eq(demo.skills.get_rank(&"archery"), 1, "Load restores the ranks")


func test_view_free_layout_curves_and_choices() -> void:
	var w := _view()
	var skills: TKSkills = w.skills
	var view: TKTreeView = w.view
	var tree := skills.trees[0]
	assert_eq(view.get_line_style(tree), TKTreeView.LineStyle.ELBOW, "grid trees keep right angles")
	tree.get_skill(&"berserk").place(Vector2(0.5, 2.5))
	var fury := tree.add(TKSkill.make(&"fury", "Fury", Vector2i(1, 1), 1))
	var calm := tree.add(TKSkill.make(&"calm", "Calm", Vector2i(2, 1), 1))
	fury.exclusive_group = &"temper"
	calm.exclusive_group = &"temper"
	fury.ability = &"rage"
	view.refresh()
	await wait_frames(2)
	assert_eq(view.get_line_style(tree), TKTreeView.LineStyle.CURVE)
	assert_eq(view._buttons[&"berserk"].position, view._place_position(Vector2(0.5, 2.5)))
	assert_eq(view._link_points(Vector2.ZERO, Vector2(0, 100), TKTreeView.LineStyle.CURVE).size(), 25)
	skills.learn(&"strength")
	skills.learn(&"strength")
	skills.learn(&"fury")
	await wait_frames(2)
	view._select(&"calm")
	assert_true(view._text.text.contains("Locked: you chose Fury"), view._text.text)
	assert_true(view._learn.disabled)
	view._select(&"fury")
	assert_true(view._text.text.contains("Unlocks: Rage"), view._text.text)
