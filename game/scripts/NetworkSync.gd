extends Node

var peer: ENetMultiplayerPeer
var is_host := false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	ActionRouter.action_requested.connect(_on_action_requested)

func _on_peer_connected(id: int) -> void:
	print("[NetworkSync] Peer connected: ", id)
	var main = Engine.get_main_loop().root.get_node_or_null("Main")
	if main and main.has_method("_hint"):
		main._hint("Live Peer Connected: " + str(id))

func _on_peer_disconnected(id: int) -> void:
	print("[NetworkSync] Peer disconnected: ", id)
	var main = Engine.get_main_loop().root.get_node_or_null("Main")
	if main and main.has_method("_hint"):
		main._hint("Live Peer Disconnected: " + str(id))

func host_game() -> void:
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(8999)
	if err != OK:
		print("[NetworkSync] Failed to host on port 8999")
		return
	multiplayer.multiplayer_peer = peer
	is_host = true
	var main = Engine.get_main_loop().root.get_node_or_null("Main")
	if main and main.has_method("_hint"):
		main._hint("Hosting Live Game on port 8999...")

func join_game() -> void:
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client("127.0.0.1", 8999)
	if err != OK:
		print("[NetworkSync] Failed to join localhost:8999")
		return
	multiplayer.multiplayer_peer = peer
	is_host = false
	var main = Engine.get_main_loop().root.get_node_or_null("Main")
	if main and main.has_method("_hint"):
		main._hint("Joining Live Game at 127.0.0.1:8999...")

func _on_action_requested(actor, action_name: String, cell: Vector2i = Vector2i(-1,-1)) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		# Don't echo RPCs we just received (ActionRouter emits for all requested actions)
		var u_id = actor.unit_id if actor else -1
		rpc("_rpc_receive_action", u_id, action_name, cell)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_action(u_id: int, action_name: String, cell: Vector2i) -> void:
	var main = Engine.get_main_loop().root.get_node_or_null("Main")
	if main:
		var actor = null
		if u_id >= 0:
			for u in main.units:
				if u.unit_id == u_id:
					actor = u
					break
		if u_id >= 0 and actor == null:
			return
		
		print("[NetworkSync] Remote action: ", action_name, " for ", u_id)
		
		# Prevent loopback echo by temporarily disconnecting
		ActionRouter.action_requested.disconnect(_on_action_requested)
		if cell != Vector2i(-1,-1):
			ActionRouter.request_action(actor, action_name, cell)
		else:
			ActionRouter.request_action(actor, action_name)
		ActionRouter.action_requested.connect(_on_action_requested)
