extends CanvasLayer


const Config = preload("res://scripts/GameConfig.gd")
const Maneuvers = preload("res://scripts/ManeuverState.gd")
const HudLayout = preload("res://scripts/HudLayout.gd")

# The layout and contrast model lives in `HudLayout` so headless checks and the
# M05-B evidence emitter can read it without a viewport or the autoloads.
const STATUS_RAIL_RIGHT := HudLayout.STATUS_RAIL_RIGHT
const RESPONSIVE_GUTTER := HudLayout.RESPONSIVE_GUTTER
const TUTORIAL_LEFT_ANCHOR := HudLayout.TUTORIAL_LEFT_ANCHOR
const ACTION_DOCK_LEFT_ANCHOR := HudLayout.ACTION_DOCK_LEFT_ANCHOR
const TUTORIAL_TOP := HudLayout.TUTORIAL_TOP
const TUTORIAL_HEIGHT := HudLayout.TUTORIAL_HEIGHT
const ACTION_DOCK_BOTTOM_MARGIN := HudLayout.ACTION_DOCK_BOTTOM_MARGIN
const ACTION_DOCK_BASE_HEIGHT := HudLayout.ACTION_DOCK_BASE_HEIGHT
const EVENT_RAIL_TOP := HudLayout.EVENT_RAIL_TOP
const FOCUS_ORDER_KEYS := HudLayout.FOCUS_ORDER_KEYS
const GRIP_SIZE := 16.0

## The tactical runtime runs inside the launcher's iframe, so the profile bridge
## lives on the host window, not this one. Same-origin, and it mirrors the
## existing extraction hand-off in `PayloadBridge`.
const HOST_BRIDGE_JS := (
	"(window.BSS_BRIDGE"
	+ " || (window.parent && window.parent !== window && window.parent.BSS_BRIDGE)"
	+ " || (window.opener && window.opener.BSS_BRIDGE)"
	+ " || null)"
)
const SUPPORTED_VIEWPORTS := HudLayout.SUPPORTED_VIEWPORTS

var main: Node
var last_layout_metrics: Dictionary = {}
var focused_control_key: String = ""

# Adaptive HUD surfaces. Each entry holds the surface's node, the edge it parks
# against, its current opacity, and its slide state. Player intent is recorded
# separately from automatic adaptation so a surface the player opened is never
# silently taken away by a later resize.
var hud_surfaces: Dictionary = {}
var hud_surface_cursor: int = 0
var _hud_layout_pass: bool = false

# Nodes
var turn_label: Label
var enemy_label: Label
var neural_label: Label
var pilot_label: Label
var phase_help_label: Label
var roster_box: VBoxContainer
var roster_rows: Array = []
var narrative_box: VBoxContainer
var hud_name: Label
var hud_hp_label: Label
var hud_ap_label: Label
var hud_hands_label: Label
var hud_carry_label: Label
var hud_stance_label: Label
var core_costs_label: Label
var hud_hp_pips: Array = []
var hud_ap_pips: Array = []
var weapons_grid: GridContainer = null
var weapon_btns: Dictionary = {}
var action_btns: Dictionary = {}
var action_groups: Dictionary = {}
var hint_label: Label
var tutorial_panel: PanelContainer
var tutorial_title_label: Label
var tutorial_body_label: Label
var help_panel: PanelContainer

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
	"endturn": "End Turn — finish Commander actions, resolve allied Agents, then both hostile faction phases.",
	"equip_fist": "Equip Fists – ready unarmed attacks (%d AP)." % Config.EQUIP_COST
}

func _init(main_ref: Node):
	main = main_ref
	name = "TacticalUI"

func _ready():
	_build_ui()
	var viewport := get_viewport()
	if viewport and not viewport.size_changed.is_connected(_apply_responsive_layout):
		viewport.size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")

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

func _enable_keyboard_focus(button: Button) -> void:
	button.focus_mode = Control.FOCUS_ALL
	var focus_outline := StyleBoxFlat.new()
	focus_outline.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	focus_outline.border_color = Color(0.3, 0.95, 1.0, 1.0)
	focus_outline.set_border_width_all(2)
	focus_outline.set_corner_radius_all(4)
	button.add_theme_stylebox_override("focus", focus_outline)

func _add_action_btn(container: Node, key: String, text: String, cb: Callable, min_w := 54) -> void:
	var b := Button.new()
	_enable_keyboard_focus(b)
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

func layout_metrics_for_width(
	viewport_width: float,
	status_rail_right: float = STATUS_RAIL_RIGHT,
	event_rail_right: float = STATUS_RAIL_RIGHT
) -> Dictionary:
	return HudLayout.metrics_for_width(
		viewport_width,
		status_rail_right,
		event_rail_right
	)

func layout_metrics_for_viewport(
	viewport_width: float,
	viewport_height: float,
	status_rail_right: float = STATUS_RAIL_RIGHT,
	event_rail_right: float = STATUS_RAIL_RIGHT,
	tutorial_height: float = TUTORIAL_HEIGHT,
	action_dock_height: float = ACTION_DOCK_BASE_HEIGHT,
	status_rail_content_bottom: float = HudLayout.STATUS_RAIL_BASE_BOTTOM
) -> Dictionary:
	return HudLayout.metrics_for_viewport(
		viewport_width,
		viewport_height,
		status_rail_right,
		event_rail_right,
		tutorial_height,
		action_dock_height,
		status_rail_content_bottom
	)

