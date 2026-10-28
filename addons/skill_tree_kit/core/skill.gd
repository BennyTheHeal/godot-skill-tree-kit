@tool
class_name TKSkill
extends Resource
## One node of a tree: ranks, what it costs, what it needs, what it gives.

## Stable id, stored in save files. Pick it once and never change it.
@export var id: StringName
@export var title: String = ""
## "%d" is replaced by the total bonus at the shown rank: "+%d damage".
@export_multiline var description: String = ""
## Place in the tree: column, row (row 0 at the top). With [member use_free_position], the
## view draws the skill at [member free_position] instead, but the row still counts for row gates.
@export var position: Vector2i = Vector2i.ZERO
@export_range(1, 20) var max_rank: int = 1
## Skill points per rank.
@export_range(0, 20) var cost: int = 1
## Skills (and ranks) needed first, {skill_id: rank}. Drawn as lines in the tree view.
@export var requires: Dictionary[StringName, int] = {}
## Bonus per rank, {stat: amount}: {&"damage": 2.0} gives +2 per rank.
@export var effects: Dictionary[StringName, float] = {}
@export_group("Look")
## Icon. Empty = the icon of [member icon_item] from the item database.
@export var icon: Texture2D
@export var icon_item: StringName
@export_group("Ability")
## Active ability this skill unlocks (a spell, a dash, a new attack): [signal TKSkills.ability_unlocked]
## tells your game when to grant it. Empty = only the numeric [member effects].
@export var ability: StringName
## Rank at which [member ability] unlocks.
@export_range(1, 20) var ability_rank: int = 1
@export_group("Choice")
## Skills sharing a group are exclusive ("choose A or B"): learning one locks the others
## until it is unlearned or reset. Groups count across every tree of a [TKSkills].
@export var exclusive_group: StringName
@export_group("Layout")
## Draws the skill at [member free_position] instead of its grid cell.
@export var use_free_position := false
## Position in grid units: (1.5, 0.5) = halfway between columns 1 and 2, half a row down.
@export var free_position := Vector2.ZERO


static func make(p_id: StringName, p_title: String, p_position: Vector2i, p_max_rank: int = 1,
		p_effects: Dictionary = {}, p_requires: Dictionary = {}, p_icon_item: StringName = &"") -> TKSkill:
	var skill := TKSkill.new()
	skill.id = p_id
	skill.title = p_title
	skill.position = p_position
	skill.max_rank = p_max_rank
	skill.effects.assign(p_effects)
	skill.requires.assign(p_requires)
	skill.icon_item = p_icon_item
	return skill


func get_title() -> String:
	return TKText.t(title) if not title.is_empty() else String(id).capitalize()


## Description with "%d" filled for [param rank] (at least rank 1, to show what it does).
func get_description(rank: int) -> String:
	var text := TKText.t(description)
	if not text.contains("%d") or effects.is_empty():
		return text
	var first: float = effects.values()[0]
	return text % roundi(first * maxi(1, rank))


func get_icon(database: IKItemDatabase) -> Texture2D:
	if icon != null:
		return icon
	var definition := database.get_item(icon_item) if database != null and not icon_item.is_empty() else null
	return definition.icon if definition != null else null


## Free placement in grid units (see [member free_position]); returns the skill, to chain.
func place(at: Vector2) -> TKSkill:
	use_free_position = true
	free_position = at
	return self


## Where the view draws it, in grid units.
func get_layout_position() -> Vector2:
	return free_position if use_free_position else Vector2(position)


## True once [param rank] reaches [member ability_rank] (and there is an ability).
func gives_ability(rank: int) -> bool:
	return not ability.is_empty() and rank >= ability_rank
