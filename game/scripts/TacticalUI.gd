extends CanvasLayer


const Config = preload("res://scripts/GameConfig.gd")
const Maneuvers = preload("res://scripts/ManeuverState.gd")

var main: Node

# Nodes
var turn_label: Label
var enemy_label: Label
var neural_label: Label
var roster_box: VBoxContainer
var roster_rows: Array = []
var narrative_box: VBoxContainer
var hud_name: Label
var hud_hp_label: Label
var hud_ap_label: Label
var hud_hands_label: Label
var hud_carry_label: Label
var hud_stance_label: Label
var hud_hp_pips: Array = []
var hud_ap_pips: Array = []
var weapons_grid: GridContainer = null
var weapon_btns: Dictionary = {}
var action_btns: Dictionary = {}
var action_groups: Dictionary = {}
var hint_label: Label

var action_tooltips: Dictionary = {
	"brace": "Brace – hold position and block incoming attacks (%d AP)." % Config.BLOCK_COST,
	"crouch": "Crouch – lower posture and move for %d AP per flat step (%d AP)." % [Config.CROUCH_MOVE_COST, Config.CROUCH_COST],
	"prone": "Prone – lie flat and crawl for %d AP per flat step (%d AP)." % [Config.PRONE_MOVE_COST, Config.PRONE_COST],
	"lean_l": "Lean Left – shift stance left to peek around cover (%d AP)." % Config.LEAN_COST,
	"lean_r": "Lean Right – shift stance right to peek around cover (%d AP)." % Config.LEAN_COST,
	"take_cover": "Take Cover – commit to adjacent cover and brace automatically (%d AP); leaving also costs %d AP." % [Config.TAKE_COVER_COST, Config.LEAVE_COVER_COST],
	"toggle_orient": "Face Up/Down – flip orientation when prone.",
	"jump": "Jump – spend AP to enter an airborne anchor; a second paid Jump lands or revectors (%d AP each)." % Config.JUMP_COST,
	"toggle_walk": "Walk - reset movement speed to standard (%d AP per flat step)." % Config.MOVE_COST,
	"toggle_run": "Run/Sprint – switch between %d AP and %d AP per flat step." % [Config.MOVE_COST, Config.SPRINT_MOVE_COST],
	"dodge": "Dodge – quick step to avoid attacks (%d AP)." % Config.DODGE_COST,
	"flip": "Flip – airborne Dodge roll; available only during a committed aerial maneuver (%d AP)." % Config.FLIP_COST,
	"wall_run": "Wall Run – spend actual Run/Sprint momentum to traverse an adjacent wall as local ground (%d AP per segment)." % Config.WALL_RUN_COST,
	"wall_jump": "Wall Jump – launch from active wall contact into an airborne maneuver (%d AP)." % Config.WALL_JUMP_COST,
	"cover_monkey": "Cover Monkey – dev special stance: movement costs +%d AP; automatic cover entry and movement exit are free." % Config.COVER_MONKEY_MOVE_SURCHARGE,
	"remotes": "Remotes – jack into a squad agent and pilot them directly. Click again (or the Commander) to return home. God Mode special.",
	"remotes_home": "Remotes Home – drop the agent link and return control to the Commander.",
	"hover": "Hover – stay airborne briefly for vertical maneuvering (%d AP)." % Config.HOVER_COST,
	"toggle_flight": "Flight – engage flight for %d AP, then target an air cube; wheel changes altitude." % Config.FLIGHT_TOGGLE_COST,
	"flight_up": "Layer Up – raise the flight targeting cube one altitude layer (Page Up).",
	"flight_down": "Layer Down – lower the flight targeting cube one altitude layer (Page Down).",
	"flight_land": "Land Here – descend the selected unit to its current terrain surface (L).",
	"grab": "Grab – pick up debris or items on the tile (%d AP)." % Config.GRAB_COST,
	"assemble": "Assemble – combine bow and string into a stringed bow (%d AP)." % Config.ASSEMBLE_COST,
	"endturn": "End Turn – finish your actions and pass to AI.",
	"equip_fist": "Equip Fists – ready unarmed attacks (%d AP)." % Config.EQUIP_COST
}

func _init(main_ref: Node):
	main = main_ref
	name = "TacticalUI"

func _ready():
	_build_ui()

	var Narrative = get_node_or_null("/root/Narrative")
	var Economy = get_node_or_null("/root/Economy")
	if Narrative:
		Narrative.narrative_logged.connect(_on_narrative_logged)
	if Economy:
		Economy.neural_changed.connect(_on_neural_changed)