func _apply_responsive_layout() -> void:
	if _hud_layout_pass:
		return
	_hud_layout_pass = true
	_layout_pass()
	# Grips are placed last, once every surface has its final rectangle.
	_place_hud_grips()
	_hud_layout_pass = false

func _layout_pass() -> void:
	var viewport_width := get_viewport().get_visible_rect().size.x
	var status_rail_right := STATUS_RAIL_RIGHT
	# Rail extents are measured from the authored gutter plus the surface's own
	# width, never from its current position: a slid surface must report the room
	# it would need when open, or the model and the applied layout disagree.
	var status_panel := get_node_or_null("StatusPanel") as Control
	if status_panel:
		status_rail_right = maxf(
			status_rail_right,
			RESPONSIVE_GUTTER
			+ maxf(status_panel.size.x, status_panel.get_combined_minimum_size().x)
		)
	var event_rail_right := STATUS_RAIL_RIGHT
	var event_panel := get_node_or_null("EventPanel") as Control
	if event_panel:
		event_rail_right = maxf(
			event_rail_right,
			RESPONSIVE_GUTTER
			+ maxf(event_panel.size.x, event_panel.get_combined_minimum_size().x)
		)
	var viewport_height := get_viewport().get_visible_rect().size.y
	var action_dock := get_node_or_null("ActionDock") as Control
	var action_dock_height := ACTION_DOCK_BASE_HEIGHT
	if action_dock:
		action_dock_height = maxf(
			action_dock.size.y,
			action_dock.get_combined_minimum_size().y
		)
	var tutorial_height := TUTORIAL_HEIGHT
	if tutorial_panel:
		tutorial_height = maxf(
			tutorial_height,
			tutorial_panel.get_combined_minimum_size().y
		)
	var status_rail_content_bottom := HudLayout.STATUS_RAIL_BASE_BOTTOM
	if status_panel:
		status_rail_content_bottom = maxf(
			status_rail_content_bottom,
			maxf(status_panel.position.y, status_panel.offset_top)
			+ maxf(status_panel.size.y, status_panel.get_combined_minimum_size().y)
		)
	# Adaptive pass. A canvas that cannot host the open arrangement parks the
	# tactical feed, then the status rail, rather than reporting a broken layout.
	# Only deliberate player intent is an input. Automatic parking is recomputed
	# from scratch every pass, so the metrics always describe the arrangement that
	# is actually applied and a previous adaptation can never compound.
	var requested_states := {}
	for key in hud_surfaces:
		requested_states[key] = {
			"opacity": float(hud_surfaces[key]["opacity"]),
			"slide": (
				HudLayout.Slide.PARKED
				if bool(hud_surfaces[key]["player_parked"])
				else HudLayout.Slide.OPEN
			)
		}
	var metrics := HudLayout.adaptive_metrics(
		viewport_width,
		viewport_height,
		requested_states,
		status_rail_right,
		event_rail_right,
		tutorial_height,
		action_dock_height,
		status_rail_content_bottom
	)
	# Apply exactly the arrangement the metrics describe: player intent plus this
	# pass's automatic parking. A surface the player never parked is restored as
	# soon as the room returns.
	var auto_parked: Array = metrics.get("auto_parked", [])
	for key in hud_surfaces:
		var surface_key := String(key)
		var should_park := (
			bool(hud_surfaces[surface_key]["player_parked"])
			or auto_parked.has(surface_key)
		)
		if is_surface_parked(surface_key) != should_park:
			set_surface_parked(surface_key, should_park, false)
	last_layout_metrics = metrics
	# Park offsets are derived from the same measurements the model just used, in
	# this same pass. Deriving them from a node's live size instead let a size that
	# settled a frame later leave the handle a few pixels off the model's contract.
	var status_shift := Vector2(
		(HudLayout.HANDLE_EXTENT - (status_rail_right - RESPONSIVE_GUTTER))
		if is_surface_parked("status") else 0.0,
		0.0
	)
	var feed_shift := Vector2(
		(HudLayout.HANDLE_EXTENT - (event_rail_right - RESPONSIVE_GUTTER))
		if is_surface_parked("feed") else 0.0,
		0.0
	)
	var tutorial_shift := Vector2(
		0.0,
		-maxf(tutorial_height - HudLayout.HANDLE_EXTENT, 0.0)
		if is_surface_parked("tutorial") else 0.0
	)
	var dock_shift := Vector2(
		0.0,
		maxf(action_dock_height - HudLayout.HANDLE_EXTENT, 0.0)
		if is_surface_parked("dock") else 0.0
	)
	if tutorial_panel:
		tutorial_panel.offset_left = (
			float(metrics["tutorial_left"])
			- viewport_width * tutorial_panel.anchor_left
			+ tutorial_shift.x
		)
		tutorial_panel.offset_top = HudLayout.TUTORIAL_TOP + tutorial_shift.y
		tutorial_panel.offset_bottom = (
			HudLayout.TUTORIAL_TOP + HudLayout.TUTORIAL_HEIGHT + tutorial_shift.y
		)
	if action_dock:
		action_dock.offset_left = (
			float(metrics["action_dock_left"])
			- viewport_width * action_dock.anchor_left
			+ dock_shift.x
		)
		action_dock.offset_bottom = -HudLayout.ACTION_DOCK_BOTTOM_MARGIN + dock_shift.y
	if status_panel:
		status_panel.offset_left = RESPONSIVE_GUTTER + status_shift.x
		status_panel.offset_right = HudLayout.STATUS_RAIL_RIGHT + status_shift.x
	# The tactical-feed rail is bottom-anchored. Its previous fixed -112 offset
	# assumed a single-row action dock; a wrapped dock overlapped the feed. On a
	# short canvas the status rail above it compresses first.
	if event_panel:
		event_panel.offset_left = RESPONSIVE_GUTTER + feed_shift.x
		event_panel.offset_right = HudLayout.STATUS_RAIL_RIGHT + feed_shift.x
		if bool(metrics["event_rail_visible"]):
			event_panel.offset_top = float(metrics["event_rail_top"]) + feed_shift.y
			event_panel.offset_bottom = (
				float(metrics["event_rail_bottom_offset"]) + feed_shift.y
			)

