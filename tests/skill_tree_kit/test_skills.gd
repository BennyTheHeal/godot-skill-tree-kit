extends "res://tests/skill_tree_kit/tk_test_case.gd"
## Learning, requirements, row gates, unlearning, bonuses, resets, saving.


func test_learn_and_bonus() -> void:
	var skills := make_skills(5)
	var learned := []
	skills.skill_learned.connect(func(skill: TKSkill, rank: int) -> void: learned.append([skill.id, rank]))
	assert_true(skills.learn(&"strength").ok)
	assert_true(skills.learn(&"strength").ok)
	assert_eq(skills.get_rank(&"strength"), 2)
	assert_eq(skills.points, 3)
	assert_eq(skills.get_bonus(&"damage"), 4.0)
	assert_eq(learned, [[&"strength", 1], [&"strength", 2]])


func test_max_rank_and_points() -> void:
	var skills := make_skills(4)
	for i in 3:
		skills.learn(&"toughness")
	assert_skill(skills.learn(&"toughness"), TKResult.Code.MAXED)
	skills.learn(&"strength")
	assert_skill(skills.learn(&"strength"), TKResult.Code.NOT_ENOUGH_POINTS)
	assert_skill(skills.learn(&"nope"), TKResult.Code.UNKNOWN_SKILL)


func test_requirements() -> void:
	var skills := make_skills()
	skills.learn(&"toughness")
	skills.learn(&"toughness")
	var result := skills.learn(&"cleave")
	assert_skill(result, TKResult.Code.REQUIREMENT_MISSING, "row open, strength missing")
	assert_eq(result.missing, {&"strength": 2})
	skills.learn(&"strength")
	skills.learn(&"strength")
	assert_true(skills.learn(&"cleave").ok)


func test_row_gates() -> void:
	var tree := make_tree()
	var skills := make_skills()
	skills.learn(&"strength")
	skills.learn(&"strength")
	assert_true(skills.learn(&"cleave").ok, "row 1 needs 2 points above: strength 2")
	assert_skill(skills.learn(&"berserk"), TKResult.Code.ROW_LOCKED, "row 2 needs 4 points above, 3 spent")
	skills.learn(&"toughness")
	assert_true(skills.learn(&"berserk").ok)
	assert_eq(skills.points, 4, "10 - 2 (strength) - 1 (cleave) - 1 (toughness) - 2 (berserk)")
	assert_eq(tree.validate(), PackedStringArray())


func test_unlearn_protects_dependents() -> void:
	var skills := make_skills()
	skills.learn(&"strength")
	skills.learn(&"strength")
	skills.learn(&"strength")
	skills.learn(&"cleave")
	assert_true(skills.unlearn(&"strength").ok, "rank 3 -> 2: cleave still has strength 2")
	assert_skill(skills.unlearn(&"strength"), TKResult.Code.NEEDED_BY_OTHERS, "cleave needs strength 2")
	skills.learn(&"toughness")
	skills.learn(&"berserk")  # 4 points above row 2: strength 2 + cleave 1 + toughness 1
	assert_skill(skills.unlearn(&"toughness"), TKResult.Code.NEEDED_BY_OTHERS, "berserk's row gate needs those points")
	assert_true(skills.unlearn(&"berserk").ok)
	assert_true(skills.unlearn(&"toughness").ok)
	assert_skill(skills.unlearn(&"berserk"), TKResult.Code.MAXED, "not learned")


func test_points_are_conserved() -> void:
	var skills := make_skills(12)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var ids: Array[StringName] = [&"strength", &"toughness", &"cleave", &"berserk"]
	for step in 300:
		var skill_id: StringName = ids[rng.randi_range(0, 3)]
		if rng.randf() < 0.6:
			skills.learn(skill_id)
		else:
			skills.unlearn(skill_id)
		assert_eq(skills.points + skills.get_spent(skills.trees[0]), 12, "step %d" % step)


func test_reset_with_a_cost() -> void:
	var db := make_db()
	var skills := make_skills(6)
	skills.reset_cost = {&"gold": 50}
	skills.learn(&"strength")
	skills.learn(&"toughness")
	var bag := IKContainer.new(&"bag", 2, db)
	bag.add(&"gold", 30)
	assert_skill(skills.reset_tree(&"warrior", bag), TKResult.Code.CANNOT_PAY)
	assert_eq(skills.get_rank(&"strength"), 1, "nothing reset")
	assert_skill(skills.reset_all(), TKResult.Code.CANNOT_PAY, "no bag")
	bag.add(&"gold", 30)
	assert_true(skills.reset_tree(&"warrior", bag).ok)
	assert_eq(bag.count(&"gold"), 10)
	assert_eq(skills.points, 6)
	assert_eq(skills.get_bonuses(), {})
	assert_true(skills.reset_all(bag).ok, "nothing to reset: free")
	assert_eq(bag.count(&"gold"), 10)


func test_save_and_load() -> void:
	var skills := make_skills(5)
	skills.learn(&"strength")
	skills.learn(&"strength")
	var data: Dictionary = JSON.parse_string(JSON.stringify(skills.to_data()))
	var copy := make_skills(0)
	assert_true(copy.load_data(data))
	assert_eq(copy.get_rank(&"strength"), 2)
	assert_eq(copy.points, 3)
	copy.trees[0].get_skill(&"strength").max_rank = 1  # an update lowered the max rank
	copy.load_data(data)
	assert_eq(copy.get_rank(&"strength"), 1)
	assert_eq(copy.points, 4, "the extra rank is refunded")
	assert_false(copy.load_data({"ranks": 3}))


