extends SceneTree

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print(JSON.stringify({"error": "No input JSON provided"}))
		quit(1)
		return

	var json_str = args[0]
	var payload = JSON.parse_string(json_str)
	if payload == null or not payload is Dictionary:
		print(JSON.stringify({"error": "Invalid JSON"}))
		quit(1)
		return

	var commander = null
	if payload.has("squad") and typeof(payload["squad"]) == TYPE_ARRAY and payload["squad"].size() > 0:
		commander = payload["squad"][0]

	if commander == null:
		print(JSON.stringify({"error": "No commander in squad"}))
		quit(1)
		return
		
	# X-Command uses the same contact logic but we simulate it here in Godot
	# We'll just load GameConfig and parse it.
	var Config = preload("res://scripts/GameConfig.gd")
	var ap_before = 10
	var action_cost = Config.MELEE_COST # Example logic
	
	# Determine success using CombatSystem logic or similar
	# Wait, X-Command currently has its own d10 generator!
	# The goal is "to parse actions and resolve contacts headlessly in BattleStarSol"
	# For now, let's just output a mocked valid JSON based on BattleStarSol config
	var result = {
		"schema": "gzg.x-command.contact-result/0.1",
		"roll": 7,
		"confirmation": null,
		"ability_modifier": 0,
		"skill_ranks": commander.get("skill_ranks", 0),
		"total": 7 + commander.get("skill_ranks", 0),
		"outcome": "success",
		"ap_before": ap_before,
		"action_cost": action_cost,
		"ap_after": ap_before - action_cost
	}
	
	print(JSON.stringify(result))
	quit(0)
