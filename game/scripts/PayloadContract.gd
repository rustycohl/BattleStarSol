extends RefCounted
class_name PayloadContract

## Canonical boundary between A.T.L.A.S., the tactical engine, and themed layers.
## The runtime accepts the current flat deploy shape plus the older
## tactical_state.deploy envelope, then normalizes both to one representation.

const CONTRACT_VERSION := "1.0"
const GENERATOR_VERSION := 1
const RULES_VERSION := "alpha-1"
const FALLBACK_SEED := 84021
const GALAXY_MESSAGE_MAJOR := 1
const DEPLOY_MESSAGE_TYPES := ["battlestar.deploy", "dealer.deploy"]

static func normalize_deploy(raw: Dictionary) -> Dictionary:
	var source: Dictionary = raw.duplicate(true)
	var galaxy_message_id := ""
	var correlation_id := ""
	var envelope_error := ""
	if String(source.get("gzg", "")) == "galaxy-message":
		var version_parts := String(source.get("version", "")).split(".")
		if version_parts.size() != 2 or not String(version_parts[0]).is_valid_int():
			envelope_error = "galaxy-message version must use major.minor form"
		elif int(version_parts[0]) != GALAXY_MESSAGE_MAJOR:
			envelope_error = "unsupported galaxy-message major version"
		if not DEPLOY_MESSAGE_TYPES.has(String(source.get("type", ""))):
			envelope_error = "unsupported tactical deployment message type"
		galaxy_message_id = String(source.get("id", ""))
		correlation_id = String(source.get("correlation_id", galaxy_message_id))
		var message_payload = source.get("payload", {})
		if message_payload is Dictionary:
			source = Dictionary(message_payload).duplicate(true)
			if source.get("deploy") is Dictionary:
				source = Dictionary(source["deploy"]).duplicate(true)
		else:
			source = {}
	if String(source.get("type", "")) == "tactical_state" and source.get("deploy") is Dictionary:
		source = Dictionary(source["deploy"]).duplicate(true)

	var normalized := {
		"type": "deploy",
		"payload_contract_version": CONTRACT_VERSION,
		"generator_version": int(source.get("generator_version", GENERATOR_VERSION)),
		"rules_version": String(source.get("rules_version", RULES_VERSION)),
		"sector": String(source.get("sector", "Unknown Sector")),
		"faction": String(source.get("faction", "HAD // VANGUARD-1")),
		"seed": int(source.get("seed", FALLBACK_SEED)),
		"squad": source.get("squad", []).duplicate(true) if source.get("squad", []) is Array else [],
		"objectives": source.get("objectives", []).duplicate(true) if source.get("objectives", []) is Array else [],
		"resources": source.get("resources", {}).duplicate(true) if source.get("resources", {}) is Dictionary else {},
		"atlas_state": source.get("atlas_state", {}),
		"map": source.get("map", {}).duplicate(true) if source.get("map", {}) is Dictionary else {},
		"cell_size": float(source.get("cell_size", 2.0)),
		"macro_grid": bool(source.get("macro_grid", false)),
		"characters": source.get("characters", []).duplicate(true) if source.get("characters", []) is Array else [],
		"deck": source.get("deck", []).duplicate(true) if source.get("deck", []) is Array else []
	}
	if not galaxy_message_id.is_empty():
		normalized["galaxy_message_id"] = galaxy_message_id
		normalized["correlation_id"] = correlation_id
	if not envelope_error.is_empty():
		normalized["_envelope_error"] = envelope_error

	if int(normalized["seed"]) <= 0:
		normalized["seed"] = FALLBACK_SEED
	if normalized["squad"].is_empty():
		normalized["squad"] = [{"name": "Vanguard-1", "cls": "Heavy"}]
	if normalized["objectives"].is_empty():
		normalized["objectives"] = ["Extract safely"]
	if normalized["resources"].is_empty():
		normalized["resources"] = {"neural": 0, "capital": 0}

	return normalized

static func validate_deploy(payload: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not String(payload.get("_envelope_error", "")).is_empty():
		errors.append(String(payload["_envelope_error"]))
	if String(payload.get("type", "")) != "deploy":
		errors.append("type must be 'deploy'")
	if String(payload.get("sector", "")).strip_edges().is_empty():
		errors.append("sector must be a non-empty string")
	if String(payload.get("faction", "")).strip_edges().is_empty():
		errors.append("faction must be a non-empty string")
	if int(payload.get("seed", 0)) <= 0:
		errors.append("seed must be a positive integer")
	if not (payload.get("squad", null) is Array) or payload.get("squad", []).is_empty():
		errors.append("squad must contain at least one unit")
	if not (payload.get("objectives", null) is Array):
		errors.append("objectives must be an array")
	if not (payload.get("resources", null) is Dictionary):
		errors.append("resources must be an object")
	return errors

## Which fields of a deploy payload were absent and had to be filled in.
##
## `normalize_deploy` substitutes plausible values for anything missing — sector becomes
## "Unknown Sector", faction becomes "HAD // VANGUARD-1", seed becomes FALLBACK_SEED. That is
## correct behaviour: a partial payload should still produce a playable mission rather than a
## crash. What was missing is any way to tell that it happened.
##
## The same failure shape as the terrain cell built by hand: a default absorbed a malformed
## input and the result behaved plausibly, so nothing reported it. A hand-off that silently
## became "Unknown Sector // HAD VANGUARD-1 // seed 84021" is a broken hand-off that looks like
## a real mission, and the seed being a constant means it looks like a *reproducible* one.
##
## Pure, and reports rather than rejects: the substitution stays, the silence does not.
const DEPLOY_SUBSTITUTED_FIELDS := [
	"sector", "faction", "seed", "squad", "objectives", "resources", "cell_size"
]

static func deploy_shape_report(raw: Dictionary) -> Dictionary:
	var source: Dictionary = raw
	if raw.has("payload") and raw["payload"] is Dictionary:
		source = raw["payload"]
	var substituted: Array = []
	for field in DEPLOY_SUBSTITUTED_FIELDS:
		if not source.has(field):
			substituted.append(field)
	# A squad of zero is not a mission. Distinguished from an absent squad, because an explicit
	# empty array is a different mistake from a missing key and the caller may want to know which.
	var empty_squad := source.has("squad") and source["squad"] is Array and (source["squad"] as Array).is_empty()
	return {
		"complete": substituted.is_empty() and not empty_squad,
		"substituted": substituted,
		"empty_squad": empty_squad,
		"summary": (
			"complete"
			if substituted.is_empty() and not empty_squad
			else "substituted %s%s" % [str(substituted), " and the squad is empty" if empty_squad else ""]
		)
	}