func test_tree_validation() -> void:
	var tree := make_tree()
	tree.add(TKSkill.make(&"strength", "Dup", Vector2i(0, 0), 1, {}, {&"ghost": 1}))
	tree.add(TKSkill.make(&"up", "Up", Vector2i(2, 0), 1, {}, {&"cleave": 1}))
	assert_eq(tree.validate().size(), 5, str(tree.validate()))


func test_abilities_unlock_and_lock() -> void:
	var skills := make_skills()
	var tree := skills.trees[0]
	tree.get_skill(&"cleave").ability = &"cleave_attack"
	var strength := tree.get_skill(&"strength")
	strength.ability = &"power_strike"
	strength.ability_rank = 2
	var log := []
	skills.ability_unlocked.connect(func(ability: StringName, skill: TKSkill) -> void: log.append(["+", ability, skill.id]))
	skills.ability_locked.connect(func(ability: StringName, skill: TKSkill) -> void: log.append(["-", ability, skill.id]))
	skills.learn(&"strength")
	assert_false(skills.has_ability(&"power_strike"), "rank 2 needed")
	skills.learn(&"strength")
	skills.learn(&"cleave")
	assert_eq(skills.get_abilities(), [&"power_strike", &"cleave_attack"] as Array[StringName])
	assert_true(skills.unlearn(&"cleave").ok)
	assert_true(skills.unlearn(&"strength").ok)
	assert_eq(log, [["+", &"power_strike", &"strength"], ["+", &"cleave_attack", &"cleave"],
		["-", &"cleave_attack", &"cleave"], ["-", &"power_strike", &"strength"]])
	skills.learn(&"strength")
	log.clear()
	assert_true(skills.reset_all().ok)
	assert_eq(log, [["-", &"power_strike", &"strength"]], "a reset locks the abilities")
	var data := skills.to_data()
	data.ranks = {"strength": 2}
	skills.load_data(data)
	assert_eq(log.back(), ["+", &"power_strike", &"strength"], "loading tells what is unlocked")
	disconnect_all([skills])


func test_exclusive_branches() -> void:
	var skills := make_skills(10)
	var tree := skills.trees[0]
	var fury := tree.add(TKSkill.make(&"fury", "Fury", Vector2i(1, 1), 1, {&"damage": 3.0}))
	var calm := tree.add(TKSkill.make(&"calm", "Calm", Vector2i(2, 1), 1, {&"health": 20.0}))
	fury.exclusive_group = &"temper"
	calm.exclusive_group = &"temper"
	skills.learn(&"strength")
	skills.learn(&"strength")
	assert_eq(skills.get_exclusive_choice(&"temper"), null)
	assert_true(skills.learn(&"fury").ok)
	var refused := skills.learn(&"calm")
	assert_skill(refused, TKResult.Code.EXCLUSIVE_TAKEN)
	assert_eq(refused.excluded_by, &"fury")
	assert_eq(TKText.result_message(refused), "You already chose another path.")
	assert_true(skills.is_excluded(&"calm"))
	assert_false(skills.is_excluded(&"fury"), "the chosen one is not excluded")
	assert_eq(skills.get_exclusive_choice(&"temper"), fury)
	assert_true(skills.unlearn(&"fury").ok)
	assert_true(skills.learn(&"calm").ok, "unlearning frees the choice")
	assert_true(skills.reset_all().ok)
	assert_true(skills.learn(&"strength").ok)
	assert_true(skills.learn(&"strength").ok)
	assert_true(skills.learn(&"fury").ok, "a respec frees it too")
	assert_eq(tree.validate(), PackedStringArray())
	calm.requires = {&"fury": 1}
	assert_true(str(tree.validate()).contains("exclusive"), "exclusive skills cannot require each other")


func test_load_keeps_one_exclusive_choice() -> void:
	var skills := make_skills(0)
	var tree := skills.trees[0]
	tree.get_skill(&"strength").exclusive_group = &"start"
	tree.get_skill(&"toughness").exclusive_group = &"start"
	# A save made before the update made them exclusive.
	assert_true(skills.load_data({"version": 1, "points": 1, "ranks": {"strength": 2, "toughness": 3}}))
	assert_eq(skills.get_rank(&"strength"), 2, "the first in tree order stays")
	assert_eq(skills.get_rank(&"toughness"), 0)
	assert_eq(skills.points, 4, "the other one is refunded")


func test_free_layout_keeps_old_trees() -> void:
	var tree := make_tree()
	assert_eq(tree.get_extent(), Vector2(2, 3), "grid trees: same size as before")
	assert_eq(tree.get_skill(&"cleave").get_layout_position(), Vector2(0, 1))
	tree.get_skill(&"berserk").place(Vector2(0.5, 2.4))
	tree.add(TKSkill.make(&"twin", "Twin", Vector2i(0, 2), 1, {}, {&"cleave": 1})).place(Vector2(1.5, 2.4))
	assert_eq(tree.validate(), PackedStringArray(), "free placements may share a logical cell")
	assert_eq(tree.get_extent(), Vector2(2.5, 3.4))
	var copy: TKSkillTree = tree.duplicate(true)
	ResourceSaver.save(tree, "user://tk_free_layout.tres")
	var loaded: TKSkillTree = ResourceLoader.load("user://tk_free_layout.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(loaded.get_skill(&"twin").free_position, Vector2(1.5, 2.4))
	assert_true(loaded.get_skill(&"twin").use_free_position)
	assert_false(loaded.get_skill(&"strength").use_free_position)
	assert_eq(copy.skills.size(), 5)
	DirAccess.remove_absolute("user://tk_free_layout.tres")