func _build_ui() -> void:
	var left_sidebar := PanelContainer.new()
	left_sidebar.name = "StatusPanel"
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

	tutorial_panel = PanelContainer.new()
	tutorial_panel.name = "TutorialPanel"
	tutorial_panel.anchor_left = 0.24
	tutorial_panel.anchor_top = 0.0
	tutorial_panel.anchor_right = 0.76
	tutorial_panel.anchor_bottom = 0.0
	tutorial_panel.offset_top = 14
	tutorial_panel.offset_bottom = 112
	tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tutorial_sb := StyleBoxFlat.new()
	tutorial_sb.bg_color = Color(0.025, 0.12, 0.11, 0.96)
	tutorial_sb.border_color = Color(0.2, 0.95, 0.72, 0.9)
	tutorial_sb.set_border_width_all(2)
	tutorial_sb.set_corner_radius_all(8)
	tutorial_sb.content_margin_left = 14
	tutorial_sb.content_margin_right = 14
	tutorial_sb.content_margin_top = 10
	tutorial_sb.content_margin_bottom = 10
	tutorial_panel.add_theme_stylebox_override("panel", tutorial_sb)
	add_child(tutorial_panel)

	var tutorial_vbox := VBoxContainer.new()
	tutorial_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_vbox.add_theme_constant_override("separation", 5)
	tutorial_panel.add_child(tutorial_vbox)
	tutorial_title_label = _mk_label("", 13, Color(0.35, 1.0, 0.78))
	tutorial_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_vbox.add_child(tutorial_title_label)
	tutorial_body_label = _mk_label("", 12, Color(0.9, 0.96, 1.0), true)
	tutorial_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tutorial_vbox.add_child(tutorial_body_label)
	tutorial_panel.visible = false

	var b_bev := Button.new()
	b_bev.name = "btn_bev"
	b_bev.text = "BEV"
	_enable_keyboard_focus(b_bev)
	b_bev.pressed.connect(func(): _set_camera_mode(0))
	view_mode_box.add_child(b_bev)

	var b_fps := Button.new()
	b_fps.name = "btn_fps"
	b_fps.text = "FPS"
	_enable_keyboard_focus(b_fps)
	b_fps.pressed.connect(func(): _set_camera_mode(2))
	view_mode_box.add_child(b_fps)

	var b_ots := Button.new()
	b_ots.name = "btn_ots"
	b_ots.text = "OTS"
	_enable_keyboard_focus(b_ots)
	b_ots.pressed.connect(func(): _set_camera_mode(1))
	view_mode_box.add_child(b_ots)

	var b_rem := Button.new()
	b_rem.name = "btn_rem"
	b_rem.text = "REMOTES"
	_enable_keyboard_focus(b_rem)
	b_rem.pressed.connect(func(): main._hint("Remotes view activated!"))
	view_mode_box.add_child(b_rem)

	var b_help := Button.new()
	b_help.name = "btn_help"
	b_help.text = "HELP (F1)"
	_enable_keyboard_focus(b_help)
	b_help.tooltip_text = "Core controls, turn order, AP, extraction, and developer-feature boundary"
	b_help.pressed.connect(toggle_help)
	view_mode_box.add_child(b_help)

	var b_full := Button.new()
	b_full.name = "btn_full"
	b_full.text = "FULL"
	_enable_keyboard_focus(b_full)
	b_full.tooltip_text = "Toggle fullscreen tactical view"
	b_full.pressed.connect(_toggle_fullscreen)
	view_mode_box.add_child(b_full)

	# The persistent status content is taller than the rail's authored box, so it
	# used to spill past the bottom edge and sit under the tactical-feed rail.
	# Scrolling keeps the rail's height honest: the panel now reports the size it
	# actually occupies, which is what the responsive layout measures.
	var left_scroll := ScrollContainer.new()
	left_scroll.name = "StatusScroll"
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.follow_focus = true
	left_sidebar.add_child(left_scroll)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 6)
	left_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left_vbox)

	var topline := HBoxContainer.new()
	topline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	topline.add_theme_constant_override("separation", 12)
	left_vbox.add_child(topline)

	turn_label = _mk_label("YOUR TURN", 15, Color(1, 1, 1))
	topline.add_child(turn_label)

	var Economy = get_node_or_null("/root/Economy")
	neural_label = _mk_label("NEURAL: %d" % (Economy.player_neural if Economy else 0), 13, Color(0.2, 0.9, 0.6))
	topline.add_child(neural_label)

	pilot_label = _mk_label("ACTIVE PILOT: —", 11, Color(0.35, 1.0, 0.75), true)
	pilot_label.custom_minimum_size = Vector2(205, 0)
	left_vbox.add_child(pilot_label)
	phase_help_label = _mk_label("", 10, Color(0.72, 0.82, 0.95), true)
	phase_help_label.custom_minimum_size = Vector2(205, 0)
	left_vbox.add_child(phase_help_label)

	var god_mode_cb := CheckBox.new()
	god_mode_cb.focus_mode = Control.FOCUS_NONE
	god_mode_cb.text = "[DEV] ADVANCED MOBILITY + REMOTES"
	god_mode_cb.button_pressed = main.dev_god_mode
	god_mode_cb.add_theme_font_size_override("font_size", 10)
	god_mode_cb.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2))
	god_mode_cb.tooltip_text = "Optional experimental controls. Not required for the core play loop or Proving Ground."
	god_mode_cb.toggled.connect(func(t): main.dev_god_mode = t; update_ui())
	left_vbox.add_child(god_mode_cb)

	var btn_export = Button.new()
	btn_export.text = "BUG REPORT (EXPORT)"
	_enable_keyboard_focus(btn_export)
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
	roster_box.add_child(enemy_label)

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
	core_costs_label = _mk_label(
		"CORE COSTS: Move %d/step · Brace %d · Cover %d · Melee %d · Equip %d" % [
			Config.MOVE_COST,
			Config.BLOCK_COST,
			Config.TAKE_COVER_COST,
			Config.MELEE_COST,
			Config.EQUIP_COST
		],
		9,
		Color(0.65, 0.76, 0.88),
		true
	)
	core_costs_label.custom_minimum_size = Vector2(205, 0)
	vit.add_child(core_costs_label)

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

	# The dock wraps at narrow widths and would otherwise grow past the canvas.
	# Scrolling keeps its height honest, which is what the layout model measures.
	var bar_scroll := ScrollContainer.new()
	bar_scroll.name = "ActionDockScroll"
	bar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bar_scroll.follow_focus = true
	# A ScrollContainer has no intrinsic height, which would collapse the dock to a
	# sliver and hand the layout a false measurement. Hold the authored height and
	# scroll only what exceeds it.
	bar_scroll.custom_minimum_size = Vector2(0, HudLayout.ACTION_DOCK_BASE_HEIGHT)
	bar.add_child(bar_scroll)

	var bar_hbox := HFlowContainer.new()
	bar_hbox.add_theme_constant_override("separation", 12)
	bar_hbox.alignment = FlowContainer.ALIGNMENT_CENTER
	bar_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_scroll.add_child(bar_hbox)

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

	var g_spec := _bar_group(bar_hbox, "DEV / ADVANCED")
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
	_enable_keyboard_focus(b_end)
	b_end.text = "END TURN (SPACE)"
	b_end.custom_minimum_size = Vector2(118, 30)
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
	_enable_keyboard_focus(b_evac)
	b_evac.text = "⏏ EXTRACT (F8)"
	b_evac.custom_minimum_size = Vector2(110, 30)
	b_evac.add_theme_font_size_override("font_size", 11)
	b_evac.add_theme_color_override("font_color", Color(1, 0.75, 0.2))
	b_evac.tooltip_text = "Evac / extract now (F8). Loops back to strategy with whatever you've got."
	b_evac.pressed.connect(func(): main._do_evac())
	bar_hbox.add_child(b_evac)
	action_btns["evac"] = b_evac
	_apply_focus_order()
	_register_hud_surfaces()
	_build_hud_grips()
	_build_help_panel()

