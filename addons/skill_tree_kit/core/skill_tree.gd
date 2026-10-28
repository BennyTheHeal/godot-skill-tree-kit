@tool
class_name TKSkillTree
extends Resource
## A tree (or a talent page): skills on a grid, optional row gates.

@export var id: StringName
@export var title: String = ""
@export var skills: Array[TKSkill] = []
## Points to spend in this tree before row N opens: N × this. 0 = no row gates.
@export_range(0, 50) var points_per_row: int = 0

var _index: Dictionary = {}
var _indexed_count := -1


func get_skill(skill_id: StringName) -> TKSkill:
	if _indexed_count != skills.size():
		_index.clear()
		for skill in skills:
			if skill != null and not skill.id.is_empty():
				_index[skill.id] = skill
		_indexed_count = skills.size()
	return _index.get(skill_id)


func add(skill: TKSkill) -> TKSkill:
	skills.append(skill)
	_indexed_count = -1
	return skill


func get_title() -> String:
	return TKText.t(title) if not title.is_empty() else String(id).capitalize()


## Grid size: columns, rows.
func get_size() -> Vector2i:
	var size := Vector2i.ZERO
	for skill in skills:
		if skill != null:
			size = size.max(skill.position + Vector2i.ONE)
	return size


## Size in grid units, free placements included (what the view draws).
func get_extent() -> Vector2:
	var extent := Vector2.ZERO
	for skill in skills:
		if skill != null:
			extent = extent.max(skill.get_layout_position() + Vector2.ONE)
	return extent


## Problems a developer should fix: duplicate ids or positions, unknown or circular
## requirements, exclusive skills that require each other.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var ids := {}
	var cells := {}
	for skill in skills:
		if skill == null:
			problems.append("empty slot in tree %s" % id)
			continue
		if skill.id.is_empty() or ids.has(skill.id):
			problems.append("skill id missing or duplicated: '%s'" % skill.id)
		ids[skill.id] = true
		if skill.use_free_position:
			continue  # free placements may share a logical cell
		if cells.has(skill.position):
			problems.append("%s and %s share the cell %s" % [cells[skill.position], skill.id, skill.position])
		cells[skill.position] = skill.id
	for skill in skills:
		if skill == null:
			continue
		for required in skill.requires:
			var other := get_skill(required)
			if other == null:
				problems.append("%s requires unknown skill %s" % [skill.id, required])
			elif skill.requires[required] > other.max_rank:
				problems.append("%s requires rank %d of %s (max %d)" % [skill.id, skill.requires[required], required, other.max_rank])
			elif other.position.y >= skill.position.y:
				problems.append("%s requires %s, which is not on a row above" % [skill.id, required])
			if other != null and not skill.exclusive_group.is_empty() and other.exclusive_group == skill.exclusive_group:
				problems.append("%s requires %s, but they are exclusive (%s)" % [skill.id, required, skill.exclusive_group])
	return problems
