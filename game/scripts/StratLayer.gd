extends Node

# StratLayer.gd — Real A.T.L.A.S. Integration Launcher
# Replaces the "godot-inspired toy" mimic with a direct bridge to the actual ATLAS web application.

var ui_layer: CanvasLayer
var callsign_input: LineEdit
var faction_select: OptionButton

func _ready() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	_draw_ui()

func _draw_ui() -> void:
	# Clear previous UI elements
	for child in ui_layer.get_children():
		ui_layer.remove_child(child)
		child.queue_free()

	if not GameState.session_active:
		_build_login_ui()
	else:
		_build_launcher_ui()

		# Restore any sub-panels if returning from tactical layer
		if GameState.return_action == "vault":
			call_deferred("_open_vault")
		elif GameState.return_action == "lab":
			call_deferred("_open_lab")
		GameState.return_action = ""

func _build_login_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.01, 0.02, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title = Label.new()
	title.text = "A.T.L.A.S. // COVERT INGRESS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))
	vbox.add_child(title)

	var desc = Label.new()
	desc.text = "ESTABLISH ORACLE LINK TO STRATEGIC SUBSTRATE"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	vbox.add_child(desc)

	callsign_input = LineEdit.new()
	callsign_input.placeholder_text = "ENTER CALLSIGN"
	callsign_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	callsign_input.custom_minimum_size = Vector2(300, 36)
	vbox.add_child(callsign_input)

	faction_select = OptionButton.new()
	faction_select.add_item("HAD // HEAVY ARMOR DIVISION")
	faction_select.add_item("SYND // METROPOLIS SYNDICATE")
	faction_select.add_item("Kaiju/Aliens // ANOMALY HOST")
	faction_select.custom_minimum_size = Vector2(300, 36)
	vbox.add_child(faction_select)

	var btn_login = Button.new()
	btn_login.text = "INITIATE COGNITIVE LINK"
	btn_login.custom_minimum_size = Vector2(300, 48)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.4, 0.6)
	btn_login.add_theme_stylebox_override("normal", sb)
	btn_login.pressed.connect(_on_login_pressed)
	vbox.add_child(btn_login)

func _on_login_pressed() -> void:
	var cs = callsign_input.text.strip_edges()
	if cs == "":
		cs = "GUEST_" + str(randi() % 1000)
	GameState.commander_callsign = cs
	var fac_text = faction_select.get_item_text(faction_select.selected)
	GameState.commander_faction = fac_text
	GameState.session_active = true
	_draw_ui()

