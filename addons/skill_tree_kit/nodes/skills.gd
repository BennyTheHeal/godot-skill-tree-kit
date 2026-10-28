class_name TKSkills
extends Node
## The player's skill points and learned ranks across one or more trees.
##
## Learning checks points, requirements and row gates; unlearning refuses what would
## leave another skill (or a row) without what it needs. A full reset can cost items
## (gold, a respec potion), paid in one Inventory Kit transaction. Skills can also unlock
## active abilities ([signal ability_unlocked]) and form exclusive choices
## ([member TKSkill.exclusive_group]: taking one locks the others until a respec).
## [codeblock]
## skills.add_points(1)                      # on level up
## var result := skills.learn(&"heavy_blows")
## var damage := base_damage + skills.get_bonus(&"damage")
## skills.ability_unlocked.connect(func(ability, _skill): hotbar.add(ability))
## [/codeblock]

signal skill_learned(skill: TKSkill, rank: int)
signal skill_unlearned(skill: TKSkill, rank: int)
signal points_changed(points: int)
signal changed
## [param ability] is now available (a skill reached its [member TKSkill.ability_rank]),
## after a learn or a load. Not emitted again while another skill already gives it.
signal ability_unlocked(ability: StringName, skill: TKSkill)
## No learned skill gives [param ability] any more (unlearn, reset, load).
## [param skill] is the one that gave it.
signal ability_locked(ability: StringName, skill: TKSkill)

const DATA_VERSION := 1

@export var trees: Array[TKSkillTree] = []
## Item definitions, for icons. Optional.
@export var database: IKItemDatabase
## Unspent skill points.
@export var points: int = 0:
	set(value):
		points = maxi(0, value)
		points_changed.emit(points)
## Items taken by [method reset_tree] / [method reset_all], {item_id: amount}. Empty = free.
@export var reset_cost: Dictionary[StringName, int] = {}

var _ranks: Dictionary = {}  # skill id -> rank


# --- Reading -------------------------------------------------------------------

func get_rank(skill_id: StringName) -> int:
	return _ranks.get(skill_id, 0)


func get_skill(skill_id: StringName) -> TKSkill:
	var tree := get_tree_of(skill_id)
	return tree.get_skill(skill_id) if tree != null else null


func get_tree_of(skill_id: StringName) -> TKSkillTree:
	for tree in trees:
		if tree != null and tree.get_skill(skill_id) != null:
			return tree
	return null


func get_tree_by_id(tree_id: StringName) -> TKSkillTree:
	for tree in trees:
		if tree != null and tree.id == tree_id:
			return tree
	return null


## Points spent in [param tree], in every row or only in rows above [param above_row].
func get_spent(tree: TKSkillTree, above_row: int = -1) -> int:
	var spent := 0
	for skill in tree.skills:
		if skill != null and (above_row < 0 or skill.position.y < above_row):
			spent += get_rank(skill.id) * skill.cost
	return spent


## Sum of every learned effect on [param stat]: rank × effect, across all trees.
func get_bonus(stat: StringName) -> float:
	var total := 0.0
	for tree in trees:
		if tree == null:
			continue
		for skill in tree.skills:
			if skill != null and skill.effects.has(stat):
				total += skill.effects[stat] * get_rank(skill.id)
	return total


## Every stat with a bonus, {stat: total}.
func get_bonuses() -> Dictionary:
	var totals := {}
	for tree in trees:
		if tree == null:
			continue
		for skill in tree.skills:
			if skill == null or get_rank(skill.id) == 0:
				continue
			for stat in skill.effects:
				totals[stat] = totals.get(stat, 0.0) + skill.effects[stat] * get_rank(skill.id)
	return totals


## True when a learned skill gives [param ability].
func has_ability(ability: StringName) -> bool:
	return _abilities_now().has(ability)


## Every ability the learned skills give, in tree order.
func get_abilities() -> Array[StringName]:
	var list: Array[StringName] = []
	list.assign(_abilities_now().keys())
	return list


## The learned skill of exclusive [param group], or null while the choice is open.
func get_exclusive_choice(group: StringName) -> TKSkill:
	if group.is_empty():
		return null
	for tree in trees:
		if tree == null:
			continue
		for skill in tree.skills:
			if skill != null and skill.exclusive_group == group and get_rank(skill.id) > 0:
				return skill
	return null


