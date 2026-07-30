extends Node
## PayloadBridge - versioned boundary between the strategic and tactical layers.
## Local files and postMessage are the canonical path. Optional HTTP GET/POST
## calls are relay integration and require a dynamic endpoint.

signal payload_fetched(success: bool, payload: Dictionary)
signal extraction_pushed(success: bool, response: String)

const Contract = preload("res://scripts/PayloadContract.gd")

var _payload: Dictionary = {}
var strat_server_url: String = "" # e.g. "https://username.github.io/stratlayer/payload.json"
var tac_server_url: String = ""   # e.g. "https://username.github.io/taclayer/api"

# LOCAL never touches HTTP. RELAY permits payload GET and result POST to
# explicitly configured endpoints. It does not provide real-time multiplayer.
enum Mode { OFFLINE, ONLINE }
var mode: int = Mode.OFFLINE

var _http_fetcher: HTTPRequest
var _http_pusher: HTTPRequest

func _ready() -> void:
	_http_fetcher = HTTPRequest.new()
	_http_fetcher.name = "HTTPFetcher"
	_http_fetcher.request_completed.connect(_on_fetch_completed)
	add_child(_http_fetcher)

	_http_pusher = HTTPRequest.new()
	_http_pusher.name = "HTTPPusher"
	_http_pusher.request_completed.connect(_on_push_completed)
	add_child(_http_pusher)

	if OS.has_feature("web"):
		var encoded = JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('p') || ''",
			true
		)
		if typeof(encoded) == TYPE_STRING and not String(encoded).is_empty():
			var decoded := Marshalls.base64_to_utf8(String(encoded))
			var json = JSON.parse_string(decoded)
			if typeof(json) == TYPE_DICTIONARY and set_payload(json):
				print("[PayloadBridge] Loaded payload from Web URL!")
				return

	_load_default_mock_payload()

func _load_default_mock_payload() -> void:
	set_payload({
		"type": "deploy",
		"payload_contract_version": Contract.CONTRACT_VERSION,
		"generator_version": Contract.GENERATOR_VERSION,
		"rules_version": Contract.RULES_VERSION,
		"sector": "5. North American Megacity",
		"faction": "HAD // VANGUARD-1",
		"seed": 84021,
		"squad": [{"name": "Vanguard-1", "cls": "Heavy"}],
		"objectives": ["Extract data core"],
		"resources": {"neural": 50, "capital": 25000}
	})

func set_payload(p: Dictionary) -> bool:
	var normalized := Contract.normalize_deploy(p)
	var errors := Contract.validate_deploy(normalized)
	if not errors.is_empty():
		push_error("[PayloadBridge] Invalid deployment payload: %s" % str(errors))
		return false
	_payload = normalized
	_payload["_shape_report"] = Contract.deploy_shape_report(p)

	var config = get_node_or_null("/root/GameConfig")
	if config:
		config.cell_size = float(_payload.get("cell_size", 2.0))
		if _payload.get("macro_grid", false) == true:
			config.cell_size = 16.0
	print("[PayloadBridge] Payload updated: ", _payload.get("sector", "?"), " seed=", get_seed())
	return true

func has_payload() -> bool:
	return not _payload.is_empty()

func get_payload() -> Dictionary:
	return _payload

func get_seed() -> int:
	return int(_payload.get("seed", 0))

## Fetch mission deployment payload from a remote web server (e.g., GitHub Pages)
func fetch_remote_payload(url: String = "") -> void:
	if not is_online():
		_load_default_mock_payload()
		emit_signal("payload_fetched", true, _payload)
		return
	var target_url = url if url != "" else tac_server_url
	if target_url == "":
		print("[PayloadBridge] No server URL set — using local mock payload.")
		_load_default_mock_payload()
		emit_signal("payload_fetched", true, _payload)
		return

	print("[PayloadBridge] Fetching remote payload from: ", target_url)
	var err = _http_fetcher.request(target_url)
	if err != OK:
		print("[PayloadBridge] HTTP Request error (%d) — falling back to mock payload." % err)
		_load_default_mock_payload()
		emit_signal("payload_fetched", false, _payload)

func _on_fetch_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
			print("[PayloadBridge] Remote payload parsed successfully!")
			set_payload(json.data)
			emit_signal("payload_fetched", true, _payload)
			return

	print("[PayloadBridge] Remote fetch failed (Code %d) — falling back to mock payload." % response_code)
	_load_default_mock_payload()
	emit_signal("payload_fetched", false, _payload)