func _build_launcher_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

	var user_info = Label.new()
	user_info.text = "COMMANDER: %s\nFACTION: %s" % [GameState.commander_callsign, GameState.commander_faction]
	user_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	user_info.add_theme_font_size_override("font_size", 12)
	user_info.add_theme_color_override("font_color", Color(0.2, 0.9, 0.6))
	vbox.add_child(user_info)

	var title = Label.new()
	title.text = "BATTLE/STAR.SOL\nSTRATEGIC SUBSTRATE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))
	vbox.add_child(title)

	var desc = Label.new()
	desc.text = "A.T.L.A.S. runs in the browser through an automatic local link.\nSelect a target and deploy directly into the tactical Web build."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	vbox.add_child(desc)

	var btn_atlas = Button.new()
	btn_atlas.text = "LAUNCH A.T.L.A.S. TERMINAL (BROWSER)"
	btn_atlas.custom_minimum_size = Vector2(400, 64)
	btn_atlas.add_theme_font_size_override("font_size", 18)
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.5, 0.8)
	btn_atlas.add_theme_stylebox_override("normal", sb)
	btn_atlas.pressed.connect(_launch_atlas)
	vbox.add_child(btn_atlas)

	var btn_vault = Button.new()
	btn_vault.text = "◈ PAYLOAD VAULT (INJECT DEPLOYMENT)"
	btn_vault.custom_minimum_size = Vector2(400, 48)
	var sbv = StyleBoxFlat.new()
	sbv.bg_color = Color(0.1, 0.2, 0.3)
	btn_vault.add_theme_stylebox_override("normal", sbv)
	btn_vault.pressed.connect(_open_vault)
	vbox.add_child(btn_vault)

	var btn_dev = Button.new()
	btn_dev.text = "[DEV] QUICK TACTICAL DEPLOY (LOCAL SIM)"
	btn_dev.custom_minimum_size = Vector2(400, 32)
	var sbd = StyleBoxFlat.new()
	sbd.bg_color = Color(0.2, 0.1, 0.1)
	btn_dev.add_theme_stylebox_override("normal", sbd)
	btn_dev.pressed.connect(_quick_deploy)
	vbox.add_child(btn_dev)

	var btn_tutorial = Button.new()
	btn_tutorial.text = "PROVING GROUND (TUTORIAL SIMULATION)"
	btn_tutorial.custom_minimum_size = Vector2(400, 32)
	var sbt = StyleBoxFlat.new()
	sbt.bg_color = Color(0.1, 0.3, 0.2)
	btn_tutorial.add_theme_stylebox_override("normal", sbt)
	btn_tutorial.pressed.connect(_tutorial_deploy)
	vbox.add_child(btn_tutorial)

	var btn_lab = Button.new()
	btn_lab.text = "R&D LABORATORY (SPEND NEURAL/CAPITAL)"
	btn_lab.custom_minimum_size = Vector2(400, 32)
	var sbl = StyleBoxFlat.new()
	sbl.bg_color = Color(0.4, 0.2, 0.6)
	btn_lab.add_theme_stylebox_override("normal", sbl)
	btn_lab.pressed.connect(_open_lab)
	vbox.add_child(btn_lab)

	var btn_logout = Button.new()
	btn_logout.text = "✕ TERMINATE ORACLE LINK (LOGOUT)"
	btn_logout.custom_minimum_size = Vector2(400, 32)
	var sblo = StyleBoxFlat.new()
	sblo.bg_color = Color(0.4, 0.1, 0.1)
	btn_logout.add_theme_stylebox_override("normal", sblo)
	btn_logout.pressed.connect(_on_logout_pressed)
	vbox.add_child(btn_logout)

func _launch_atlas() -> void:
	# Godot Web exports must be served over HTTP so their .pck and WebAssembly
	# can load. Start the bundled loopback-only server; it opens the correct
	# strategic URL itself and reuses an existing Battle/Star server.
	var server_script := ProjectSettings.globalize_path("res://tools/launch-web.ps1")
	if not FileAccess.file_exists(server_script):
		push_error("Missing local Web launcher: " + server_script)
		return
	var pid := OS.create_process(
		"powershell.exe",
		[
			"-NoProfile",
			"-ExecutionPolicy", "Bypass",
			"-File", server_script
		],
		false
	)
	if pid <= 0:
		push_error("Could not start the local A.T.L.A.S. Web link.")

func _open_vault() -> void:
	var PayloadPanel = load("res://scripts/PayloadPanel.gd")
	if PayloadPanel:
		ui_layer.add_child(PayloadPanel.new())

func _open_lab() -> void:
	var ResearchLab = load("res://scripts/ResearchLab.gd")
	if ResearchLab:
		ui_layer.add_child(ResearchLab.new())

func _quick_deploy() -> void:
	# Generate a dev payload and jump straight to tactical
	PayloadBridge.set_payload({
		"type": "deploy",
		"sector": "Local Dev Sector",
		"faction": GameState.commander_faction if GameState.commander_faction != "" else "HAD",
		"seed": int(Time.get_unix_time_from_system()),
		"squad": [
			{"name": "Dev-1", "cls": "Heavy"},
			{"name": "Scout-2", "cls": "Scout"},
			{"name": "Support-3", "cls": "Support"}
		],
		"objectives": ["Test"],
		"resources": {"neural": GameState.vault_neural, "capital": GameState.vault_fiat}
	})
	get_tree().change_scene_to_file("res://Main.tscn")

func _tutorial_deploy() -> void:
	PayloadBridge.set_payload({
		"type": "deploy",
		"sector": "Proving Ground",
		"faction": GameState.commander_faction if GameState.commander_faction != "" else "HAD",
		"seed": 999999,
		"squad": [{"name": "Recruit-1", "cls": "Scout"}],
		"objectives": ["Complete Tutorial"],
		"resources": {"neural": 0, "capital": 0}
	})
	get_tree().change_scene_to_file("res://Main.tscn")

func _on_logout_pressed() -> void:
	GameState.session_active = false
	GameState.commander_callsign = ""
	GameState.commander_faction = ""
	_draw_ui()