## The other skills of [param skill_id]'s exclusive group, across all trees.
func get_exclusive_rivals(skill_id: StringName) -> Array[TKSkill]:
	var rivals: Array[TKSkill] = []
	var skill := get_skill(skill_id)
	if skill == null or skill.exclusive_group.is_empty():
		return rivals
	for tree in trees:
		if tree == null:
			continue
		for other in tree.skills:
			if other != null and other != skill and other.exclusive_group == skill.exclusive_group:
				rivals.append(other)
	return rivals


## True when another skill of its exclusive group is learned (it cannot be learned now).
func is_excluded(skill_id: StringName) -> bool:
	return _excluded_by(skill_id) != null


# --- Learning ------------------------------------------------------------------

func can_learn(skill_id: StringName) -> TKResult:
	var tree := get_tree_of(skill_id)
	if tree == null:
		return TKResult.failure(TKResult.Code.UNKNOWN_SKILL, "no skill '%s'" % skill_id)
	var skill := tree.get_skill(skill_id)
	if get_rank(skill_id) >= skill.max_rank:
		return TKResult.failure(TKResult.Code.MAXED, "%s is at rank %d" % [skill_id, skill.max_rank])
	var rival := _excluded_by(skill_id)
	if rival != null:
		var excluded := TKResult.failure(TKResult.Code.EXCLUSIVE_TAKEN, "%s is exclusive with %s" % [skill_id, rival.id])
		excluded.excluded_by = rival.id
		return excluded
	var missing := {}
	for required in skill.requires:
		if get_rank(required) < skill.requires[required]:
			missing[required] = skill.requires[required]
	if not missing.is_empty():
		var result := TKResult.failure(TKResult.Code.REQUIREMENT_MISSING, "%s needs %s" % [skill_id, missing])
		result.missing = missing
		return result
	if tree.points_per_row > 0 and get_spent(tree, skill.position.y) < skill.position.y * tree.points_per_row:
		return TKResult.failure(TKResult.Code.ROW_LOCKED, "row %d needs %d points spent above" % [skill.position.y, skill.position.y * tree.points_per_row])
	if points < skill.cost:
		return TKResult.failure(TKResult.Code.NOT_ENOUGH_POINTS, "%d points, %d needed" % [points, skill.cost])
	return TKResult.success(skill_id)


func learn(skill_id: StringName) -> TKResult:
	var result := can_learn(skill_id)
	if not result.ok:
		return result
	var skill := get_skill(skill_id)
	var before := _abilities_now()
	_ranks[skill_id] = get_rank(skill_id) + 1
	points -= skill.cost
	skill_learned.emit(skill, _ranks[skill_id])
	_emit_ability_changes(before)
	changed.emit()
	return result


func can_unlearn(skill_id: StringName) -> TKResult:
	var tree := get_tree_of(skill_id)
	if tree == null:
		return TKResult.failure(TKResult.Code.UNKNOWN_SKILL, "no skill '%s'" % skill_id)
	var rank := get_rank(skill_id)
	if rank <= 0:
		return TKResult.failure(TKResult.Code.MAXED, "%s is not learned" % skill_id)
	# Pretend the rank is gone, then check every other learned skill still has what it needs.
	_ranks[skill_id] = rank - 1
	var broken := ""
	for other in tree.skills:
		if other == null or other.id == skill_id or get_rank(other.id) == 0:
			continue
		if other.requires.has(skill_id) and get_rank(skill_id) < other.requires[skill_id]:
			broken = String(other.id)
			break
		if tree.points_per_row > 0 and get_spent(tree, other.position.y) < other.position.y * tree.points_per_row:
			broken = String(other.id)
			break
	_ranks[skill_id] = rank
	if not broken.is_empty():
		return TKResult.failure(TKResult.Code.NEEDED_BY_OTHERS, "%s depends on %s" % [broken, skill_id])
	return TKResult.success(skill_id)


## Takes one rank back and refunds its points.
func unlearn(skill_id: StringName) -> TKResult:
	var result := can_unlearn(skill_id)
	if not result.ok:
		return result
	var skill := get_skill(skill_id)
	var before := _abilities_now()
	_ranks[skill_id] = get_rank(skill_id) - 1
	if _ranks[skill_id] == 0:
		_ranks.erase(skill_id)
	points += skill.cost
	skill_unlearned.emit(skill, get_rank(skill_id))
	_emit_ability_changes(before)
	changed.emit()
	return result


