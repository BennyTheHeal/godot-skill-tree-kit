class_name TKText
extends RefCounted
## Every text Skill Tree Kit shows to players goes through here, so it can be translated
## or reworded with Godot's translation system (template:
## [code]addons/skill_tree_kit/translations/skill_tree_kit.csv[/code]).

static var result_texts := {
	TKResult.Code.INVALID_ARGUMENT: "That did not work.",
	TKResult.Code.UNKNOWN_SKILL: "Unknown skill.",
	TKResult.Code.MAXED: "Already at its highest rank.",
	TKResult.Code.NOT_ENOUGH_POINTS: "Not enough skill points.",
	TKResult.Code.REQUIREMENT_MISSING: "Learn the skills above it first.",
	TKResult.Code.ROW_LOCKED: "Spend more points in this tree to open this row.",
	TKResult.Code.NEEDED_BY_OTHERS: "Other skills depend on this one.",
	TKResult.Code.CANNOT_PAY: "You cannot pay for the reset.",
	TKResult.Code.EXCLUSIVE_TAKEN: "You already chose another path.",
}


static func t(text: String) -> String:
	if text.is_empty():
		return text
	return String(TranslationServer.translate(text))


static func result_message(result: TKResult) -> String:
	if result == null or result.ok:
		return ""
	if result.inventory_result != null and not result.inventory_result.player_text.is_empty():
		return IKText.result_message(result.inventory_result)
	return t(result_texts.get(result.code, "That did not work."))
