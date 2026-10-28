extends RefCounted
## Base class for Skill Tree Kit tests: assertions and shared fixtures.

var _failures := PackedStringArray()
var _nodes: Array[Node] = []


func get_failures() -> PackedStringArray:
	return _failures


func get_tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Adds [param node] to the scene root; it is freed after the test.
func add_to_tree(node: Node) -> Node:
	get_tree().root.add_child(node)
	_nodes.append(node)
	return node


func wait_frames(count: int = 1) -> void:
	for i in count:
		await get_tree().process_frame


## Called by the runner after each test.
func cleanup() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	await get_tree().process_frame


func fail(message: String) -> void:
	_failures.append(message)


func assert_true(condition: bool, message: String = "expected true") -> void:
	if not condition:
		fail(message)


func assert_false(condition: bool, message: String = "expected false") -> void:
	if condition:
		fail(message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("%sexpected <%s> but got <%s>" % [message + ": " if message else "", expected, actual])


func assert_ok(result: IKResult, message: String = "") -> void:
	if result == null or not result.ok:
		fail("%sexpected OK, got %s" % [message + ": " if message else "", result])


func assert_code(result: IKResult, code: IKResult.Code, message: String = "") -> void:
	if result == null or result.code != code:
		fail("%sexpected %s, got %s" % [message + ": " if message else "", IKResult.Code.keys()[code], result])


## Disconnects every signal of [param objects]. Call at the end of tests whose
## lambdas capture the emitter, otherwise the reference cycle leaks.
func disconnect_all(objects: Array) -> void:
	for object: Object in objects:
		for info in object.get_signal_list():
			for connection in object.get_signal_connection_list(info.name):
				object.disconnect(info.name, connection.callable)




# --- Fixtures ----------------------------------------------------------------

func assert_skill(result: TKResult, code: TKResult.Code, message: String = "") -> void:
	if result == null or result.code != code:
		fail("%sexpected %s, got %s" % [message + ": " if message else "", TKResult.Code.keys()[code], result])


## Warrior tree, 2 points per row:
##   row 0: strength (3 ranks, +2 damage)   toughness (3 ranks, +5 health)
##   row 1: cleave (needs strength 2, +4 damage)
##   row 2: berserk (needs cleave 1, cost 2, +10 damage)
func make_tree() -> TKSkillTree:
	var tree := TKSkillTree.new()
	tree.id = &"warrior"
	tree.points_per_row = 2
	tree.add(TKSkill.make(&"strength", "Strength", Vector2i(0, 0), 3, {&"damage": 2.0}))
	tree.add(TKSkill.make(&"toughness", "Toughness", Vector2i(1, 0), 3, {&"health": 5.0}))
	tree.add(TKSkill.make(&"cleave", "Cleave", Vector2i(0, 1), 1, {&"damage": 4.0}, {&"strength": 2}))
	var berserk := tree.add(TKSkill.make(&"berserk", "Berserk", Vector2i(0, 2), 1, {&"damage": 10.0}, {&"cleave": 1}))
	berserk.cost = 2
	return tree


func make_skills(points: int = 10) -> TKSkills:
	var skills := TKSkills.new()
	skills.trees = [make_tree()]
	skills.points = points
	add_to_tree(skills)
	return skills


func make_db() -> IKItemDatabase:
	var db := IKItemDatabase.new()
	var gold := IKItemDefinition.new()
	gold.id = &"gold"
	gold.max_stack = 999
	db.add_item(gold)
	return db
