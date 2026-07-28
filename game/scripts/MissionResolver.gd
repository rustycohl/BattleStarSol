extends RefCounted
class_name MissionResolver

## Mission end / extraction policy.
## Victory, defeat, and emergency evac all produce ExtractionResult artifacts
## for A.T.L.A.S. / local vault via PayloadBridge.

const Config = preload("res://scripts/GameConfig.gd")

static func count_living(units: Array, team: int) -> int:
	var n := 0
	for u in units:
		if u != null and bool(u.alive) and int(u.team) == team:
			n += 1
	return n

static func count_hostiles(units: Array, player_faction: int) -> int:
	var n := 0
	for u in units:
		if u != null and bool(u.alive) and int(u.team) != player_faction:
			n += 1
	return n

static func compile_salvage(units: Array, debris: Dictionary, player_faction: int, mission_type: String, rng: RandomNumberGenerator) -> Array:
	var loot: Array = []
	var mtype := mission_type if mission_type != "" else "covert"
	if mtype == "kinetic" or mtype == "ballistic":
		for cell in debris.keys():
			for k in debris[cell].keys():
				var q = int(debris[cell].get(k, 0))
				for _i in range(q):
					if mtype == "ballistic" and rng != null and rng.randf() < 0.75:
						continue
					loot.append(k)
	for u in units:
		if u == null or not bool(u.alive) or int(u.team) != player_faction:
			continue
		for k in u.inv.keys():
			var q2 = int(u.inv.get(k, 0))
			for _j in range(q2):
				if mtype == "ballistic" and rng != null and rng.randf() < 0.5:
					continue
				loot.append(k)
	return loot

static func build_gains(salvage: Array) -> Dictionary:
	var gains := {"neural": 0, "capital": 0, "loot": salvage}
	if GameState:
		gains["neural"] = int(GameState.pending_loot.get("neural", 0))
		gains["capital"] = int(GameState.pending_loot.get("fiat", 0))
	return gains
