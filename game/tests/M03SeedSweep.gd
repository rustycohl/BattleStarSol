extends SceneTree

## M03-002 headless scenario sweep.
##
##   Godot --path game --headless --script res://tests/M03SeedSweep.gd
##
## Instantiates the real mission for a range of deployment seeds and asks the
## production AI what each armed hostile would do on its own turn. It changes no
## production behavior and asserts nothing: it measures whether the ordinary
## non-Proving-Ground mission can express the canonical M03 cover and flank
## rationale, and reports which seeds do.
##
## Seeds are the ones the live launcher can actually produce. The launcher hashes
## `<sector>|<latitude>|<longitude>|<deployment_count>` with FNV-1a, so the same
## hash is reproduced here and self-checked against known launcher values.

const Config = preload("res://scripts/GameConfig.gd")

const COVER_SIGNATURES: Array[String] = [
	"protective cover now",
	"lean from committed cover",
	"cover has no legal attack lane",
	"cover route",
	"simple flank"
]

# A coordinate selection on the A.T.L.A.S. globe. Any sector name other than
# "Proving Ground" takes the armed-hostile spawn path.
const SECTOR := "COORD 34.05N 118.24W"
const LATITUDE := 34.0522
const LONGITUDE := -118.2437
const FIRST_DEPLOYMENT := 1
const DEPLOYMENT_COUNT := 8
# Cover-seeking is a mid-engagement behavior: it needs a hostile holding line of
# sight. At spawn the forces are twenty cells apart and every agent correctly
# chooses approach, so the sweep must let the mission close the distance.
const ROUNDS := 8

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var self_check := _self_check_seed_hash()
	var rows: Array = []
	var expressive: Array = []
	for deployment in range(FIRST_DEPLOYMENT, FIRST_DEPLOYMENT + DEPLOYMENT_COUNT):
		var seed_value := _launcher_seed(SECTOR, LATITUDE, LONGITUDE, deployment)
		var row := await _probe_seed(seed_value, deployment)
		rows.append(row)
		if bool(row["canonical"]):
			expressive.append(row)
		print("  seed %d (deployment %d): armed=%d rounds=%d canonical=%s round=%d [%s] decisions=%s" % [
			seed_value,
			deployment,
			int(row["armed_hostiles"]),
			int(row["rounds_played"]),
			str(row["canonical"]),
			int(row["first_canonical_round"]),
			", ".join(PackedStringArray(row["signatures"])),
			", ".join(PackedStringArray(row["decisions"]))
		])
	var document := {
		"schema": "gzg.battlestar.m03-seed-sweep/1.0",
		"engine": Engine.get_version_info().get("string", ""),
		"sector": SECTOR,
		"latitude": LATITUDE,
		"longitude": LONGITUDE,
		"seed_hash_self_check": self_check,
		"deployments_probed": DEPLOYMENT_COUNT,
		"expressive_seeds": expressive.size(),
		"rows": rows
	}
	print("M03_SWEEP_JSON_BEGIN")
	print(JSON.stringify(document, "  "))
	print("M03_SWEEP_JSON_END")
	quit(0)

func _probe_seed(seed_value: int, deployment: int) -> Dictionary:
	var bridge = root.get_node_or_null("PayloadBridge")
	if bridge:
		bridge.set_payload({
			"type": "deploy",
			"sector": SECTOR,
			"faction": "HAD",
			"seed": seed_value,
			"squad": [{"name": "SWEEP-1"}, {"name": "SCOUT-3"}, {"name": "MEDIC-2"}],
			"objectives": ["Recon selected coordinates", "Neutralize hostiles", "Extract"],
			"resources": {"neural": 50, "capital": 25000}
		})
	var main = (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var game_state = root.get_node_or_null("GameState")
	var signatures := {}
	var decisions := {}
	var hostiles := 0
	var armed := 0
	var rounds_played := 0
	var first_canonical_round := 0
	for unit in main.units:
		if unit == null or not bool(unit.alive):
			continue
		if int(unit.team) == int(main.player_faction):
			continue
		hostiles += 1
		if int(unit.max_ap) > 0:
			armed += 1

	# Play real rounds. The player simply ends its turn; every hostile decision is
	# the production AI's own, recorded by the game rather than asked for here.
	for _round in range(ROUNDS):
		if main.selected == null:
			break
		main._end_turn()
		var guard := 0
		while (main.turn != main.player_faction or main.busy) and guard < 400:
			await process_frame
			guard += 1
		if guard >= 400:
			break
		rounds_played += 1
		if game_state != null:
			for event in game_state.event_records:
				if String(event.get("event", "")) != "agent_decision":
					continue
				var payload = event.get("payload", {})
				if not (payload is Dictionary):
					continue
				decisions[String(payload.get("decision", "unknown"))] = true
				var rationale := String(payload.get("rationale", ""))
				for signature in COVER_SIGNATURES:
					if rationale.contains(signature):
						if signatures.is_empty():
							first_canonical_round = int(payload.get("round", rounds_played))
						signatures[signature] = true
		if not signatures.is_empty():
			break
	main.free()
	await process_frame
	var router = root.get_node_or_null("ActionRouter")
	if router != null:
		router.bind(null)
	return {
		"seed": seed_value,
		"deployment_count": deployment,
		"hostiles": hostiles,
		"armed_hostiles": armed,
		"rounds_played": rounds_played,
		"first_canonical_round": first_canonical_round,
		"decisions": decisions.keys(),
		"signatures": signatures.keys(),
		"canonical": signatures.size() > 0
	}

## FNV-1a 32-bit, matching `positiveSeed` in `game/web/bridge.js`.
func _launcher_seed(sector: String, latitude: float, longitude: float, deployment: int) -> int:
	return _fnv1a_positive("%s|%s|%s|%d" % [
		sector,
		_launcher_number(latitude),
		_launcher_number(longitude),
		deployment
	])

## JavaScript renders 34.0522 as "34.0522" and drops a trailing ".0".
func _launcher_number(value: float) -> String:
	var text := String.num(value, 10)
	while text.contains(".") and text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text

func _fnv1a_positive(value: String) -> int:
	var hash_value := 0x811c9dc5
	for unit_code in value.to_utf32_buffer().to_int32_array():
		hash_value ^= int(unit_code)
		hash_value = (hash_value * 0x01000193) & 0xFFFFFFFF
	return (hash_value % 2147483646) + 1

func _self_check_seed_hash() -> Dictionary:
	# Values produced by `positiveSeed` in the shipped launcher.
	var expected := {
		"Proving Ground|34.0522|-118.2437|1": 1167583760,
		"Proving Ground|34.0522|-118.2437|2": 1117250903,
		"Proving Ground|34.0522|-118.2437|3": 1134028522
	}
	var mismatches: Array = []
	for key in expected:
		var actual := _fnv1a_positive(String(key))
		if actual != int(expected[key]):
			mismatches.append("%s expected %d got %d" % [key, int(expected[key]), actual])
	return {
		"checked": expected.size(),
		"mismatches": mismatches,
		"ok": mismatches.is_empty()
	}