func _mk_label(txt: String, sz: int, col: Color, autowrap: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	if autowrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _make_pips(n: int, parent: Node) -> Array:
	var arr := []
	for i in n:
		var p := ColorRect.new()
		p.focus_mode = Control.FOCUS_NONE
		p.custom_minimum_size = Vector2(8, 10)
		p.color = Color(0.2, 0.2, 0.2)
		parent.add_child(p)
		arr.append(p)
	return arr

func _bar_group(parent: Node, title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(v)
	var lbl = _mk_label(title, 10, Color(0.5, 0.6, 0.7))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lbl)
	return v

func _add_action_btn(container: Node, key: String, text: String, cb: Callable, min_w := 54) -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 22)
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.4, 0.6))
	b.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	if action_tooltips.has(key):
		b.tooltip_text = action_tooltips[key]

	var action_events = InputMap.action_get_events(key)
	if action_events.size() > 0:
		var ev = action_events[0]
		var shortcut = Shortcut.new()
		shortcut.events.append(ev)
		b.shortcut = shortcut
		var key_name = OS.get_keycode_string(ev.keycode)
		b.tooltip_text = "%s (%s)" % [text, key_name]

	b.pressed.connect(cb)
	container.add_child(b)
	action_btns[key] = b

func _build_ui() -> void:
	var left_sidebar := PanelContainer.new()
	left_sidebar.anchor_left = 0.0
	left_sidebar.anchor_top = 0.0
	left_sidebar.anchor_right = 0.0
	left_sidebar.anchor_bottom = 0.0
	left_sidebar.offset_left = 14
	left_sidebar.offset_top = 14
	left_sidebar.offset_right = 230
	left_sidebar.offset_bottom = 410
	left_sidebar.mouse_filter = Control.MOUSE_FILTER_STOP
	var sidebar_sb := StyleBoxFlat.new()
	sidebar_sb.bg_color = Color(0.04, 0.05, 0.08, 0.92)
	sidebar_sb.border_color = Color(0.2, 0.25, 0.35)
	sidebar_sb.border_width_left = 2
	sidebar_sb.border_width_top = 2
	sidebar_sb.border_width_right = 2
	sidebar_sb.border_width_bottom = 2
	sidebar_sb.content_margin_left = 12
	sidebar_sb.content_margin_right = 12
	sidebar_sb.content_margin_top = 10
	sidebar_sb.content_margin_bottom = 10
	left_sidebar.add_theme_stylebox_override("panel", sidebar_sb)
	add_child(left_sidebar)

	var view_mode_box := HBoxContainer.new()
	view_mode_box.name = "ViewModeBox"
	view_mode_box.anchor_left = 1.0
	view_mode_box.anchor_top = 0.0
	view_mode_box.anchor_right = 1.0
	view_mode_box.anchor_bottom = 0.0
	view_mode_box.offset_left = -340
	view_mode_box.offset_top = 16
	view_mode_box.offset_right = -16
	view_mode_box.offset_bottom = 48
	view_mode_box.alignment = BoxContainer.ALIGNMENT_END
	view_mode_box.add_theme_constant_override("separation", 8)
	add_child(view_mode_box)

	var b_bev := Button.new()
	b_bev.name = "btn_bev"
	b_bev.text = "BEV"
	b_bev.pressed.connect(func(): _set_camera_mode(0))
	view_mode_box.add_child(b_bev)

	var b_fps := Button.new()
	b_fps.name = "btn_fps"
	b_fps.text = "FPS"
	b_fps.pressed.connect(func(): _set_camera_mode(2))
	view_mode_box.add_child(b_fps)

	var b_ots := Button.new()
	b_ots.name = "btn_ots"
	b_ots.text = "OTS"
	b_ots.pressed.connect(func(): _set_camera_mode(1))
	view_mode_box.add_child(b_ots)

	var b_rem := Button.new()
	b_rem.name = "btn_rem"
	b_rem.text = "REMOTES"
	b_rem.pressed.connect(func(): main._hint("Remotes view activated!"))
	view_mode_box.add_child(b_rem)

	var b_full := Button.new()
	b_full.name = "btn_full"
	b_full.text = "FULL"
	b_full.tooltip_text = "Toggle fullscreen tactical view"
	b_full.pressed.connect(_toggle_fullscreen)
	view_mode_box.add_child(b_full)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 6)
	left_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_sidebar.add_child(left_vbox)

	var topline := HBoxContainer.new()
	topline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	topline.add_theme_constant_override("separation", 12)
	left_vbox.add_child(topline)

	turn_label = _mk_label("YOUR TURN", 15, Color(1, 1, 1))
	topline.add_child(turn_label)

	var Economy = get_node_or_null("/root/Economy")
	neural_label = _mk_label("NEURAL: %d" % (Economy.player_neural if Economy else 0), 13, Color(0.2, 0.9, 0.6))
	topline.add_child(neural_label)

	var god_mode_cb := CheckBox.new()
	god_mode_cb.focus_mode = Control.FOCUS_NONE
	god_mode_cb.text = "DEV: GOD MODE (Specials)"
	god_mode_cb.button_pressed = main.dev_god_mode
	god_mode_cb.add_theme_font_size_override("font_size", 10)
	god_mode_cb.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2))
	god_mode_cb.toggled.connect(func(t): main.dev_god_mode = t; update_ui())
	left_vbox.add_child(god_mode_cb)

	var btn_export = Button.new()
	btn_export.text = "BUG REPORT (EXPORT)"
	btn_export.custom_minimum_size = Vector2(0, 24)
	btn_export.add_theme_font_size_override("font_size", 10)
	var exp_sb = StyleBoxFlat.new()
	exp_sb.bg_color = Color(0.6, 0.2, 0.2)
	btn_export.add_theme_stylebox_override("normal", exp_sb)
	btn_export.pressed.connect(_export_bug)
	left_vbox.add_child(btn_export)

	hint_label = _mk_label("", 12, Color(0.7, 0.85, 1.0), true)
	hint_label.custom_minimum_size = Vector2(205, 0)

	roster_box = VBoxContainer.new()
	roster_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_vbox.add_child(roster_box)
	roster_box.add_child(_mk_label("SQUAD", 11, Color(0.6, 0.7, 0.8)))
	enemy_label = _mk_label("", 11, Color(1, 0.6, 0.55))

	narrative_box = VBoxContainer.new()
	narrative_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(spacer)

	left_vbox.add_child(HSeparator.new())

	var vit := VBoxContainer.new()
	vit.add_theme_constant_override("separation", 4)
	vit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_vbox.add_child(vit)

	hud_name = _mk_label("—", 14, Color(1, 1, 1))
	vit.add_child(hud_name)

	var hpline := HBoxContainer.new()
	hpline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hpline.add_theme_constant_override("separation", 6)
	vit.add_child(hpline)
	hud_hp_label = _mk_label("HP", 11, Color(1, 0.7, 0.7))
	hud_hp_label.custom_minimum_size = Vector2(40, 0)
	hpline.add_child(hud_hp_label)
	var hppips := HBoxContainer.new()
	hppips.add_theme_constant_override("separation", 2)
	hppips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hpline.add_child(hppips)
	hud_hp_pips = _make_pips(Config.UNIT_HP, hppips)

	var apline := HBoxContainer.new()
	apline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apline.add_theme_constant_override("separation", 6)
	vit.add_child(apline)
	hud_ap_label = _mk_label("AP", 11, Color(0.7, 0.9, 1.0))
	hud_ap_label.custom_minimum_size = Vector2(40, 0)
	apline.add_child(hud_ap_label)
	var appips := HBoxContainer.new()
	appips.add_theme_constant_override("separation", 2)
	appips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apline.add_child(appips)
	hud_ap_pips = _make_pips(Config.AP_DISPLAY_SEGMENTS, appips)

	var handsline := HBoxContainer.new()
	handsline.add_theme_constant_override("separation", 10)
	handsline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vit.add_child(handsline)
	hud_hands_label = _mk_label("[-|-]", 12, Color(0.9, 0.9, 0.7))
	handsline.add_child(hud_hands_label)
	hud_carry_label = _mk_label("bare", 11, Color(0.8, 0.85, 0.7))
	handsline.add_child(hud_carry_label)

	hud_stance_label = _mk_label("", 11, Color(1, 0.9, 0.4))
	vit.add_child(hud_stance_label)

	# Keep transient targeting, combat, NPC, and narrative activity in a
	# separate rail so it cannot push the persistent squad controls around.
	var event_panel := PanelContainer.new()
	event_panel.name = "EventPanel"
	event_panel.anchor_left = 0.0
	event_panel.anchor_top = 0.0
	event_panel.anchor_right = 0.0
	event_panel.anchor_bottom = 1.0
	event_panel.offset_left = 14
	event_panel.offset_top = 424
	event_panel.offset_right = 230
	event_panel.offset_bottom = -112
	event_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var event_sb := sidebar_sb.duplicate() as StyleBoxFlat
	event_sb.bg_color = Color(0.04, 0.05, 0.08, 0.78)
	event_panel.add_theme_stylebox_override("panel", event_sb)
	add_child(event_panel)

	var event_vbox := VBoxContainer.new()
	event_vbox.add_theme_constant_override("separation", 6)
	event_panel.add_child(event_vbox)
	event_vbox.add_child(hint_label)
	event_vbox.add_child(HSeparator.new())
	event_vbox.add_child(_mk_label("TACTICAL FEED", 11, Color(0.7, 0.7, 0.9)))
	var narrative_scroll := ScrollContainer.new()
	narrative_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	narrative_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_vbox.add_child(narrative_scroll)
	narrative_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	narrative_scroll.add_child(narrative_box)

	var bar := PanelContainer.new()
	bar.name = "ActionDock"
	bar.anchor_left = 0.16
	bar.anchor_top = 1.0
	bar.anchor_right = 0.84
	bar.anchor_bottom = 1.0
	bar.offset_bottom = -12
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.94)
	sb.border_color = Color(0.2, 0.28, 0.4)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", sb)
	add_child(bar)

	var bar_hbox := HFlowContainer.new()
	bar_hbox.add_theme_constant_override("separation", 12)
	bar_hbox.alignment = FlowContainer.ALIGNMENT_CENTER
	bar_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bar_hbox)

	var g_weapons := _bar_group(bar_hbox, "WEAPONS")
	weapons_grid = GridContainer.new()
	weapons_grid.columns = 4
	weapons_grid.add_theme_constant_override("h_separation", 4)
	weapons_grid.add_theme_constant_override("v_separation", 4)
	weapons_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g_weapons.add_child(weapons_grid)
	action_groups["weapons"] = {"group": g_weapons, "content": weapons_grid}

	var g_stance := _bar_group(bar_hbox, "STANCE")
	var sg := GridContainer.new()
	sg.columns = 3
	sg.add_theme_constant_override("h_separation", 4)
	sg.add_theme_constant_override("v_separation", 4)
	sg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g_stance.add_child(sg)
	_add_action_btn(sg, "brace", "Brace (B)", func(): ActionRouter.request_action(main.selected, "brace"), 74)
	_add_action_btn(sg, "crouch", "Crouch (C)", func(): ActionRouter.request_action(main.selected, "crouch"), 74)
	_add_action_btn(sg, "prone", "Prone (P)", func(): ActionRouter.request_action(main.selected, "prone"), 74)
	_add_action_btn(sg, "lean_l", "Lean L (Q)", func(): ActionRouter.request_action(main.selected, "lean_l"), 74)
	_add_action_btn(sg, "lean_r", "Lean R (E)", func(): ActionRouter.request_action(main.selected, "lean_r"), 74)
	_add_action_btn(sg, "toggle_orient", "Face Up/Dn", func(): ActionRouter.request_action(main.selected, "toggle_orient"), 74)
	_add_action_btn(sg, "take_cover", "Take Cover (T)", _request_cover_action, 74)
	action_groups["stance"] = {"group": g_stance, "content": sg}

	var g_move := _bar_group(bar_hbox, "MOVEMENT")
	var mg := GridContainer.new()
	mg.columns = 3
	mg.add_theme_constant_override("h_separation", 4)
	mg.add_theme_constant_override("v_separation", 4)
	mg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g_move.add_child(mg)
	_add_action_btn(mg, "jump", "Jump (J)", func(): main.begin_targeting("jump"))
	_add_action_btn(mg, "toggle_walk", "Walk", func(): ActionRouter.request_action(main.selected, "toggle_walk"))
	_add_action_btn(mg, "toggle_run", "Sprint (M)", func(): ActionRouter.request_action(main.selected, "toggle_run"))
	_add_action_btn(mg, "dodge", "Dodge (Z)", func(): ActionRouter.request_action(main.selected, "dodge"))
	action_groups["movement"] = {"group": g_move, "content": mg}

	var g_spec := _bar_group(bar_hbox, "SPECIAL")
	var spg := GridContainer.new()
	spg.columns = 3
	spg.add_theme_constant_override("h_separation", 4)
	spg.add_theme_constant_override("v_separation", 4)
	spg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g_spec.add_child(spg)
	_add_action_btn(spg, "flip", "Flip (X)", func(): ActionRouter.request_action(main.selected, "flip"))
	_add_action_btn(spg, "frenzy", "Frenzy", func(): ActionRouter.request_action(main.selected, "frenzy"))
	_add_action_btn(spg, "wall_run", "Wall Run", func(): main.begin_targeting("wall_run"))
	_add_action_btn(spg, "wall_jump", "Wall Jump", func(): main.begin_targeting("wall_jump"))
	_add_action_btn(spg, "cover_monkey", "Cover Monkey", func(): ActionRouter.request_action(main.selected, "cover_monkey"))
	_add_action_btn(spg, "remotes", "Remotes", func(): ActionRouter.request_action(main.selected if main.selected else main._get_commander(), "remotes"))
	_add_action_btn(spg, "remotes_home", "Remotes Home", func(): ActionRouter.request_action(main.selected if main.selected else main._get_commander(), "remotes_home"))
	_add_action_btn(spg, "hover", "Hover (H)", func(): ActionRouter.request_action(main.selected, "hover"))
	_add_action_btn(spg, "toggle_flight", "Flight (V)", func(): main.begin_targeting("flight"))
	_add_action_btn(spg, "flight_up", "Layer +", func(): main.adjust_flight_layer(1))
	_add_action_btn(spg, "flight_down", "Layer −", func(): main.adjust_flight_layer(-1))
	_add_action_btn(spg, "flight_land", "Land (L)", func(): main.land_selected_unit())
	_add_action_btn(spg, "toggle_free_fly", "Drone Cam", func(): ActionRouter.request_action(main.selected, "toggle_free_fly"))
	action_groups["special"] = {"group": g_spec, "content": spg}

	var g_misc := _bar_group(bar_hbox, "GEAR")
	var mscg := GridContainer.new()
	mscg.columns = 2
	mscg.add_theme_constant_override("h_separation", 4)
	mscg.add_theme_constant_override("v_separation", 4)
	mscg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g_misc.add_child(mscg)
	_add_action_btn(mscg, "grab", "Grab Loot (G)", func(): ActionRouter.request_action(main.selected, "grab"), 82)
	_add_action_btn(mscg, "assemble", "Assemble Bow (F)", func(): ActionRouter.request_action(main.selected, "assemble"), 82)
	action_groups["gear"] = {"group": g_misc, "content": mscg}

	var b_end := Button.new()
	b_end.focus_mode = Control.FOCUS_NONE
	b_end.text = "END TURN"
	b_end.custom_minimum_size = Vector2(88, 30)
	b_end.add_theme_font_size_override("font_size", 11)
	b_end.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	var action_events = InputMap.action_get_events("endturn")
	if action_events.size() > 0:
		var ev = action_events[0]
		var shortcut = Shortcut.new()
		shortcut.events.append(ev)
		b_end.shortcut = shortcut
		var key_name = OS.get_keycode_string(ev.keycode)
		b_end.tooltip_text = "End Turn (%s)" % key_name
	b_end.pressed.connect(func(): ActionRouter.request_action(main.selected, "endturn"))
	bar_hbox.add_child(b_end)
	action_btns["endturn"] = b_end

	var b_evac := Button.new()
	b_evac.text = "⏏ EXTRACT"
	b_evac.custom_minimum_size = Vector2(92, 30)
	b_evac.add_theme_font_size_override("font_size", 11)
	b_evac.add_theme_color_override("font_color", Color(1, 0.75, 0.2))
	b_evac.tooltip_text = "Evac / extract now (F8). Loops back to strategy with whatever you've got."
	b_evac.pressed.connect(func(): main._do_evac())
	bar_hbox.add_child(b_evac)
	action_btns["evac"] = b_evac