## Pointer affordance for the adaptive surfaces. Without these the behaviour
## exists but is invisible to anyone who does not press F2. Each surface gets a
## slide grip and an opacity grip; when a surface is parked its slide grip moves
## into the visible handle, so a slid surface can always be clicked back.
func _build_hud_grips() -> void:
	var grips := Control.new()
	grips.name = "HudGrips"
	grips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grips.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(grips)
	for key in surface_keys():
		var slide_grip := _mk_grip(">", "Slide %s out of the way (F4)" % key)
		slide_grip.name = "Slide_%s" % key
		slide_grip.pressed.connect(func(): toggle_surface_parked(key))
		grips.add_child(slide_grip)
		hud_surfaces[key]["slide_grip"] = slide_grip

		var fade_grip := _mk_grip("%", "Cycle %s transparency (F3)" % key)
		fade_grip.name = "Fade_%s" % key
		fade_grip.pressed.connect(func(): cycle_surface_opacity(key))
		grips.add_child(fade_grip)
		hud_surfaces[key]["fade_grip"] = fade_grip

func _mk_grip(glyph: String, tip: String) -> Button:
	var grip := Button.new()
	grip.text = glyph
	grip.tooltip_text = tip
	grip.custom_minimum_size = Vector2(GRIP_SIZE, GRIP_SIZE)
	grip.size = Vector2(GRIP_SIZE, GRIP_SIZE)
	grip.add_theme_font_size_override("font_size", 9)
	grip.add_theme_color_override("font_color", Color(0.65, 0.8, 0.95))
	# The grips are pointer affordances and stay out of the keyboard action order,
	# which the F2/F3/F4 bindings already cover.
	grip.focus_mode = Control.FOCUS_NONE
	var grip_style := StyleBoxFlat.new()
	grip_style.bg_color = Color(0.06, 0.09, 0.14, 0.9)
	grip_style.border_color = Color(0.25, 0.45, 0.6)
	grip_style.set_border_width_all(1)
	grip_style.set_corner_radius_all(3)
	grip.add_theme_stylebox_override("normal", grip_style)
	return grip

