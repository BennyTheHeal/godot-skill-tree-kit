class_name TKResult
extends RefCounted
## Outcome of learning, unlearning or resetting skills.

enum Code {
	OK,
	INVALID_ARGUMENT,
	UNKNOWN_SKILL,
	## Already at its max rank (learn) or at rank 0 (unlearn).
	MAXED,
	NOT_ENOUGH_POINTS,
	## A required skill (or rank) is missing: see [member missing].
	REQUIREMENT_MISSING,
	## Not enough points spent in this tree to open the row.
	ROW_LOCKED,
	## Unlearn: another learned skill, or a row gate, depends on it.
	NEEDED_BY_OTHERS,
	## Respec: the item cost could not be paid.
	CANNOT_PAY,
	## Another skill of the same [member TKSkill.exclusive_group] is learned: see [member excluded_by].
	EXCLUSIVE_TAKEN,
}

var code: Code = Code.OK
var message: String = ""
var skill_id: StringName
## REQUIREMENT_MISSING: {skill_id: rank needed}.
var missing: Dictionary = {}
var inventory_result: IKResult
## EXCLUSIVE_TAKEN: the learned skill that locks this one.
var excluded_by: StringName

var ok: bool:
	get:
		return code == Code.OK


static func success(p_skill_id: StringName = &"") -> TKResult:
	var result := TKResult.new()
	result.skill_id = p_skill_id
	return result


static func failure(error_code: Code, error_message: String = "") -> TKResult:
	var result := TKResult.new()
	result.code = error_code
	result.message = error_message
	return result


func code_name() -> String:
	return Code.keys()[code]


func _to_string() -> String:
	return "TKResult(OK, %s)" % skill_id if ok else "TKResult(%s: %s)" % [code_name(), message]