func _request_cover_action() -> void:
	if main.selected == null:
		return
	if main.selected.taking_cover:
		ActionRouter.request_action(main.selected, "leave_cover")
	else:
		main.begin_targeting("take_cover")

func _set_camera_mode(m: int) -> void:
	if main.camera_controller:
		main.camera_controller.set_mode(m)
	update_ui()

func _toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN
	)
	var full_button := get_node_or_null("ViewModeBox/btn_full") as Button
	if full_button:
		full_button.text = "FULL" if full else "WINDOW"

func hint(msg: String) -> void:
	if hint_label:
		hint_label.text = msg

func update_ui() -> void:
	if turn_label:
		if main.turn == main.player_faction: turn_label.text = "YOUR TURN (T%d)" % main.global_turn
		else: turn_label.text = "ENEMY TURN (T%d)" % main.global_turn
		if main.turn == Config.FACTION_SYND: turn_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.9))
		elif main.turn == Config.FACTION_TIME: turn_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2))
		else: turn_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.9))

	var is_player = (main.turn == main.player_faction)
	var can = (is_player and not main.busy and not main.game_over)
	var e_cnt := 0
	for u in main.units:
		if u.alive and u.team != main.player_faction: e_cnt += 1
	if enemy_label:
		enemy_label.text = "%d HOSTILES REMAIN" % e_cnt
		if e_cnt == 0: enemy_label.text = "SECTOR CLEAR"

	for row in roster_rows:
		var ru = row["unit"]
		var rb: Button = row["btn"]
		if not ru.alive:
			rb.text = "-- DOWN --"
			rb.disabled = true
			rb.add_theme_color_override("font_color", Color(0.5, 0.3, 0.3))
		else:
			var role = "CMDR" if bool(ru.is_commander) else ("REMOTE" if bool(ru.player_controlled) else "BOT")
			rb.text = "[%s] %s  HP%d AP%d" % [role, ru.name, max(ru.hp, 0), ru.ap]
			# Always allow inspect/select; control is gated elsewhere.
			rb.disabled = not is_player or main.busy or main.game_over
			if bool(ru.player_controlled):
				rb.add_theme_color_override("font_color", Color(0.35, 1.0, 0.75) if ru == main.selected else Color(0.45, 0.9, 0.7))
			elif ru == main.selected:
				rb.add_theme_color_override("font_color", Color(0.95, 1.0, 0.9))
			else:
				rb.add_theme_color_override("font_color", Color(0.55, 0.65, 0.75))

		if main.camera_controller:
			var mode = main.camera_controller.active_mode
			var vb = get_node_or_null("ViewModeBox")
			if vb:
				vb.get_node("btn_bev").visible = (mode != 0)
				vb.get_node("btn_ots").visible = (mode != 1)
				vb.get_node("btn_fps").visible = (mode != 2)
				vb.get_node("btn_rem").visible = main.dev_god_mode

	for b in action_btns.values():
		if b: b.disabled = true
	if action_btns.has("take_cover"):
		action_btns["take_cover"].visible = false
	for contextual_name in ["lean_l", "lean_r", "flip", "wall_run", "wall_jump", "cover_monkey", "frenzy", "remotes", "remotes_home"]:
		if action_btns.has(contextual_name):
			action_btns[contextual_name].visible = false

	# God-mode specials (Remotes, Cover Monkey, Flip/Wall, etc.)
	var god = bool(main.dev_god_mode)
	for special_name in ["remotes", "cover_monkey", "flip", "wall_run", "wall_jump", "frenzy"]:
		if action_btns.has(special_name):
			action_btns[special_name].visible = god
	if action_btns.has("remotes_home"):
		var pilot_home = main._active_human_pilot() if main.has_method("_active_human_pilot") else null
		var remoted = pilot_home != null and not bool(pilot_home.is_commander)
		action_btns["remotes_home"].visible = god and remoted
		action_btns["remotes_home"].disabled = main.busy or main.game_over or not is_player

	if is_player and not main.game_over:
		action_btns["endturn"].disabled = main.busy
		if action_btns.has("evac"): action_btns["evac"].disabled = main.busy
		var can_pilot = (
			main.selected
			and main.selected.team == main.player_faction
			and main.selected.alive
			and not main.busy
			and bool(main.selected.player_controlled)
		)
		if action_btns.has("remotes"):
			action_btns["remotes"].disabled = main.busy or not god
		if can_pilot:
			action_btns["dodge"].disabled = (main.selected.ap < Config.DODGE_COST)
			action_btns["brace"].disabled = (main.selected.ap < Config.BLOCK_COST or main.selected.blocking)
			action_btns["crouch"].disabled = (main.selected.ap < Config.CROUCH_COST)
			action_btns["prone"].disabled = (main.selected.ap < Config.PRONE_COST)
			action_btns["lean_l"].visible = main.selected.taking_cover
			action_btns["lean_r"].visible = main.selected.taking_cover
			action_btns["lean_l"].disabled = (main.selected.ap < Config.LEAN_COST or not main.selected.taking_cover)
			action_btns["lean_r"].disabled = (main.selected.ap < Config.LEAN_COST or not main.selected.taking_cover)
			action_btns["toggle_orient"].disabled = (main.selected.stance != "prone")
			var cover_button: Button = action_btns["take_cover"]
			var adjacent_cover: Array[Vector2i] = main.cover_options(main.selected)
			cover_button.visible = main.selected.taking_cover or not adjacent_cover.is_empty()
			if main.selected.taking_cover:
				cover_button.text = "Leave Cover (T)"
				cover_button.tooltip_text = "Leave Cover – release the committed position (%d AP)." % Config.LEAVE_COVER_COST
				cover_button.disabled = main.selected.ap < Config.LEAVE_COVER_COST
			else:
				cover_button.text = "Take Cover (T)"
				cover_button.tooltip_text = action_tooltips["take_cover"]
				cover_button.disabled = adjacent_cover.is_empty() or main.selected.ap < Config.TAKE_COVER_COST
			var btn_walk = action_btns["toggle_walk"]
			var btn_run = action_btns["toggle_run"]
			btn_walk.disabled = false
			btn_run.disabled = false
			if main.selected.move_mode == "walk":
				btn_walk.text = "► Walk"
				btn_walk.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
				btn_run.text = "Run (M)"
				btn_run.add_theme_color_override("font_color", Color(1, 1, 1))
			elif main.selected.move_mode == "run":
				btn_walk.text = "Walk"
				btn_walk.add_theme_color_override("font_color", Color(1, 1, 1))
				btn_run.text = "► Run (M)"
				btn_run.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
			else: # sprint
				btn_walk.text = "Walk"
				btn_walk.add_theme_color_override("font_color", Color(1, 1, 1))
				btn_run.text = "► Sprint (M)"
				btn_run.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
			var airborne := Maneuvers.is_airborne(main.selected.maneuver)
			var wall_running := Maneuvers.is_wall_running(main.selected.maneuver)
			action_btns["jump"].text = "Complete Jump (J)" if airborne else "Jump (J)"
			action_btns["jump"].disabled = not main.can_begin_jump(main.selected)
			action_btns["grab"].disabled = (main.selected.ap < Config.GRAB_COST) or not main.debris.has(main.selected.cell)
			action_btns["assemble"].disabled = (main.selected.ap < Config.ASSEMBLE_COST)
			if main.dev_god_mode:
				var runnable_walls: Array[Vector2i] = main.wall_run_options(main.selected)
				action_btns["flip"].disabled = (not airborne or main.selected.ap < Config.FLIP_COST)
				action_btns["wall_run"].disabled = (
					main.selected.ap < Config.WALL_RUN_COST
					or (not wall_running and runnable_walls.is_empty())
				)
				action_btns["wall_jump"].disabled = (not wall_running or main.selected.ap < Config.WALL_JUMP_COST)
				action_btns["cover_monkey"].disabled = false
				action_btns["cover_monkey"].text = "Cover Monkey: %s" % ["ON" if main.selected.cover_monkey_active else "OFF"]
				action_btns["hover"].disabled = (main.selected.ap < Config.HOVER_COST)
				action_btns["frenzy"].disabled = (main.selected.frenzied and main.selected.ap < 1)
				action_btns["frenzy"].text = "Frenzy: %s" % ["ON" if main.selected.frenzied else "OFF"]
				action_btns["toggle_flight"].disabled = (main.selected.ap < Config.FLIGHT_TOGGLE_COST and not main.selected.flying)
				action_btns["flight_up"].disabled = main.pending_target_action != "flight"
				action_btns["flight_down"].disabled = main.pending_target_action != "flight"
				var terrain_z := int(main.cells.get(main.selected.cell, {}).get("z", 0))
				action_btns["flight_land"].disabled = not main.selected.flying or main.selected.z <= terrain_z
				action_btns["toggle_free_fly"].disabled = false
				action_btns["flip"].visible = airborne
				action_btns["wall_run"].visible = wall_running or not runnable_walls.is_empty()
				action_btns["wall_jump"].visible = wall_running
				action_btns["cover_monkey"].visible = true
				action_btns["hover"].visible = true
				action_btns["frenzy"].visible = true
				action_btns["toggle_flight"].visible = true
				action_btns["flight_up"].visible = true
				action_btns["flight_down"].visible = true
				action_btns["flight_land"].visible = true
				action_btns["toggle_free_fly"].visible = true
			else:
				action_btns["flip"].visible = false
				action_btns["wall_run"].visible = false
				action_btns["wall_jump"].visible = false
				action_btns["cover_monkey"].visible = false
				action_btns["hover"].visible = false
				action_btns["frenzy"].visible = false
				action_btns["toggle_flight"].visible = false
				action_btns["flight_up"].visible = false
				action_btns["flight_down"].visible = false
				action_btns["flight_land"].visible = false
				action_btns["toggle_free_fly"].visible = false

	_update_weapons_bar()
	_refresh_action_groups()

	if main.selected:
		hud_name.text = main.selected.name
		hud_hp_label.text = "HP %d/%d" % [main.selected.hp, main.selected.max_hp]
		hud_ap_label.text = "AP %d/%d" % [main.selected.ap, main.selected.max_ap]
		_fill_pips(hud_hp_pips, main.selected.hp, _hp_color(main.selected))
		_fill_ratio_pips(hud_ap_pips, main.selected.ap, main.selected.max_ap, Color(0.3, 0.8, 1.0))
		hud_hands_label.text = "HANDS " + main.selected.grip_str()
		hud_carry_label.text = "CARRY: " + _inv_str(main.selected.inv)
		var st_text := ""
		if main.selected.move_mode == "sprint": st_text += "[SPRINTING] "
		if main.selected.run_distance_this_turn > 0 or main.selected.sprint_distance_this_turn > 0:
			st_text += "[MOMENTUM R%d/S%d] " % [main.selected.run_distance_this_turn, main.selected.sprint_distance_this_turn]
		if main.selected.cover_monkey_active: st_text += "[COVER MONKEY] "
		if main.selected.taking_cover: st_text += "[IN COVER] "
		elif main.selected.blocking: st_text += "[BRACED] "
		if main.selected.dodging: st_text += "[DODGING] "
		if main.selected.flying: st_text += "[FLYING] "
		elif main.selected.hovering: st_text += "[HOVERING] "
		if main.selected.wall_running: st_text += "[WALLRUN] "
		if Maneuvers.is_airborne(main.selected.maneuver):
			st_text += "[AIRBORNE STAGE %d] " % int(main.selected.maneuver.get("stage", 1))
		st_text += main.selected.stance.to_upper()
		if main.selected.lean != "none":
			st_text += " (LEAN %s)" % main.selected.lean.to_upper()
		hud_stance_label.text = st_text
	else:
		hud_name.text = "—"
		_fill_pips(hud_hp_pips, 0, Color.BLACK)
		_fill_pips(hud_ap_pips, 0, Color.BLACK)
		hud_hp_label.text = "HP"
		hud_ap_label.text = "AP"
		hud_stance_label.text = ""
		hud_hands_label.text = "[-|-]"
		hud_carry_label.text = "bare"