## Places every grip against its surface. A parked surface's slide grip sits in
## the handle that remains on screen; its opacity grip is hidden, because there is
## nothing legible left to fade.
func _place_hud_grips() -> void:
	var parked_edge := RESPONSIVE_GUTTER + HudLayout.HANDLE_EXTENT
	for key in hud_surfaces:
		var surface: Dictionary = hud_surfaces[key]
		var slide_grip := surface.get("slide_grip") as Button
		var fade_grip := surface.get("fade_grip") as Button
		var node := surface["node"] as Control
		if slide_grip == null or fade_grip == null or node == null:
			continue
		var parked := int(surface["slide"]) == HudLayout.Slide.PARKED
		var rect := node.get_global_rect()
		var anchor := Vector2.ZERO
		match String(surface["edge"]):
			"left":
				anchor = (
					Vector2(parked_edge - GRIP_SIZE - 1.0, rect.position.y + 3.0)
					if parked
					else Vector2(rect.end.x - GRIP_SIZE - 3.0, rect.position.y + 3.0)
				)
			"top":
				anchor = Vector2(
					rect.position.x + 3.0,
					(parked_edge - GRIP_SIZE - 1.0) if parked else rect.position.y + 3.0
				)
			"bottom":
				anchor = Vector2(
					rect.position.x + 3.0,
					(rect.position.y + 1.0) if parked else rect.position.y + 3.0
				)
		slide_grip.position = anchor
		slide_grip.text = "<" if parked else ">"
		slide_grip.visible = node.visible
		fade_grip.visible = node.visible and not parked
		fade_grip.position = anchor + (
			Vector2(0.0, GRIP_SIZE + 2.0)
			if String(surface["edge"]) == "left"
			else Vector2(GRIP_SIZE + 2.0, 0.0)
		)

## Registers the adaptive surfaces. `edge` is the side a surface parks against;
## `player_parked` records deliberate player intent, which automatic adaptation
## may add to but never overrides.
func _register_hud_surfaces() -> void:
	var registry := {
		"status": {"node": get_node_or_null("StatusPanel"), "edge": "left"},
		"feed": {"node": get_node_or_null("EventPanel"), "edge": "left"},
		"tutorial": {"node": tutorial_panel, "edge": "top"},
		"dock": {"node": get_node_or_null("ActionDock"), "edge": "bottom"}
	}
	hud_surfaces.clear()
	for key in HudLayout.SURFACE_KEYS:
		var entry: Dictionary = registry.get(key, {})
		var node := entry.get("node") as Control
		if node == null:
			continue
		hud_surfaces[key] = {
			"node": node,
			"edge": String(entry["edge"]),
			"opacity": HudLayout.OPACITY_MAX,
			"slide": HudLayout.Slide.OPEN,
			"player_parked": false,
			"open_offset": Vector2(node.offset_left, node.offset_top),
			"open_offset_far": Vector2(node.offset_right, node.offset_bottom)
		}
	_load_hud_preferences()
	_apply_surface_states()

## HUD preferences live in the Commander profile, read and written through the
## launcher's bridge so the runtime never needs to know the storage shape. Only
## the Web export has a bridge; every other host keeps the authored HUD.
func _load_hud_preferences() -> void:
	if not OS.has_feature("web"):
		return
	var raw = JavaScriptBridge.eval(
		(
			"(function(){try{var b=%s;return b?JSON.stringify(b.readHudPreferences()):'';}"
			+ "catch(e){return '';}})()"
		) % HOST_BRIDGE_JS,
		true
	)
	var text := String(raw)
	if text.is_empty():
		return
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var surfaces = (parsed as Dictionary).get("surfaces", {})
	if not (surfaces is Dictionary):
		return
	for key in hud_surfaces:
		var entry = (surfaces as Dictionary).get(key, null)
		if not (entry is Dictionary):
			continue
		var stored: Dictionary = entry
		hud_surfaces[key]["opacity"] = HudLayout.clamp_opacity(
			float(stored.get("opacity", HudLayout.OPACITY_MAX))
		)
		var stored_parked := bool(stored.get("parked", false))
		hud_surfaces[key]["player_parked"] = stored_parked
		hud_surfaces[key]["slide"] = (
			HudLayout.Slide.PARKED if stored_parked else HudLayout.Slide.OPEN
		)

func _save_hud_preferences() -> void:
	if not OS.has_feature("web"):
		return
	var surfaces := {}
	for key in hud_surfaces:
		surfaces[String(key)] = {
			"opacity": snappedf(float(hud_surfaces[key]["opacity"]), 0.01),
			"parked": bool(hud_surfaces[key]["player_parked"])
		}
	var payload := JSON.stringify({"surfaces": surfaces})
	JavaScriptBridge.eval(
		"(function(){try{var b=%s;if(b)b.writeHudPreferences(%s);}catch(e){}})()" % [
			HOST_BRIDGE_JS,
			payload
		],
		true
	)

