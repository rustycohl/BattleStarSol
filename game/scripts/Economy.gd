extends Node

# Economy.gd — NEURAL Closed-Loop Economy & DAO Simulation

signal neural_changed(new_amount: int)
signal proposal_submitted(proposal: Dictionary)
signal proposal_resolved(id: int, passed: bool)

var player_neural: int = 150
var staked: Dictionary = {}
var proposals: Array = []
var proposal_id_counter: int = 1

func _ready() -> void:
	_init_default_proposals()

func _init_default_proposals() -> void:
	submit_proposal("DAO Proposal #1: Air-drop Heavy Spear Crate", 40)
	submit_proposal("DAO Proposal #2: Boost Squad AP Regeneration (+1 AP)", 80)

func earn_neural(amount: int, reason: String = "") -> void:
	player_neural += amount
	emit_signal("neural_changed", player_neural)
	if Narrative:
		Narrative.log_event("Earned +%d NEURAL tokens (%s)." % [amount, reason], "economy")

func stake(amount: int, duration_turns: int) -> bool:
	if player_neural < amount:
		return false
	player_neural -= amount
	staked["turns_remaining"] = duration_turns
	staked["amount"] = amount
	emit_signal("neural_changed", player_neural)
	if Narrative:
		Narrative.log_event("Staked %d NEURAL for %d turns." % [amount, duration_turns], "economy")
	return true

func submit_proposal(description: String, cost: int = 50) -> bool:
	if player_neural < cost and proposals.size() > 0:
		return false
	if proposals.size() > 0:
		player_neural -= cost
		emit_signal("neural_changed", player_neural)

	var prop := {
		"id": proposal_id_counter,
		"description": description,
		"cost": cost,
		"votes_for": 1,
		"votes_against": 0,
		"status": "active"
	}
	proposal_id_counter += 1
	proposals.append(prop)
	emit_signal("proposal_submitted", prop)
	if Narrative:
		Narrative.log_event("Submitted DAO Proposal: %s" % description, "dao")
	return true

func vote_proposal(id: int, approve: bool) -> bool:
	for p in proposals:
		if p["id"] == id and p["status"] == "active":
			if approve:
				p["votes_for"] += 1
				p["status"] = "passed"
				emit_signal("proposal_resolved", id, true)
				earn_neural(25, "DAO Vote Reward")
				if Narrative:
					Narrative.log_event("DAO Proposal PASSED: %s" % p["description"], "dao")
			else:
				p["votes_against"] += 1
				p["status"] = "rejected"
				emit_signal("proposal_resolved", id, false)
				if Narrative:
					Narrative.log_event("DAO Proposal REJECTED: %s" % p["description"], "dao")
			return true
	return false