func _refresh_action_groups() -> void:
	for entry in action_groups.values():
		var group: Control = entry.get("group")
		var content: Control = entry.get("content")
		var has_visible_control := false
		if is_instance_valid(content):
			for child in content.get_children():
				if child is Control and child.visible:
					has_visible_control = true
					break
		if is_instance_valid(group):
			group.visible = has_visible_control

func _update_weapons_bar() -> void:
	for c in weapons_grid.get_children():
		c.queue_free()
	weapon_btns.clear()

	var is_player = (main.turn == main.player_faction)
	var ItemDB = main.get_node_or_null("/root/ItemDB")

	if main.selected and main.selected.team == main.player_faction and main.selected.alive:
		var _has_any = false
		for k in main.selected.inv.keys():
			if int(main.selected.inv.get(k, 0)) > 0:
				_has_any = true
				var b := Button.new()
				b.focus_mode = Control.FOCUS_NONE
				b.text = k.capitalize()
				var display_name = b.text
				var lacks_skills = false
				var missing_skills = []
				# Declare outside the ItemDB branch — GDScript block-scopes `var`,
				# and the tooltip path below must still see the item dict.
				var itm: Dictionary = {}
				if ItemDB:
					itm = ItemDB.get_item(k)
					if not itm.is_empty():
						display_name = itm.get("name", display_name)
						if itm.get("category", itm.get("type", "")) == "ranged":
							display_name += " [R]"

						var reqs = itm.get("skills", [])
						for req in reqs:
							if not req in main.selected.skills:
								lacks_skills = true
								missing_skills.append(req)

				if lacks_skills:
					b.tooltip_text = "Requires Skills: %s" % ", ".join(missing_skills)
					b.add_theme_color_override("font_color", Color(0.5, 0.3, 0.3))
				else:
					var item_cost := ActionEconomy.weapon_cost(itm) if not itm.is_empty() else 0
					var dmg_type = String(itm.get("damage_type", "kinetic"))
					var apierce = int(itm.get("armor_pierce", 0))
					var pierce_str = ""
					if apierce > 0: pierce_str = " (AP: %d)" % apierce
					b.tooltip_text = "Ready %s (%d AP). Attack: %d AP.\nType: %s%s" % [display_name, Config.EQUIP_COST, item_cost, dmg_type.capitalize(), pierce_str]

				b.custom_minimum_size = Vector2(72, 22)
				b.add_theme_font_size_override("font_size", 10)
				b.pressed.connect((func(wk): ActionRouter.request_action(main.selected, "equip_" + wk)).bind(k))

				if not is_player or main.busy or main.game_over or lacks_skills or main.selected.ap < Config.EQUIP_COST:
					b.disabled = true
				weapons_grid.add_child(b)
				weapon_btns[k] = b

		var fb := Button.new()
		fb.focus_mode = Control.FOCUS_NONE
		fb.text = "Fists"
		fb.tooltip_text = "Ready unarmed attacks (%d AP)" % Config.EQUIP_COST
		fb.custom_minimum_size = Vector2(72, 22)
		fb.add_theme_font_size_override("font_size", 10)
		fb.pressed.connect(func(): ActionRouter.request_action(main.selected, "equip_fist"))
		if not is_player or main.busy or main.game_over or main.selected.ap < Config.EQUIP_COST:
			fb.disabled = true
		weapons_grid.add_child(fb)
		weapon_btns["fist"] = fb