func surface_state(key: String) -> Dictionary:
	return hud_surfaces.get(key, {})

func surface_keys() -> Array[String]:
	var keys: Array[String] = []
	for key in HudLayout.SURFACE_KEYS:
		if hud_surfaces.has(key):
			keys.append(key)
	return keys

func set_surface_opacity(key: String, value: float, persist: bool = true) -> float:
	if not hud_surfaces.has(key):
		return 0.0
	var clamped := HudLayout.clamp_opacity(value)
	hud_surfaces[key]["opacity"] = clamped
	_apply_surface_states()
	if persist:
		_save_hud_preferences()
	return clamped

func cycle_surface_opacity(key: String) -> float:
	if not hud_surfaces.has(key):
		return 0.0
	return set_surface_opacity(key, HudLayout.next_opacity(float(hud_surfaces[key]["opacity"])))

## Slides a surface off its edge, or back. `by_player` marks deliberate intent.
func set_surface_parked(key: String, parked: bool, by_player: bool = true) -> void:
	if not hud_surfaces.has(key):
		return
	hud_surfaces[key]["slide"] = HudLayout.Slide.PARKED if parked else HudLayout.Slide.OPEN
	if by_player:
		hud_surfaces[key]["player_parked"] = parked
	_apply_surface_states()
	# Only deliberate intent is stored. Automatic adaptation is a response to the
	# current window, not a preference, and must not be written back as one.
	if by_player:
		_save_hud_preferences()

func toggle_surface_parked(key: String) -> bool:
	if not hud_surfaces.has(key):
		return false
	var parked := int(hud_surfaces[key]["slide"]) != HudLayout.Slide.PARKED
	set_surface_parked(key, parked)
	return parked

func is_surface_parked(key: String) -> bool:
	return hud_surfaces.has(key) and int(hud_surfaces[key]["slide"]) == HudLayout.Slide.PARKED

## The surface the adaptive controls currently address.
func selected_surface_key() -> String:
	var keys := surface_keys()
	if keys.is_empty():
		return ""
	return keys[hud_surface_cursor % keys.size()]

func advance_surface_cursor() -> String:
	var keys := surface_keys()
	if keys.is_empty():
		return ""
	hud_surface_cursor = (hud_surface_cursor + 1) % keys.size()
	return selected_surface_key()

## Applies opacity, and records how far each parked surface must slide. The
## responsive layout pass is the single writer of offsets, so a parked surface's
## shift is added there rather than fighting it here.
func _apply_surface_states() -> void:
	for key in hud_surfaces:
		var surface: Dictionary = hud_surfaces[key]
		var node := surface["node"] as Control
		if node == null or not is_instance_valid(node):
			continue
		node.modulate.a = float(surface["opacity"])
	if not _hud_layout_pass:
		_apply_responsive_layout()
		# A HUD change alters no simulation state, but it must be observable or a
		# live run cannot evidence it.
		if main != null and main.has_method("_publish_web_observation"):
			main._publish_web_observation()

## Deterministic Tab order across the core tactical controls. Without this the
## order follows tree position, which reorders whenever a group is hidden.
## Traversal deliberately follows tree order so every action stays reachable by
## keyboard. Forcing `focus_next` between the core controls would make Tab jump
## over crouch, prone, jump, and the weapon controls and strand them. The core
## keys therefore declare what traversal must *reach*, not what it must skip.
func _apply_focus_order() -> void:
	for focus_key in FOCUS_ORDER_KEYS:
		var candidate := action_btns.get(focus_key) as Button
		if candidate != null and not candidate.focus_entered.is_connected(_on_core_control_focused):
			candidate.focus_entered.connect(_on_core_control_focused.bind(focus_key))

## Deterministic traversal from the keyboard entry point. Returns the ordered
## action keys Tab visits, so a headless check and a live browser run can compare
## against the same authority.
func keyboard_traversal_keys(limit: int = 96) -> Array[String]:
	var visited: Array[String] = []
	var entry := keyboard_entry_control(true)
	if entry == null:
		return visited
	var seen := {}
	var current := entry
	for _step in range(maxi(limit, 1)):
		if current == null or seen.has(current):
			break
		seen[current] = true
		visited.append(_focus_key_for(current))
		current = current.find_next_valid_focus()
	return visited

func _focus_key_for(owner: Control) -> String:
	if owner == null:
		return ""
	for candidate_key in action_btns:
		if action_btns[candidate_key] == owner:
			return String(candidate_key)
	for candidate_key in weapon_btns:
		if weapon_btns[candidate_key] == owner:
			return "weapon:%s" % String(candidate_key)
	return String(owner.name)

func _on_core_control_focused(focus_key: String) -> void:
	note_focus_owner(action_btns.get(focus_key) as Control, focus_key)

## Records which control holds keyboard focus so a live keyboard-only run can
## observe the real traversal instead of inferring it from a screenshot. Roster
## rows and weapon controls are rebuilt as the mission runs, so focus is read
## from the viewport rather than wired per control.
func note_focus_owner(owner: Control, known_key: String = "") -> void:
	var focus_key := known_key
	if focus_key.is_empty():
		focus_key = _focus_key_for(owner)
	if focused_control_key == focus_key:
		return
	focused_control_key = focus_key
	if main != null and main.has_method("_publish_web_observation"):
		main._publish_web_observation()

