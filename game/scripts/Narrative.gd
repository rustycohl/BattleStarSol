extends Node

# Narrative.gd — Tracery-style procedural narrative integration & event logging

signal narrative_logged(entry: String, category: String)

var log_entries: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

var grammar: Dictionary = {
	"zone": ["Fractured Core", "Voxel Depths", "Grid Outpost Delta", "Cyber-Voxel Spire"],
	"threat": ["hostile greybox synthetics", "feral voxel marauders", "autonomous combat proxies"],
	"brief": [
		"Squad inserted at #zone#. #threat# detected in sector.",
		"High-value tactical objective located at #zone#. Intercept #threat#.",
		"Grid sector #zone# compromised by #threat#. Engage with extreme prejudice."
	],
	"kill": [
		"#attacker# shattered #target# using #weapon#!",
		"#attacker# neutralized #target# with a precise #weapon# strike.",
		"#target# collapsed into voxel debris under #attacker#'s #weapon#!"
	],
	"stagger": [
		"#unit# takes critical damage and staggers in low-HP stance!",
		"#unit#'s armor compromised! Unit faltering under heavy fire!"
	],
	"assemble": [
		"#unit# strung a longbow! Ranged superiority established.",
		"#unit# combined bow and string, readying arrows."
	],
	"mobility": [
		"#unit# initiated #action#! Tactical re-positioning underway.",
		"#unit# executed an emergent #action# maneuver across the sector!",
		"#unit# engaged #action# mode to flank hostiles."
	],
	"high_ground": [
		"#attacker# unleashed fire on #target# from vertical high ground advantage!",
		"#attacker# seized the high ground structure and engaged #target#!"
	]
}

func _ready() -> void:
	_rng.seed = 84021 + 7919

func configure_seed(seed_value: int) -> void:
	_rng.seed = (seed_value if seed_value > 0 else 84021) + 7919
	log_entries.clear()

func log_event(text: String, category: String = "combat") -> void:
	var entry := {"text": text, "category": category, "timestamp": Time.get_time_string_from_system()}
	log_entries.append(entry)
	if log_entries.size() > 50:
		log_entries.pop_front()
	emit_signal("narrative_logged", text, category)

func expand_grammar(rule: String, context: Dictionary = {}) -> String:
	if not grammar.has(rule):
		return rule
	var list: Array = grammar[rule]
	var template: String = list[_rng.randi_range(0, list.size() - 1)]

	# Replace context tags
	for key in context.keys():
		template = template.replace("#" + key + "#", str(context[key]))

	# Replace nested rules
	for key in grammar.keys():
		if template.contains("#" + key + "#"):
			var sub_list: Array = grammar[key]
			var sub_val: String = sub_list[_rng.randi_range(0, sub_list.size() - 1)]
			template = template.replace("#" + key + "#", sub_val)

	return template

func generate_mission_brief() -> String:
	var brief := expand_grammar("brief")
	log_event("MISSION BRIEF: " + brief, "brief")
	return brief

func generate_kill_narrative(attacker_name: String, target_name: String, weapon: String) -> String:
	var text := expand_grammar("kill", {"attacker": attacker_name, "target": target_name, "weapon": weapon})
	log_event(text, "combat")
	return text

func generate_stagger_narrative(unit_name: String) -> String:
	var text := expand_grammar("stagger", {"unit": unit_name})
	log_event(text, "combat")
	return text

func generate_assemble_narrative(unit_name: String) -> String:
	var text := expand_grammar("assemble", {"unit": unit_name})
	log_event(text, "combat")
	return text

func generate_mobility_narrative(unit_name: String, action_name: String) -> String:
	var text := expand_grammar("mobility", {"unit": unit_name, "action": action_name})
	log_event(text, "tactical")
	return text

func generate_high_ground_narrative(attacker_name: String, target_name: String) -> String:
	var text := expand_grammar("high_ground", {"attacker": attacker_name, "target": target_name})
	log_event(text, "tactical")
	return text