func build_roster() -> void:
	if not roster_box: return
	for r in roster_rows:
		if r.has("btn") and is_instance_valid(r["btn"]): r["btn"].queue_free()
	roster_rows.clear()

	for u in main.units:
		if u.team == main.player_faction:
			var btn := Button.new()
			btn.text = u.name
			btn.add_theme_font_size_override("font_size", 11)
			btn.custom_minimum_size = Vector2(0, 22)
			btn.pressed.connect(main.perform_action.bind(u, "select"))
			roster_box.add_child(btn)
			roster_rows.append({"unit": u, "btn": btn})

	if enemy_label and enemy_label.get_parent() != null:
		roster_box.remove_child(enemy_label)
		roster_box.add_child(enemy_label)

func refresh_label(u: Unit) -> void:
	if u.label:
		var b := "  [B]" if u.blocking else ""
		u.label.text = "%d%s" % [max(u.hp, 0), b]

func _hp_color(u: Unit) -> Color:
	var r := float(u.hp) / float(u.max_hp)
	if r > 0.6: return Color(0.2, 0.9, 0.4)
	if r > 0.3: return Color(0.9, 0.8, 0.2)
	return Color(0.9, 0.3, 0.3)

func _fill_pips(pips: Array, val: int, color: Color) -> void:
	for i in pips.size():
		if i < val:
			pips[i].color = color
		else:
			pips[i].color = Color(0.2, 0.2, 0.2)