## F2 selects the next surface, F3 cycles its transparency, F4 slides it away or
## back. Every change is announced in the hint line so the control is discoverable
## without a manual.
func _handle_adaptive_hud_input(event: InputEvent) -> bool:
	if hud_surfaces.is_empty():
		return false
	if event.is_action_pressed("hud_next_surface"):
		var selected := advance_surface_cursor()
		_announce_surface(selected, "selected")
		return true
	if event.is_action_pressed("hud_cycle_opacity"):
		var key := selected_surface_key()
		var value := cycle_surface_opacity(key)
		_announce_surface(key, "%d%% opacity" % roundi(value * 100.0))
		return true
	if event.is_action_pressed("hud_toggle_park"):
		var key2 := selected_surface_key()
		var parked := toggle_surface_parked(key2)
		_announce_surface(key2, "slid away" if parked else "restored")
		return true
	return false

func _announce_surface(key: String, state: String) -> void:
	if key.is_empty() or hint_label == null:
		return
	hint_label.text = "HUD // %s %s  (F2 next, F3 opacity, F4 slide)" % [key.to_upper(), state]

## Godot advances GUI focus only from a control that already holds it, so a
## keyboard-only player starting from the canvas has no entry point. The first
## Tab (or Shift+Tab) adopts the core order instead of doing nothing. Focus is
## not taken on load, so mouse play never shows an unrequested focus ring.
func enter_keyboard_focus(forward: bool = true) -> bool:
	var entry := keyboard_entry_control(forward)
	if entry == null:
		return false
	entry.grab_focus()
	return true

## First (or last) core control a keyboard player can actually reach. Disabled or
## hidden controls are skipped because Godot's traversal skips them too.
func keyboard_entry_control(forward: bool = true) -> Control:
	var ordered: Array[Button] = []
	for focus_key in FOCUS_ORDER_KEYS:
		var candidate := action_btns.get(focus_key) as Button
		if is_keyboard_reachable(candidate):
			ordered.append(candidate)
	if ordered.is_empty():
		return null
	return ordered[0] if forward else ordered[ordered.size() - 1]