## Refunds every point of [param tree_id]. With a [member reset_cost], the items are taken
## from [param bag] first (all or nothing).
func reset_tree(tree_id: StringName, bag: IKContainer = null) -> TKResult:
	var tree := get_tree_by_id(tree_id)
	if tree == null:
		return TKResult.failure(TKResult.Code.INVALID_ARGUMENT, "no tree '%s'" % tree_id)
	return _reset([tree], bag)


func reset_all(bag: IKContainer = null) -> TKResult:
	return _reset(trees, bag)


# --- Saving ----------------------------------------------------------------------

func to_data() -> Dictionary:
	var ranks := {}
	for skill_id in _ranks:
		ranks[String(skill_id)] = _ranks[skill_id]
	return {"version": DATA_VERSION, "points": points, "ranks": ranks}


## Restores [method to_data]. Ranks of removed skills, or above a lowered max rank,
## are refunded as points; so are the extra choices of an exclusive group (when an update
## made two learned skills exclusive, the first one in tree order stays). Emits
## [signal ability_unlocked] / [signal ability_locked] for what changed.
func load_data(data: Dictionary) -> bool:
	if typeof(data.get("ranks")) != TYPE_DICTIONARY:
		return false
	var before := _abilities_now()
	var refund := 0
	var ranks := {}
	for raw: Variant in data.ranks:
		var skill_id := StringName(str(raw))
		var rank := maxi(0, int(data.ranks[raw]))
		var skill := get_skill(skill_id)
		if skill == null:
			continue
		if rank > skill.max_rank:
			refund += (rank - skill.max_rank) * skill.cost
			rank = skill.max_rank
		if rank > 0:
			ranks[skill_id] = rank
	var chosen := {}  # exclusive group -> kept skill id
	for tree in trees:
		if tree == null:
			continue
		for skill in tree.skills:
			if skill == null or skill.exclusive_group.is_empty() or not ranks.has(skill.id):
				continue
			if chosen.has(skill.exclusive_group):
				refund += int(ranks[skill.id]) * skill.cost
				ranks.erase(skill.id)
			else:
				chosen[skill.exclusive_group] = skill.id
	_ranks = ranks
	points = maxi(0, int(data.get("points", 0))) + refund
	_emit_ability_changes(before)
	changed.emit()
	return true


func _reset(reset_trees: Array, bag: IKContainer) -> TKResult:
	var refund := 0
	for tree: TKSkillTree in reset_trees:
		refund += get_spent(tree)
	if refund == 0:
		return TKResult.success()
	var before := _abilities_now()
	if not reset_cost.is_empty():
		if bag == null:
			return TKResult.failure(TKResult.Code.CANNOT_PAY, "reset costs %s, no bag given" % reset_cost)
		var paid := IKTransaction.new().consume(bag, reset_cost).commit()
		if not paid.ok:
			var refused := TKResult.failure(TKResult.Code.CANNOT_PAY, paid.message)
			refused.inventory_result = paid
			return refused
	for tree: TKSkillTree in reset_trees:
		for skill in tree.skills:
			if skill != null:
				_ranks.erase(skill.id)
	points += refund
	_emit_ability_changes(before)
	changed.emit()
	return TKResult.success()


func _excluded_by(skill_id: StringName) -> TKSkill:
	for rival in get_exclusive_rivals(skill_id):
		if get_rank(rival.id) > 0:
			return rival
	return null


## {ability: skill giving it}, first skill in tree order.
func _abilities_now() -> Dictionary:
	var found := {}
	for tree in trees:
		if tree == null:
			continue
		for skill in tree.skills:
			if skill != null and skill.gives_ability(get_rank(skill.id)) and not found.has(skill.ability):
				found[skill.ability] = skill
	return found


func _emit_ability_changes(before: Dictionary) -> void:
	var now := _abilities_now()
	for ability: StringName in before:
		if not now.has(ability):
			ability_locked.emit(ability, before[ability])
	for ability: StringName in now:
		if not before.has(ability):
			ability_unlocked.emit(ability, now[ability])