func _fill_ratio_pips(pips: Array, val: int, maximum: int, color: Color) -> void:
	var filled := 0
	if maximum > 0 and val > 0:
		filled = ceili(float(val) / float(maximum) * float(pips.size()))
	_fill_pips(pips, filled, color)

func _inv_str(inv: Dictionary) -> String:
	var s := ""
	for k in inv.keys():
		if int(inv.get(k, 0)) > 0:
			var code = k.left(4).capitalize()
			s += "%s:%d " % [code, int(inv[k])]
	s = s.strip_edges()
	return s if s != "" else "bare"

func _on_narrative_logged(msg: String, _category: String = "") -> void:
	if not narrative_box: return
	var lbl := _mk_label(msg, 11, Color(0.8, 0.8, 0.9), true)
	lbl.custom_minimum_size = Vector2(205, 0)
	narrative_box.add_child(lbl)
	var max_lines := 5
	while narrative_box.get_child_count() > max_lines:
		var c = narrative_box.get_child(0)
		narrative_box.remove_child(c)
		c.queue_free()

func _on_neural_changed(val: int) -> void:
	if neural_label:
		neural_label.text = "NEURAL: %d" % val

func _export_bug() -> void:
	var state = main.serialize_units() if main.has_method("serialize_units") else []
	var logs = []
	var Narrative = get_node_or_null("/root/Narrative")
	if Narrative: logs = Narrative.log_entries.duplicate()
	var path = PayloadBridge.export_bug_report({"units": state}, logs)
	hint("Bug Report Exported: " + path)