func is_keyboard_reachable(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree():
		return false
	if control.focus_mode != Control.FOCUS_ALL:
		return false
	if control is Button and (control as Button).disabled:
		return false
	return true

## Every action control a keyboard player should be able to reach in the current
## HUD state. Disabled and hidden controls are excluded by design.
func keyboard_reachable_action_keys() -> Array[String]:
	var keys: Array[String] = []
	for candidate_key in action_btns:
		if is_keyboard_reachable(action_btns[candidate_key] as Control):
			keys.append(String(candidate_key))
	keys.sort()
	return keys

func _unhandled_input(event: InputEvent) -> void:
	if _handle_adaptive_hud_input(event):
		return
	var forward := event.is_action_pressed("ui_focus_next")
	if not forward and not event.is_action_pressed("ui_focus_prev"):
		return
	var viewport := get_viewport()
	if viewport == null or viewport.gui_get_focus_owner() != null:
		return
	if enter_keyboard_focus(forward):
		viewport.set_input_as_handled()

func _process(_delta: float) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var owner := viewport.gui_get_focus_owner()
	if owner == null:
		return
	note_focus_owner(owner)

func contrast_report() -> Array[Dictionary]:
	return HudLayout.contrast_report()

func contrast_ratio(foreground: Color, background: Color) -> float:
	return HudLayout.contrast_ratio(foreground, background)

func _build_help_panel() -> void:
	help_panel = PanelContainer.new()
	help_panel.name = "HelpPanel"
	help_panel.anchor_left = 0.20
	help_panel.anchor_top = 0.10
	help_panel.anchor_right = 0.80
	help_panel.anchor_bottom = 0.88
	help_panel.offset_left = 0
	help_panel.offset_top = 0
	help_panel.offset_right = 0
	help_panel.offset_bottom = 0
	help_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	help_panel.z_index = 100
	var help_sb := StyleBoxFlat.new()
	help_sb.bg_color = Color(0.025, 0.035, 0.06, 0.985)
	help_sb.border_color = Color(0.25, 0.75, 0.95)
	help_sb.set_border_width_all(3)
	help_sb.set_corner_radius_all(10)
	help_sb.content_margin_left = 20
	help_sb.content_margin_right = 20
	help_sb.content_margin_top = 16
	help_sb.content_margin_bottom = 16
	help_panel.add_theme_stylebox_override("panel", help_sb)
	add_child(help_panel)

	var help_vbox := VBoxContainer.new()
	help_vbox.name = "HelpVBox"
	help_vbox.add_theme_constant_override("separation", 10)
	help_panel.add_child(help_vbox)
	var title := _mk_label("TACTICAL HELP // CORE LOOP", 18, Color(0.35, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_vbox.add_child(title)

	var body_scroll := ScrollContainer.new()
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	help_vbox.add_child(body_scroll)
	var body := _mk_label("\n".join([
		"ACTIVE PILOT — The green [CMDR] or [REMOTE] row is the only body you directly control. Other squad members are autonomous Agents.",
		"",
		"BASE-10 AP — Every active unit starts with 10 AP. The HUD and action tooltips show current AP and legal costs; the resolver is authoritative.",
		"",
		"SELECT / MOVE — Left-click a unit or squad row. Hover a floor tile to preview a path and cost, then left-click to move.",
		"",
		"DEFENSE — Brace (B), Crouch (C), Prone (P), or use Take Cover (T) when an adjacent cover face is highlighted.",
		"",
		"ATTACK — Click a hostile for legal melee/ranged resolution. Ready carried equipment in WEAPONS; tooltips show equip and attack costs.",
		"",
		"END TURN — Space/Enter or END TURN finishes Commander actions, resolves allied Agents, then the remaining faction phases.",
		"",
		"EXTRACT — F8 or EXTRACT is the always-visible escape hatch. It emits the current result and returns to strategy.",
		"",
		"DEV / ADVANCED — Remotes, wall traversal, flight, Cover Monkey, and related experimental controls stay hidden until [DEV] ADVANCED MOBILITY is enabled. They are not required for the core loop.",
		"",
		"CAMERA — Right-drag orbits; wheel zooms; WASD/arrows pan. F1 toggles this help; Escape closes it or cancels targeting.",
		"KEYBOARD — Tab and Shift+Tab move focus between tactical controls; Enter or Space activates the focused control."
	]), 13, Color(0.88, 0.92, 0.98), true)
	body.custom_minimum_size = Vector2(640, 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(body)

	var close := Button.new()
	close.name = "CloseHelp"
	close.text = "CLOSE HELP (F1 / ESC)"
	close.custom_minimum_size = Vector2(0, 36)
	_enable_keyboard_focus(close)
	close.pressed.connect(func(): set_help_visible(false))
	help_vbox.add_child(close)
	help_panel.visible = false

func set_help_visible(value: bool) -> void:
	if help_panel == null:
		return
	help_panel.visible = value
	if value:
		var close = help_panel.get_node_or_null("HelpVBox/CloseHelp")
		if close is Button:
			close.grab_focus()

func toggle_help() -> void:
	set_help_visible(not bool(help_panel and help_panel.visible))

func is_help_visible() -> bool:
	return help_panel != null and help_panel.visible

func _player_phase_sequence() -> String:
	var first_hostile := (int(main.player_faction) + 1) % 3
	var second_hostile := (first_hostile + 1) % 3
	return "Agents → %s → %s" % [
		Config.faction_name(first_hostile),
		Config.faction_name(second_hostile)
	]

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

func set_tutorial_guidance(snapshot: Dictionary) -> void:
	if tutorial_panel == null:
		return
	var is_active := bool(snapshot.get("active", false))
	tutorial_panel.visible = is_active
	if not is_active:
		return
	var display_step := int(snapshot.get("display_step", 1))
	var total_steps := int(snapshot.get("total_steps", 6))
	tutorial_title_label.text = "PROVING GROUND // %d/%d // %s" % [
		display_step,
		total_steps,
		String(snapshot.get("title", ""))
	]
	tutorial_body_label.text = String(snapshot.get("body", ""))
	if bool(snapshot.get("complete", false)):
		tutorial_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	else:
		tutorial_title_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.78))

func update_ui() -> void:
	if turn_label:
		if main.turn == main.player_faction:
			turn_label.text = "YOUR TURN · %s · T%d" % [
				Config.faction_name(main.player_faction),
				main.global_turn
			]
		else:
			turn_label.text = "%s PHASE · T%d" % [
				Config.faction_name(main.turn),
				main.global_turn
			]
		if main.turn == Config.FACTION_SYND: turn_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.9))
		elif main.turn == Config.FACTION_TIME: turn_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2))
		else: turn_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.9))

	var is_player = (main.turn == main.player_faction)
	var can = (is_player and not main.busy and not main.game_over)
	var active_pilot = main._active_human_pilot() if main.has_method("_active_human_pilot") else null
	if pilot_label:
		if active_pilot == null:
			pilot_label.text = "ACTIVE PILOT: NONE"
		else:
			var pilot_role := "CMDR" if bool(active_pilot.is_commander) else "REMOTE"
			pilot_label.text = "ACTIVE PILOT: %s [%s] · AP %d/%d" % [
				active_pilot.name,
				pilot_role,
				active_pilot.ap,
				active_pilot.max_ap
			]
	if phase_help_label:
		if main.game_over:
			phase_help_label.text = "MISSION RESOLVED · extraction handoff in progress"
		elif is_player and main.busy:
			phase_help_label.text = "INPUT LOCKED · allied Agents are resolving · next: %s" % Config.faction_name((int(main.player_faction) + 1) % 3)
		elif is_player:
			phase_help_label.text = "LEGAL ACTIONS: enabled dock controls · END TURN → %s · EXTRACT/F8 returns now" % _player_phase_sequence()
		else:
			phase_help_label.text = "INPUT LOCKED · %s is resolving · control returns after the remaining phases" % Config.faction_name(main.turn)
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
				_enable_keyboard_focus(b)
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
		_enable_keyboard_focus(fb)
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
			_enable_keyboard_focus(btn)
			btn.text = u.name
			btn.add_theme_font_size_override("font_size", 11)
			btn.custom_minimum_size = Vector2(0, 22)
			# M01-001: selection must cross the single action/ledger boundary.
			btn.pressed.connect(ActionRouter.request_action.bind(u, "select"))
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