## Push an extraction result locally and via HTTP POST if a server URL is set.
func push_extraction(result: Dictionary) -> bool:
	result["type"] = "extraction"
	result["payload_contract_version"] = Contract.CONTRACT_VERSION
	result["generator_version"] = int(_payload.get("generator_version", Contract.GENERATOR_VERSION))
	result["rules_version"] = String(_payload.get("rules_version", Contract.RULES_VERSION))
	if not result.has("sector"): result["sector"] = _payload.get("sector", "")
	if not result.has("seed"): result["seed"] = get_seed()
	if not result.has("survivors"): result["survivors"] = 0
	if not result.has("gains"): result["gains"] = {"neural": 0, "capital": 0, "loot": []}
	result["ts"] = Time.get_unix_time_from_system() * 1000.0
	result["extraction_id"] = "xcommand:%d:%d" % [int(result["seed"]), int(result["ts"])]
	# Option E from OBSERVATION-001: report the reproduction budget with the result, so a
	# mission that spent its ledger says so in the extraction rather than only failing later
	# when someone tries to bundle it.
	var game_state = Engine.get_main_loop().root.get_node_or_null("GameState")
	if game_state != null and game_state.has_method("ledger_budget"):
		var budget: Dictionary = game_state.ledger_budget()
		if not budget.is_empty():
			result["repro_budget"] = budget
	if _payload.has("_shape_report"):
		result["_shape_report"] = _payload["_shape_report"]
	var extraction_message := _build_extraction_message(result)


	print("[PayloadBridge] PUSHING EXTRACTION RESULT: ", result)

	save_payload("tactical_result", result)  # portability: local copy (backtrack / bring-your-own-save)
	save_payload("tactical_result_message", extraction_message)
	if is_online() and tac_server_url != "":
		var json_str = JSON.stringify(result)
		var headers = ["Content-Type: application/json"]
		var request_error := _http_pusher.request(tac_server_url, headers, HTTPClient.METHOD_POST, json_str)
		if request_error != OK:
			emit_signal("extraction_pushed", false, "HTTP request error %d" % request_error)

	if OS.has_feature("web"):
		var encoded_result := Marshalls.utf8_to_base64(JSON.stringify(result))
		var encoded_message := Marshalls.utf8_to_base64(JSON.stringify(extraction_message))
		var js_code = "try { var dec = function(v){ return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(v), c => c.charCodeAt(0)))); }; var p = dec('%s'); var gm = dec('%s'); var legacy = {channel:'battlestar', kind:'extraction', payload:p, galaxy_message:gm}; var o = location.protocol === 'file:' ? '*' : location.origin; var target = (window.parent && window.parent !== window) ? window.parent : window.opener; if (target) { target.postMessage(gm, o); target.postMessage(legacy, o); } } catch(e) { console.error(e); }" % [encoded_result, encoded_message]
		JavaScriptBridge.eval(js_code)
	else:
		emit_signal("extraction_pushed", true, "saved locally")
	return true

func _build_extraction_message(result: Dictionary) -> Dictionary:
	var timestamp_ms := int(result.get("ts", Time.get_unix_time_from_system() * 1000.0))
	var source_id := String(result.get("extraction_id", "xcommand:%d:%d" % [get_seed(), timestamp_ms]))
	var message := {
		"gzg": "galaxy-message",
		"version": "1.0",
		"id": source_id,
		"type": "xcommand.extraction",
		"source": {
			"galaxy": "xCommand",
			"version": String(ProjectSettings.get_setting("application/config/version", "0.1.1-prealpha.1")),
			"instance": "godot-web"
		},
		"target": {
			"galaxy": "BattleStarSol",
			"capability": "strategic.receive-extraction"
		},
		"created_at": Time.get_datetime_string_from_unix_time(int(timestamp_ms / 1000), true) + "Z",
		"payload": {
			"schema": "gzg.xcommand.extraction/1.0",
			"extraction": result.duplicate(true)
		}
	}
	var correlation := String(_payload.get("correlation_id", _payload.get("galaxy_message_id", "")))
	if not correlation.is_empty():
		message["correlation_id"] = correlation
	return message

func _on_push_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var resp_text = body.get_string_from_utf8()
	var success = result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	print("[PayloadBridge] Push response (Code %d): %s" % [response_code, resp_text])
	emit_signal("extraction_pushed", success, resp_text)

## --- Portability: "bring your own save" (NEO-GEO / LAN / Discord). Seed-driven, reproducible. ---
func _payload_dir() -> String:
	var d := "user://payloads"
	if not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)
	return d

func save_payload(kind: String, data: Dictionary) -> void:
	var safe_kind := kind.validate_filename()
	if safe_kind.is_empty():
		safe_kind = "payload"
	var f = FileAccess.open("%s/%s.json" % [_payload_dir(), safe_kind], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func load_payload(kind: String) -> Dictionary:
	var p := "%s/%s.json" % [_payload_dir(), kind.validate_filename()]
	if not FileAccess.file_exists(p): return {}
	var f = FileAccess.open(p, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}

func export_payload(data: Dictionary, dest_path: String) -> bool:
	var f = FileAccess.open(dest_path, FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

func export_tactical_state(dest_path: String) -> bool:
	var game_state = Engine.get_main_loop().root.get_node_or_null("GameState")
	var main = Engine.get_main_loop().root.get_node_or_null("Main")
	if game_state == null or main == null: return false

	var state := {
		"schema": "gzg.battlestar.tactical_state/1.0",
		"type": "tactical_state",
		"turn": game_state.turn,
		"global_turn": main.get("global_turn", 1) if main else 1,
		"seed": get_seed(),
		"generator_version": 1,
		"rules_version": "alpha-1",
		"units": main.serialize_units() if main.has_method("serialize_units") else [],
		"cells": main.cells.duplicate(true) if main else {},
		"debris": game_state.debris.duplicate(true),
		"actions": game_state.action_records.duplicate(true),
		"events": game_state.event_records.duplicate(true)
	}
	return export_payload(state, dest_path)

func import_tactical_state(src_path: String) -> bool:
	var payload = import_payload(src_path)
	if payload.is_empty() or payload.get("type", "") != "tactical_state":
		return false
	_payload = payload
	# Change scene to trigger reload, Main._ready will intercept type: tactical_state
	Engine.get_main_loop().root.get_node("Main").get_tree().change_scene_to_file("res://Main.tscn")
	return true

func export_bug_report(tactical_state: Dictionary, log_lines: Array) -> String:
	var report := {
		"type": "bug_report",
		"ts": Time.get_unix_time_from_system() * 1000.0,
		"seed": get_seed(),
		"tactical_state": tactical_state,
		"narrative_log": log_lines,
		"payload_context": _payload
	}
	var filename = "bug_report_%d" % int(Time.get_unix_time_from_system())
	save_payload(filename, report)
	return _payload_dir() + "/" + filename + ".json"

func import_payload(src_path: String) -> Dictionary:
	if not FileAccess.file_exists(src_path): return {}
	var f = FileAccess.open(src_path, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}

func import_character(src_path: String) -> bool:
	var d = import_payload(src_path)
	if d.get("schema") == "gzg.oracle.character/0.1":
		if not _payload.has("characters"): _payload["characters"] = []
		_payload["characters"].append(d)
		print("[PayloadBridge] Imported ORACLE Character: ", d.get("callsign", "Unknown"))
		return true
	print("[PayloadBridge] Invalid character payload at ", src_path)
	return false

func import_deck(src_path: String) -> bool:
	var d = import_payload(src_path)
	if d.get("schema") == "gzg.dealer.deck/0.1":
		_payload["deck"] = d.get("cards", [])
		print("[PayloadBridge] Imported DEALER Deck with ", _payload["deck"].size(), " cards")
		return true
	print("[PayloadBridge] Invalid deck payload at ", src_path)
	return false


# --- Optional HTTP relay mode ---
func configure(atlas_url: String, taclayer_url: String) -> void:
	strat_server_url = atlas_url
	tac_server_url = taclayer_url

func go_online() -> void:
	mode = Mode.ONLINE
	print("[PayloadBridge] MODE: HTTP RELAY atlas=%s tac=%s" % [strat_server_url, tac_server_url])

func go_offline() -> void:
	mode = Mode.OFFLINE
	print("[PayloadBridge] MODE: LOCAL (no HTTP)")

func is_online() -> bool:
	return mode == Mode.ONLINE and tac_server_url != ""

func list_saves() -> Array:
	var out: Array = []
	var dir = DirAccess.open(_payload_dir())
	if dir:
		dir.list_dir_begin()
		var f = dir.get_next()
		while f != "":
			if not dir.current_is_dir() and f.ends_with(".json"):
				out.append(f.get_basename())
			f = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return out
